#!/usr/bin/env python3
"""Builds the survey picture set: one 480x274 WebP per target the app can list, framed as the app frames a card for the default
2.1 x 1.2 degree field of view (or 1.5 x the object, when that is bigger), so the files are a drop-in for what hips2fits returns.

    python3 scripts/build-survey-set.py [--out build/survey-set] [--limit N] [--source auto|cds|skyview] [--delay 3]

Written 31 October 2026 after CDS's hips2fits went unreachable. Sources:
  cds      hips2fits colour DSS2 (what the app uses): one request per target.
  skyview  NASA SkyView DSS2 Red, greyscale, fetched at twice the size and shrunk here. One shared NASA service: strictly one request at a
           time, a pause between, and a longer wait when it answers "Too Many Processes" (a 200 with a web page). First run, 31 October 2026: 300 targets in well under a day. Measured 31 October 2026:
           about 75 s a target, so ~40 hours for the whole set; a Red + Blue merge was tried and rejected (each band is stretched on its own,
           so the colours came out blue or orange, and plate edges showed). Use it for a few hundred of the brightest targets at most.
  hips     the same colour DSS2 survey as cds, cut from its HiPS tiles on two public mirrors (IRSA at Caltech, CASDA at CSIRO), which carried on
           answering while CDS was down. Needs numpy and astropy-healpix. Tiles are kept in <out>/../hips-tiles, so a rerun costs no requests.
           Written 2 November 2026; checked against the SkyView picture of the same field, so the tile orientation is right.
  auto     cds, and hips for the rest once cds fails.
--pack FILE also writes the published file (see Sources/SkyCore/SurveyPack.swift for its layout), one entry per picture in --out, keyed by the numbers
of the app's card request so the app finds it without a catalogue.
Resumable: files already in --out are skipped. Brightest targets first, so a partial run holds the most useful ones.
Licence of the output: the pictures are cut from CDS's DSS2 colour HiPS, so the set is published under the Open Database License 1.0 with the DSS and CDS attribution (docs/releasing.md).
Needs Pillow (and numpy and astropy-healpix for --source hips). Writes <out>/<id>.webp and <out>/manifest.json (sizes, totals).
"""
import argparse, csv, io, json, math, sys, time, urllib.parse, urllib.request
from pathlib import Path
from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "Sources/SkyCore/Resources/catalog"
GROUPS = {"G": "galaxies", "GPair": "galaxies", "GTrpl": "galaxies", "GGroup": "galaxies",
          "OCl": "clusters", "GCl": "clusters", "Cl+N": "clusters", "*Ass": "clusters",
          "PN": "nebulae", "HII": "nebulae", "EmN": "nebulae", "Neb": "nebulae", "RfN": "nebulae", "SNR": "nebulae", "DrkN": "nebulae"}
SIZE_CORRECTIONS = {"NGC7000": 120.0}   # Catalog.sizeCorrections
FOV_W, FOV_H, WIDTH = 2.1, 1.2, 480     # the DWARF Mini's field, Nightwatch's default
HEIGHT = int(WIDTH * FOV_H / FOV_W)     # as Thumbnails.url
UA = "Nightwatch-survey-set/1 (https://github.com/rsutcliffe/nightwatch)"


def sexagesimal(s):
    sign = -1 if s.startswith("-") else 1
    p = [float(x) for x in s.lstrip("+-").split(":")]
    return sign * (p[0] + p[1] / 60 + p[2] / 3600)


def targets():
    """The objects the app lists (Planner: magnitude 12 or brighter; nebulae and cluster-plus-nebula without one are kept)."""
    out = []
    for name in ("NGC.csv", "addendum.csv"):
        for r in csv.DictReader(open(CATALOG / name, encoding="utf-8"), delimiter=";"):
            if r["Type"] not in GROUPS or not r["RA"] or not r["Dec"]:
                continue
            v = r["V-Mag"] or r["B-Mag"]
            mag = float(v) if v else None
            if mag is not None:
                if mag > 12: continue
            elif GROUPS[r["Type"]] != "nebulae" and r["Type"] != "Cl+N":
                continue
            size = SIZE_CORRECTIONS.get(r["Name"]) or (float(r["MajAx"]) if r["MajAx"] else None)
            fov = max(FOV_W, (size or 0) / 60 * 1.5, 0.05)
            out.append({"id": r["Name"], "ra": sexagesimal(r["RA"]) * 15, "dec": sexagesimal(r["Dec"]), "fov": fov, "mag": mag if mag is not None else 99})
    out.sort(key=lambda t: t["mag"])
    return out


