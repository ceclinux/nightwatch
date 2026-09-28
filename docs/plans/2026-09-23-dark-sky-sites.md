# Nightwatch v0.2 Dark-Sky Sites Implementation Plan

**Goal:** List dark-sky observing sites within a user-set radius, with tonight's conditions at each, in the target browser, the popover and Settings.

**Architecture:** New pure modules in `SkyCore` (`Geo`, `LPGrid`, `DarkSites`, `SiteComparison`) with bundled data (`certified.json`, `gb.lpgrid`) built by two Python scripts. The app's `Store` fetches per-site forecasts through the existing `ForecastService` and `Planner`, and three views gain a group, a line and a section.

**Tech Stack:** Swift 6.4 via Command Line Tools, SwiftPM, Swift Testing through `scripts/test.sh`, Python 3 with a virtual environment for the data scripts (numpy, tifffile), Wikidata SPARQL, VIIRS Nighttime Lights GeoTIFF.

**Spec:** `docs/specs/2026-09-23-dark-sky-sites-design.md` (the v0.1 spec `2026-09-23-nightwatch-design.md` still binds everything it covers)

## Global Constraints

- No API keys, no server. Bundled data plus Open-Meteo at runtime.
- No `@State` in views (toolchain ruling from v0.1); view-local state in `ObservableObject` view models via `@StateObject`.
- Radius default 50 km, range 5 to 300, unit km or miles (`Config.darkSites.unit`), stored in km.
- Computed spots carry a darkness band, never a Bortle class. Bands by radiance nW/cm²/sr: < 0.25 Very dark, < 1 Dark, < 5 Rural, < 20 Suburban, else Bright.
- Per-site forecasts: nearest eight sites per refresh, cached under `~/Library/Caches/Nightwatch/sites/<id>.json` with the 30-minute gate.
- Popover line only when the best site's score ≥ home score + 20.
- `.lpgrid` format: magic `LPG1`, float32 south latitude, float32 west longitude, float32 cell degrees, uint16 rows, uint16 cols (20 bytes, little-endian), then rows × cols float32, row 0 = southernmost, NaN = no data.
- Certified entries need `source` URLs; the build script fails without one.
- Attribution in NOTICE and About: DarkSky International, UK Dark Sky Discovery Sites, Wikidata (CC0), NOAA/NASA EOG VIIRS (CC BY 4.0).
- Commit after every task; no "time-boxed", "deferred", "partial".

---

## File Structure

```
Sources/SkyCore/Geo.swift                 distance, bearing, compass, unit formatting
Sources/SkyCore/LPGrid.swift              grid loader, radiance lookup, darkest spots, bands
Sources/SkyCore/DarkSites.swift           CertifiedSite, DarkSite, bundled loading, sites(near:)
Sources/SkyCore/SiteComparison.swift      per-site plan summary, bestAway rule
Sources/SkyCore/Config.swift              + DarkSiteSettings
Sources/SkyCore/Resources/darksky/certified.json
Sources/SkyCore/Resources/lightpollution/gb.lpgrid
scripts/build-certified.py                Wikidata + curated → certified.json
scripts/build-lp-grid.py                  VIIRS GeoTIFF → .lpgrid
data/certified-curated.json               hand-maintained UK/IE entries
Sources/Nightwatch/Store.swift            + darkSites, sitePlans, bestAway, per-site cache
Sources/Nightwatch/Views/TargetsView.swift + Dark sites group and DarkSiteCard
Sources/Nightwatch/Views/TonightView.swift + bestAway line
Sources/Nightwatch/Views/SettingsView.swift + Dark sites section
Sources/Nightwatch/Views/AboutView.swift   + attribution and band note
Tests/SkyCoreTests/GeoTests.swift, LPGridTests.swift, DarkSitesTests.swift, SiteComparisonTests.swift, ConfigTests.swift (+)
```

---

### Task 1: Geo — distance, bearing, units

**Files:**
- Create: `Sources/SkyCore/Geo.swift`
- Test: `Tests/SkyCoreTests/GeoTests.swift`

**Interfaces:**
- Produces:
  - `public struct Coordinate: Codable, Equatable, Sendable { latitude, longitude }`
  - `public enum DistanceUnit: String, Codable, Sendable { km, mi; displayName }`
  - `public enum Geo { static func distanceKm(_ a: Coordinate, _ b: Coordinate) -> Double; static func bearingDeg(from:to:) -> Double; static func compass(_ deg: Double) -> String; static func format(km:unit:) -> String; static func destination(from:bearingDeg:distanceKm:) -> Coordinate }`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import SkyCore

private let sheffield = Coordinate(latitude: 53.381, longitude: -1.470)
private let edinburgh = Coordinate(latitude: 55.953, longitude: -3.189)
private let london = Coordinate(latitude: 51.507, longitude: -0.128)

