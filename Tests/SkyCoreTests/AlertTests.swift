import Testing
import Foundation
@testable import SkyCore

private let site = Site(name: "Sheffield", latitude: 53.38, longitude: -1.47, elevationM: 100, timeZoneID: "Europe/London", bortle: 5)
private let copy = Copy()
private let settings = AlertSettings()

/// Build a plan by hand with a given window and qualifying flag.
private func plan(night: Night, window: ClearWindow?) -> NightPlan {
    NightPlan(night: night, windows: window.map { [$0] } ?? [], primary: window, score: window == nil ? 10 : 80, qualifies: window != nil,
              moonIllumination: 0.3, moonRise: nil, moonSet: nil, darkHours: [], targets: [], best: [], seeingAvailable: false)
}

private func fixtures() throws -> (Night, NightPlan, NightPlan, NightPlan) {
    let night = try Ephemeris.night(localDate: utc(2026, 9, 23, 12, 0), site: site)
    let window = ClearWindow(start: night.darkStart!.addingTimeInterval(3600), end: night.darkStart!.addingTimeInterval(5 * 3600))
    let good = plan(night: night, window: window)
    let bad = plan(night: night, window: nil)
    let tomorrowNight = try Ephemeris.night(localDate: utc(2026, 9, 24, 12, 0), site: site)
    let tomorrowGood = plan(night: tomorrowNight, window: ClearWindow(start: tomorrowNight.darkStart!, end: tomorrowNight.darkStart!.addingTimeInterval(4 * 3600)))
    return (night, good, bad, tomorrowGood)
}

@Test func headsUpFiresOneHourBeforeSunsetOnly() throws {
    let (night, good, _, _) = try fixtures()
    let early = night.sunset.addingTimeInterval(-2 * 3600)
    let r0 = AlertEngine.step(now: early, tonight: good, tomorrow: nil, state: nil, settings: settings, forecastFetchedAt: early, site: site, copy: copy)
    #expect(r0.notification == nil && r0.state.stage == .idle)
    let due = night.sunset.addingTimeInterval(-3600 + 60)
    let r1 = AlertEngine.step(now: due, tonight: good, tomorrow: nil, state: r0.state, settings: settings, forecastFetchedAt: due, site: site, copy: copy)
    #expect(r1.notification?.kind == .headsUp)
    #expect(r1.state.stage == .headsUpSent)
    let r2 = AlertEngine.step(now: due.addingTimeInterval(600), tonight: good, tomorrow: nil, state: r1.state, settings: settings, forecastFetchedAt: due, site: site, copy: copy)
    #expect(r2.notification == nil)   // idempotent
}

@Test func goFiresThirtyMinutesBeforeWindow() throws {
    let (_, good, _, _) = try fixtures()
    let state = AlertState(nightKey: good.night.key, stage: .headsUpSent)
    let tooEarly = good.primary!.start.addingTimeInterval(-45 * 60)
    #expect(AlertEngine.step(now: tooEarly, tonight: good, tomorrow: nil, state: state, settings: settings, forecastFetchedAt: tooEarly, site: site, copy: copy).notification == nil)
    let due = good.primary!.start.addingTimeInterval(-29 * 60)
    let r = AlertEngine.step(now: due, tonight: good, tomorrow: nil, state: state, settings: settings, forecastFetchedAt: due, site: site, copy: copy)
    #expect(r.notification?.kind == .go)
    #expect(r.state.stage == .goSent)
    #expect(r.notification!.title.hasPrefix("Clear from"))
}

@Test func cancelAfterHeadsUpWhenForecastDrops() throws {
    let (_, _, bad, _) = try fixtures()
    let state = AlertState(nightKey: bad.night.key, stage: .headsUpSent)
    let now = bad.night.sunset
    let r = AlertEngine.step(now: now, tonight: bad, tomorrow: nil, state: state, settings: settings, forecastFetchedAt: now, site: site, copy: copy)
    #expect(r.notification?.kind == .cancel)
    #expect(r.state.stage == .cancelled)
    #expect(r.notification!.title.hasPrefix("Cancelled"))
}

