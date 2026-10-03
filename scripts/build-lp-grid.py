#!/usr/bin/env python3
"""Crop and downsample a VIIRS Nighttime Lights GeoTIFF into Nightwatch's .lpgrid format.

Usage:
  python3 -m venv .venv && .venv/bin/pip install -r scripts/requirements-data.txt
  curl -fsSLO https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_10m_land.geojson
  .venv/bin/python scripts/build-lp-grid.py VNL_*_average_masked*.tif --bbox 49.8,-8.7,60.9,1.8 --cell 0.01 \
      --smooth 7 --land ne_10m_land.geojson --out Sources/SkyCore/Resources/lightpollution/gb.lpgrid

The VIIRS annual composite (NOAA/NASA Earth Observation Group, CC BY 4.0) is downloaded once with a free EOG
account from https://eogdata.mines.edu/products/vnl/ . Output: 20-byte header (LPG1, south, west, cell, rows, cols),
then rows x cols float32 little-endian, row 0 southernmost, NaN = no data. The "average_masked" product stores masked
and unlit cells as 0 (no NaN), which reads as very dark; the 2025 file is 33601 x 86401 float32, uncompressed, 15 arc-second cells.

The world grid (#138) is built from the whole file instead, and written compactly:
  .venv/bin/python scripts/build-lp-grid.py VNL_*_average_masked*.tif --world --cell 0.05 --smooth 1 \
      --land ne_10m_land.geojson --out Resources/LightPollution/world.lpgrid
Output: the same 20-byte header with the magic LPG2, then rows x cols bytes, row 0 southernmost: 255 = no data, else
q = round(32 * log2(1 + 8 * radiance)) capped at 254, so radiance = (2 ** (q / 32) - 1) / 8 (0.25 -> 51, 1 -> 101, 5 -> 171,
20 -> 235). At 0.05 degrees each cell is the mean of 12 x 12 source pixels, about the 7 x 7 smoothing window of the British
grid, so --smooth 1. 2800 x 7200 cells, 20 MB, read by the app through a memory map. With --land, a cell is kept when at
least a quarter of it is land (16 points across it), and its mean is divided by that share, so it is the land's alone.

Most of Britain is exactly 0 in that product, sea included, so two passes follow the downsampling:
  --land PATH  GeoJSON land polygons (Natural Earth 10 m land, public domain); cells whose centre is not on land become
               NaN, so the sea is never offered as a dark spot.
  --smooth N   NaN-aware box mean over N x N output cells (default 7, 1 disables); a cell's value reflects the glow of its
               surroundings, so a masked zero beside a town no longer reads as darkest. NaN cells stay NaN.
"""
import argparse, struct, sys
import json
import numpy as np, tifffile

MAX_WINDOW_BYTES = 2 * 1024 ** 3  # 2 GiB; the crop happens before downsampling, so this guards the raw window.

def check_limits(window_rows, window_cols, rows, cols):
    window_bytes = window_rows * window_cols * 4
    if window_bytes > MAX_WINDOW_BYTES:
        sys.exit(f'crop window {window_rows} x {window_cols} pixels ({window_bytes / 1024**3:.2f} GiB) exceeds the '
                  '2 GiB limit; use a smaller bbox or a larger --cell')
    if rows > 65535 or cols > 65535:
        sys.exit(f'grid {rows} x {cols} exceeds the 65535-cell limit of the lpgrid header; use a larger --cell or a smaller bbox')

def geo(tif):
    p = tif.pages[0]
    scale = p.tags['ModelPixelScaleTag'].value
    tie = p.tags['ModelTiepointTag'].value
    sx, sy = float(scale[0]), float(scale[1])
    # The tie point maps raster point (I, J) to (X, Y). EOG's VIIRS files use (0.5, 0.5) -> (-180, 75), the centre of
    # pixel (0, 0); other writers use (0, 0) for the corner. Shift to the top-left corner of pixel (0, 0) either way.
    lon0 = float(tie[3]) - float(tie[0]) * sx
    lat0 = float(tie[4]) + float(tie[1]) * sy
    return lon0, lat0, sx, sy