// Reference values computed independently with the spherical formulas (R = 6371.0088 km) on 2026-09-23.
@Test func distanceSheffieldEdinburgh() { #expect(abs(Geo.distanceKm(sheffield, edinburgh) - 306.59) < 0.5) }
@Test func distanceSheffieldLondon() { #expect(abs(Geo.distanceKm(sheffield, london) - 227.36) < 0.5) }
@Test func distanceIsSymmetricAndZeroAtSelf() {
    #expect(abs(Geo.distanceKm(sheffield, edinburgh) - Geo.distanceKm(edinburgh, sheffield)) < 1e-9)
    #expect(Geo.distanceKm(sheffield, sheffield) == 0)
}
@Test func bearings() {
    #expect(abs(Geo.bearingDeg(from: sheffield, to: edinburgh) - 339.6) < 0.5)
    #expect(abs(Geo.bearingDeg(from: sheffield, to: london) - 155.9) < 0.5)
}
@Test func compassPoints() {
    #expect(Geo.compass(0) == "N"); #expect(Geo.compass(339.6) == "NNW"); #expect(Geo.compass(155.9) == "SSE")
    #expect(Geo.compass(359.9) == "N"); #expect(Geo.compass(45) == "NE")
}
@Test func destinationRoundTrip() {
    let d = Geo.destination(from: sheffield, bearingDeg: 90, distanceKm: 50)
    #expect(abs(Geo.distanceKm(sheffield, d) - 50) < 0.05)
    #expect(abs(Geo.bearingDeg(from: sheffield, to: d) - 90) < 0.5)
}
@Test func unitFormatting() {
    #expect(Geo.format(km: 32.4, unit: .km) == "32 km")
    #expect(Geo.format(km: 32.4, unit: .mi) == "20 mi")
    #expect(Geo.format(km: 0.8, unit: .km) == "0.8 km")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `scripts/test.sh`
Expected: `cannot find 'Geo' in scope`.

- [ ] **Step 3: Implement Geo.swift**

```swift
import Foundation

public struct Coordinate: Codable, Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public init(latitude: Double, longitude: Double) { self.latitude = latitude; self.longitude = longitude }
}

public enum DistanceUnit: String, Codable, Sendable {
    case km, mi
    public var displayName: String { self == .km ? "Kilometres" : "Miles" }
}

public enum Geo {
    static let earthRadiusKm = 6371.0088
    private static let d2r = Double.pi / 180

    public static func distanceKm(_ a: Coordinate, _ b: Coordinate) -> Double {
        let p1 = a.latitude * d2r, p2 = b.latitude * d2r
        let dp = (b.latitude - a.latitude) * d2r, dl = (b.longitude - a.longitude) * d2r
        let h = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return 2 * earthRadiusKm * asin(min(1, sqrt(h)))
    }

    /// Initial bearing, degrees clockwise from north, 0 ..< 360.
    public static func bearingDeg(from a: Coordinate, to b: Coordinate) -> Double {
        let p1 = a.latitude * d2r, p2 = b.latitude * d2r, dl = (b.longitude - a.longitude) * d2r
        let y = sin(dl) * cos(p2)
        let x = cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dl)
        let deg = atan2(y, x) / d2r
        return (deg + 360).truncatingRemainder(dividingBy: 360)
    }

    public static func compass(_ deg: Double) -> String {
        let points = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let i = Int((deg / 22.5).rounded()) % 16
        return points[i]
    }

    public static func destination(from a: Coordinate, bearingDeg: Double, distanceKm: Double) -> Coordinate {
        let δ = distanceKm / earthRadiusKm, θ = bearingDeg * d2r
        let p1 = a.latitude * d2r, l1 = a.longitude * d2r
        let p2 = asin(sin(p1) * cos(δ) + cos(p1) * sin(δ) * cos(θ))
        let l2 = l1 + atan2(sin(θ) * sin(δ) * cos(p1), cos(δ) - sin(p1) * sin(p2))
        return Coordinate(latitude: p2 / d2r, longitude: ((l2 / d2r + 540).truncatingRemainder(dividingBy: 360)) - 180)
    }

    public static func format(km: Double, unit: DistanceUnit) -> String {
        let v = unit == .km ? km : km * 0.621371
        let s = v < 1 ? String(format: "%.1f", v) : String(format: "%.0f", v)
        return "\(s) \(unit.rawValue)"
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `scripts/test.sh`
Expected: all Geo tests pass (81 total).

- [ ] **Step 5: Commit**

```bash
git add Sources/SkyCore/Geo.swift Tests/SkyCoreTests/GeoTests.swift
git commit -m "feat(skycore): great-circle distance, bearing and unit formatting"
```

---

### Task 2: Light-pollution grid — format, lookup, darkest spots, bands

**Files:**
- Create: `Sources/SkyCore/LPGrid.swift`
- Test: `Tests/SkyCoreTests/LPGridTests.swift`

**Interfaces:**
- Consumes: `Coordinate`, `Geo.distanceKm`, `Geo.bearingDeg`.
- Produces:
  - `public enum DarknessBand: String, Codable, CaseIterable, Sendable { veryDark, dark, rural, suburban, bright; displayName; static func from(radiance: Double) -> DarknessBand }`
  - `public struct LPGrid: Sendable { south, west, cellDeg: Double; rows, cols: Int; values: [Float]; init(data: Data) throws; func encoded() -> Data; func radiance(at:) -> Double? (nil outside or NaN); func darkestSpots(center:radiusKm:count:minSpacingKm:) -> [DarkSpot] }`
  - `public struct DarkSpot: Equatable, Sendable { coordinate: Coordinate, radiance: Double, band: DarknessBand }`
  - `public enum LPGridError: Error { badMagic, truncated }`
  - `public enum LPGrids { static func bundled() -> [LPGrid] (every .lpgrid in Resources/lightpollution); static func radiance(at:in:) -> Double? }`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import SkyCore

/// 3 × 3 grid, 0.1° cells, south-west corner 53.0, −2.0. Row 0 is the southern row.
private func sampleGrid() -> LPGrid {
    let values: [Float] = [
        5, 3, 0.1,      // row 0 (south): lat 53.05
        20, .nan, 0.5,  // row 1: lat 53.15
        0.2, 8, 40      // row 2 (north): lat 53.25
    ]
    return LPGrid(south: 53.0, west: -2.0, cellDeg: 0.1, rows: 3, cols: 3, values: values)
}

@Test func roundTripsThroughBinary() throws {
    let g = sampleGrid()
    let back = try LPGrid(data: g.encoded())
    #expect(back.rows == 3 && back.cols == 3 && back.cellDeg == 0.1)
    #expect(back.values[0] == 5 && back.values[8] == 40 && back.values[4].isNaN)
    #expect(g.encoded().count == 20 + 9 * 4)
    #expect(String(decoding: g.encoded().prefix(4), as: UTF8.self) == "LPG1")
}

@Test func rejectsBadData() {
    #expect(throws: LPGridError.self) { try LPGrid(data: Data("nope".utf8)) }
    #expect(throws: LPGridError.self) { try LPGrid(data: sampleGrid().encoded().prefix(20)) }
}

@Test func lookupUsesCellCentresAndEdges() {
    let g = sampleGrid()
    #expect(g.radiance(at: Coordinate(latitude: 53.05, longitude: -1.95)) == 5)     // row 0 col 0 centre
    #expect(g.radiance(at: Coordinate(latitude: 53.29, longitude: -1.71)) == 40)    // top-right cell
    #expect(g.radiance(at: Coordinate(latitude: 53.15, longitude: -1.85)) == nil)   // NaN cell
    #expect(g.radiance(at: Coordinate(latitude: 52.9, longitude: -1.9)) == nil)     // outside
    #expect(g.radiance(at: Coordinate(latitude: 53.31, longitude: -1.9)) == nil)    // just north of the grid
}

@Test func bandsAtThresholds() {
    #expect(DarknessBand.from(radiance: 0.24) == .veryDark)
    #expect(DarknessBand.from(radiance: 0.25) == .dark)
    #expect(DarknessBand.from(radiance: 0.99) == .dark)
    #expect(DarknessBand.from(radiance: 1) == .rural)
    #expect(DarknessBand.from(radiance: 4.99) == .rural)
    #expect(DarknessBand.from(radiance: 5) == .suburban)
    #expect(DarknessBand.from(radiance: 19.99) == .suburban)
    #expect(DarknessBand.from(radiance: 20) == .bright)
}

@Test func darkestSpotsRespectRadiusAndSpacing() {
    let g = sampleGrid()
    let centre = Coordinate(latitude: 53.15, longitude: -1.85)   // middle cell
    let spots = g.darkestSpots(center: centre, radiusKm: 30, count: 3, minSpacingKm: 5)
    #expect(spots.count == 3)
    #expect(spots[0].radiance == 0.1)   // darkest first
    #expect(spots[1].radiance == 0.2)
    #expect(spots[2].radiance == 0.5)
    #expect(spots.allSatisfy { Geo.distanceKm(centre, $0.coordinate) <= 30 })
    for i in 0..<spots.count { for j in (i + 1)..<spots.count { #expect(Geo.distanceKm(spots[i].coordinate, spots[j].coordinate) >= 5) } }
    let tight = g.darkestSpots(center: centre, radiusKm: 8, count: 3, minSpacingKm: 5)
    #expect(tight.count <= 2)          // only the centre's neighbours are within 8 km
    let spaced = g.darkestSpots(center: centre, radiusKm: 30, count: 3, minSpacingKm: 25)
    #expect(spaced.count == 1)         // spacing larger than the grid
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `scripts/test.sh`
Expected: `cannot find 'LPGrid' in scope`.

- [ ] **Step 3: Implement LPGrid.swift**

```swift
import Foundation

public enum DarknessBand: String, Codable, CaseIterable, Sendable {
    case veryDark, dark, rural, suburban, bright
    public var displayName: String {
        switch self {
        case .veryDark: "Very dark"
        case .dark: "Dark"
        case .rural: "Rural"
        case .suburban: "Suburban"
        case .bright: "Bright"
        }
    }
    /// Heuristic bands on VIIRS upward radiance (nW/cm²/sr). Not a Bortle class; the About window says so.
    public static func from(radiance r: Double) -> DarknessBand {
        switch r {
        case ..<0.25: .veryDark
        case ..<1: .dark
        case ..<5: .rural
        case ..<20: .suburban
        default: .bright
        }
    }
}

public struct DarkSpot: Equatable, Sendable {
    public let coordinate: Coordinate
    public let radiance: Double
    public let band: DarknessBand
}

public enum LPGridError: Error { case badMagic, truncated }

/// Row 0 is the southernmost row; column 0 the westernmost. Cell (r, c) covers
/// [south + r·cell, south + (r+1)·cell) × [west + c·cell, west + (c+1)·cell).
public struct LPGrid: Sendable {
    public let south: Double
    public let west: Double
    public let cellDeg: Double
    public let rows: Int
    public let cols: Int
    public let values: [Float]

    public init(south: Double, west: Double, cellDeg: Double, rows: Int, cols: Int, values: [Float]) {
        self.south = south; self.west = west; self.cellDeg = cellDeg; self.rows = rows; self.cols = cols; self.values = values
    }

    public init(data: Data) throws {
        guard data.count >= 16, String(decoding: data.prefix(4), as: UTF8.self) == "LPG1" else { throw LPGridError.badMagic }
        func f32(_ o: Int) -> Float { Float(bitPattern: UInt32(littleEndian: data[o..<o + 4].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })) }
        func u16(_ o: Int) -> Int { Int(UInt16(littleEndian: data[o..<o + 2].withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) })) }
        let s = Double(f32(4)), w = Double(f32(8)), c = Double(f32(12))
        // header is 16 bytes: magic 4 + 3 floats 12 = 16, so rows/cols follow at 16 and 18 in a 20-byte header
        let r = u16(16), k = u16(18)
        guard data.count == 20 + r * k * 4 else { throw LPGridError.truncated }
        var vals = [Float](repeating: .nan, count: r * k)
        data[20...].withUnsafeBytes { raw in
            for i in 0..<(r * k) { vals[i] = Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: i * 4, as: UInt32.self))) }
        }
        self.init(south: s, west: w, cellDeg: c, rows: r, cols: k, values: vals)
    }

    public func encoded() -> Data {
        var d = Data("LPG1".utf8)
        for v in [Float(south), Float(west), Float(cellDeg)] { var le = v.bitPattern.littleEndian; d.append(Data(bytes: &le, count: 4)) }
        for n in [UInt16(rows), UInt16(cols)] { var le = n.littleEndian; d.append(Data(bytes: &le, count: 2)) }
        d.reserveCapacity(d.count + values.count * 4)
        for v in values { var le = v.bitPattern.littleEndian; d.append(Data(bytes: &le, count: 4)) }
        return d
    }

    public var north: Double { south + Double(rows) * cellDeg }
    public var east: Double { west + Double(cols) * cellDeg }

    public func radiance(at c: Coordinate) -> Double? {
        let r = Int(floor((c.latitude - south) / cellDeg)), k = Int(floor((c.longitude - west) / cellDeg))
        guard r >= 0, r < rows, k >= 0, k < cols else { return nil }
        let v = values[r * cols + k]
        return v.isNaN ? nil : Double(v)
    }

    func centre(row: Int, col: Int) -> Coordinate {
        Coordinate(latitude: south + (Double(row) + 0.5) * cellDeg, longitude: west + (Double(col) + 0.5) * cellDeg)
    }

    /// Lowest-radiance cells within `radiusKm`, greedy from darkest, each at least `minSpacingKm` from the ones already picked.
    public func darkestSpots(center: Coordinate, radiusKm: Double, count: Int, minSpacingKm: Double) -> [DarkSpot] {
        let latSpan = radiusKm / 111.2, lonSpan = radiusKm / (111.2 * max(0.1, cos(center.latitude * .pi / 180)))
        let r0 = max(0, Int(floor((center.latitude - latSpan - south) / cellDeg))), r1 = min(rows - 1, Int(floor((center.latitude + latSpan - south) / cellDeg)))
        let c0 = max(0, Int(floor((center.longitude - lonSpan - west) / cellDeg))), c1 = min(cols - 1, Int(floor((center.longitude + lonSpan - west) / cellDeg)))
        guard r0 <= r1, c0 <= c1 else { return [] }
        var candidates: [(Coordinate, Double)] = []
        for r in r0...r1 { for k in c0...c1 {
            let v = values[r * cols + k]
            guard !v.isNaN else { continue }
            let p = centre(row: r, col: k)
            if Geo.distanceKm(center, p) <= radiusKm { candidates.append((p, Double(v))) }
        } }
        candidates.sort { $0.1 < $1.1 }
        var picked: [DarkSpot] = []
        for (p, v) in candidates where picked.count < count {
            if picked.allSatisfy({ Geo.distanceKm($0.coordinate, p) >= minSpacingKm }) {
                picked.append(DarkSpot(coordinate: p, radiance: v, band: DarknessBand.from(radiance: v)))
            }
        }
        return picked
    }
}

