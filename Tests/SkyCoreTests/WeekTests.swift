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

@Test func weekRowsReadPlainly() throws {
    let start = utc(2026, 9, 30, 6, 0)
    // Clear from 22:00 to 01:00 UTC on the first night only: a 3 h run, then cloud.
    let f = forecast(from: start, hours: 72, cloud: { i in (16...18).contains(i) ? 0 : 90 })
    let (t0, t1) = try plans(f)
    let w = try #require(t0.primary)
    #expect(Copy.weekVerdict(t0, rule: GoRule(), site: site) == "Clear \(Copy.span(w.start, w.end, site: site)) · \(Copy.hoursText(w.hours))")
    #expect(Copy.weekVerdict(t1, rule: GoRule(), site: site) == "No clear window")
    var loose = GoRule(); loose.minHours = 4
    let (l0, _) = (Planner.plan(night: t0.night, forecast: f, catalog: Catalog(objects: []), constellations: [], site: site,
                                fov: FieldOfView(widthDeg: 2, heightDeg: 1), rule: loose), 0)
    #expect(Copy.weekVerdict(l0, rule: loose, site: site).hasPrefix("No clear window · longest clear run 3 h from "))
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