def smooth(a, n):
    """Box mean over n x n cells, ignoring NaN; cells that were NaN stay NaN."""
    if n <= 1: return a
    lo, hi = n // 2, n - 1 - n // 2
    valid = ~np.isnan(a)
    def box(x):
        c = np.pad(np.pad(x, ((lo, hi), (lo, hi))).cumsum(0).cumsum(1), ((1, 0), (1, 0)))
        return c[n:, n:] - c[:-n, n:] - c[n:, :-n] + c[:-n, :-n]
    total, count = box(np.where(valid, a, 0).astype(np.float64)), box(valid.astype(np.float64))
    with np.errstate(invalid='ignore', divide='ignore'):
        out = (total / count).astype(np.float32)
    out[~valid] = np.nan
    return out

def load_land(path, south, west, cell, rows, cols):
    """The land polygons within the grid, as one prepared geometry."""
    import shapely
    geoms = np.array([shapely.geometry.shape(f['geometry']) for f in json.load(open(path))['features']])
    north, east = south + rows * cell, west + cols * cell
    land = shapely.union_all(shapely.clip_by_rect(geoms, west - cell, south - cell, east + cell, north + cell))
    shapely.prepare(land)
    return land

def on_land(land, south, west, cell, rows, cols, dy=0.5, dx=0.5):
    """True where the point (dy, dx) of the way across each cell lies on land; row 0 south, as in the output."""
    import shapely
    lat = south + (np.arange(rows) + dy) * cell
    lon = west + (np.arange(cols) + dx) * cell
    out = np.empty((rows, cols), dtype=bool)
    for r in range(0, rows, 200):                                   # in bands of rows, so a world grid stays within memory
        x, y = np.meshgrid(lon, lat[r:r + 200])
        out[r:r + 200] = shapely.contains_xy(land, x, y)
    return out

def land_mask(path, south, west, cell, rows, cols):
    """True where the cell centre lies on a land polygon; row 0 south, as in the output."""
    return on_land(load_land(path, south, west, cell, rows, cols), south, west, cell, rows, cols)

def land_fraction(path, south, west, cell, rows, cols, n=4):
    """The share of each cell that is land, from n x n points spread across it. A world cell is 5.5 km, so its centre
    alone would call a coastal town sea (Reykjavik, 3 October 2026)."""
    land = load_land(path, south, west, cell, rows, cols)
    total = np.zeros((rows, cols), dtype=np.float32)
    for i in range(n):
        for j in range(n):
            total += on_land(land, south, west, cell, rows, cols, (i + 0.5) / n, (j + 0.5) / n)
    return total / (n * n)

def quantise(a):
    """One byte per cell on a log scale; NaN becomes 255. See the module docstring for the scale."""
    with np.errstate(invalid='ignore'):
        q = np.minimum(254, np.rint(32 * np.log2(1 + 8 * np.maximum(a, 0))))
    return np.where(np.isnan(a), 255, q).astype(np.uint8)