@Test func tomorrowPreviewWhenTonightFails() throws {
    let (night, _, bad, tomorrowGood) = try fixtures()
    let due = night.sunset.addingTimeInterval(-3000)
    let r = AlertEngine.step(now: due, tonight: bad, tomorrow: tomorrowGood, state: nil, settings: settings, forecastFetchedAt: due, site: site, copy: copy)
    #expect(r.notification?.kind == .tomorrowPreview)
    #expect(r.state.stage == .previewSent)
    let again = AlertEngine.step(now: due.addingTimeInterval(600), tonight: bad, tomorrow: tomorrowGood, state: r.state, settings: settings, forecastFetchedAt: due, site: site, copy: copy)
    #expect(again.notification == nil && again.state.stage == .previewSent)   // never resent
}

@Test func quietHoursDropButAdvance() throws {
    let (_, good, _, _) = try fixtures()
    // 02:00 local on the 24th is inside 00:00–07:00
    let cal = site.calendar
    let two = cal.date(bySettingHour: 2, minute: 0, second: 0, of: cal.date(byAdding: .day, value: 1, to: good.night.localDate)!)!
    let late = plan(night: good.night, window: ClearWindow(start: two.addingTimeInterval(1200), end: two.addingTimeInterval(4 * 3600)))
    let state = AlertState(nightKey: late.night.key, stage: .headsUpSent)
    let r = AlertEngine.step(now: two, tonight: late, tomorrow: nil, state: state, settings: settings, forecastFetchedAt: two, site: site, copy: copy)
    #expect(r.notification == nil)
    #expect(r.state.stage == .goSent)
    #expect(AlertEngine.inQuietHours(two, site: site, settings: settings))
}

@Test func staleForecastSendsNothing() throws {
    let (night, good, _, _) = try fixtures()
    let due = night.sunset.addingTimeInterval(-3000)
    let r = AlertEngine.step(now: due, tonight: good, tomorrow: nil, state: nil, settings: settings, forecastFetchedAt: due.addingTimeInterval(-7 * 3600), site: site, copy: copy)
    #expect(r.notification == nil && r.state.stage == .idle)
}

@Test func newNightResetsState() throws {
    let (night, good, _, _) = try fixtures()
    let stale = AlertState(nightKey: "2026-09-22", stage: .done)
    let due = night.sunset.addingTimeInterval(-3000)
    let r = AlertEngine.step(now: due, tonight: good, tomorrow: nil, state: stale, settings: settings, forecastFetchedAt: due, site: site, copy: copy)
    #expect(r.state.nightKey == "2026-09-23")
    #expect(r.notification?.kind == .headsUp)
}

@Test func wordingIsPlainWithNoDiscworldPhrases() {   // removed in 0.7.0 for the App Store (rule 5.2.1)
    let c = Copy()
    #expect(c.refresh == "Refresh")
    #expect(c.noWindow == "No clear window tonight.")
    let all = [c.refresh, c.noWindow, c.cancelTitle, c.lessCertainTitle, c.offlineSince("21:00"), c.goTitle(windowStart: "22:00")]
    for phrase in ["Patrol", "Move along", "Stand down", "Hold fire", "Off the beat", "All's well"] {
        #expect(!all.contains { $0.contains(phrase) }, "\(phrase)")
    }
}

@Test func cancelledRecoversToGoWhenForecastClears() throws {
    let (_, good, _, _) = try fixtures()
    let state = AlertState(nightKey: good.night.key, stage: .cancelled)
    let due = good.primary!.start.addingTimeInterval(-20 * 60)
    let r = AlertEngine.step(now: due, tonight: good, tomorrow: nil, state: state, settings: settings, forecastFetchedAt: due, site: site, copy: copy)
    #expect(r.notification?.kind == .go)
    #expect(r.state.stage == .goSent)
}

@Test func goSentFinishesAtSunriseWhenDowngradedWithoutCancel() throws {
    let (night, _, bad, _) = try fixtures()
    var noCancel = settings
    noCancel.cancelOnDowngrade = false
    let state = AlertState(nightKey: bad.night.key, stage: .goSent)

    let afterSunrise = night.sunrise.addingTimeInterval(60)
    let r1 = AlertEngine.step(now: afterSunrise, tonight: bad, tomorrow: nil, state: state, settings: noCancel, forecastFetchedAt: afterSunrise, site: site, copy: copy)
    #expect(r1.notification == nil)
    #expect(r1.state.stage == .done)

    let stillInWindow = night.sunset.addingTimeInterval(2 * 3600)
    let r2 = AlertEngine.step(now: stillInWindow, tonight: bad, tomorrow: nil, state: state, settings: noCancel, forecastFetchedAt: stillInWindow, site: site, copy: copy)
    #expect(r2.state.stage == .goSent)
}