def get(url, timeout=60):
    with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": UA}), timeout=timeout) as r:
        return r.read()


def is_jpeg(b): return b[:2] == b"\xff\xd8"


def from_cds(t):
    q = urllib.parse.urlencode({"hips": "CDS/P/DSS2/color", "ra": "%.5f" % t["ra"], "dec": "%.5f" % t["dec"], "fov": "%.3f" % t["fov"],
                                "width": WIDTH, "height": HEIGHT, "projection": "TAN", "format": "jpg"})
    data = get("https://alasky.cds.unistra.fr/hips-image-services/hips2fits?" + q, timeout=30)
    if not is_jpeg(data): raise ValueError("not a JPEG")
    return Image.open(io.BytesIO(data)).convert("RGB")


def skyview_band(t, survey, delay, tries=6):
    w, h = WIDTH * 2, HEIGHT * 2
    q = urllib.parse.urlencode({"Position": "%.5f,%.5f" % (t["ra"], t["dec"]), "Survey": survey, "Pixels": "%d,%d" % (w, h),
                                "Size": "%.4f,%.4f" % (t["fov"], t["fov"] * HEIGHT / WIDTH), "Projection": "Tan", "Return": "JPEG", "Scaling": "Sqrt"},
                               quote_via=urllib.parse.quote)
    for attempt in range(tries):
        try:
            data = get("https://skyview.gsfc.nasa.gov/current/cgi/runquery.pl?" + q)
            if is_jpeg(data):
                # Sqrt, then a stretch of our own: SkyView's default (log) washed 16 of the first 300 out to near-white (31 October 2026),
                # and plates differ in exposure, so every picture is stretched to its own range.
                grey = Image.open(io.BytesIO(data)).convert("L").resize((WIDTH, HEIGHT), Image.LANCZOS)
                return ImageOps.autocontrast(grey, cutoff=(0.5, 0.05))
        except Exception as e:
            print("   ", survey, "error:", e, file=sys.stderr)
        time.sleep(delay * (attempt + 2) * 2)   # busy: wait longer each time
    raise ValueError("SkyView stayed busy for " + survey)


def from_skyview(t, delay):
    return skyview_band(t, "DSS2 Red", delay).convert("RGB")

HIPS_MIRRORS = ["https://irsa.ipac.caltech.edu/data/hips/CDS/DSS2/color", "https://casda.csiro.au/hips/DSS2/color"]
_tiles, _tile_dir, _mirror = {}, ROOT / "build/hips-tiles", [0]


def hips_tile(order, tile, delay):
    """One 512 px JPEG tile, from disk if kept, else from a mirror (alternating, with a pause after each request and a retry on failure)."""
    f = _tile_dir / f"{order}-{tile}.jpg"
    if f not in _tiles:
        if not f.exists():
            _tile_dir.mkdir(parents=True, exist_ok=True)
            path = f"/Norder{order}/Dir{tile // 10000 * 10000}/Npix{tile}.jpg"
            for attempt in range(6):
                _mirror[0] += 1
                try:
                    data = get(HIPS_MIRRORS[_mirror[0] % 2] + path, timeout=30)
                    if not is_jpeg(data): raise ValueError("not a JPEG")
                    f.write_bytes(data); time.sleep(delay); break
                except Exception as e:
                    print("   tile", order, tile, "error:", e, file=sys.stderr); time.sleep(2 * (attempt + 1))
            else:
                raise ValueError(f"no mirror gave tile {order}/{tile}")
        import numpy as np
        _tiles[f] = np.asarray(Image.open(f).convert("RGB"))
    return _tiles[f]


