import Testing
import Foundation
@testable import SkyCore

private let site = Site(name: "Test site", latitude: 54.0, longitude: -1.5, elevationM: 100, timeZoneID: "Europe/London", bortle: 4)

private func forecast(from start: Date, hours: Int, cloud: (Int) -> Int) -> Forecast {
    let hs = (0..<hours).map { i in
        HourlyConditions(time: start.addingTimeInterval(Double(i) * 3600), cloudTotal: cloud(i), cloudLow: nil, cloudMid: nil, cloudHigh: nil,
                         tempC: nil, dewPointC: nil, humidityPct: nil, windKmh: nil, gustKmh: nil, visibilityM: nil, seeing: nil, transparency: nil)
    }
    return Forecast(fetchedAt: start, latitude: site.latitude, longitude: site.longitude, hours: hs, seeingSource: nil)
}

private func plans(_ f: Forecast) throws -> (NightPlan, NightPlan) {
    let n0 = try Ephemeris.night(localDate: utc(2026, 9, 30, 12, 0), site: site)
    let n1 = try Ephemeris.night(localDate: utc(2026, 10, 1, 12, 0), site: site)
    let fov = FieldOfView(widthDeg: 2.1, heightDeg: 1.2)
    return (Planner.plan(night: n0, forecast: f, catalog: Catalog(objects: []), constellations: [], site: site, fov: fov, rule: GoRule()),
            Planner.plan(night: n1, forecast: f, catalog: Catalog(objects: []), constellations: [], site: site, fov: fov, rule: GoRule()))
}

/// The week runs as far as the forecast reaches the end of a night's darkness, and no further (owner's mock-up A, 30 September 2026).
@Test func theWeekStopsWhereTheForecastEnds() throws {
    let start = utc(2026, 9, 30, 6, 0)
    let fov = FieldOfView(widthDeg: 2.1, heightDeg: 1.2)
    let long = forecast(from: start, hours: 238, cloud: { _ in 0 })
    let (t0, t1) = try plans(long)
    let week = Planner.week(tonight: t0, tomorrow: t1, forecast: long, site: site, fov: fov, rule: GoRule(), bright: nil)
    #expect(week.count == 9 || week.count == 10)
    #expect(week.map(\.daysAhead) == Array(0..<week.count))
    #expect(week[0].plan.night.key == "2026-09-30" && week[1].plan.night.key == "2026-10-01" && week[2].plan.night.key == "2026-10-02")
    #expect(week.allSatisfy { $0.plan.primary != nil })   // a cloudless forecast: every night has a window
    #expect(week[2].plan.targets.allSatisfy { $0.group == .planets })   // later nights: no catalogue, so no deep-sky ranking
    // 72 hours from 06:00 reach the end of the third night's darkness; 60 hours stop short of it.
    for (hours, nights) in [(72, 3), (60, 2)] {
        let short = forecast(from: start, hours: hours, cloud: { _ in 0 })
        let (s0, s1) = try plans(short)
        #expect(Planner.week(tonight: s0, tomorrow: s1, forecast: short, site: site, fov: fov, rule: GoRule(), bright: nil).count == nights)
    }
}

/// The week row measures a short run as the window finder does: inside darkness, never as whole forecast hours.
@Test func weekRowMeasuresTheRunInsideDarkness() throws {
    let start = utc(2026, 9, 30, 6, 0)
    let night = try Ephemeris.night(localDate: utc(2026, 9, 30, 12, 0), site: site)
    let ds = try #require(night.darkStart)
    let slot = Int(floor(ds.timeIntervalSince(start) / 3600))   // the forecast hour darkness begins in
    try #require(start.addingTimeInterval(Double(slot) * 3600) != ds)
    let f = forecast(from: start, hours: 72, cloud: { i in (slot..<slot + 3).contains(i) ? 0 : 90 })   // exactly three clear hours
    let p = Planner.plan(night: night, forecast: f, catalog: Catalog(objects: []), constellations: [], site: site,
                         fov: FieldOfView(widthDeg: 2.1, heightDeg: 1.2), rule: GoRule())
    #expect(p.primary == nil)
    let v = Copy.weekVerdict(p, rule: GoRule(), bright: BrightSettings(), site: site)
    #expect(!v.contains("run 3 h"))
    #expect(v.hasPrefix("No clear window · longest clear run 2.") && v.hasSuffix(" h from \(Copy.hhmm(ds, site: site))"))
}