@Test func lateClearanceAfterSunsetFiresGo() throws {
    let (night, _, bad, _) = try fixtures()
    let r0 = AlertEngine.step(now: night.sunset, tonight: bad, tomorrow: nil, state: nil, settings: settings, forecastFetchedAt: night.sunset, site: site, copy: copy)
    #expect(r0.notification == nil)
    #expect(r0.state.stage == .idle)

    let now = night.sunset.addingTimeInterval(3600)
    let late = plan(night: night, window: ClearWindow(start: now.addingTimeInterval(20 * 60), end: now.addingTimeInterval(5 * 3600)))
    let r1 = AlertEngine.step(now: now, tonight: late, tomorrow: nil, state: r0.state, settings: settings, forecastFetchedAt: now, site: site, copy: copy)
    #expect(r1.notification?.kind == .go)
    #expect(r1.state.stage == .goSent)
}

@Test func lateClearanceAfterPreviewFiresGo() throws {
    let (_, good, _, tomorrowGood) = try fixtures()
    let state = AlertState(nightKey: good.night.key, stage: .previewSent)
    let due = good.primary!.start.addingTimeInterval(-20 * 60)
    let r1 = AlertEngine.step(now: due, tonight: good, tomorrow: tomorrowGood, state: state, settings: settings, forecastFetchedAt: due, site: site, copy: copy)
    #expect(r1.notification?.kind == .go)
    #expect(r1.state.stage == .goSent)
    let r2 = AlertEngine.step(now: due, tonight: good, tomorrow: tomorrowGood, state: r1.state, settings: settings, forecastFetchedAt: due, site: site, copy: copy)
    #expect(r2.notification == nil)
}

// MARK: - v0.3 bright nights

private func brightTarget(_ id: String, _ name: String, _ subtitle: String, alt: Double) -> RankedTarget {
    RankedTarget(id: id, name: name, subtitle: subtitle, group: .planets, raHours: 0, decDeg: 0, sizeArcmin: nil, magnitude: nil,
                 fit: .small, peakAltDeg: alt, peakTime: Date(timeIntervalSince1970: 0), moonSepDeg: 0, moonWashed: false, visibleFraction: 1)
}
private func bright(_ p: NightPlan) -> NightPlan {
    var b = p
    b.mode = .bright
    b.brightTargets = [brightTarget("moon", "Moon", "62% illuminated", alt: 22), brightTarget("planet-saturn", "Saturn", "Planet", alt: 18)]
    return b
}

@Test func brightListNamesTheMoonWithItsPhase() {
    #expect(Copy.brightList(bright(NightPlan(night: Night(key: "k", localDate: Date(), sunset: Date(), sunrise: Date(), darkStart: nil, darkEnd: nil),
                                             windows: [], primary: nil, score: 0, qualifies: false, moonIllumination: 0, moonRise: nil, moonSet: nil,
                                             darkHours: [], targets: [], best: [], seeingAvailable: false)).brightTargets) == "Moon 62%, Saturn")
}

@Test func brightHeadsUpGoAndPreviewUseBrightWording() throws {
    let (night, good, bad, tomorrowGood) = try fixtures()
    let tonight = bright(good)
    let due = night.sunset.addingTimeInterval(-3600 + 60)
    let heads = AlertEngine.step(now: due, tonight: tonight, tomorrow: nil, state: nil, settings: settings, forecastFetchedAt: due, site: site, copy: copy)
    let h = try #require(heads.notification)
    #expect(h.kind == .headsUp)
    #expect(h.title == "Bright night tonight from \(Copy.hhmm(tonight.primary!.start, site: site)) · Moon 62%, Saturn")
    // A fresh install (no state): the first clear window is named once, before the usual body (#64).
    #expect(h.body == Copy.firstClear(tonight.primary!, site: site) + " Moon 62%, Saturn well placed.")

    let goAt = tonight.primary!.start.addingTimeInterval(-Double(settings.preWindowMinutes) * 60 + 60)
    let go = AlertEngine.step(now: goAt, tonight: tonight, tomorrow: nil, state: heads.state, settings: settings, forecastFetchedAt: goAt, site: site, copy: copy)
    #expect(go.notification?.title == "Bright night. Clear from \(Copy.hhmm(tonight.primary!.start, site: site))")

    let preview = AlertEngine.step(now: due, tonight: bad, tomorrow: bright(tomorrowGood), state: nil, settings: settings, forecastFetchedAt: due, site: site, copy: copy)
    #expect(preview.notification?.title == String(format: "Tomorrow looks bright and clear · %.1f h", tomorrowGood.primary!.hours))
}