public enum LPGrids {
    public static func bundled() -> [LPGrid] {
        guard let urls = Bundle.module.urls(forResourcesWithExtension: "lpgrid", subdirectory: "Resources/lightpollution") else { return [] }
        return urls.compactMap { url in (try? Data(contentsOf: url)).flatMap { try? LPGrid(data: $0) } }
    }
    public static func radiance(at c: Coordinate, in grids: [LPGrid]) -> Double? {
        for g in grids { if let v = g.radiance(at: c) { return v } }
        return nil
    }
}
```

The header is 20 bytes: magic 4, three float32 12, two uint16 4. The spec §4.2 states 20 bytes.

- [ ] **Step 4: Run tests to verify they pass**

Run: `scripts/test.sh`
Expected: all LPGrid tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/SkyCore/LPGrid.swift Tests/SkyCoreTests/LPGridTests.swift docs/specs/2026-09-23-dark-sky-sites-design.md
git commit -m "feat(skycore): light-pollution grid format, lookup, darkest spots and darkness bands"
```

---
### Task 3: `scripts/build-lp-grid.py` — VIIRS GeoTIFF to `.lpgrid`

**Files:**
- Create: `scripts/build-lp-grid.py`, `scripts/requirements-data.txt`
- Test: `scripts/test_build_lp_grid.py` (Python unittest on a synthetic GeoTIFF)

**Interfaces:**
- Produces a file readable by `LPGrid(data:)` from Task 2. Header 20 bytes, row 0 southernmost.
- Consumes a VIIRS annual composite GeoTIFF (`*.average_masked*.tif`, float32, geographic WGS84, north-up), read through `tifffile` with `numpy`. `tifffile` and `numpy` 2.5 install into a Python 3.14 virtual environment on this Mac (verified 2026-09-23).

- [ ] **Step 1: Write the test**

`scripts/test_build_lp_grid.py`:

```python
import os, struct, subprocess, sys, tempfile, unittest
import numpy as np, tifffile

HERE = os.path.dirname(os.path.abspath(__file__))

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
            subprocess.check_call([sys.executable, os.path.join(HERE, 'build-lp-grid.py'), tif, '--bbox', '50,-10,60,5', '--cell', '0.5', '--out', out])
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
            subprocess.check_call([sys.executable, os.path.join(HERE, 'build-lp-grid.py'), tif, '--bbox', '50,-10,60,5', '--cell', '1.0', '--out', out])
            b = open(out, 'rb').read(); rows, cols = struct.unpack('<HH', b[16:20])
            self.assertEqual((rows, cols), (10, 15))
            vals = np.frombuffer(b[20:], dtype='<f4').reshape(rows, cols)
            self.assertAlmostEqual(float(vals[rows - 1, 0]), 10.0, 5)   # 40 + 0 + 0 + 0 over 4 cells

if __name__ == '__main__':
    unittest.main()
```

- [ ] **Step 2: Write the script**

`scripts/requirements-data.txt`:

```
numpy>=2.0
tifffile>=2024.1
```

`scripts/build-lp-grid.py`:

