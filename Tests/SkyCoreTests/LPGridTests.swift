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
    #expect(back.rows == 3 && back.cols == 3)
    #expect(abs(back.cellDeg - 0.1) < 1e-6)
    #expect(back.values[0] == 5 && back.values[8] == 40 && back.values[4].isNaN)
    #expect(g.encoded().count == 20 + 9 * 4)
    #expect(String(decoding: g.encoded().prefix(4), as: UTF8.self) == "LPG1")
}

@Test func rejectsBadData() {
    #expect(throws: LPGridError.self) { try LPGrid(data: Data("nope".utf8)) }
    #expect(throws: LPGridError.self) { try LPGrid(data: sampleGrid().encoded().prefix(20)) }
}

@Test func rejectsHeaderOnlyInput() {
    #expect(throws: LPGridError.self) { try LPGrid(data: sampleGrid().encoded().prefix(17)) }
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
    #expect(abs(spots[0].radiance - 0.1) < 1e-6)   // darkest first
    #expect(abs(spots[1].radiance - 0.2) < 1e-6)
    #expect(abs(spots[2].radiance - 0.5) < 1e-6)
    #expect(spots.allSatisfy { Geo.distanceKm(centre, $0.coordinate) <= 30 })
    for i in 0..<spots.count { for j in (i + 1)..<spots.count { #expect(Geo.distanceKm(spots[i].coordinate, spots[j].coordinate) >= 5) } }
    let tight = g.darkestSpots(center: centre, radiusKm: 8, count: 3, minSpacingKm: 5)
    #expect(tight.count <= 2)          // only the centre's neighbours are within 8 km
    // The grid's own longest diagonal (opposite corners, e.g. row0/col2 to row2/col0) is
    // ~25.93 km by great-circle distance — verified against Geo.distanceKm, the same
    // formula GeoTests.swift checks against independently-computed reference values.
    // 25 km undershoots that by under a kilometre, which isn't "larger than the grid";
    // 26 km safely exceeds it, matching this test's documented intent.
    let spaced = g.darkestSpots(center: centre, radiusKm: 30, count: 3, minSpacingKm: 26)
    #expect(spaced.count == 1)         // spacing larger than the grid
}

@Test func loadsScriptOutput() throws {
    let g = try LPGrid(data: try fixture("synthetic.lpgrid"))
    #expect(g.rows == 20 && g.cols == 30)
    #expect(g.radiance(at: Coordinate(latitude: 59.75, longitude: -9.75)) == 40)
    #expect(g.radiance(at: Coordinate(latitude: 50.25, longitude: 4.75))! < 0.11)
}

@Test func equalZeroCellsTieToTheNearest() {
    // 21 × 21 cells of exactly 0 (VIIRS masked zeros), 0.01° cells; home at the centre cell (10, 10).
    let g = LPGrid(south: 53.0, west: -2.0, cellDeg: 0.01, rows: 21, cols: 21, values: [Float](repeating: 0, count: 21 * 21))
    let home = Coordinate(latitude: 53.105, longitude: -1.895)
    let spots = g.darkestSpots(center: home, radiusKm: 15, count: 3, minSpacingKm: 1)
    #expect(spots.count == 3)
    #expect(Geo.distanceKm(home, spots[0].coordinate) < 0.01)   // the home cell itself, not the southern rim
    let d = spots.map { Geo.distanceKm(home, $0.coordinate) }
    #expect(d == d.sorted())                                    // nearest first among equals
    #expect(d.allSatisfy { $0 < 2 })
}

/// Add a site suggests the sky's darkness from the grid, with the same band-to-Bortle mapping the dark sites use
/// (place search, 30 September 2026).
@Test func addASiteSuggestsBortleFromTheGrid() {
    #expect(DarknessBand.allCases.map(\.bortle) == [2, 3, 4, 6, 8])
    let g = [sampleGrid()]
    #expect(DarkSites.suggestedBortle(at: Coordinate(latitude: 53.05, longitude: -1.75), grids: g) == 2)   // 0.1: very dark
    #expect(DarkSites.suggestedBortle(at: Coordinate(latitude: 53.25, longitude: -1.75), grids: g) == 8)   // 40: bright
    #expect(DarkSites.suggestedBortle(at: Coordinate(latitude: 40.0, longitude: -74.0), grids: g) == nil)  // outside the grid
}

// MARK: the world grid (#138)

/// A compact grid file (LPG2), as `scripts/build-lp-grid.py --world` writes it: the usual header, then a byte per cell.
private func compactGrid(south: Float, west: Float, cell: Float, rows: UInt16, cols: UInt16, bytes: [UInt8]) -> Data {
    var d = Data("LPG2".utf8)
    for v in [south, west, cell] { var le = v.bitPattern.littleEndian; d.append(Data(bytes: &le, count: 4)) }
    for n in [rows, cols] { var le = n.littleEndian; d.append(Data(bytes: &le, count: 2)) }
    d.append(contentsOf: bytes)
    return d
}

@Test func aCompactGridReadsItsLogScaleAndNoData() throws {
    let data = compactGrid(south: 10, west: 20, cell: 0.5, rows: 2, cols: 3, bytes: [0, 51, 101, 171, 235, 255])
    // Read from the middle of a larger buffer too, as a slice keeps its parent's indices.
    for source in [data, (Data([9, 9, 9]) + data).dropFirst(3)] {
        let g = try LPGrid(data: source)
        #expect(g.rows == 2 && g.cols == 3 && g.values.isEmpty)
        func at(_ r: Int, _ k: Int) -> Double? {
            g.radiance(at: Coordinate(latitude: 10.25 + 0.5 * Double(r), longitude: 20.25 + 0.5 * Double(k)))
        }
        #expect(at(0, 0) == 0)
        for (cell, want) in [((0, 1), 0.25), ((0, 2), 1.0), ((1, 0), 5.0), ((1, 1), 20.0)] {
            let got = try #require(at(cell.0, cell.1))
            #expect(abs(got - want) / want < 0.02)   // the scale's steps are about 2%
        }
        #expect(at(1, 2) == nil)                      // 255: no data
        #expect(g.encoded() == data)
    }
    #expect(throws: LPGridError.self) { try LPGrid(data: data.dropLast()) }
}

@Test func theFinerGridAnswersWhereTwoOverlap() throws {
    let fine = LPGrid(south: 53.0, west: -2.0, cellDeg: 0.1, rows: 3, cols: 3, values: [Float](repeating: 0.1, count: 9))                  // very dark
    let coarse = try LPGrid(data: compactGrid(south: 50, west: -5, cell: 1, rows: 6, cols: 8, bytes: [UInt8](repeating: 235, count: 48)))   // bright
    let grids = LPGrids.finestFirst([coarse, fine])
    #expect(grids.first?.cellDeg == 0.1)
    let inside = Coordinate(latitude: 53.15, longitude: -1.85), outside = Coordinate(latitude: 51.5, longitude: -3.5)
    #expect(LPGrids.radiance(at: inside, in: grids).map(DarknessBand.from) == .veryDark)
    #expect(LPGrids.radiance(at: outside, in: grids).map(DarknessBand.from) == .bright)
    // Spots come from one grid only: the fine one's nine cells here, never the coarse grid's as well.
    let near = LPGrids.darkestSpots(center: inside, radiusKm: 200, count: 20, minSpacingKm: 1, in: grids)
    #expect(near.count == 9)
    let allVeryDark = near.allSatisfy { $0.band == .veryDark }
    #expect(allVeryDark)
    let far = LPGrids.darkestSpots(center: outside, radiusKm: 100, count: 3, minSpacingKm: 1, in: grids)
    let allBright = far.allSatisfy { $0.band == .bright }
    #expect(far.count == 3 && allBright)
    #expect(LPGrids.darkestSpots(center: Coordinate(latitude: 0, longitude: 100), radiusKm: 100, count: 3, minSpacingKm: 1, in: grids).isEmpty)
}

/// The real world grid, as the app ships it (Resources/LightPollution/world.lpgrid, built 3 October 2026 from the 2025
/// composite): cities, dark country, a coastal town and the open sea, and dark spots near a city outside Britain.
@Test func theWorldGridTellsCitiesFromDarkCountry() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let world = try #require(LPGrids.load(root.appendingPathComponent("Resources/LightPollution/world.lpgrid")))
    #expect(world.rows == 2800 && world.cols == 7200 && abs(world.cellDeg - 0.05) < 1e-6)
    #expect(abs(world.south + 65) < 0.01 && abs(world.west + 180) < 0.01)
    func band(_ lat: Double, _ lon: Double) -> DarknessBand? {
        world.radiance(at: Coordinate(latitude: lat, longitude: lon)).map(DarknessBand.from)
    }
    #expect(band(48.857, 2.352) == .bright)        // central Paris
    #expect(band(35.68, 139.76) == .bright)        // central Tokyo
    #expect(band(64.147, -21.94) == .bright)       // Reykjavik: on the coast, so its cell is partly sea
    #expect(band(40.30, -5.15) == .veryDark)       // Sierra de Gredos, Spain
    #expect(band(-31.27, 149.00) == .veryDark)     // Warrumbungle National Park, Australia
    #expect(band(53.50, -9.80) == .veryDark)       // Connemara: west of the British grid's edge
    #expect(band(45.0, -30.0) == nil)              // mid-Atlantic
    #expect(band(80.0, 20.0) == nil)               // north of the data

    // Britain keeps its own finer grid: at Malham the British grid answers, not the world's.
    let grids = LPGrids.finestFirst(LPGrids.bundled() + [world])
    #expect(grids.count == 2 && grids[0].cellDeg < 0.01)
    let malham = Coordinate(latitude: 54.07, longitude: -2.15)
    #expect(LPGrids.radiance(at: malham, in: grids) == grids[0].radiance(at: malham))

    // Dark spots within 100 km of central Madrid: five, each darker than the city and at least 10 km apart.
    let madrid = Coordinate(latitude: 40.417, longitude: -3.704)
    let sites = DarkSites.sites(near: madrid, radiusKm: 100, certified: [], grids: grids, maxSpots: 5)
    #expect(sites.count == 5)
    let allDark = sites.allSatisfy { $0.isComputed && ($0.band == .veryDark || $0.band == .dark) && $0.distanceKm <= 100 }
    #expect(allDark)
    #expect(DarkSites.suggestedBortle(at: madrid, grids: grids) == 8)
}