def world(tif_path, cell):
    """The whole raster as block means, row 0 south, read in bands of source rows (the file is 11.6 GB)."""
    with tifffile.TiffFile(tif_path) as tif:
        lon0, lat0, sx, sy = geo(tif)
        h, w = tif.pages[0].shape[:2]
    f = max(1, int(round(cell / sx)))
    rows, cols = h // f, w // f
    if rows > 65535 or cols > 65535: sys.exit(f'grid {rows} x {cols} exceeds the 65535-cell limit of the lpgrid header; use a larger --cell')
    m = tifffile.memmap(tif_path)
    out = np.empty((rows, cols), dtype=np.float32)
    band = 100                                                      # output rows per read
    for r in range(0, rows, band):
        n = min(band, rows - r)
        a = np.asarray(m[r * f:(r + n) * f, :cols * f], dtype=np.float32).reshape(n, f, cols, f)
        with np.errstate(invalid='ignore'):
            out[r:r + n] = np.nanmean(a, axis=(1, 3))
    return out[::-1, :], lat0 - sy * rows * f, lon0, sx * f

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('tif'); ap.add_argument('--bbox', help='south,west,north,east in degrees')
    ap.add_argument('--world', action='store_true', help='the whole raster, written compactly (LPG2) instead of a --bbox crop')
    ap.add_argument('--cell', type=float, required=True, help='output cell size in degrees')
    ap.add_argument('--out', required=True)
    ap.add_argument('--smooth', type=int, default=7, help='box mean over N x N output cells after downsampling; 1 disables')
    ap.add_argument('--land', help='GeoJSON land polygons; cells whose centre is not on land are written as NaN')
    a = ap.parse_args()
    if a.world:
        out, grid_south, grid_west, cell = world(a.tif, a.cell)
        rows, cols = out.shape
        if a.land:
            # A cell is land when a quarter of it is, and its radiance is that of its land: the sea is 0 in the source and
            # would dilute a coastal town's mean. The British grid gets the same from its NaN-aware smoothing.
            share = land_fraction(a.land, grid_south, grid_west, cell, rows, cols)
            with np.errstate(invalid='ignore', divide='ignore'):
                out = np.where(share >= 0.25, out / share, np.nan).astype(np.float32)
        out = smooth(out, a.smooth)
        with open(a.out, 'wb') as fh:
            fh.write(b'LPG2'); fh.write(struct.pack('<fff', grid_south, grid_west, cell)); fh.write(struct.pack('<HH', rows, cols))
            fh.write(quantise(out).tobytes())
        print(f'wrote {a.out}: {rows} x {cols} cells of {cell:.4f} deg, south {grid_south:.4f} west {grid_west:.4f}, '
              f'smooth {a.smooth}, {int(np.isnan(out).sum())} cells without data')
        return
    if not a.bbox: sys.exit('give --bbox south,west,north,east, or --world')
    south, west, north, east = (float(x) for x in a.bbox.split(','))
    with tifffile.TiffFile(a.tif) as tif:
        lon0, lat0, sx, sy = geo(tif)
        page = tif.pages[0]
        h, w = page.shape[:2]
        r0 = max(0, int((lat0 - north) / sy)); r1 = min(h, int(np.ceil((lat0 - south) / sy)))
        c0 = max(0, int((west - lon0) / sx)); c1 = min(w, int(np.ceil((east - lon0) / sx)))
        if r0 >= r1 or c0 >= c1: sys.exit('bbox does not intersect the raster')
    f = max(1, int(round(a.cell / sx)))
    window_rows, window_cols = r1 - r0, c1 - c0
    rows, cols = window_rows // f, window_cols // f
    check_limits(window_rows, window_cols, rows, cols)
    # The global file is 11.6 GB uncompressed; read only the window through a memory map (verified memmappable 2026-09-23).
    m = tifffile.memmap(a.tif)
    arr = np.array(m[r0:r1, c0:c1], dtype=np.float32)               # north-up window
    arr = arr[:rows * f, :cols * f].reshape(rows, f, cols, f)
    with np.errstate(invalid='ignore'):
        out = np.nanmean(arr, axis=(1, 3)).astype(np.float32)        # mean of valid cells, NaN where none
    out = out[::-1, :]                                              # row 0 becomes the southern row
    cell = sx * f
    grid_south = lat0 - sy * (r0 + rows * f)
    grid_west = lon0 + sx * c0
    if a.land: out[~land_mask(a.land, grid_south, grid_west, cell, rows, cols)] = np.nan
    out = smooth(out, a.smooth)
    with open(a.out, 'wb') as fh:
        fh.write(b'LPG1'); fh.write(struct.pack('<fff', grid_south, grid_west, cell)); fh.write(struct.pack('<HH', rows, cols))
        fh.write(out.astype('<f4').tobytes())
    print(f'wrote {a.out}: {rows} x {cols} cells of {cell:.4f} deg, south {grid_south:.4f} west {grid_west:.4f}, '
          f'smooth {a.smooth}, {int(np.isnan(out).sum())} NaN cells')

if __name__ == '__main__':
    main()
