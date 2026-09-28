import Testing
import Foundation
@testable import SkyCore

private let testSite = Site(name: "Test site", latitude: 54.0, longitude: -1.5, elevationM: 100, timeZoneID: "Europe/London", bortle: 5)
private let rule = GoRule()   // 3 h at 25 %

/// A plan over a test-site November night (GMT, so UTC is local) with the given primary hours from 17:00.
private func plan(primaryCloud: [Int], mode: PlanMode = .dark) throws -> NightPlan {
    let night = try Ephemeris.night(localDate: utc(2026, 11, 20, 12, 0), site: testSite)
    let t0 = utc(2026, 11, 20, 17, 0)
    let hours = primaryCloud.enumerated().map { i, c in
        HourlyConditions(time: t0.addingTimeInterval(Double(i) * 3600), cloudTotal: c, cloudLow: nil, cloudMid: nil, cloudHigh: nil,
                         tempC: nil, dewPointC: nil, humidityPct: nil, windKmh: nil, gustKmh: nil, visibilityM: nil, seeing: nil, transparency: nil)
    }
    var p = Planner.plan(night: night, forecast: Forecast(fetchedAt: t0, latitude: testSite.latitude, longitude: testSite.longitude, hours: hours, seeingSource: nil),
                         catalog: Catalog(objects: []), constellations: [], site: testSite, fov: FieldOfView(widthDeg: 2.1, heightDeg: 1.2), rule: rule)
    if mode == .bright { p.mode = .bright }
    return p
}
private func second(_ cloud: [Int]) -> SecondOpinion {
    let t0 = utc(2026, 11, 20, 17, 0)
    return SecondOpinion(source: "Open-Meteo", hours: cloud.enumerated().map { HourlyCloud(time: t0.addingTimeInterval(Double($0.offset) * 3600), cloudTotal: $0.element) })
}
/// 17:00 … 07:00: cloudy until 20:00, clear 20:00–02:00, cloudy after.
private let primary = [90, 90, 90, 10, 10, 10, 10, 10, 10, 90, 90, 90, 90, 90, 90]

@Test func bothClearAgrees() throws {
    let p = try plan(primaryCloud: primary)
    #expect(Planner.agreement(plan: p, second: second(primary), rule: rule) == .agree)
}

@Test func cloudPartWayThroughTheWindow() throws {
    let p = try plan(primaryCloud: primary)
    var s = primary; s[7] = 80; s[8] = 80          // Open-Meteo clouds over at 00:00
    #expect(Planner.agreement(plan: p, second: second(s), rule: rule) == .cloudFrom(utc(2026, 11, 21, 0, 0)))
}

@Test func noClearRunInTheWindow() throws {
    let p = try plan(primaryCloud: primary)
    var s = primary; s[4] = 80; s[6] = 80          // no 3 h clear run left inside 20:00–02:00
    #expect(Planner.agreement(plan: p, second: second(s), rule: rule) == .noWindow)
}

@Test func neitherSeesAWindow() throws {
    let cloudy = Array(repeating: 90, count: 15)
    let p = try plan(primaryCloud: cloudy)
    #expect(p.primary == nil)
    #expect(Planner.agreement(plan: p, second: second(cloudy), rule: rule) == .agreeNoWindow)
}

@Test func onlyOpenMeteoSeesAWindow() throws {
    let cloudy = Array(repeating: 90, count: 15)
    let p = try plan(primaryCloud: cloudy)
    var s = cloudy; for i in 6...9 { s[i] = 5 }       // 23:00–03:00 clear in Open-Meteo
    #expect(Planner.agreement(plan: p, second: second(s), rule: rule) == .clearRun(utc(2026, 11, 20, 23, 0), utc(2026, 11, 21, 3, 0)))
}

@Test func agreementIsNilWhenAHourIsMissing() throws {
    let p = try plan(primaryCloud: primary)
    var s = second(primary); s.hours.remove(at: 5)
    #expect(Planner.agreement(plan: p, second: s, rule: rule) == nil)
    #expect(Planner.agreement(plan: p, second: nil, rule: rule) == nil)
}

