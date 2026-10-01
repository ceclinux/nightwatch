import Testing
import Foundation
@testable import SkyCore

private let open = Site(name: "Garden", latitude: 53.9, longitude: -1.7, elevationM: 100, timeZoneID: "Europe/London", bortle: 5)
private func walled(_ h: [Double]) -> Site { var s = open; s.horizon = h; return s }

@Test func aHorizonIsReadByCompassDirection() {
    let s = walled([30, 31, 32, 33, 34, 35, 36, 37])
    #expect(s.horizonDeg(azimuthDeg: 0) == 30 && s.horizonDeg(azimuthDeg: 359) == 30 && s.horizonDeg(azimuthDeg: 22.4) == 30)
    #expect(s.horizonDeg(azimuthDeg: 22.6) == 31 && s.horizonDeg(azimuthDeg: 180) == 34 && s.horizonDeg(azimuthDeg: 315) == 37)
    #expect(s.horizonDeg(azimuthDeg: -45) == 37)
    #expect(open.horizonDeg(azimuthDeg: 180) == nil)
}

@Test func theHorizonReplacesTheGoRuleButOnlyRaisesALowerFloor() {
    let s = walled([20, 30, 30, 30, 45, 30, 30, 30])
    #expect(s.floorDeg(azimuthDeg: 0, minAlt: 30, replacesFloor: true) == 20)    // lower than usual to the north
    #expect(s.floorDeg(azimuthDeg: 180, minAlt: 30, replacesFloor: true) == 45)  // the house to the south
    #expect(s.floorDeg(azimuthDeg: 0, minAlt: 10, replacesFloor: false) == 20)   // the Moon: raised to the horizon
    #expect(s.floorDeg(azimuthDeg: 0, minAlt: 25, replacesFloor: false) == 25)
    #expect(open.floorDeg(azimuthDeg: 180, minAlt: 30, replacesFloor: true) == 30)
}

@Test func aBlockedSouthShortensWhenATargetCountsAsUp() throws {
    let night = try Ephemeris.night(localDate: utc(2026, 10, 1, 12, 0), site: open)
    let w = ClearWindow(start: night.darkStart!, end: night.darkEnd!)
    // Altair: low in the south-west through the evening.
    let plain = Planner.track(raHours: 19.846, decDeg: 8.87, window: w, site: open, minAlt: 30)
    let house = Planner.track(raHours: 19.846, decDeg: 8.87, window: w, site: walled([30, 30, 30, 30, 45, 45, 30, 30]), minAlt: 30)
    let v = try #require(plain.viewable)
    #expect(house.fraction < plain.fraction)
    #expect(house.viewable.map { $0.end < v.end } ?? true)
}

@Test func aSiteSavedBeforeHorizonsStillDecodesAndRoundTrips() throws {
    let old = #"{"name":"Garden","latitude":53.9,"longitude":-1.7,"elevationM":100,"timeZoneID":"Europe/London","bortle":5}"#
    let s = try JSONDecoder().decode(Site.self, from: Data(old.utf8))
    #expect(s.horizon == nil)
    let w = walled([30, 30, 30, 40, 45, 45, 30, 20])
    #expect(try JSONDecoder().decode(Site.self, from: JSONEncoder().encode(w)) == w)
}

@Test func theSettingsRowSummarisesTheHorizon() {
    #expect(Copy.horizonSummary(open, openDeg: 30) == "Horizon: open sky")
    #expect(Copy.horizonSummary(walled(Array(repeating: 30, count: 8)), openDeg: 30) == "Horizon: open sky")
    #expect(Copy.horizonSummary(walled([30, 30, 25, 40, 45, 45, 30, 20]), openDeg: 30) == "Horizon: 45° S, SW · 40° SE · 25° E · 20° NW")
}