@Test func weekRowsReadPlainly() throws {
    let start = utc(2026, 9, 30, 6, 0)
    // Clear from 22:00 to 01:00 UTC on the first night only: a 3 h run, then cloud.
    let f = forecast(from: start, hours: 72, cloud: { i in (16...18).contains(i) ? 0 : 90 })
    let (t0, t1) = try plans(f)
    let w = try #require(t0.primary)
    #expect(Copy.weekVerdict(t0, rule: GoRule(), bright: BrightSettings(), site: site) == "Clear \(Copy.span(w.start, w.end, site: site)) · \(Copy.hoursText(w.hours))")
    #expect(Copy.weekVerdict(t1, rule: GoRule(), bright: BrightSettings(), site: site) == "No clear window")
    var loose = GoRule(); loose.minHours = 4
    let (l0, _) = (Planner.plan(night: t0.night, forecast: f, catalog: Catalog(objects: []), constellations: [], site: site,
                                fov: FieldOfView(widthDeg: 2, heightDeg: 1), rule: loose), 0)
    #expect(Copy.weekVerdict(l0, rule: loose, bright: BrightSettings(), site: site).hasPrefix("No clear window · longest clear run 3 h from "))
    #expect(Copy.weekDetail(t0, site: site).hasPrefix("Dark ") && Copy.weekDetail(t0, site: site).contains(" · Moon "))
    #expect(!Copy.weekDetail(t0, site: site).contains("seeing"))   // no seeing data, no seeing
    #expect(Copy.weekLead(daysAhead: 2) == nil && Copy.weekLead(daysAhead: 3) == "Less certain · 3 days ahead")
    #expect(Copy.weekDay(WeekNight(plan: t0, daysAhead: 0), site: site) == "Tonight")
    #expect(Copy.weekDay(WeekNight(plan: t1, daysAhead: 1), site: site) == "Tomorrow")
    #expect(Copy.weekDay(WeekNight(plan: t1, daysAhead: 2), site: site) == "Thursday")   // 1 October 2026 is a Thursday
    #expect(Copy.hoursText(5) == "5 h" && Copy.hoursText(4.5) == "4.5 h")
}

@Test func seeingTextMatchesThePopoverBands() {
    func hour(_ s: Int?) -> HourlyConditions {
        HourlyConditions(time: Date(), cloudTotal: 0, cloudLow: nil, cloudMid: nil, cloudHigh: nil, tempC: nil, dewPointC: nil,
                         humidityPct: nil, windKmh: nil, gustKmh: nil, visibilityM: nil, seeing: s, transparency: nil)
    }
    #expect(Copy.seeingText([hour(5), hour(5)]) == "1.25–1.5″")
    #expect(Copy.seeingText([hour(nil)]) == nil)
    #expect(Copy.seeingText([hour(12)]) == ">2.5″")
}

// MARK: highlights (owner, 25 November 2026: "what would be the highlights to see on that one clear night?")

private let frame = FieldOfView(widthDeg: 2.1, heightDeg: 1.2)

/// A night's plan made with the catalogue, clear for `clear` hours from 20:00 that evening and cloudy otherwise.
private func clearNight(_ y: Int, _ m: Int, _ d: Int, hours clear: Int) throws -> NightPlan {
    let night = try Ephemeris.night(localDate: utc(y, m, d, 12, 0), site: site)
    let f = forecast(from: utc(y, m, d, 12, 0), hours: 30, cloud: { (8..<(8 + clear)).contains($0) ? 0 : 100 })
    return Planner.plan(night: night, forecast: f, catalog: try Catalog.bundled(), constellations: try Constellations.bundled(),
                        stars: try BrightStars.bundled(), site: site, fov: frame, rule: GoRule())
}
/// Minutes after noon of the "best HH:MM" a highlight ends with, so times either side of midnight compare.
private func bestMinutes(_ highlight: String) -> Int {
    let p = highlight.suffix(5).split(separator: ":").compactMap { Int($0) }
    return ((p[0] + 12) % 24) * 60 + p[1]
}

@Test func aFourHourWindowNamesOneTargetAndItIsAShowpiece() throws {
    let p = try clearNight(2026, 12, 2, hours: 4)   // the owner's night: clear 20:00–00:00
    #expect(p.primary.map { Copy.span($0.start, $0.end, site: site) } == "20:00–00:00")
    let h = Planner.highlights(plan: p, site: site, fov: frame, showers: try MeteorShowers.bundled())
    #expect(h.count == 1 && h[0].contains(", best ") && !h[0].contains("at peak"))
    let window = try #require(p.primary)
    let pick = try #require(SessionPlanner.suggestions(anchors: [], plan: p, excluding: [], window: window, brightest: true).first)
    #expect(pick.isShowpiece && !pick.isSharplessOnly && pick.fit == .fits && !pick.moonWashed && h[0].contains(pick.catalogueID))
    // One with a name, when one qualifies: by brightness alone it was "M39", a cluster known only by its number.
    #expect(pick.commonName != nil && h[0].hasPrefix(pick.commonName ?? "?") && pick.id != "NGC7092")
    // The brightest that qualifies, not the highest: Tonight's plan still suggests by height, and that night it is a fainter object.
    let highest = try #require(SessionPlanner.suggestions(anchors: [], plan: p, excluding: [], window: window).first)
    #expect(highest.id != pick.id && (pick.magnitude ?? 99) < (highest.magnitude ?? 99) && highest.peakAltDeg > pick.peakAltDeg)
    #expect(Copy.weekHighlights(WeekNight(plan: p, daysAhead: 7, highlights: h)) == "Highlights: " + h[0])
    print("HIGHLIGHT 2 Dec: \(h)")
}