def from_hips(t, delay):
    """The picture hips2fits would give (colour DSS2, TAN projection, 480x274), cut from the HiPS tiles: each output pixel is turned into
    a sky position, then into the HiPS pixel that holds it. The tile order is the coarsest whose pixels are no bigger than the output's."""
    import numpy as np, astropy.units as u
    from astropy_healpix import HEALPix
    scale = math.radians(t["fov"]) / WIDTH
    order = next((o for o in range(10) if math.sqrt(4 * math.pi / (12 * 4 ** (o + 9))) <= scale), 9)
    px, py = np.meshgrid(np.arange(WIDTH), np.arange(HEIGHT))
    xi, eta = -(px - (WIDTH - 1) / 2) * scale, ((HEIGHT - 1) / 2 - py) * scale
    d0, den = math.radians(t["dec"]), None
    den = math.cos(d0) - eta * math.sin(d0)
    ra = math.radians(t["ra"]) + np.arctan2(xi, den)
    dec = np.arctan2(math.sin(d0) + eta * math.cos(d0), np.hypot(xi, den))
    index = HEALPix(nside=2 ** (order + 9), order="nested").lonlat_to_healpix((np.degrees(ra) % 360) * u.deg, np.degrees(dec) * u.deg).astype(np.int64)
    tile, within = index >> 18, index & (2 ** 18 - 1)
    x, y = np.zeros_like(within), np.zeros_like(within)
    for b in range(9):   # a tile's pixels are in nested order: even bits are one axis, odd bits the other
        x |= ((within >> (2 * b)) & 1) << b
        y |= ((within >> (2 * b + 1)) & 1) << b
    out = np.zeros((HEIGHT, WIDTH, 3), np.uint8)
    for n in np.unique(tile):
        m = tile == n
        out[m] = hips_tile(order, int(n), delay)[x[m], y[m]]   # row x, column y: of the 8 flips and swaps, the one that matches SkyView's pictures (correlation 0.98 to 0.99 on M31 and M42)
    return Image.fromarray(out)


def card_key(t):
    """The app's card request as SurveyPack.key(for:) reads it: ra, dec, fov as printed into the hips2fits address, then the picture size."""
    return "%.5f|%.5f|%.3f|%d|%d" % (t["ra"], t["dec"], t["fov"], WIDTH, HEIGHT)


def write_pack(out, todo, path):
    """The pack: 8-byte magic, little-endian UInt32 length of the JSON index, the index {"entries": {key: [offset, length]}}, then the pictures."""
    body, entries = bytearray(), {}
    for t in todo:
        f = out / (t["id"] + ".webp")
        if f.exists() and card_key(t) not in entries:
            data = f.read_bytes(); entries[card_key(t)] = [len(body), len(data)]; body += data
    index = json.dumps({"entries": entries}, separators=(",", ":")).encode()
    Path(path).write_bytes(b"NWSURV1\n" + len(index).to_bytes(4, "little") + index + bytes(body))
    print(f"pack {path}: {len(entries)} pictures, {Path(path).stat().st_size / 1e6:.1f} MB", flush=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(ROOT / "build/survey-set"))
    ap.add_argument("--limit", type=int)
    ap.add_argument("--source", choices=["auto", "cds", "hips", "skyview"], default="auto")
    ap.add_argument("--delay", type=float, default=3.0, help="seconds between requests to SkyView")
    ap.add_argument("--quality", type=int, default=65)
    ap.add_argument("--pack", help="also write the published pack file here")
    a = ap.parse_args()
    out = Path(a.out); out.mkdir(parents=True, exist_ok=True)
    todo = targets()[: a.limit]
    source, done, failed = a.source, 0, []
    print(f"{len(todo)} targets, {WIDTH}x{HEIGHT}, source {source}", flush=True)
    for i, t in enumerate(todo, 1):
        f = out / (t["id"] + ".webp")
        if f.exists(): continue
        try:
            if source in ("auto", "cds"):
                try: img = from_cds(t)
                except Exception as e:
                    if source == "cds": raise
                    print("CDS unreachable, using the HiPS mirrors:", e, flush=True); source = "hips"; img = from_hips(t, a.delay)
            elif source == "hips":
                img = from_hips(t, a.delay)
            else:
                img = from_skyview(t, a.delay); time.sleep(a.delay)
            img.save(f, "WEBP", quality=a.quality, method=6)
            done += 1
            print(f"[{i}/{len(todo)}] {t['id']} {f.stat().st_size} B", flush=True)
        except Exception as e:
            failed.append(t["id"]); print(f"[{i}/{len(todo)}] {t['id']} FAILED: {e}", flush=True)
    files = sorted(out.glob("*.webp"))
    sizes = {p.stem: p.stat().st_size for p in files}
    manifest = {"width": WIDTH, "height": HEIGHT, "fovWidthDeg": FOV_W, "fovHeightDeg": FOV_H, "count": len(sizes),
                "totalBytes": sum(sizes.values()), "failed": failed, "bytes": sizes}
    (out / "manifest.json").write_text(json.dumps(manifest, indent=1))
    n = max(1, len(sizes))
    print(f"{len(sizes)} files, {manifest['totalBytes'] / 1e6:.1f} MB, mean {manifest['totalBytes'] // n} B; {len(failed)} failed", flush=True)
    if a.pack: write_pack(out, todo, a.pack)
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
