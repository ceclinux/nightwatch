import Testing
import Foundation
@testable import SkyCore

private let testSite = Site(name: "Test site", latitude: 54.0, longitude: -1.5, elevationM: 100, timeZoneID: "Europe/London", bortle: 5)
private let copy = Copy()

private func hours(from t0: Date, _ cloud: [Int]) -> [HourlyConditions] {
    cloud.enumerated().map { i, c in
        HourlyConditions(time: t0.addingTimeInterval(Double(i) * 3600), cloudTotal: c, cloudLow: nil, cloudMid: nil, cloudHigh: nil,
                         tempC: nil, dewPointC: nil, humidityPct: nil, windKmh: nil, gustKmh: nil, visibilityM: nil, seeing: nil, transparency: nil)
    }
}
/// Plans for a test-site night from `day` (12:00 UTC), hourly cloud from 17:00 UTC that day.
private func plans(_ day: Date, _ cloud: [Int], bright: Bool = false) throws -> (NightPlan, NightPlan) {
    let night = try Ephemeris.night(localDate: day, site: testSite)
    let next = try Ephemeris.night(localDate: day.addingTimeInterval(86_400), site: testSite)
    let fc = Forecast(fetchedAt: day, latitude: testSite.latitude, longitude: testSite.longitude,
                      hours: hours(from: day.addingTimeInterval(5 * 3600), cloud + cloud), seeingSource: nil)
    var b = BrightSettings(); b.enabled = bright
    func p(_ n: Night) -> NightPlan {
        Planner.plan(night: n, forecast: fc, catalog: Catalog(objects: []), constellations: [], site: testSite,
                     fov: FieldOfView(widthDeg: 2.1, heightDeg: 1.2), rule: GoRule(), bright: b)
    }
    return (p(night), p(next))
}
private func snap(_ p: NightPlan, _ t: NightPlan?, fetchedAt: Date = Date()) -> WidgetSnapshot {
    WidgetSnapshot.make(plan: p, tomorrow: t, fetchedAt: fetchedAt, site: testSite, rule: GoRule(), bright: BrightSettings(), alerts: AlertSettings(), copy: copy)
}
private let november = utc(2026, 11, 20, 12, 0)
private let clearMiddle = [90, 90, 90, 10, 10, 10, 10, 10, 10, 90, 90, 90, 90, 90, 90, 90, 90, 90, 90, 90, 90, 90, 90, 90]

@Test func snapshotForAClearNight() throws {
    let (p, t) = try plans(november, clearMiddle)
    let s = snap(p, t)
    #expect(s.headline == "Clear window tonight")
    #expect(s.window == "20:00–02:00 · 6.0 h" && s.windowShort == "Clear 20:00–02:00")
    #expect(s.slots.count == 60 && !s.bars.isEmpty && s.notifyShort == "notify 19:30")
    #expect(s.brightList == nil && s.source == nil)
    #expect(s.targets.count <= 3 && s.siteName == "Test site" && s.tomorrow == nil)
}

@Test func snapshotForNoWindow() throws {
    let cloudy = Array(repeating: 90, count: 24)
    let (p, t) = try plans(november, cloudy)
    #expect(p.primary == nil)
    let s = snap(p, t)
    #expect(s.headline == copy.noWindow && s.window == nil && s.notifyShort == nil)
    #expect(s.reason == Planner.noWindowReasonText(plan: p, rule: GoRule(), bright: BrightSettings(), site: testSite))
    #expect(s.tomorrow == nil)                                                    // tomorrow is cloudy too
    let (clearTomorrow, _) = try plans(november.addingTimeInterval(86_400), clearMiddle)
    #expect(snap(p, clearTomorrow).tomorrow == "Tomorrow 20:00–02:00")
}

@Test func snapshotWithNoDarkness() throws {
    let (p, t) = try plans(utc(2026, 6, 21, 12, 0), Array(repeating: 5, count: 24))
    #expect(!p.night.hasDarkness)
    let s = snap(p, t)
    #expect(s.headline == "No astronomical darkness")
    #expect(s.window == nil && s.bars.isEmpty && s.slots.allSatisfy { $0 == .daylight })
    // The popover never shows a Tomorrow line under "No astronomical darkness", even when tomorrow has a window.
    let (clearTomorrow, _) = try plans(november.addingTimeInterval(86_400), clearMiddle)
    #expect(snap(p, clearTomorrow).tomorrow == nil)
}

