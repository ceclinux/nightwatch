import Testing
import Foundation
@testable import SkyCore

private let moor = Site(name: "Moor", latitude: 54.06, longitude: -2.15, elevationM: 200, timeZoneID: "Europe/London", bortle: 2)

private struct FakeElevation: Fetcher {
    let failFirst: Int
    let height: @Sendable (Double, Double) -> Double
    let calls = Counter()
    final class Counter: @unchecked Sendable { var n = 0 }
    func get(_ url: URL) async throws -> Data {
        calls.n += 1
        if calls.n <= failFirst { throw URLError(.badServerResponse) }
        let q = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        let lats = q.first { $0.name == "latitude" }!.value!.split(separator: ",").compactMap { Double($0) }
        let lons = q.first { $0.name == "longitude" }!.value!.split(separator: ",").compactMap { Double($0) }
        let e = zip(lats, lons).map { height($0, $1) }
        return try JSONEncoder().encode(["elevation": e])
    }
}

@Test func theHillsAreTheHighestAngleToTheLandInEachDirection() throws {
    let pts = Terrain.samplePoints(around: moor)
    #expect(pts.count == 289 && pts[0] == Coordinate(latitude: 54.06, longitude: -2.15))
    // A ridge 100 m above the site, 2 km to the north only.
    var e = Array(repeating: 200.0, count: pts.count)
    let per = 36
    for o in 0..<3 { e[1 + 0 * per + o * 12 + 4] = 300 }        // N, each bearing, 2 km
    let h = try #require(Terrain.horizon(elevations: e))
    #expect(abs(h[0] - (atan2(98.5, 2000) * 180 / .pi - 2 / (2 * Geo.earthRadiusKm) * 180 / .pi)) < 0.001)   // about 2.8°
    #expect(h[1...].allSatisfy { $0 == 0 })                     // flat land elsewhere: never below 0
    #expect(Terrain.horizon(elevations: [1, 2, 3]) == nil)
}

@Test func theTerrainFetchesInBatchesAndRetriesARefusal() async throws {
    let f = FakeElevation(failFirst: 1) { lat, _ in lat > 54.07 ? 400 : 200 }    // higher ground to the north
    let h = try await Terrain.fetch(site: moor, fetcher: f, retryWait: .zero, pause: .zero)
    #expect(f.calls.n == 4)                                      // 289 points: three batches, one refused and retried
    #expect(h[0] > 3 && h[4] == 0)
    let refused = FakeElevation(failFirst: 9) { _, _ in 0 }
    await #expect(throws: (any Error).self) { try await Terrain.fetch(site: moor, fetcher: refused, retryWait: .zero, pause: .zero) }
}

@Test func theHillsOnlyEverRaiseADirection() {
    var s = moor
    #expect(Terrain.raises(terrain: [6, 6, 4, 3, 2, 3, 6, 7], site: s, openDeg: 30).isEmpty)
    #expect(Terrain.raises(terrain: [6, 6, 4, 3, 34, 3, 6, 7], site: s, openDeg: 30) == [4: 35])
    s.horizon = [20, 20, 20, 20, 40, 20, 20, 20]
    #expect(Terrain.raises(terrain: [6, 22, 4, 3, 34, 3, 6, 7], site: s, openDeg: 30).isEmpty)          // under the go rule and the house
    #expect(Terrain.raises(terrain: [6, 22, 4, 3, 34, 3, 6, 7], site: s, openDeg: 15) == [1: 25])       // with the go rule lowered
}

@Test func theTerrainSummaryNamesTheHighestHills() {
    #expect(Copy.terrainSummary([6.5, 6.1, 4.4, 3.1, 1.6, 3.2, 6.3, 6.9]) == "Hills reach 7° to the N and NW, 6° to the NE and W")
    #expect(Copy.terrainSummary(Array(repeating: 0.2, count: 8)) == "No hills above the horizon around here")
}