@Test func switchingBrightModeMidEveningDoesNotStandDown() throws {
    let (night, good, _, _) = try fixtures()
    let due = night.sunset.addingTimeInterval(-3600 + 60)
    let dark = AlertEngine.step(now: due, tonight: good, tomorrow: nil, state: nil, settings: settings, forecastFetchedAt: due, site: site, copy: copy)
    #expect(dark.state.stage == .headsUpSent && dark.state.mode == .dark)
    // The same night now planned in bright mode (the owner toggled Bright nights): no "Stand down", a fresh bright heads-up instead.
    let later = due.addingTimeInterval(600)
    let r = AlertEngine.step(now: later, tonight: bright(good), tomorrow: nil, state: dark.state, settings: settings, forecastFetchedAt: later, site: site, copy: copy)
    #expect(r.notification?.kind != .cancel)
    #expect(r.notification?.title.hasPrefix("Bright night tonight") == true)
}

@Test func aBrightPlanFromThePlannerDrivesTheHeadsUp() throws {
    // The seam: Planner.plan(bright:) straight into AlertEngine.step, no hand-built plan.
    let testSite = Site(name: "Test site", latitude: 54.0, longitude: -1.5, elevationM: 100, timeZoneID: "Europe/London", bortle: 5)
    let night = try Ephemeris.night(localDate: utc(2026, 7, 30, 12, 0), site: testSite)
    let t0 = utc(2026, 7, 30, 18, 0)
    let hours = (0..<14).map { HourlyConditions(time: t0.addingTimeInterval(Double($0) * 3600), cloudTotal: 5, cloudLow: nil, cloudMid: nil, cloudHigh: nil,
                                                 tempC: nil, dewPointC: nil, humidityPct: nil, windKmh: nil, gustKmh: nil, visibilityM: nil, seeing: nil, transparency: nil) }
    var b = BrightSettings(); b.enabled = true
    let plan = Planner.plan(night: night, forecast: Forecast(fetchedAt: t0, latitude: testSite.latitude, longitude: testSite.longitude, hours: hours, seeingSource: nil),
                            catalog: Catalog(objects: []), constellations: [], site: testSite, fov: FieldOfView(widthDeg: 2.1, heightDeg: 1.2), rule: GoRule(), bright: b)
    let due = night.sunset.addingTimeInterval(-3600 + 60)
    let r = AlertEngine.step(now: due, tonight: plan, tomorrow: nil, state: nil, settings: settings, forecastFetchedAt: due, site: testSite, copy: copy)
    #expect(plan.mode == .bright)
    #expect(r.notification?.title.hasPrefix("Bright night tonight from") == true)
    #expect(r.notification?.body.contains("Moon") == true)
}

@Test func alertSettingsFromZeroFourDecode() throws {
    let json = #"{"headsUp":false,"tomorrowPreview":true,"preWindowMinutes":45,"cancelOnDowngrade":true,"quietStartHour":1,"quietEndHour":6}"#
    let s = try JSONDecoder().decode(AlertSettings.self, from: Data(json.utf8))
    #expect(s.requireAgreement == false)
    #expect(s.headsUp == false && s.preWindowMinutes == 45 && s.quietStartHour == 1 && s.quietEndHour == 6)
}