@Test func snapshotForABrightNight() throws {
    let (p, t) = try plans(utc(2026, 7, 30, 12, 0), Array(repeating: 5, count: 24), bright: true)
    #expect(p.mode == .bright && p.primary != nil)
    let s = snap(p, t)
    #expect(s.headline == "Bright night: Moon and planets")
    #expect(s.windowShort?.hasPrefix("Bright ") == true)
    #expect(s.targets.map(\.id) == Array(p.brightTargets.prefix(3)).map(\.id))
    #expect(s.brightList == Copy.brightList(p.brightTargets) && s.brightList?.isEmpty == false)
}

@Test func snapshotCarriesSourceAndDecodesWithoutNewFields() throws {
    let (p, t) = try plans(november, clearMiddle)
    let s = WidgetSnapshot.make(plan: p, tomorrow: t, fetchedAt: november, site: testSite, rule: GoRule(), bright: BrightSettings(),
                                alerts: AlertSettings(), copy: copy, source: "Apple Weather")
    #expect(s.source == "Apple Weather")
    // A widget.json written by the first v0.6 build has no notifyShort, brightList or source: it must still decode.
    let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
    var obj = try JSONSerialization.jsonObject(with: e.encode(s)) as! [String: Any]
    for k in ["notifyShort", "brightList", "source", "updated"] { obj.removeValue(forKey: k) }
    let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
    let old = try d.decode(WidgetSnapshot.self, from: JSONSerialization.data(withJSONObject: obj))
    #expect(old.source == nil && old.headline == s.headline)
}

@Test func sampleSnapshotIsWellFormed() {
    let s = WidgetSnapshot.sample
    #expect(s.slots.count == 60 && s.bars.count == 8 && s.bars.filter(\.peak).count == 1 && s.windowShort != nil)
}

@Test func snapshotCarriesAgreement() throws {
    var (p, t) = try plans(november, clearMiddle)
    p.agreement = .cloudFrom(utc(2026, 11, 21, 0, 0))
    let s = snap(p, t)
    // A disagreement is the popover's plain line; agreement keeps its own.
    #expect(s.agreement == "Less certain: a second forecast sees cloud from 00:00." && s.agreementWarns)
    p.agreement = .agree
    let agreed = snap(p, t)
    #expect(agreed.agreement == "Open-Meteo agrees" && !agreed.agreementWarns)
}

@Test func snapshotStaleText() throws {
    let (p, t) = try plans(november, clearMiddle)
    let s = snap(p, t, fetchedAt: november)
    #expect(s.staleText(now: november.addingTimeInterval(5 * 3600)) == nil)
    #expect(s.staleText(now: november.addingTimeInterval(7 * 3600 + 1200)) == "Forecast 7 h old")
}

@Test func snapshotRoundTrips() throws {
    let (p, t) = try plans(november, clearMiddle)
    let s = snap(p, t, fetchedAt: november)
    // The popover's clock: the site's time zone, 24-hour (12:00 UTC is 12:00 in London in November).
    #expect(s.updated == "Updated 12:00")
    let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
    let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
    #expect(try d.decode(WidgetSnapshot.self, from: e.encode(s)) == s)
}

@Test func widgetLinkRoundTrip() throws {
    for link in [WidgetLink.targets, .plan, .target("NGC7000"), .target("moon"), .target("planet-saturn"), .target("C/2023 A3 +x"), .search("Crescent Nebula"), .search("M 42 & friends?")] {
        #expect(WidgetLink(url: link.url) == link)
    }
    #expect(WidgetLink.targets.url.absoluteString == "nightwatch://targets")
    #expect(WidgetLink.target("NGC7000").url.absoluteString == "nightwatch://target/NGC7000")
    #expect(!WidgetLink.target("C/2023 A3 +x").url.absoluteString.dropFirst("nightwatch://target/".count).contains("/"))
    #expect(WidgetLink(url: URL(string: "https://example.com/targets")!) == nil)
    #expect(WidgetLink(url: URL(string: "nightwatch://unknown")!) == nil)
    #expect(WidgetLink(url: URL(string: "nightwatch://target/")!) == nil)
}

