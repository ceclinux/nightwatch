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