@Test func requireAgreementHoldsBackTheHeadsUpUntilOpenMeteoAgrees() throws {
    let testSite = Site(name: "Test site", latitude: 54.0, longitude: -1.5, elevationM: 100, timeZoneID: "Europe/London", bortle: 5)
    let night = try Ephemeris.night(localDate: utc(2026, 11, 20, 12, 0), site: testSite)
    let t0 = utc(2026, 11, 20, 17, 0)
    let hours = (0..<15).map { HourlyConditions(time: t0.addingTimeInterval(Double($0) * 3600), cloudTotal: (3...8).contains($0) ? 10 : 90, cloudLow: nil, cloudMid: nil, cloudHigh: nil,
                                                 tempC: nil, dewPointC: nil, humidityPct: nil, windKmh: nil, gustKmh: nil, visibilityM: nil, seeing: nil, transparency: nil) }
    var p = Planner.plan(night: night, forecast: Forecast(fetchedAt: t0, latitude: testSite.latitude, longitude: testSite.longitude, hours: hours, seeingSource: nil),
                         catalog: Catalog(objects: []), constellations: [], site: testSite, fov: FieldOfView(widthDeg: 2.1, heightDeg: 1.2), rule: GoRule())
    var s = AlertSettings(); s.requireAgreement = true
    let due = night.sunset.addingTimeInterval(-3600 + 60)
    p.agreement = .noWindow
    let held = AlertEngine.step(now: due, tonight: p, tomorrow: nil, state: nil, settings: s, forecastFetchedAt: due, site: testSite, copy: Copy())
    #expect(held.notification == nil && held.state.stage == .idle)
    p.agreement = .agree
    let sent = AlertEngine.step(now: due.addingTimeInterval(1800), tonight: p, tomorrow: nil, state: held.state, settings: s, forecastFetchedAt: due, site: testSite, copy: Copy())
    #expect(sent.notification?.kind == .headsUp)
}

@Test func requireAgreementWithoutSecondOpinionStillAlerts() throws {
    let testSite = Site(name: "Test site", latitude: 54.0, longitude: -1.5, elevationM: 100, timeZoneID: "Europe/London", bortle: 5)
    let night = try Ephemeris.night(localDate: utc(2026, 11, 20, 12, 0), site: testSite)
    let t0 = utc(2026, 11, 20, 17, 0)
    let hours = (0..<15).map { HourlyConditions(time: t0.addingTimeInterval(Double($0) * 3600), cloudTotal: (3...8).contains($0) ? 10 : 90, cloudLow: nil, cloudMid: nil, cloudHigh: nil,
                                                 tempC: nil, dewPointC: nil, humidityPct: nil, windKmh: nil, gustKmh: nil, visibilityM: nil, seeing: nil, transparency: nil) }
    let p = Planner.plan(night: night, forecast: Forecast(fetchedAt: t0, latitude: testSite.latitude, longitude: testSite.longitude, hours: hours, seeingSource: nil),
                         catalog: Catalog(objects: []), constellations: [], site: testSite, fov: FieldOfView(widthDeg: 2.1, heightDeg: 1.2), rule: GoRule())
    #expect(p.agreement == nil)
    var s = AlertSettings(); s.requireAgreement = true
    let due = night.sunset.addingTimeInterval(-3600 + 60)
    #expect(AlertEngine.step(now: due, tonight: p, tomorrow: nil, state: nil, settings: s, forecastFetchedAt: due, site: testSite, copy: Copy()).notification?.kind == .headsUp)
}

@Test func alertSettingsRoundTripKeepsEveryKey() throws {
    var s = AlertSettings(); s.requireAgreement = true; s.preWindowMinutes = 45; s.quietStartHour = 1
    let data = try JSONEncoder().encode(s)
    #expect(String(decoding: data, as: UTF8.self).contains("\"requireAgreement\":true"))
    #expect(try JSONDecoder().decode(AlertSettings.self, from: data) == s)
}

// After a heads-up or go, the message follows both forecasts (owner ruling, 25 September 2026): both lose the window →
// stand down; they split → "less certain", saying what each one sees.
private func with(_ p: NightPlan, _ a: Agreement?) -> NightPlan { var q = p; q.agreement = a; return q }
private let optIn: AlertSettings = { var s = AlertSettings(); s.requireAgreement = true; return s }()

@Test func standDownWhenBothForecastsLoseTheWindow() throws {
    let (_, _, bad, _) = try fixtures()
    let r = AlertEngine.step(now: bad.night.sunset, tonight: with(bad, .agreeNoWindow), tomorrow: nil, state: AlertState(nightKey: bad.night.key, stage: .headsUpSent),
                             settings: settings, forecastFetchedAt: bad.night.sunset, site: site, copy: copy)
    #expect(r.notification?.kind == .cancel && r.state.stage == .cancelled)
    #expect(r.notification?.title == "Cancelled. Clouds moving in")
    #expect(r.notification?.body == "Apple Weather and Open-Meteo both see cloud.")
    // With no second opinion the only forecast decides, as before.
    let solo = AlertEngine.step(now: bad.night.sunset, tonight: bad, tomorrow: nil, state: AlertState(nightKey: bad.night.key, stage: .headsUpSent),
                                settings: settings, forecastFetchedAt: bad.night.sunset, site: site, copy: copy)
    #expect(solo.notification?.kind == .cancel && solo.notification?.body == copy.noWindow)
}

