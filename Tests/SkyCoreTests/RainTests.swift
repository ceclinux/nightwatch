import Testing
import Foundation
@testable import SkyCore

// Rain after the clear window (#180): for a telescope left running outside, the first hour before sunrise with rain likely.

private let testSite = Site(name: "Test site", latitude: 54.0, longitude: -1.5, elevationM: 100, timeZoneID: "Europe/London", bortle: 5)
private let t0 = utc(2026, 11, 20, 17, 0)   // a November night in GMT, so UTC is local

/// Hours from 17:00 with the given cloud and chance of rain.
private func hours(cloud: [Int], rain: [Int?]) -> [HourlyConditions] {
    zip(cloud, rain).enumerated().map { i, v in
        var h = HourlyConditions(time: t0.addingTimeInterval(Double(i) * 3600), cloudTotal: v.0, cloudLow: nil, cloudMid: nil, cloudHigh: nil,
                                 tempC: nil, dewPointC: nil, humidityPct: nil, windKmh: nil, gustKmh: nil, visibilityM: nil, seeing: nil, transparency: nil)
        h.rainChancePct = v.1
        return h
    }
}
/// 17:00 … 07:00: cloudy until 20:00, clear 20:00–02:00, cloudy after.
private let cloud = [90, 90, 90, 10, 10, 10, 10, 10, 10, 90, 90, 90, 90, 90, 90]
private func plan(rain: [Int?], cloud c: [Int] = cloud) throws -> NightPlan {
    let night = try Ephemeris.night(localDate: utc(2026, 11, 20, 12, 0), site: testSite)
    return Planner.plan(night: night, forecast: Forecast(fetchedAt: t0, latitude: testSite.latitude, longitude: testSite.longitude, hours: hours(cloud: c, rain: rain), seeingSource: nil),
                        catalog: Catalog(objects: []), constellations: [], site: testSite, fov: FieldOfView(widthDeg: 2.1, heightDeg: 1.2), rule: GoRule())
}
private func rain(_ at: [Int: Int]) -> [Int?] { (0..<cloud.count).map { at[$0] ?? 0 } }

@Test func rainIsTheFirstLikelyHourBetweenTheWindowOpeningAndSunrise() {
    let window = ClearWindow(start: t0.addingTimeInterval(3 * 3600), end: t0.addingTimeInterval(9 * 3600))   // 20:00–02:00
    let sunrise = t0.addingTimeInterval(14.5 * 3600)                                                          // 07:30
    func from(_ r: [Int: Int]) -> Date? { Planner.rainFrom(hours: hours(cloud: cloud, rain: rain(r)), window: window, sunrise: sunrise) }
    #expect(from([10: 60, 12: 90]) == utc(2026, 11, 21, 3, 0))            // the first of two, after the window has closed
    #expect(from([10: Planner.rainRiskPct]) == utc(2026, 11, 21, 3, 0))   // the level itself counts
    #expect(from([10: Planner.rainRiskPct - 1]) == nil)                   // just under it does not
    #expect(from([1: 80]) == nil)                                         // rain that ends before the window opens is not the worry
    #expect(from([:]) == nil)
    // An hour that starts before sunrise counts; a forecast with no rain chance says nothing.
    #expect(from([14: 70]) == utc(2026, 11, 21, 7, 0))
    #expect(Planner.rainFrom(hours: hours(cloud: cloud, rain: cloud.map { _ in nil }), window: window, sunrise: sunrise) == nil)
    // The window opening part-way through a wet hour: the line never names a time before the window.
    let late = ClearWindow(start: t0.addingTimeInterval(3.5 * 3600), end: window.end)
    #expect(Planner.rainFrom(hours: hours(cloud: cloud, rain: rain([3: 40])), window: late, sunrise: sunrise) == late.start)
    // Rain after sunrise is somebody else's forecast.
    #expect(Planner.rainFrom(hours: hours(cloud: cloud, rain: rain([14: 70])), window: window, sunrise: t0.addingTimeInterval(14 * 3600)) == nil)
}

@Test func thePlanCarriesTheRainTimeOnlyWithAClearWindow() throws {
    let wet = try plan(rain: rain([10: 60]))
    #expect(wet.primary != nil)
    #expect(wet.rainFrom == utc(2026, 11, 21, 3, 0))
    #expect(try plan(rain: rain([:])).rainFrom == nil)
    // No clear window: nothing to leave a telescope out for, so nothing is said.
    let cloudy = try plan(rain: rain([10: 60]), cloud: cloud.map { _ in 90 })
    #expect(cloudy.primary == nil && cloudy.rainFrom == nil)
}

@Test func theRainLineIsOneSentenceInThePopoverAndAtTheEndOfTonightsNotifications() throws {
    var wet = try plan(rain: rain([10: 60]))
    #expect(Copy.rain(wet, site: testSite) == "Rain possible from 03:00")
    let copy = Copy()
    #expect(copy.notificationBody(plan: wet, site: testSite).hasSuffix(" Rain possible from 03:00."))
    // After the second opinion, and never in the tomorrow preview.
    wet.agreement = .agree
    #expect(copy.notificationBody(plan: wet, site: testSite).hasSuffix(" Open-Meteo agrees. Rain possible from 03:00."))
    #expect(!copy.notificationBody(plan: wet, site: testSite, agreement: false).contains("Rain"))
    let dry = try plan(rain: rain([:]))
    #expect(Copy.rain(dry, site: testSite) == nil)
    #expect(!copy.notificationBody(plan: dry, site: testSite).contains("Rain"))
}

@Test func theHeadsUpAndTheNudgeEndWithTheRainLine() throws {
    let wet = try plan(rain: rain([10: 60]))
    let settings = AlertSettings(), copy = Copy()
    let due = wet.night.sunset.addingTimeInterval(-3600 + 60)
    let headsUp = AlertEngine.step(now: due, tonight: wet, tomorrow: nil, state: nil, settings: settings, forecastFetchedAt: due, site: testSite, copy: copy)
    #expect(headsUp.notification?.kind == .headsUp)
    #expect(headsUp.notification?.body.hasSuffix(" Rain possible from 03:00.") == true)
    let nudge = wet.primary!.start.addingTimeInterval(-29 * 60)
    let go = AlertEngine.step(now: nudge, tonight: wet, tomorrow: nil, state: headsUp.state, settings: settings, forecastFetchedAt: nudge, site: testSite, copy: copy)
    #expect(go.notification?.kind == .go)
    #expect(go.notification?.body.hasSuffix(" Rain possible from 03:00.") == true)
}

@Test func aPlanSavedBeforeTheRainLineStillLoads() throws {
    let wet = try plan(rain: rain([10: 60]))
    let data = try JSONEncoder().encode(wet)
    #expect(try JSONDecoder().decode(NightPlan.self, from: data).rainFrom == wet.rainFrom)
    var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    object.removeValue(forKey: "rainFrom")
    let old = try JSONDecoder().decode(NightPlan.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(old.rainFrom == nil && old.qualifies == wet.qualifies)
}