```python
#!/usr/bin/env python3
"""Crop and downsample a VIIRS Nighttime Lights GeoTIFF into Nightwatch's .lpgrid format.

Usage:
  python3 -m venv .venv && .venv/bin/pip install -r scripts/requirements-data.txt
  .venv/bin/python scripts/build-lp-grid.py VNL_*_average_masked*.tif --bbox 49.8,-8.7,60.9,1.8 --cell 0.01 --out Sources/SkyCore/Resources/lightpollution/gb.lpgrid

The VIIRS annual composite (NOAA/NASA Earth Observation Group, CC BY 4.0) is downloaded once with a free EOG
account from https://eogdata.mines.edu/products/vnl/ . Output: 20-byte header (LPG1, south, west, cell, rows, cols),
then rows x cols float32 little-endian, row 0 southernmost, NaN = no data. The "average_masked" product stores masked
and unlit cells as 0 (no NaN), which reads as very dark; the 2025 file is 33601 x 86401 float32, uncompressed, 15 arc-second cells.
"""
import argparse, struct, sys
import numpy as np, tifffile

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

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('tif'); ap.add_argument('--bbox', required=True, help='south,west,north,east in degrees')
    ap.add_argument('--cell', type=float, required=True, help='output cell size in degrees')
    ap.add_argument('--out', required=True)
    a = ap.parse_args()
    south, west, north, east = (float(x) for x in a.bbox.split(','))
    with tifffile.TiffFile(a.tif) as tif:
        lon0, lat0, sx, sy = geo(tif)
        page = tif.pages[0]
        h, w = page.shape[:2]
        r0 = max(0, int((lat0 - north) / sy)); r1 = min(h, int(np.ceil((lat0 - south) / sy)))
        c0 = max(0, int((west - lon0) / sx)); c1 = min(w, int(np.ceil((east - lon0) / sx)))
        if r0 >= r1 or c0 >= c1: sys.exit('bbox does not intersect the raster')
    # The global file is 11.6 GB uncompressed; read only the window through a memory map (verified memmappable 2026-09-23).
    m = tifffile.memmap(a.tif)
    arr = np.array(m[r0:r1, c0:c1], dtype=np.float32)               # north-up window
    f = max(1, int(round(a.cell / sx)))
    rows, cols = arr.shape[0] // f, arr.shape[1] // f
    arr = arr[:rows * f, :cols * f].reshape(rows, f, cols, f)
    with np.errstate(invalid='ignore'):
        out = np.nanmean(arr, axis=(1, 3)).astype(np.float32)        # mean of valid cells, NaN where none
    out = out[::-1, :]                                              # row 0 becomes the southern row
    cell = sx * f
    grid_south = lat0 - sy * (r0 + rows * f)
    grid_west = lon0 + sx * c0
    with open(a.out, 'wb') as fh:
        fh.write(b'LPG1'); fh.write(struct.pack('<fff', grid_south, grid_west, cell)); fh.write(struct.pack('<HH', rows, cols))
        fh.write(out.astype('<f4').tobytes())
    print(f'wrote {a.out}: {rows} x {cols} cells of {cell:.4f} deg, south {grid_south:.4f} west {grid_west:.4f}')

if __name__ == '__main__':
    main()
```

- [ ] **Step 3: Run the Python test**

```bash
python3 -m venv .venv && .venv/bin/pip install -q -r scripts/requirements-data.txt
.venv/bin/python -m unittest scripts/test_build_lp_grid.py -v
```

Expected: 2 tests OK. Add `.venv/` to `.gitignore`.

- [ ] **Step 4: Cross-check with Swift**

Generate the synthetic `.lpgrid` from the test (copy the temp-file logic into a one-off run writing `Tests/SkyCoreTests/Fixtures/synthetic.lpgrid`), then add to `LPGridTests.swift`:

```swift
@Test func loadsScriptOutput() throws {
    let g = try LPGrid(data: try fixture("synthetic.lpgrid"))
    #expect(g.rows == 20 && g.cols == 30)
    #expect(g.radiance(at: Coordinate(latitude: 59.75, longitude: -9.75)) == 40)
    #expect(g.radiance(at: Coordinate(latitude: 50.25, longitude: 4.75))! < 0.11)
}
```

Run `scripts/test.sh`; expected pass. This proves the row order and header agree between Python and Swift.

- [ ] **Step 5: Commit**

```bash
git add scripts/build-lp-grid.py scripts/test_build_lp_grid.py scripts/requirements-data.txt .gitignore Tests/SkyCoreTests/Fixtures/synthetic.lpgrid Tests/SkyCoreTests/LPGridTests.swift
git commit -m "feat(data): VIIRS GeoTIFF to lpgrid converter with a synthetic round-trip test"
```

---

### Task 4: Certified places — build script, bundled JSON, `DarkSites`

**Files:**
- Create: `scripts/build-certified.py`, `data/certified-curated.json`, `Sources/SkyCore/Resources/darksky/certified.json`, `Sources/SkyCore/DarkSites.swift`
- Test: `Tests/SkyCoreTests/DarkSitesTests.swift`

**Interfaces:**
- Consumes: `Coordinate`, `Geo`, `LPGrid`, `DarkSpot`, `DarknessBand`, `Site`.
- Produces:
  - `public struct CertifiedSite: Codable, Equatable, Sendable, Identifiable { id, name, kind: Kind, country, latitude, longitude, designated: Int?, bortle: Int?, source: String, wikidata: String? }` with `enum Kind: String, Codable { park, reserve, sanctuary, community, urban, discovery }`
  - `public struct DarkSite: Codable, Equatable, Sendable, Identifiable { id, name, kind: String ("park" … or "spot"), coordinate, distanceKm, bearingDeg, band: DarknessBand?, bortle: Int?, source: String?, isComputed: Bool; var compass }`
  - `public enum DarkSites { static func bundledCertified() throws -> [CertifiedSite]; static func sites(near:radiusKm:certified:grids:maxSpots:) -> [DarkSite] (sorted by distance); static func toSite(_:) -> Site }`

- [ ] **Step 1: Write the curated data and the build script**

`data/certified-curated.json` — one object per UK and Ireland place. Each needs a `source` URL whose page states the certification. The implementer verifies every entry by fetching its source (WebFetch) and its coordinates from the Wikidata item (`https://www.wikidata.org/wiki/Special:EntityData/<QID>.json`, claim P625). Start from this list and drop any entry that cannot be verified; record what was dropped in the report:

| name | kind | wikidata search term |
|---|---|---|
| Northumberland International Dark Sky Park | park | Northumberland National Park |
| Exmoor International Dark Sky Reserve | reserve | Exmoor National Park |
| Bannau Brycheiniog International Dark Sky Reserve | reserve | Brecon Beacons National Park |
| Eryri International Dark Sky Reserve | reserve | Snowdonia National Park |
| Galloway Forest International Dark Sky Park | park | Galloway Forest Park |
| Elan Valley International Dark Sky Park | park | Elan Valley |
| Cranborne Chase International Dark Sky Reserve | reserve | Cranborne Chase |
| Moore's Reserve (South Downs) | reserve | South Downs National Park |
| Yorkshire Dales International Dark Sky Reserve | reserve | Yorkshire Dales National Park |
| North York Moors International Dark Sky Reserve | reserve | North York Moors National Park |
| Bodmin Moor Dark Sky Landscape | park | Bodmin Moor |
| Sark Dark Sky Community | community | Sark |
| Moffat Dark Sky Community | community | Moffat |
| Coll Dark Sky Community | community | Coll |
| Tomintoul and Glenlivet Dark Sky Park | park | Tomintoul |
| Kerry International Dark Sky Reserve | reserve | Kerry Dark-Sky Reserve |
| Mayo Dark Sky Park | park | Mayo Dark Sky Park |

Entry shape:

```json
{"id":"gb-northumberland","name":"Northumberland International Dark Sky Park","kind":"park","country":"GB",
 "latitude":55.30,"longitude":-2.30,"designated":2013,"bortle":null,
 "source":"https://en.wikipedia.org/wiki/Northumberland_National_Park","wikidata":"Q1195889"}
```

`scripts/build-certified.py`:

```python
#!/usr/bin/env python3
"""Build Sources/SkyCore/Resources/darksky/certified.json from Wikidata plus data/certified-curated.json."""
import json, re, sys, urllib.parse, urllib.request
UA = {'User-Agent': 'Nightwatch-data/0.2 (https://github.com/rsutcliffe/nightwatch)'}
SPARQL = '''SELECT ?item ?label ?coord ?type ?country WHERE {
  VALUES ?type { wd:Q3457162 wd:Q52216504 wd:Q72114283 }
  ?item wdt:P31 ?type ; wdt:P625 ?coord .
  OPTIONAL { ?item wdt:P17 ?country }
  OPTIONAL { ?item rdfs:label ?label FILTER(LANG(?label)="en") } }'''
KIND = {'Q52216504': 'park', 'Q72114283': 'reserve', 'Q3457162': 'park'}

def wikidata():
    url = 'https://query.wikidata.org/sparql?' + urllib.parse.urlencode({'query': SPARQL})
    req = urllib.request.Request(url, headers={**UA, 'Accept': 'application/sparql-results+json'})
    rows = json.load(urllib.request.urlopen(req, timeout=170))['results']['bindings']
    out = {}
    for r in rows:
        qid = r['item']['value'].rsplit('/', 1)[1]
        m = re.match(r'Point\(([-\d.]+) ([-\d.]+)\)', r['coord']['value'])
        if not m: continue
        lon, lat = float(m.group(1)), float(m.group(2))
        out.setdefault(qid, {
            'id': 'wd-' + qid.lower(), 'name': r.get('label', {}).get('value', qid), 'kind': KIND[r['type']['value'].rsplit('/', 1)[1]],
            'country': r.get('country', {}).get('value', '').rsplit('/', 1)[-1] or None,
            'latitude': round(lat, 4), 'longitude': round(lon, 4), 'designated': None, 'bortle': None,
            'source': 'https://www.wikidata.org/wiki/' + qid, 'wikidata': qid})
    return list(out.values())

def main():
    curated = json.load(open('data/certified-curated.json'))
    for c in curated:
        for k in ('id', 'name', 'kind', 'country', 'latitude', 'longitude', 'source'):
            if c.get(k) in (None, ''): sys.exit(f'curated entry missing {k}: {c}')
    wd = wikidata()
    curated_q = {c.get('wikidata') for c in curated if c.get('wikidata')}
    merged = curated + [w for w in wd if w['wikidata'] not in curated_q]
    merged.sort(key=lambda e: (e['country'] or '', e['name']))
    json.dump(merged, open('Sources/SkyCore/Resources/darksky/certified.json', 'w'), indent=1, ensure_ascii=False)
    print(f'{len(curated)} curated + {len(merged) - len(curated)} from Wikidata = {len(merged)} places')

if __name__ == '__main__':
    main()
```

Run it: `python3 scripts/build-certified.py` (standard library only). Expected: about 17 curated plus about 38 Wikidata places. Wikidata's SPARQL endpoint was slow on 2026-09-23; retry once on timeout.

- [ ] **Step 2: Write the failing tests**

```swift
import Testing
import Foundation
@testable import SkyCore

@Test func certifiedListLoadsAndHasSources() throws {
    let all = try DarkSites.bundledCertified()
    #expect(all.count >= 40)
    #expect(all.allSatisfy { $0.source.hasPrefix("http") })
    #expect(Set(all.map(\.id)).count == all.count)
    #expect(all.contains { $0.id == "gb-northumberland" })
}

@Test func sitesNearSheffieldWithinRadius() throws {
    let all = try DarkSites.bundledCertified()
    let home = Coordinate(latitude: 53.381, longitude: -1.470)
    let near = DarkSites.sites(near: home, radiusKm: 120, certified: all, grids: [], maxSpots: 0)
    #expect(near.allSatisfy { $0.distanceKm <= 120 })
    #expect(near.contains { $0.id == "gb-yorkshire-dales" })
    #expect(!near.contains { $0.id == "gb-northumberland" })     // 220 km away
    #expect(near == near.sorted { $0.distanceKm < $1.distanceKm })
}

@Test func computedSpotsAreMergedAndNamed() {
    let values: [Float] = [5, 3, 0.1, 20, .nan, 0.5, 0.2, 8, 40]
    let g = LPGrid(south: 53.0, west: -2.0, cellDeg: 0.1, rows: 3, cols: 3, values: values)
    let home = Coordinate(latitude: 53.15, longitude: -1.85)
    let sites = DarkSites.sites(near: home, radiusKm: 30, certified: [], grids: [g], maxSpots: 2)
    #expect(sites.count == 2)
    #expect(sites.allSatisfy { $0.isComputed && $0.kind == "spot" && $0.band != nil && $0.bortle == nil })
    #expect(sites[0].name.hasPrefix("Dark spot "))
    #expect(sites[0].id.hasPrefix("spot-"))
}

@Test func toSiteCarriesCoordinatesAndName() throws {
    let s = DarkSite(id: "x", name: "Elan Valley", kind: "park", coordinate: Coordinate(latitude: 52.27, longitude: -3.6),
                     distanceKm: 100, bearingDeg: 250, band: nil, bortle: 2, source: nil, isComputed: false)
    let site = DarkSites.toSite(s, timeZoneID: "Europe/London")
    #expect(site.name == "Elan Valley" && site.latitude == 52.27 && site.bortle == 2)
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `scripts/test.sh`
Expected: `cannot find 'DarkSites' in scope`.

- [ ] **Step 4: Implement DarkSites.swift**

```swift
import Foundation

public struct CertifiedSite: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable { case park, reserve, sanctuary, community, urban, discovery }
    public let id: String
    public let name: String
    public let kind: Kind
    public let country: String?
    public let latitude: Double
    public let longitude: Double
    public let designated: Int?
    public let bortle: Int?
    public let source: String
    public let wikidata: String?
    public var coordinate: Coordinate { Coordinate(latitude: latitude, longitude: longitude) }
}

public struct DarkSite: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let kind: String
    public let coordinate: Coordinate
    public let distanceKm: Double
    public let bearingDeg: Double
    public let band: DarknessBand?
    public let bortle: Int?
    public let source: String?
    public let isComputed: Bool
    public var compass: String { Geo.compass(bearingDeg) }

    public init(id: String, name: String, kind: String, coordinate: Coordinate, distanceKm: Double, bearingDeg: Double,
                band: DarknessBand?, bortle: Int?, source: String?, isComputed: Bool) {
        self.id = id; self.name = name; self.kind = kind; self.coordinate = coordinate; self.distanceKm = distanceKm
        self.bearingDeg = bearingDeg; self.band = band; self.bortle = bortle; self.source = source; self.isComputed = isComputed
    }
}

public enum DarkSites {
    public static func bundledCertified() throws -> [CertifiedSite] {
        guard let url = Bundle.module.url(forResource: "certified", withExtension: "json", subdirectory: "Resources/darksky") else {
            throw CatalogError.missingResource("certified")
        }
        return try JSONDecoder().decode([CertifiedSite].self, from: Data(contentsOf: url))
    }