@Test func lessCertainWhenOnlyAppleWeatherLosesTheWindow() throws {
    let (_, good, bad, _) = try fixtures()
    let run = (good.primary!.start, good.primary!.end)
    let r = AlertEngine.step(now: bad.night.sunset, tonight: with(bad, .clearRun(run.0, run.1)), tomorrow: nil, state: AlertState(nightKey: bad.night.key, stage: .headsUpSent),
                             settings: settings, forecastFetchedAt: bad.night.sunset, site: site, copy: copy)
    #expect(r.notification?.kind == .lessCertain && r.state.stage == .doubted)
    #expect(r.notification?.title == "Less certain. Forecasts disagree")
    #expect(r.notification?.body == "Apple Weather now sees cloud. Open-Meteo has a clear run \(Copy.hhmm(run.0, site: site))–\(Copy.hhmm(run.1, site: site)).")
}

@Test func lessCertainWhenOnlyOpenMeteoDisagreesAndTheOptInHoldsTheGo() throws {
    let (_, good, _, _) = try fixtures()
    let split = with(good, .noWindow), now = good.night.sunset
    let r = AlertEngine.step(now: now, tonight: split, tomorrow: nil, state: AlertState(nightKey: good.night.key, stage: .headsUpSent),
                             settings: optIn, forecastFetchedAt: now, site: site, copy: copy)
    #expect(r.notification?.kind == .lessCertain && r.state.stage == .doubted)
    #expect(r.notification?.body == "Apple Weather still sees clear from \(Copy.hhmm(good.primary!.start, site: site)). Open-Meteo sees no clear window.")
    // Opt-in off: nothing is held back, so no message; the go nudge still fires and carries Open-Meteo's line.
    let off = AlertEngine.step(now: now, tonight: split, tomorrow: nil, state: AlertState(nightKey: good.night.key, stage: .headsUpSent),
                               settings: settings, forecastFetchedAt: now, site: site, copy: copy)
    #expect(off.notification == nil && off.state.stage == .headsUpSent)
    // Once only: a second patrol with the same split says nothing.
    let again = AlertEngine.step(now: now.addingTimeInterval(600), tonight: split, tomorrow: nil, state: r.state, settings: optIn, forecastFetchedAt: now, site: site, copy: copy)
    #expect(again.notification == nil && again.state.stage == .doubted)
}

@Test func lessCertainResolves() throws {
    let (_, good, bad, _) = try fixtures()
    let doubted = AlertState(nightKey: good.night.key, stage: .doubted)
    // Both lose the window: stand down.
    let down = AlertEngine.step(now: bad.night.sunset, tonight: with(bad, .agreeNoWindow), tomorrow: nil, state: doubted, settings: optIn,
                                forecastFetchedAt: bad.night.sunset, site: site, copy: copy)
    #expect(down.notification?.kind == .cancel && down.state.stage == .cancelled)
    // Both agree again: the go nudge fires at its time.
    let due = good.primary!.start.addingTimeInterval(-29 * 60)
    let go = AlertEngine.step(now: due, tonight: with(good, .agree), tomorrow: nil, state: doubted, settings: optIn, forecastFetchedAt: due, site: site, copy: copy)
    #expect(go.notification?.kind == .go && go.state.stage == .goSent)
}

@Test func lessCertainAfterGo() throws {
    let (_, good, bad, _) = try fixtures()
    let run = (good.primary!.start, good.primary!.end), now = good.primary!.start
    let r = AlertEngine.step(now: now, tonight: with(bad, .clearRun(run.0, run.1)), tomorrow: nil, state: AlertState(nightKey: good.night.key, stage: .goSent),
                             settings: settings, forecastFetchedAt: now, site: site, copy: copy)
    #expect(r.notification?.kind == .lessCertain && r.state.stage == .doubted)
}

@Test func noSecondGoAndOneHoldFirePerNightWhenForecastsFlipFlop() throws {
    let (_, good, _, _) = try fixtures()
    let now = good.primary!.start.addingTimeInterval(600)
    var st = AlertState(nightKey: good.night.key, stage: .goSent, goFired: true)
    var notes: [AlertNotification.Kind] = []
    for a in [Agreement.noWindow, .agree, .noWindow, .agree] {
        let r = AlertEngine.step(now: now, tonight: with(good, a), tomorrow: nil, state: st, settings: optIn, forecastFetchedAt: now, site: site, copy: copy)
        if let n = r.notification { notes.append(n.kind) }
        st = r.state
    }
    #expect(notes == [.lessCertain])            // one "Less certain", no second go
    #expect(st.stage == .goSent)
}

