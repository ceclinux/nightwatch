import importlib.util, json, os, struct, subprocess, sys, tempfile, unittest
import numpy as np, tifffile

HERE = os.path.dirname(os.path.abspath(__file__))

def _load_build_lp_grid():
    spec = importlib.util.spec_from_file_location('build_lp_grid', os.path.join(HERE, 'build-lp-grid.py'))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

build_lp_grid = _load_build_lp_grid()

def make_tiff(path):
    # 20 rows x 30 cols, 0.5 degree cells, north-up, top-left corner at lat 60, lon -10 (GeoTIFF tie point)
    a = np.zeros((20, 30), dtype=np.float32)
    a[0, 0] = 40.0          # NW corner cell, lat 59.75 lon -9.75
    a[19, 29] = 0.1         # SE corner cell, lat 50.25 lon 4.75
    a[10, 10] = np.nan
    tags = [(33550, 'd', 3, (0.5, 0.5, 0.0), True),                       # ModelPixelScaleTag
            (33922, 'd', 6, (0.0, 0.0, 0.0, -10.0, 60.0, 0.0), True)]       # ModelTiepointTag
    tifffile.imwrite(path, a, extratags=tags)

class BuildLPGrid(unittest.TestCase):
    def test_crops_and_flips(self):
        with tempfile.TemporaryDirectory() as d:
            tif = os.path.join(d, 'viirs.tif'); out = os.path.join(d, 'x.lpgrid')
            make_tiff(tif)
            subprocess.check_call([sys.executable, os.path.join(HERE, 'build-lp-grid.py'), tif, '--bbox', '50,-10,60,5', '--cell', '0.5', '--smooth', '1', '--out', out])
            b = open(out, 'rb').read()
            self.assertEqual(b[:4], b'LPG1')
            south, west, cell = struct.unpack('<fff', b[4:16]); rows, cols = struct.unpack('<HH', b[16:20])
            self.assertAlmostEqual(south, 50.0, 5); self.assertAlmostEqual(west, -10.0, 5); self.assertAlmostEqual(cell, 0.5, 5)
            self.assertEqual((rows, cols), (20, 30))
            vals = np.frombuffer(b[20:], dtype='<f4').reshape(rows, cols)
            self.assertEqual(vals[rows - 1, 0], 40.0)        # NW cell ends up in the top (northern) row of a south-first array
            self.assertAlmostEqual(float(vals[0, cols - 1]), 0.1, 5)   # SE cell in row 0
            self.assertTrue(np.isnan(vals[9, 10]))            # nan preserved, flipped row index 19-10

    def test_downsamples_by_mean_of_valid(self):
        with tempfile.TemporaryDirectory() as d:
            tif = os.path.join(d, 'viirs.tif'); out = os.path.join(d, 'x.lpgrid')
            make_tiff(tif)
            subprocess.check_call([sys.executable, os.path.join(HERE, 'build-lp-grid.py'), tif, '--bbox', '50,-10,60,5', '--cell', '1.0', '--smooth', '1', '--out', out])
            b = open(out, 'rb').read(); rows, cols = struct.unpack('<HH', b[16:20])
            self.assertEqual((rows, cols), (10, 15))
            vals = np.frombuffer(b[20:], dtype='<f4').reshape(rows, cols)
            self.assertAlmostEqual(float(vals[rows - 1, 0]), 10.0, 5)   # 40 + 0 + 0 + 0 over 4 cells

    def test_world_mode_writes_one_byte_per_cell(self):
        with tempfile.TemporaryDirectory() as d:
            tif = os.path.join(d, 'viirs.tif'); out = os.path.join(d, 'w.lpgrid')
            make_tiff(tif)
            subprocess.check_call([sys.executable, os.path.join(HERE, 'build-lp-grid.py'), tif, '--world', '--cell', '1.0', '--smooth', '1', '--out', out])
            b = open(out, 'rb').read()
            self.assertEqual(b[:4], b'LPG2')
            south, west, cell = struct.unpack('<fff', b[4:16]); rows, cols = struct.unpack('<HH', b[16:20])
            self.assertAlmostEqual(south, 50.0, 5); self.assertAlmostEqual(west, -10.0, 5); self.assertAlmostEqual(cell, 1.0, 5)
            self.assertEqual((rows, cols), (10, 15)); self.assertEqual(len(b), 20 + 10 * 15)
            q = np.frombuffer(b[20:], dtype=np.uint8).reshape(rows, cols)
            radiance = (2.0 ** (q.astype(np.float64) / 32) - 1) / 8
            self.assertAlmostEqual(float(radiance[rows - 1, 0]), 10.0, delta=0.3)   # NW block: 40 over 4 cells, within the scale's step
            self.assertEqual(int(q[0, 0]), 0)                                        # an unlit block is exactly 0

    def test_world_mode_keeps_a_coastal_cell_and_counts_only_its_land(self):
        with tempfile.TemporaryDirectory() as d:
            tif = os.path.join(d, 'viirs.tif'); out = os.path.join(d, 'w.lpgrid'); land = os.path.join(d, 'land.geojson')
            make_tiff(tif)
            # Land is the western half of the NW 1-degree block (lon -10 .. -9.5) and nothing else: its centre is on the
            # coast, half of it is land, and the 40 in its NW pixel is all on land.
            poly = {'type': 'Polygon', 'coordinates': [[[-10, 59], [-9.5, 59], [-9.5, 60], [-10, 60], [-10, 59]]]}
            json.dump({'type': 'FeatureCollection', 'features': [{'type': 'Feature', 'properties': {}, 'geometry': poly}]}, open(land, 'w'))
            subprocess.check_call([sys.executable, os.path.join(HERE, 'build-lp-grid.py'), tif, '--world', '--cell', '1.0', '--smooth', '1',
                                   '--land', land, '--out', out])
            b = open(out, 'rb').read(); rows, cols = struct.unpack('<HH', b[16:20])
            q = np.frombuffer(b[20:], dtype=np.uint8).reshape(rows, cols)
            radiance = (2.0 ** (q.astype(np.float64) / 32) - 1) / 8
            self.assertAlmostEqual(float(radiance[rows - 1, 0]), 20.0, delta=0.5)   # 40 / 4 pixels = 10 over the block, 20 over its land half
            self.assertEqual(int(q[rows - 1, 1]), 255)                               # the next block east is all sea: no data
            self.assertEqual(int((q != 255).sum()), 1)

    def test_quantise_scale_and_no_data(self):
        q = build_lp_grid.quantise(np.array([0, 0.25, 1, 5, 20, 500, np.nan], dtype=np.float32))
        self.assertEqual(q.tolist(), [0, 51, 101, 171, 235, 254, 255])

    def test_rejects_grids_over_uint16(self):
        with self.assertRaises(SystemExit):
            build_lp_grid.check_limits(1, 1, 70000, 10)           # grid dimension over the uint16 header field
        with self.assertRaises(SystemExit):
            build_lp_grid.check_limits(30000, 30000, 1, 1)        # crop window over the 2 GiB float32 read limit
        build_lp_grid.check_limits(100, 100, 100, 100)            # within both limits, must not raise

    def test_smooth_spreads_a_bright_cell_and_ignores_nan(self):
        a = np.zeros((5, 5), dtype=np.float32)
        a[2, 2] = 9.0
        a[1, 1] = np.nan
        out = build_lp_grid.smooth(a, 3)
        self.assertAlmostEqual(float(out[2, 2]), 9.0 / 8, 5)        # 3 x 3 window, one NaN neighbour ignored: 9 / 8 valid cells
        self.assertAlmostEqual(float(out[2, 3]), 9.0 / 9, 5)        # neighbour without NaN in its window: 9 / 9
        self.assertAlmostEqual(float(out[3, 3]), 9.0 / 9, 5)        # diagonal neighbour receives the glow too
        self.assertEqual(float(out[0, 4]), 0.0)                    # outside the window: untouched
        self.assertTrue(np.isnan(out[1, 1]))                       # NaN stays NaN
        self.assertTrue(np.array_equal(build_lp_grid.smooth(a, 1), a, equal_nan=True))   # 1 disables

    def test_land_mask_turns_sea_into_nan(self):
        with tempfile.TemporaryDirectory() as d:
            tif = os.path.join(d, 'viirs.tif'); out = os.path.join(d, 'x.lpgrid'); land = os.path.join(d, 'land.geojson')
            make_tiff(tif)
            # Land is the western half of the bbox only: lon -10 .. -2.5, lat 50 .. 60
            poly = {'type': 'Polygon', 'coordinates': [[[-10, 50], [-2.5, 50], [-2.5, 60], [-10, 60], [-10, 50]]]}
            json.dump({'type': 'FeatureCollection', 'features': [{'type': 'Feature', 'properties': {}, 'geometry': poly}]}, open(land, 'w'))
            subprocess.check_call([sys.executable, os.path.join(HERE, 'build-lp-grid.py'), tif, '--bbox', '50,-10,60,5', '--cell', '0.5',
                                   '--smooth', '1', '--land', land, '--out', out])
            b = open(out, 'rb').read(); rows, cols = struct.unpack('<HH', b[16:20])
            vals = np.frombuffer(b[20:], dtype='<f4').reshape(rows, cols)
            self.assertEqual(vals[rows - 1, 0], 40.0)                 # NW cell centre (-9.75, 59.75) is on land: kept
            self.assertTrue(np.isnan(vals[:, 15:]).all())             # every cell centre east of -2.5 is sea: NaN
            self.assertEqual(int(np.isnan(vals[:, :15]).sum()), 1)    # on land only the source NaN remains

if __name__ == '__main__':
    unittest.main()