    /// Certified places within the radius plus up to `maxSpots` computed dark spots, sorted by distance.
    public static func sites(near home: Coordinate, radiusKm: Double, certified: [CertifiedSite], grids: [LPGrid], maxSpots: Int) -> [DarkSite] {
        var out: [DarkSite] = []
        for c in certified {
            let d = Geo.distanceKm(home, c.coordinate)
            guard d <= radiusKm else { continue }
            let band = LPGrids.radiance(at: c.coordinate, in: grids).map { DarknessBand.from(radiance: $0) }
            out.append(DarkSite(id: c.id, name: c.name, kind: c.kind.rawValue, coordinate: c.coordinate, distanceKm: d,
                                bearingDeg: Geo.bearingDeg(from: home, to: c.coordinate), band: band, bortle: c.bortle, source: c.source, isComputed: false))
        }
        if maxSpots > 0 {
            let spots = grids.flatMap { $0.darkestSpots(center: home, radiusKm: radiusKm, count: maxSpots, minSpacingKm: 10) }
                .sorted { $0.radiance < $1.radiance }.prefix(maxSpots)
            for s in spots {
                let d = Geo.distanceKm(home, s.coordinate), b = Geo.bearingDeg(from: home, to: s.coordinate)
                let name = "Dark spot \(Geo.compass(b)) \(Int(d.rounded())) km"
                out.append(DarkSite(id: String(format: "spot-%.3f-%.3f", s.coordinate.latitude, s.coordinate.longitude), name: name, kind: "spot",
                                    coordinate: s.coordinate, distanceKm: d, bearingDeg: b, band: s.band, bortle: nil, source: nil, isComputed: true))
            }
        }
        return out.sorted { $0.distanceKm < $1.distanceKm }
    }