@Test func nothingFiresAfterTheWindowHasClosed() throws {
    let (_, good, _, _) = try fixtures()
    let after = good.primary!.end.addingTimeInterval(600)
    let late = AlertEngine.step(now: after, tonight: with(good, .agree), tomorrow: nil, state: AlertState(nightKey: good.night.key, stage: .doubted),
                                settings: optIn, forecastFetchedAt: after, site: site, copy: copy)
    #expect(late.notification == nil)
    let split = AlertEngine.step(now: after, tonight: with(good, .noWindow), tomorrow: nil, state: AlertState(nightKey: good.night.key, stage: .goSent),
                                 settings: optIn, forecastFetchedAt: after, site: site, copy: copy)
    #expect(split.notification == nil && split.state.stage == .done)
}

@Test func lessCertainAfterGoWhileAppleIsStillClear() throws {
    let (_, good, _, _) = try fixtures()
    let now = good.primary!.start.addingTimeInterval(600)
    let r = AlertEngine.step(now: now, tonight: with(good, .noWindow), tomorrow: nil, state: AlertState(nightKey: good.night.key, stage: .goSent),
                             settings: optIn, forecastFetchedAt: now, site: site, copy: copy)
    #expect(r.notification?.kind == .lessCertain && r.state.stage == .doubted)
}

@Test func holdFireRespectsTheSwitchAndQuietHours() throws {
    let (_, good, bad, _) = try fixtures()
    let run = with(bad, .clearRun(good.primary!.start, good.primary!.end))
    var off = settings; off.cancelOnDowngrade = false
    let r = AlertEngine.step(now: bad.night.sunset, tonight: run, tomorrow: nil, state: AlertState(nightKey: bad.night.key, stage: .headsUpSent),
                             settings: off, forecastFetchedAt: bad.night.sunset, site: site, copy: copy)
    #expect(r.notification == nil && r.state.stage == .headsUpSent)
    var quiet = settings; quiet.quietStartHour = 0; quiet.quietEndHour = 23
    let q = AlertEngine.step(now: bad.night.sunset, tonight: run, tomorrow: nil, state: AlertState(nightKey: bad.night.key, stage: .headsUpSent),
                             settings: quiet, forecastFetchedAt: bad.night.sunset, site: site, copy: copy)
    #expect(q.notification == nil && q.state.stage == .doubted)   // dropped, not deferred, as every alert
}

/// The app checks again at each due time, so alerts go out on the minute (owner's review, 30 September 2026). A check a
/// few seconds after each due time sends the alert that falls due then.
@Test func dueTimesAreWhenTheAlertsFire() throws {
    let (night, good, bad, _) = try fixtures()
    let due = AlertEngine.dueTimes(tonight: good, settings: settings)
    #expect(due == [night.sunset.addingTimeInterval(-3600), good.primary!.start.addingTimeInterval(-30 * 60)])
    #expect(AlertEngine.dueTimes(tonight: bad, settings: settings) == [night.sunset.addingTimeInterval(-3600)])   // no window, no nudge
    var custom = settings; custom.preWindowMinutes = 60
    #expect(AlertEngine.dueTimes(tonight: good, settings: custom)[1] == good.primary!.start.addingTimeInterval(-3600))
    // Checking 5 s after each due time sends the heads-up, then the go.
    let r1 = AlertEngine.step(now: due[0].addingTimeInterval(5), tonight: good, tomorrow: nil, state: nil, settings: settings, forecastFetchedAt: due[0], site: site, copy: copy)
    #expect(r1.notification?.kind == .headsUp)
    let r2 = AlertEngine.step(now: due[1].addingTimeInterval(5), tonight: good, tomorrow: nil, state: r1.state, settings: settings, forecastFetchedAt: due[1], site: site, copy: copy)
    #expect(r2.notification?.kind == .go)
    // A second before a due time sends nothing.
    #expect(AlertEngine.step(now: due[0].addingTimeInterval(-1), tonight: good, tomorrow: nil, state: nil, settings: settings, forecastFetchedAt: due[0], site: site, copy: copy).notification == nil)
}