// Aurora on the widget (v0.6.6): the popover's rule — alerts on, at or above the chosen level, published within the hour.
@Test func snapshotCarriesAuroraAtOrAboveTheThreshold() throws {
    let (p, t) = try plans(november, clearMiddle)
    var on = AuroraSettings(); on.enabled = true; on.threshold = .amber
    func make(_ level: AuroraLevel, _ settings: AuroraSettings) -> WidgetSnapshot {
        WidgetSnapshot.make(plan: p, tomorrow: t, fetchedAt: november, site: testSite, rule: GoRule(), bright: BrightSettings(), alerts: AlertSettings(),
                            copy: copy, aurora: AuroraStatus(level: level, updated: november), auroraSettings: settings)
    }
    let amber = make(.amber, on)
    #expect(amber.auroraLine(now: november.addingTimeInterval(600))?.text == "Aurora amber")
    #expect(amber.auroraLine(now: november.addingTimeInterval(600))?.hex == AuroraLevel.amber.hex)
    #expect(amber.auroraLine(now: november.addingTimeInterval(3601)) == nil)            // stale after an hour, as in the popover
    #expect(make(.yellow, on).aurora == nil)                                              // below the chosen level
    var off = on; off.enabled = false
    #expect(make(.red, off).aurora == nil)                                                // alerts off
    #expect(amber.auroraExpires == november.addingTimeInterval(3600))
}

/// A snapshot written before Apple Weather's attribution fields (v1.0.1) still loads, without them.
@Test func aSnapshotWithoutTheAttributionFieldsDecodes() throws {
    var s = WidgetSnapshot.sample
    s.weatherMarkFile = "apple-weather-mark.png"; s.weatherLegalURL = "https://weatherkit.apple.com/legal-attribution.html"
    let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
    let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
    var json = try JSONSerialization.jsonObject(with: enc.encode(s)) as! [String: Any]
    json.removeValue(forKey: "weatherMarkFile"); json.removeValue(forKey: "weatherLegalURL")
    let old = try dec.decode(WidgetSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(old.weatherMarkFile == nil && old.weatherLegalURL == nil && old.score == s.score)
    let back = try dec.decode(WidgetSnapshot.self, from: enc.encode(s))   // ISO dates drop fractions of a second, so compare the fields
    #expect(back.weatherMarkFile == s.weatherMarkFile && back.weatherLegalURL == s.weatherLegalURL)
}

// Siri and Spotlight (#53): spoken answers built from the same snapshot as the widget.
@Test func siriSaysTonightFromTheCachedSnapshot() throws {
    let (p, t) = try plans(november, Array(repeating: 0, count: 24))
    var s = snap(p, t, fetchedAt: november)
    s.source = "Apple Weather"
    let text = Copy.siriTonight(s)
    #expect(text.hasPrefix("Sky score \(s.score) at Test site. "))
    #expect(text.hasSuffix(" Forecast from Apple Weather."))
    #expect(!text.contains("..") && !text.contains(" nil"))
    #expect(Copy.siriTonight(nil) == "Nightwatch has no forecast yet. Open it once to set where you observe.")
}

@Test func siriListsTheBestTargetsAndEvents() throws {
    let (p, t) = try plans(november, Array(repeating: 100, count: 24))
    let cloudy = snap(p, t, fetchedAt: november)
    #expect(Copy.siriBest(cloudy, session: nil, site: testSite).hasSuffix("No targets are suggested tonight."))
    var clearTomorrow = cloudy
    clearTomorrow.tomorrow = "Tomorrow 22:00–01:00"
    #expect(Copy.siriBest(clearTomorrow, session: nil, site: testSite).hasSuffix("No targets are suggested tonight. Tomorrow night looks clear 22:00–01:00."))
    var s = cloudy
    s.targets = [WidgetTarget(id: "M31", catalogueID: "M31", name: "Andromeda Galaxy", best: "Best 00:40 · 64° up", group: .galaxies)]
    #expect(Copy.siriBest(s, session: nil, site: testSite) == "Tonight's best targets: Andromeda Galaxy, best 00:40 · 64° up.")
    #expect(Copy.siriEvents([]) == "No events tonight.")
}

@Test func siriReadsEachClauseOnceWithOneFullStop() throws {
    // Cloudy tonight, clear tomorrow: the reason and "Tomorrow …" once each, not "Tomorrow: Tomorrow".
    let (p, t) = try plans(november, Array(repeating: 100, count: 24))
    let (_, clearTomorrow) = try plans(november, Array(repeating: 0, count: 24))
    var s = snap(p, clearTomorrow, fetchedAt: november)
    s.tomorrow = "Tomorrow 21:10–01:40"
    let cloudy = Copy.siriTonight(s)
    #expect(cloudy.contains(" Tomorrow 21:10–01:40.") && !cloudy.contains("Tomorrow: ") && !cloudy.contains(".."))
    // A reason without its own full stop gets one.
    s.reason = "Held back by a 40% moon"
    #expect(Copy.siriTonight(s).contains("Held back by a 40% moon. "))
    _ = t
}