@Test func anEventOfThatNightLeadsAndTheLineStaysAtThree() throws {
    let p = try clearNight(2026, 12, 13, hours: 9)   // the Geminids' peak night
    let h = Planner.highlights(plan: p, site: site, fov: frame, showers: try MeteorShowers.bundled())
    #expect(h.first?.hasPrefix("Geminids at peak, best ") == true)
    #expect(h.count <= Planner.highlightLimit && h.count >= 2)
    print("HIGHLIGHT 13 Dec: \(h)")
    // The same night with no showers known: targets only, as many as nine hours can hold.
    let plain = Planner.highlights(plan: p, site: site, fov: frame)
    #expect(plain.count == 2 && plain.allSatisfy { !$0.contains("at peak") })
}

@Test func aShowerWhoseRadiantStaysLowIsLeftOut() throws {
    let p = try clearNight(2026, 12, 2, hours: 4)
    func shower(_ name: String, dec: Double) -> MeteorShower {
        MeteorShower(id: name, name: name, startMonth: 11, startDay: 25, endMonth: 12, endDay: 9, peakMonth: 12, peakDay: 2, zhr: 50,
                     raHours: 2, decDeg: dec, parent: "", velocityKms: 40)
    }
    #expect(Planner.highlights(plan: p, site: site, fov: frame, showers: [shower("Highids", dec: 40)]).first?.hasPrefix("Highids at peak, best ") == true)
    // From 54° north a radiant at −25° never passes 11°: under the 20° it needs.
    #expect(!Planner.highlights(plan: p, site: site, fov: frame, showers: [shower("Lowids", dec: -25)]).contains { $0.contains("Lowids") })
}

@Test func aLongerWindowNamesTwoTargetsThreeHoursApartAndACloudyNightNone() throws {
    let h = Planner.highlights(plan: try clearNight(2026, 12, 2, hours: 8), site: site, fov: frame)
    #expect(h.count == 2 && bestMinutes(h[1]) - bestMinutes(h[0]) >= 180)
    #expect(Planner.highlights(plan: try clearNight(2026, 12, 2, hours: 0), site: site, fov: frame).isEmpty)
    #expect(Copy.weekHighlights(WeekNight(plan: try clearNight(2026, 12, 2, hours: 0), daysAhead: 3)) == nil)   // never an empty "Highlights:"
}

@Test func theWeekGivesEachClearNightItsHighlightsAndKeepsLaterRowsLight() throws {
    let start = utc(2026, 9, 30, 6, 0)
    // Clear on the fourth night only.
    let f = forecast(from: start, hours: 238, cloud: { (84..<96).contains($0) ? 0 : 100 })
    let (t0, t1) = try plans(f)
    let clock = ContinuousClock()
    var week: [WeekNight] = []
    let took = try clock.measure {
        week = Planner.week(tonight: t0, tomorrow: t1, forecast: f, site: site, fov: frame, rule: GoRule(), bright: nil,
                            catalog: try Catalog.bundled(), constellations: try Constellations.bundled(), stars: try BrightStars.bundled(),
                            showers: try MeteorShowers.bundled())
    }
    print("HIGHLIGHT week of \(week.count) nights took \(took)")
    let clear = week.filter { $0.plan.primary != nil }
    #expect(clear.count == 1 && clear[0].daysAhead == 3 && !clear[0].highlights.isEmpty)
    #expect(week.filter { $0.plan.primary == nil }.allSatisfy { $0.highlights.isEmpty })
    #expect(clear[0].plan.targets.allSatisfy { $0.group == .planets })   // the row's own plan stays without the catalogue
    // Without the catalogue, as before: no highlights.
    #expect(Planner.week(tonight: t0, tomorrow: t1, forecast: f, site: site, fov: frame, rule: GoRule(), bright: nil).allSatisfy { $0.highlights.isEmpty })
}
