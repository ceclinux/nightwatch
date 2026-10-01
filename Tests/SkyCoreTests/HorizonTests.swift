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

@Test func theBestMomentIsTheHighestOneClearOfTheHorizon() throws {
    let night = try Ephemeris.night(localDate: utc(2026, 10, 1, 12, 0), site: open)
    let w = ClearWindow(start: night.darkStart!, end: night.darkEnd!)
    // Altair crosses the south early in the window: with the south walled off, its best moment moves off the meridian.
    let plain = Planner.track(raHours: 19.846, decDeg: 8.87, window: w, site: open, minAlt: 20)
    let walled = walled([20, 20, 20, 20, 80, 20, 20, 20])
    let house = Planner.track(raHours: 19.846, decDeg: 8.87, window: w, site: walled, minAlt: 20)
    #expect(house.peakTime != plain.peakTime && house.peakAlt < plain.peakAlt)
    let (alt, az) = Ephemeris.altAz(raHours: 19.846, decDeg: 8.87, at: house.peakTime, site: walled)
    #expect(alt >= walled.floorDeg(azimuthDeg: az, minAlt: 20, replacesFloor: true))
    let again = Planner.track(raHours: 19.846, decDeg: 8.87, window: w, site: open, minAlt: 20)
    #expect(again.peakTime == plain.peakTime && again.peakAlt == plain.peakAlt)   // no horizon: unchanged
}

@Test func aFavouriteBehindTheHorizonSaysSo() throws {
    let night = try Ephemeris.night(localDate: utc(2026, 10, 1, 12, 0), site: open)
    let w = ClearWindow(start: night.darkStart!, end: night.darkEnd!)
    let fov = FieldOfView(widthDeg: 2.1, heightDeg: 1.2)
    func reason(_ s: Site) -> String? {
        Planner.favouriteTargets(["planet-saturn"], ranked: [], catalog: Catalog(objects: []), constellations: [], stars: [], window: w,
                                 night: night, site: s, fov: fov, rule: GoRule()).first?.notTonight
    }
    #expect(reason(walled(Array(repeating: 85, count: 8))) == "Behind your horizon in tonight's window")
    #expect(reason(open).map { !$0.contains("horizon") } ?? true)
}

@Test func eventsBehindTheHorizonAreMarkedAndLeftOutOfTheHeadsUp() throws {
    let pass = SatellitePass(rise: utc(2026, 10, 1, 19, 10), peak: utc(2026, 10, 1, 19, 14), set: utc(2026, 10, 1, 19, 18),
                             maxElevationDeg: 40, peakAzimuthDeg: 250, riseAzimuthDeg: 300, setAzimuthDeg: 180)
    let house = walled([30, 30, 30, 30, 35, 50, 55, 45])
    #expect(Events.issPass(pass, site: house).behindHorizon)          // 40° in the WSW, under the 55° wall
    #expect(!Events.issPass(pass, site: open).behindHorizon)
    var e = Events.issPass(pass, site: house)
    e.clear = true
    let night = try Ephemeris.night(localDate: utc(2026, 10, 1, 12, 0), site: house)
    #expect(Copy.alsoTonight([e], night: night, site: house) == nil)
    let night2 = try Ephemeris.night(localDate: utc(2026, 10, 1, 12, 0), site: open)
    let hidden = Events.highest(raHours: 19.846, decDeg: 8.87, from: night2.darkStart!, to: night2.darkEnd!, site: walled(Array(repeating: 85, count: 8)))
    #expect(!hidden.clear)
    #expect(Events.highest(raHours: 19.846, decDeg: 8.87, from: night2.darkStart!, to: night2.darkEnd!, site: open).clear)
}

@Test func altitudeSamplesRunSunsetToSunriseAndBoldOnlyWhereClear() throws {
    let night = try Ephemeris.night(localDate: utc(2026, 10, 1, 12, 0), site: open)
    let w = ClearWindow(start: night.darkStart!.addingTimeInterval(3600), end: night.darkStart!.addingTimeInterval(4 * 3600))
    let s = AltitudeTrack.samples(raHours: 19.846, decDeg: 8.87, night: night, window: w, site: open, minAlt: 30)
    #expect(s.first?.time == night.sunset && s.last?.time == night.sunrise && s.first?.fraction == 0 && s.last?.fraction == 1)
    #expect(s.contains { $0.time == w.start } && s.contains { $0.time == w.end })
    let runs = AltitudeTrack.clearRuns(s, window: w)
    #expect(!runs.isEmpty && runs.allSatisfy { $0.allSatisfy { $0.isClear(in: w) && $0.alt >= 30 } })
    #expect(runs.flatMap { $0 }.count == s.filter { $0.isClear(in: w) }.count)
    let walledSite = walled([20, 20, 20, 20, 85, 85, 20, 20])
    let hidden = AltitudeTrack.samples(raHours: 19.846, decDeg: 8.87, night: night, window: w, site: walledSite, minAlt: 30)
    #expect(AltitudeTrack.clearRuns(hidden, window: w).flatMap { $0 }.count < runs.flatMap { $0 }.count)
}