@Test func cloudFromIsClampedToTheWindowStart() throws {
    // Clear from 18:00 while darkness starts part-way through the 18:00 hour, so the window starts off the hour.
    var clearEarly = primary; clearEarly[1] = 10; clearEarly[2] = 10
    let p = try plan(primaryCloud: clearEarly)
    let w = try #require(p.primary)
    #expect(w.start > utc(2026, 11, 20, 18, 0))
    var s = clearEarly; s[1] = 80                      // Open-Meteo cloudy in the straddling 18:00 hour only
    let a = Planner.agreement(plan: p, second: second(s), rule: rule)
    #expect(a == .clearFrom(utc(2026, 11, 20, 19, 0)))
    if case .clearFrom(let t) = a { #expect(t >= w.start) }
}

@Test func cloudOnlyBeforeTheRunReadsAsClearingLater() throws {
    let p = try plan(primaryCloud: primary)
    var s = primary; s[3] = 80                         // cloudy at 20:00 only, clear 21:00–02:00
    #expect(Planner.agreement(plan: p, second: second(s), rule: rule) == .clearFrom(utc(2026, 11, 20, 21, 0)))
}

@Test func cloudBeforeAndAfterTheRunReportsTheLaterCloud() throws {
    let p = try plan(primaryCloud: primary)
    var s = primary; s[3] = 80; s[8] = 80              // clear 21:00–01:00, cloudy at 20:00 and 01:00
    #expect(Planner.agreement(plan: p, second: second(s), rule: rule) == .cloudFrom(utc(2026, 11, 21, 1, 0)))
}

@Test func aClearRunElsewhereIsNotNoWindow() throws {
    let p = try plan(primaryCloud: primary)
    var s = primary
    for i in 3...8 { s[i] = 80 }                       // cloudy through Apple's window
    for i in 9...11 { s[i] = 5 }                       // clear 02:00–05:00 instead
    let a = Planner.agreement(plan: p, second: second(s), rule: rule)
    #expect(a == .clearRun(utc(2026, 11, 21, 2, 0), utc(2026, 11, 21, 5, 0)))
    #expect(!Planner.agreementHolds(a))                // the opt-in still holds the alert: Open-Meteo is not clear in the window
}

@Test func agreementSurvivesThePlanCache() throws {
    for a in [Agreement.agree, .cloudFrom(utc(2026, 11, 21, 0, 0)), .clearFrom(utc(2026, 11, 20, 21, 0)), .noWindow, .agreeNoWindow,
              .clearRun(utc(2026, 11, 20, 23, 0), utc(2026, 11, 21, 2, 0))] {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        #expect(try d.decode(Agreement.self, from: e.encode(a)) == a)
    }
}

@Test func aBrightWindowGetsTheLine() throws {
    let night = try Ephemeris.night(localDate: utc(2026, 7, 30, 12, 0), site: testSite)
    let t0 = utc(2026, 7, 30, 18, 0)
    let hours = (0..<14).map { HourlyConditions(time: t0.addingTimeInterval(Double($0) * 3600), cloudTotal: 5, cloudLow: nil, cloudMid: nil, cloudHigh: nil,
                                                 tempC: nil, dewPointC: nil, humidityPct: nil, windKmh: nil, gustKmh: nil, visibilityM: nil, seeing: nil, transparency: nil) }
    let om = SecondOpinion(source: "Open-Meteo", hours: hours.map { HourlyCloud(time: $0.time, cloudTotal: 5) })
    var b = BrightSettings(); b.enabled = true
    let p = Planner.plan(night: night, forecast: Forecast(fetchedAt: t0, latitude: testSite.latitude, longitude: testSite.longitude, hours: hours, seeingSource: nil, secondOpinion: om),
                         catalog: Catalog(objects: []), constellations: [], site: testSite, fov: FieldOfView(widthDeg: 2.1, heightDeg: 1.2), rule: GoRule(), bright: b)
    #expect(p.mode == .bright && p.primary != nil)
    #expect(p.agreement == .agree)
}

@Test func brightPlanWithoutAWindowHasNoLine() throws {
    let p = try plan(primaryCloud: Array(repeating: 90, count: 15), mode: .bright)
    #expect(Planner.agreement(plan: p, second: second(Array(repeating: 5, count: 15)), rule: rule) == nil)
}

@Test func agreementHoldsUnlessOpenMeteoMissesTheWindow() {
    #expect(Planner.agreementHolds(.agree) && Planner.agreementHolds(.cloudFrom(Date())) && Planner.agreementHolds(.clearFrom(Date())) && Planner.agreementHolds(nil))
    #expect(!Planner.agreementHolds(.noWindow) && !Planner.agreementHolds(.clearRun(Date(), Date())))
}

@Test func thePlannerStoresTheAgreement() throws {
    let night = try Ephemeris.night(localDate: utc(2026, 11, 20, 12, 0), site: testSite)
    let t0 = utc(2026, 11, 20, 17, 0)
    let hours = primary.enumerated().map { i, c in
        HourlyConditions(time: t0.addingTimeInterval(Double(i) * 3600), cloudTotal: c, cloudLow: nil, cloudMid: nil, cloudHigh: nil,
                         tempC: nil, dewPointC: nil, humidityPct: nil, windKmh: nil, gustKmh: nil, visibilityM: nil, seeing: nil, transparency: nil)
    }
    let fc = Forecast(fetchedAt: t0, latitude: testSite.latitude, longitude: testSite.longitude, hours: hours, seeingSource: nil, secondOpinion: second(primary))
    let p = Planner.plan(night: night, forecast: fc, catalog: Catalog(objects: []), constellations: [], site: testSite,
                         fov: FieldOfView(widthDeg: 2.1, heightDeg: 1.2), rule: rule)
    #expect(p.agreement == .agree)
}

@Test func testSiteDarknessCoversTheTestWindow() throws {
    let n = try Ephemeris.night(localDate: utc(2026, 11, 20, 12, 0), site: testSite)
    #expect(n.darkStart! < utc(2026, 11, 20, 20, 0) && n.darkEnd! > utc(2026, 11, 21, 3, 0))
}

@Test func agreementWording() {
    let a = utc(2026, 11, 20, 23, 0), b = utc(2026, 11, 21, 2, 0)
    #expect(Copy.agreementText(.agree, site: testSite) == "Open-Meteo agrees")
    #expect(Copy.agreementText(.cloudFrom(a), site: testSite) == "Open-Meteo sees cloud from 23:00")
    #expect(Copy.agreementText(.clearFrom(a), site: testSite) == "Open-Meteo sees it clear from 23:00")
    #expect(Copy.agreementText(.noWindow, site: testSite) == "Open-Meteo sees no clear window")
    #expect(Copy.agreementText(.agreeNoWindow, site: testSite) == "Open-Meteo agrees: no clear window")
    #expect(Copy.agreementText(.clearRun(a, b), site: testSite) == "Open-Meteo has a clear run 23:00–02:00")
    #expect(!Copy.agreementWarns(.agree) && !Copy.agreementWarns(.agreeNoWindow))
    #expect(Copy.agreementWarns(.cloudFrom(a)) && Copy.agreementWarns(.clearFrom(a)) && Copy.agreementWarns(.noWindow) && Copy.agreementWarns(.clearRun(a, b)))
}

@Test func notificationBodyCarriesTheLineButNotForTomorrow() throws {
    var p = try plan(primaryCloud: primary)
    p.agreement = .agree
    let copy = Copy()
    #expect(copy.notificationBody(plan: p, site: testSite).hasSuffix(" Open-Meteo agrees."))
    #expect(!copy.notificationBody(plan: p, site: testSite, agreement: false).contains("Open-Meteo"))
    p.agreement = nil
    #expect(!copy.notificationBody(plan: p, site: testSite).contains("Open-Meteo"))
}

/// A disagreement says what to do (owner, 28 September 2026): "Check again at …" with no window, "Less certain" with one.
@Test func adviceWhenTheForecastsDisagree() throws {
    let a = utc(2026, 11, 20, 23, 0), b = utc(2026, 11, 21, 2, 0), early = utc(2026, 11, 20, 12, 0)
    var alerts = AlertSettings(); alerts.preWindowMinutes = 30
    // No window from Apple Weather; Open-Meteo clear 23:00–02:00: check again at the nudge time before it.
    var none = try plan(primaryCloud: Array(repeating: 90, count: 15))
    none.agreement = .clearRun(a, b)
    let check = try #require(Copy.advice(none, site: testSite, alerts: alerts, now: early))
    #expect(check.line == "Check again at 22:30: a second forecast sees 23:00–02:00 clear.")
    // Once that time has passed, look now.
    #expect(Copy.advice(none, site: testSite, alerts: alerts, now: utc(2026, 11, 20, 22, 45))?.line == "Check the sky now: a second forecast sees 23:00–02:00 clear.")
    // After the run has ended there is nothing to check, until the next refresh brings a new plan.
    #expect(Copy.advice(none, site: testSite, alerts: alerts, now: utc(2026, 11, 21, 2, 0)) == nil)
    // A window, and Open-Meteo sees cloud part-way: less certain, never "don't go".
    var window = try plan(primaryCloud: primary)
    window.agreement = .cloudFrom(a)
    let less = try #require(Copy.advice(window, site: testSite, alerts: alerts, now: early))
    #expect(less.line == "Less certain: a second forecast sees cloud from 23:00.")
    #expect(less.sentence == "A second forecast sees cloud from 23:00, so this window is less certain than usual.")
    window.agreement = .noWindow
    #expect(Copy.advice(window, site: testSite, alerts: alerts)?.line == "Less certain: a second forecast sees no clear window.")
    // Agreement needs no advice.
    window.agreement = .agree
    #expect(Copy.advice(window, site: testSite, alerts: alerts) == nil)
    // Notifications carry the same sentence.
    window.agreement = .cloudFrom(a)
    #expect(Copy().notificationBody(plan: window, site: testSite).hasSuffix(" A second forecast sees cloud from 23:00, so this window is less certain than usual."))
}

@Test func aBrightWindowNeverSuggestsARunElsewhere() throws {
    // The bright rule also needs a target 15° up, which cloud alone cannot show, so a cloudy bright window reads "no clear window".
    let night = try Ephemeris.night(localDate: utc(2026, 7, 30, 12, 0), site: testSite)
    let t0 = utc(2026, 7, 30, 18, 0)
    let hours = (0..<14).map { HourlyConditions(time: t0.addingTimeInterval(Double($0) * 3600), cloudTotal: 5, cloudLow: nil, cloudMid: nil, cloudHigh: nil,
                                                 tempC: nil, dewPointC: nil, humidityPct: nil, windKmh: nil, gustKmh: nil, visibilityM: nil, seeing: nil, transparency: nil) }
    var b = BrightSettings(); b.enabled = true
    let p0 = Planner.plan(night: night, forecast: Forecast(fetchedAt: t0, latitude: testSite.latitude, longitude: testSite.longitude, hours: hours, seeingSource: nil),
                          catalog: Catalog(objects: []), constellations: [], site: testSite, fov: FieldOfView(widthDeg: 2.1, heightDeg: 1.2), rule: GoRule(), bright: b)
    let w = try #require(p0.primary)
    // Open-Meteo: cloudy through the bright window, clear in every other hour of nautical darkness.
    let om = SecondOpinion(source: "Open-Meteo", hours: hours.map { HourlyCloud(time: $0.time, cloudTotal: w.overlapsHour(startingAt: $0.time) ? 90 : 5) })
    #expect(Planner.agreement(plan: p0, second: om, rule: GoRule(minHours: 1)) == .noWindow)
}