    public static func toSite(_ s: DarkSite, timeZoneID: String) -> Site {
        Site(name: s.name, latitude: s.coordinate.latitude, longitude: s.coordinate.longitude, elevationM: 0, timeZoneID: timeZoneID,
             bortle: s.bortle ?? (s.band.map { [DarknessBand.veryDark: 2, .dark: 3, .rural: 4, .suburban: 6, .bright: 8][$0]! } ?? 5))
    }
}
```

`toSite` maps a band to a Bortle-like number only because `Site.bortle` is a required integer shown in the popover header; the browser card itself never shows a Bortle class for computed spots (spec ruling).

- [ ] **Step 5: Run tests to verify they pass**

Run: `scripts/test.sh`
Expected: all DarkSites tests pass. `sitesNearSheffieldWithinRadius` depends on `gb-yorkshire-dales` being in the curated file within 120 km of Sheffield (the Dales centre is about 80 km away).

- [ ] **Step 6: Commit**

```bash
git add scripts/build-certified.py data/certified-curated.json Sources/SkyCore/Resources/darksky Sources/SkyCore/DarkSites.swift Tests/SkyCoreTests/DarkSitesTests.swift
git commit -m "feat(skycore): certified dark-sky places and computed dark spots"
```

---

### Task 5: Settings and site comparison

**Files:**
- Modify: `Sources/SkyCore/Config.swift` (+ `DarkSiteSettings`)
- Create: `Sources/SkyCore/SiteComparison.swift`
- Test: `Tests/SkyCoreTests/ConfigTests.swift` (+), `Tests/SkyCoreTests/SiteComparisonTests.swift`

**Interfaces:**
- Produces:
  - `public struct DarkSiteSettings: Codable, Equatable, Sendable { enabled = true, radiusKm = 50, unit: DistanceUnit = .km }` on `Config.darkSites`, decoded with a default like the other fields.
  - `public struct SitePlan: Codable, Equatable, Sendable, Identifiable { id (site id), site: DarkSite, score: Int, primary: ClearWindow?, qualifies: Bool, forecastMissing: Bool }`
  - `public enum SiteComparison { static func bestAway(home: NightPlan, sites: [SitePlan], margin: Int = 20) -> SitePlan?; static func sorted(_:) -> [SitePlan] (score desc, then distance, forecastMissing last) }`

- [ ] **Step 1: Write the failing tests**

```swift
// ConfigTests.swift additions
@Test func darkSiteSettingsDefaultAndDecode() throws {
    #expect(Config.default.darkSites == DarkSiteSettings())
    #expect(DarkSiteSettings().radiusKm == 50 && DarkSiteSettings().unit == .km && DarkSiteSettings().enabled)
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("config.json")
    try Data(#"{"darkSites":{"radiusKm":80,"unit":"mi"}}"#.utf8).write(to: url)
    let c = try ConfigStore.load(from: url)
    #expect(c.darkSites.radiusKm == 80 && c.darkSites.unit == .mi && c.darkSites.enabled)
}
```

```swift
// SiteComparisonTests.swift
import Testing
import Foundation
@testable import SkyCore

private func plan(score: Int, qualifies: Bool) -> NightPlan {
    let night = try! Ephemeris.night(localDate: utc(2026, 9, 23, 12, 0), site: Site(name: "S", latitude: 53.38, longitude: -1.47, elevationM: 100, timeZoneID: "Europe/London", bortle: 5))
    let w = qualifies ? ClearWindow(start: night.darkStart!, end: night.darkStart!.addingTimeInterval(4 * 3600)) : nil
    return NightPlan(night: night, windows: w.map { [$0] } ?? [], primary: w, score: score, qualifies: qualifies, moonIllumination: 0.3,
                     moonRise: nil, moonSet: nil, darkHours: [], targets: [], best: [], seeingAvailable: false)
}
private func site(_ id: String, km: Double) -> DarkSite {
    DarkSite(id: id, name: id, kind: "park", coordinate: Coordinate(latitude: 53, longitude: -2), distanceKm: km, bearingDeg: 0, band: .dark, bortle: nil, source: nil, isComputed: false)
}

@Test func bestAwayNeedsTwentyPointMargin() {
    let home = plan(score: 40, qualifies: false)
    let a = SitePlan(id: "a", site: site("a", km: 30), score: 59, primary: nil, qualifies: true, forecastMissing: false)
    let b = SitePlan(id: "b", site: site("b", km: 60), score: 60, primary: nil, qualifies: true, forecastMissing: false)
    #expect(SiteComparison.bestAway(home: home, sites: [a]) == nil)
    #expect(SiteComparison.bestAway(home: home, sites: [a, b])?.id == "b")
}

@Test func bestAwayIgnoresMissingForecastsAndNonQualifying() {
    let home = plan(score: 10, qualifies: false)
    let missing = SitePlan(id: "m", site: site("m", km: 10), score: 0, primary: nil, qualifies: false, forecastMissing: true)
    let noWindow = SitePlan(id: "n", site: site("n", km: 10), score: 70, primary: nil, qualifies: false, forecastMissing: false)
    #expect(SiteComparison.bestAway(home: home, sites: [missing, noWindow]) == nil)
}

@Test func sortedByScoreThenDistanceMissingLast() {
    let s = [SitePlan(id: "far", site: site("far", km: 90), score: 80, primary: nil, qualifies: true, forecastMissing: false),
             SitePlan(id: "near", site: site("near", km: 20), score: 80, primary: nil, qualifies: true, forecastMissing: false),
             SitePlan(id: "miss", site: site("miss", km: 5), score: 0, primary: nil, qualifies: false, forecastMissing: true),
             SitePlan(id: "low", site: site("low", km: 10), score: 30, primary: nil, qualifies: false, forecastMissing: false)]
    #expect(SiteComparison.sorted(s).map(\.id) == ["near", "far", "low", "miss"])
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `scripts/test.sh`
Expected: `cannot find 'DarkSiteSettings' in scope`.

- [ ] **Step 3: Implement**

In `Config.swift` add:

```swift
public struct DarkSiteSettings: Codable, Equatable, Sendable {
    public var enabled = true
    public var radiusKm: Double = 50
    public var unit: DistanceUnit = .km
    public init() {}
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        radiusKm = try c.decodeIfPresent(Double.self, forKey: .radiusKm) ?? 50
        unit = try c.decodeIfPresent(DistanceUnit.self, forKey: .unit) ?? .km
    }
    enum CodingKeys: String, CodingKey { case enabled, radiusKm, unit }
}
```

and on `Config`: `public var darkSites = DarkSiteSettings()`, a `darkSites` case in `CodingKeys`, and `darkSites = try c.decodeIfPresent(DarkSiteSettings.self, forKey: .darkSites) ?? DarkSiteSettings()` in `init(from:)`.

`SiteComparison.swift`:

```swift
import Foundation

public struct SitePlan: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let site: DarkSite
    public let score: Int
    public let primary: ClearWindow?
    public let qualifies: Bool
    public let forecastMissing: Bool
    public init(id: String, site: DarkSite, score: Int, primary: ClearWindow?, qualifies: Bool, forecastMissing: Bool) {
        self.id = id; self.site = site; self.score = score; self.primary = primary; self.qualifies = qualifies; self.forecastMissing = forecastMissing
    }
}

public enum SiteComparison {
    public static func sorted(_ plans: [SitePlan]) -> [SitePlan] {
        plans.sorted {
            if $0.forecastMissing != $1.forecastMissing { return !$0.forecastMissing }
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.site.distanceKm < $1.site.distanceKm
        }
    }

    /// The best qualifying site whose score beats home by at least `margin`; nil when none.
    public static func bestAway(home: NightPlan, sites: [SitePlan], margin: Int = 20) -> SitePlan? {
        sorted(sites).first { !$0.forecastMissing && $0.qualifies && $0.score >= home.score + margin }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `scripts/test.sh`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/SkyCore/Config.swift Sources/SkyCore/SiteComparison.swift Tests/SkyCoreTests/ConfigTests.swift Tests/SkyCoreTests/SiteComparisonTests.swift
git commit -m "feat(skycore): dark-site settings and site comparison"
```

---
### Task 6: Store — per-site forecasts and plans

**Files:**
- Modify: `Sources/Nightwatch/Store.swift`

**Interfaces:**
- Consumes: `DarkSites`, `LPGrids`, `SiteComparison`, `ForecastService`, `Planner`, `Config.darkSites`.
- Produces on `Store`: `@Published var darkSites: [DarkSite]`, `@Published var sitePlans: [SitePlan]`, `@Published var bestAway: SitePlan?`, `func adoptAsBeat(_ site: DarkSite)`, `var distanceUnit: DistanceUnit`.

- [ ] **Step 1: Add state and loading**

In `Store`:

```swift
    @Published var darkSites: [DarkSite] = []
    @Published var sitePlans: [SitePlan] = []
    @Published var bestAway: SitePlan?
    private let certified: [CertifiedSite]
    private let grids: [LPGrid]
    static let siteCacheDir = cacheDir.appendingPathComponent("sites", isDirectory: true)
    var distanceUnit: DistanceUnit { config.darkSites.unit }
```

In `init()`: `certified = (try? DarkSites.bundledCertified()) ?? []`, `grids = LPGrids.bundled()`, create `siteCacheDir`.

- [ ] **Step 2: Compute sites after the home plan**

At the end of `recompute(now:)`, after `plan`/`tomorrow`/`events` are set:

```swift
        await recomputeDarkSites(now: now, site: site, night: night)
```

and add:

```swift
    /// Sites within the radius; forecasts for the nearest eight (30-minute cache under sites/<id>.json); plans with the home rule.
    private func recomputeDarkSites(now: Date, site: Site, night: Night) async {
        guard config.darkSites.enabled else { darkSites = []; sitePlans = []; bestAway = nil; return }
        let home = Coordinate(latitude: site.latitude, longitude: site.longitude)
        let sites = DarkSites.sites(near: home, radiusKm: config.darkSites.radiusKm, certified: certified, grids: grids, maxSpots: 5)
        darkSites = sites
        var plans: [SitePlan] = []
        for s in sites.prefix(8) {
            let cacheURL = Store.siteCacheDir.appendingPathComponent("\(s.id).json")
            var fc: Forecast? = Store.readFile(cacheURL)
            if fc.map({ now.timeIntervalSince($0.fetchedAt) > 30 * 60 }) ?? true {
                let siteAsSite = DarkSites.toSite(s, timeZoneID: site.timeZoneID)
                if let fresh = try? await ForecastService.fetch(site: siteAsSite, fetcher: fetcher, now: now) { fc = fresh; Store.writeFile(fresh, cacheURL) }
            }
            guard let fc else { plans.append(SitePlan(id: s.id, site: s, score: 0, primary: nil, qualifies: false, forecastMissing: true)); continue }
            let p = Planner.plan(night: night, forecast: fc, catalog: Catalog(objects: []), constellations: [], site: DarkSites.toSite(s, timeZoneID: site.timeZoneID), fov: config.fov, rule: config.goRule)
            plans.append(SitePlan(id: s.id, site: s, score: p.score, primary: p.primary, qualifies: p.qualifies, forecastMissing: false))
        }
        sitePlans = SiteComparison.sorted(plans)
        bestAway = plan.map { SiteComparison.bestAway(home: $0, sites: plans) } ?? nil
    }
```

`Store.readFile`/`writeFile` are the existing `read`/`write` helpers generalised to take a URL (add two one-line overloads). Planning a site with an empty catalogue keeps it cheap: only windows and score are needed.

- [ ] **Step 3: Adopt a site as the active beat**

```swift
    func adoptAsBeat(_ s: DarkSite) {
        let tz = site?.timeZoneID ?? TimeZone.current.identifier
        var new = DarkSites.toSite(s, timeZoneID: tz)
        if config.sites.contains(where: { $0.name == new.name }) { new.name += " (dark site)" }
        config.sites.append(new)
        config.activeSiteName = new.name
        saveConfig()
    }
```

- [ ] **Step 4: Build and live check**

```bash
swift build -c release 2>&1 | grep -E 'error:|Build complete'
scripts/test.sh | tail -1
scripts/build-app.sh
sleep 60; ls ~/Library/Caches/Nightwatch/sites/ | head; python3 -c "import json,os;p=json.load(open(os.path.expanduser('~/Library/Caches/Nightwatch/plan.json')));print('home score',p['score'])"
```

Expected: up to eight `sites/<id>.json` files appear within a minute of launch with the test site (Sheffield: Yorkshire Dales, North York Moors and any computed spots within 50 km once the grid exists).

- [ ] **Step 5: Commit**

```bash
git add Sources/Nightwatch/Store.swift
git commit -m "feat(app): per-site forecasts and plans for nearby dark-sky sites"
```

---

### Task 7: Views — Dark sites group, popover line, Settings, About

**Files:**
- Modify: `Sources/Nightwatch/Views/TargetsView.swift`, `TonightView.swift`, `SettingsView.swift`, `AboutView.swift`, `Theme.swift`, `NOTICE`

- [ ] **Step 1: Group and glyph**

`TargetGroup` is in SkyCore; do not change it. In `TargetsView` add a sidebar entry after Constellations, driven by a local enum:

```swift
enum BrowserSection: Hashable { case group(TargetGroup), darkSites }
```

`TargetsViewState.section: BrowserSection = .group(.nebulae)`. The `List(selection:)` iterates `TargetGroup.allCases.map { .group($0) } + [.darkSites]`; the Dark sites row uses `Image(systemName: "moon.stars")` and the count `store.darkSites.count`. In the detail area, `.darkSites` renders `darkSitesList`:

```swift
    private var darkSitesList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Text("Dark sites").font(.title2.weight(.semibold))
                Text("Within \(Geo.format(km: store.config.darkSites.radiusKm, unit: store.distanceUnit)) of \(store.site?.name ?? "home") · sorted by tonight's score").font(.caption).foregroundStyle(Theme.dim)
            }.frame(maxWidth: .infinity, alignment: .leading).padding([.horizontal, .top], 20)
            if store.darkSites.isEmpty {
                Text("No dark sites within \(Geo.format(km: store.config.darkSites.radiusKm, unit: store.distanceUnit)). Widen the radius in Settings.")
                    .foregroundStyle(Theme.dim).padding(20)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                ForEach(store.sitePlans) { DarkSiteCard(plan: $0) }
                ForEach(store.darkSites.dropFirst(8)) { DarkSiteCard(plan: SitePlan(id: $0.id, site: $0, score: 0, primary: nil, qualifies: false, forecastMissing: true)) }
            }.padding(20)
        }
    }
```

`DarkSiteCard`:

```swift
struct DarkSiteCard: View {
    @EnvironmentObject var store: Store
    let plan: SitePlan
    var body: some View {
        let s = plan.site
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(s.name).font(.callout.weight(.semibold)).lineLimit(2)
                Spacer()
                if !plan.forecastMissing { Text("\(plan.score)").font(.title3.weight(.semibold)).foregroundStyle(plan.qualifies ? Theme.accent : Theme.dim) }
            }
            Text("\(Geo.format(km: s.distanceKm, unit: store.distanceUnit)) \(s.compass) · \(s.kind.capitalized)" + (s.bortle.map { " · Bortle \($0)" } ?? s.band.map { " · \($0.displayName)" } ?? ""))
                .font(.caption).foregroundStyle(Theme.dim)
            if let w = plan.primary, let home = store.site {
                Text("Clear \(Copy.hhmm(w.start, site: home))–\(Copy.hhmm(w.end, site: home)) · \(String(format: "%.1f h", w.hours))").font(.caption)
            } else if plan.forecastMissing {
                Text("No forecast fetched (beyond the nearest eight, or offline)").font(.caption).foregroundStyle(Theme.dim)
            } else {
                Text(store.copy.noWindow).font(.caption).foregroundStyle(Theme.dim)
            }
            HStack {
                if let src = s.source, let url = URL(string: src) { Link("Source", destination: url).font(.caption) }
                Spacer()
                Button("Use as beat") { store.adoptAsBeat(s) }.font(.caption)
            }
        }
        .padding(12).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line))
    }
}
```

- [ ] **Step 2: Popover line**

In `TonightView.verdict`, after the verdict `VStack`, add inside the same `HStack`'s parent (below the verdict row):

```swift
    private func awayLine(_ site: Site) -> some View {
        Group {
            if let a = store.bestAway, let w = a.primary {
                Button {
                    open("targets")
                } label: {
                    Text("Darker sky \(Geo.format(km: a.site.distanceKm, unit: store.distanceUnit)) \(a.site.compass): \(a.site.name), clear \(Copy.hhmm(w.start, site: site))–\(Copy.hhmm(w.end, site: site)) →")
                        .font(.caption).foregroundStyle(Theme.accent).multilineTextAlignment(.leading)
                }.buttonStyle(.plain)
            }
        }
    }
```

and call `awayLine(site)` right after `verdict(plan, site)` in `body`.

- [ ] **Step 3: Settings section**

Add before the App section:

```swift
            Section("Dark sites") {
                Toggle("Look for darker skies nearby", isOn: bind(\.darkSites.enabled))
                Picker("Distance unit", selection: bind(\.darkSites.unit)) { Text("Kilometres").tag(DistanceUnit.km); Text("Miles").tag(DistanceUnit.mi) }
                stepperRow("Search radius", value: Geo.format(km: store.config.darkSites.radiusKm, unit: store.config.darkSites.unit),
                           binding: bind(\.darkSites.radiusKm), range: 5...300, step: 5)
                Text("Certified places plus the darkest spots on the bundled light-pollution grid. Tonight's forecast is fetched for the nearest eight.").font(.caption).foregroundStyle(Theme.dim)
            }
```

- [ ] **Step 4: About and NOTICE**

Append to `NOTICE`:

```
Dark-sky places: certification by DarkSky International (darksky.org) and the UK Dark Sky Discovery Sites programme; list compiled by the Nightwatch project with coordinates from Wikidata (CC0).
Light-pollution grid derived from the NOAA/NASA Earth Observation Group VIIRS Nighttime Lights annual composite, CC BY 4.0. https://eogdata.mines.edu/products/vnl/
```

In `AboutView`, under the attribution line, add: `Text("Darkness bands (Very dark to Bright) are Nightwatch's own thresholds on VIIRS upward radiance, not a Bortle class.").font(.caption2).foregroundStyle(Theme.dim)`.

- [ ] **Step 5: Build, relaunch, check**

```bash
scripts/build-app.sh
```

Expected: Targets sidebar shows "Dark sites" with a count; cards render with score, distance and window; the popover shows the away line only when a site scores 20 above home; Settings shows the section. Take notes of what was seen for the report.

- [ ] **Step 6: Commit**

```bash
git add Sources/Nightwatch NOTICE
git commit -m "feat(app): dark sites group, popover away line, settings and attribution"
```

---

### Task 8: The UK grid, README, UAT, tag

**Files:**
- Create: `Sources/SkyCore/Resources/lightpollution/gb.lpgrid` (from the owner's VIIRS download)
- Modify: `README.md`, `docs/uat.md`

- [ ] **Step 1: Build the grid (needs the owner's file)**

The owner downloads the latest VIIRS annual "average_masked" GeoTIFF for the whole globe from https://eogdata.mines.edu/products/vnl/ (free EOG account) and places it anywhere. Then:

```bash
.venv/bin/python scripts/build-lp-grid.py /path/to/VNL_*average_masked*.tif --bbox 49.8,-8.7,60.9,1.8 --cell 0.01 --out Sources/SkyCore/Resources/lightpollution/gb.lpgrid
ls -la Sources/SkyCore/Resources/lightpollution/gb.lpgrid     # about 4.7 MB
```

If the file is not available when this task runs, report BLOCKED for this step only, complete Steps 2 to 4, and leave the tag for after the grid lands. The app works without the grid (certified places only).

- [ ] **Step 2: README**

Add a "Dark-sky sites" section: what is listed, the radius setting, the band caveat, how to build a grid for another country (the two commands above with a different bbox), and the attribution.

- [ ] **Step 3: UAT**

Append to `docs/uat.md`:

```
9. Targets › Dark sites lists the Yorkshire Dales and North York Moors from the Sheffield test site at 120 km, each with tonight's score. → pass.
10. Settings › Dark sites › radius 20 km → the list empties or shrinks within one Patrol. → pass.
11. A card's "Use as beat" adds the site under Beats and the popover header changes to it. → pass.
12. With the grid installed, at least one "Dark spot" card appears within 50 km of a rural site. → pass.
```

- [ ] **Step 4: Verify and tag**

```bash
scripts/test.sh | tail -1
scripts/build-app.sh
git add -A && git commit -m "docs: dark-sky sites README and UAT"
git tag -a v0.2.0 -m "Men at Arms"
```

---

## Self-review against the spec

- §1 criteria: 1 (Tasks 4, 6, 7), 2 (Tasks 5, 7), 3 (Task 6 `adoptAsBeat`, Task 7 button), 4 (Tasks 5, 7), 5 (bundled data, cached forecasts).
- §4.1 certified JSON and build script: Task 4. §4.2 grid format and script: Tasks 2, 3, 8. §4.3 bands: Task 2.
- §5.1 modules: Geo (1), LPGrid (2), DarkSites (4), SiteComparison and Config (5). §5.2 app: Store (6), views (7). §5.3 failure handling: Task 6 forecastMissing, Task 7 empty state. §5.4 tests: Tasks 1, 2, 3, 4, 5.
- Names used consistently: `Geo.distanceKm`, `Geo.bearingDeg(from:to:)`, `Geo.compass`, `Geo.format(km:unit:)`, `LPGrid(data:)`, `LPGrid.darkestSpots(center:radiusKm:count:minSpacingKm:)`, `LPGrids.bundled()`, `DarkSites.sites(near:radiusKm:certified:grids:maxSpots:)`, `DarkSites.toSite(_:timeZoneID:)`, `SiteComparison.bestAway(home:sites:margin:)`, `SiteComparison.sorted(_:)`, `Store.adoptAsBeat(_:)`, `Config.darkSites`.
