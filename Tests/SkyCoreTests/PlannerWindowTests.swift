import Testing
import Foundation
@testable import SkyCore

private func hour(_ t0: Date, _ i: Int, cloud: Int, wind: Double? = nil, temp: Double? = nil, dew: Double? = nil, seeing: Int? = nil, transp: Int? = nil) -> HourlyConditions {
    HourlyConditions(time: t0.addingTimeInterval(Double(i) * 3600), cloudTotal: cloud, cloudLow: nil, cloudMid: nil, cloudHigh: nil,
                     tempC: temp, dewPointC: dew, humidityPct: nil, windKmh: wind, gustKmh: nil, visibilityM: nil, seeing: seeing, transparency: transp)
}

private let t0 = Date(timeIntervalSince1970: 1_790_000_000)   // any fixed instant
private let rule = GoRule()

@Test func oneClearWindowClippedToDarkness() {
    // darkness 20:30 -> 04:30 relative to t0 = 20:00
    let dark = (t0.addingTimeInterval(1800), t0.addingTimeInterval(8.5 * 3600))
    let hours = (0..<12).map { hour(t0, $0, cloud: $0 < 2 ? 80 : ($0 < 8 ? 10 : 90)) }   // clear 22:00–04:00
    let w = Planner.windows(hours: hours, darkStart: dark.0, darkEnd: dark.1, rule: rule)
    #expect(w.count == 1)
    #expect(w[0].start == t0.addingTimeInterval(2 * 3600))
    #expect(w[0].end == t0.addingTimeInterval(8 * 3600))
    #expect(w[0].hours == 6)
}

@Test func windowShorterThanRuleIsDropped() {
    let dark = (t0, t0.addingTimeInterval(10 * 3600))
    let hours = (0..<10).map { hour(t0, $0, cloud: (3...4).contains($0) ? 0 : 90) }   // 2 h clear
    #expect(Planner.windows(hours: hours, darkStart: dark.0, darkEnd: dark.1, rule: rule).isEmpty)
}

@Test func twoWindowsSortedLongestFirstByCaller() {
    let dark = (t0, t0.addingTimeInterval(12 * 3600))
    let hours = (0..<12).map { hour(t0, $0, cloud: ((0...2).contains($0) || (5...9).contains($0)) ? 5 : 95) }
    let w = Planner.windows(hours: hours, darkStart: dark.0, darkEnd: dark.1, rule: rule)
    #expect(w.count == 2)
    #expect(w.map(\.hours) == [3, 5])
}

@Test func windowCrossingMidnightIsContiguous() {
    // t0 = 22:00, darkness 22:00 -> 05:00; clear 23:00 -> 03:00 spans midnight
    let dark = (t0, t0.addingTimeInterval(7 * 3600))
    let hours = (0..<7).map { hour(t0, $0, cloud: (1...4).contains($0) ? 0 : 100) }
    let w = Planner.windows(hours: hours, darkStart: dark.0, darkEnd: dark.1, rule: rule)
    #expect(w.count == 1 && w[0].hours == 4)
}

@Test func cloudAtThresholdCounts() {
    let dark = (t0, t0.addingTimeInterval(4 * 3600))
    let hours = (0..<4).map { hour(t0, $0, cloud: 25) }
    #expect(Planner.windows(hours: hours, darkStart: dark.0, darkEnd: dark.1, rule: rule).count == 1)
}

@Test func scoreExtremes() {
    let dark = (t0, t0.addingTimeInterval(8 * 3600))
    let clear = (0..<8).map { hour(t0, $0, cloud: 0, wind: 5, temp: 10, dew: 2, seeing: 1, transp: 1) }
    let overcast = (0..<8).map { hour(t0, $0, cloud: 100, wind: 50, temp: 10, dew: 9.5) }
    let full = ScoreInputs(darkHours: clear, windows: [ClearWindow(start: dark.0, end: dark.1)], darkness: dark, moonIllumination: 0, moonAboveFraction: 0)
    let none = ScoreInputs(darkHours: overcast, windows: [], darkness: dark, moonIllumination: 1, moonAboveFraction: 1)
    #expect(Planner.score(full) == 100)
    #expect(Planner.score(none) == 0)
}

@Test func scoreWithoutSeeingRedistributesWeight() {
    let dark = (t0, t0.addingTimeInterval(8 * 3600))
    let clear = (0..<8).map { hour(t0, $0, cloud: 0, wind: 5, temp: 10, dew: 2) }
    let s = Planner.score(ScoreInputs(darkHours: clear, windows: [ClearWindow(start: dark.0, end: dark.1)], darkness: dark, moonIllumination: 0, moonAboveFraction: 0))
    #expect(s == 100)
}

@Test func fullMoonAllNightCostsFifteen() {
    let dark = (t0, t0.addingTimeInterval(8 * 3600))
    let clear = (0..<8).map { hour(t0, $0, cloud: 0, wind: 5, temp: 10, dew: 2, seeing: 1, transp: 1) }
    let s = Planner.score(ScoreInputs(darkHours: clear, windows: [ClearWindow(start: dark.0, end: dark.1)], darkness: dark, moonIllumination: 1, moonAboveFraction: 1))
    #expect(s == 85)
}

@Test func noDarknessScoresZero() {
    #expect(Planner.score(ScoreInputs(darkHours: [], windows: [], darkness: nil, moonIllumination: 0, moonAboveFraction: 0)) == 0)
}

@Test func maxCloudPctOverrideAffectsScore() {
    let dark = (t0, t0.addingTimeInterval(8 * 3600))
    let hazy = (0..<8).map { hour(t0, $0, cloud: 35) }
    let strictWindows = Planner.windows(hours: hazy, darkStart: dark.0, darkEnd: dark.1, rule: GoRule(maxCloudPct: 25))
    let looseWindows = Planner.windows(hours: hazy, darkStart: dark.0, darkEnd: dark.1, rule: GoRule(maxCloudPct: 40))
    #expect(strictWindows.isEmpty)   // 35% cloud fails the default 25% rule -> no window
    let strict = Planner.score(ScoreInputs(darkHours: hazy, windows: strictWindows, darkness: dark, moonIllumination: 0, moonAboveFraction: 0, maxCloudPct: 25))
    let loose = Planner.score(ScoreInputs(darkHours: hazy, windows: looseWindows, darkness: dark, moonIllumination: 0, moonAboveFraction: 0, maxCloudPct: 40))
    #expect(strict == 25)   // 0 clear hours -> cloud component 0; moon(15) + baseline(10) still apply
    #expect(loose == 100)   // all 8 hours clear and contiguous under the 40% rule
    #expect(loose - strict >= 75)
}

private func reasonHours(_ clouds: [Int], from t0: Date) -> [HourlyConditions] {
    clouds.enumerated().map { i, c in HourlyConditions(time: t0.addingTimeInterval(Double(i) * 3600), cloudTotal: c, cloudLow: nil, cloudMid: nil, cloudHigh: nil,
                                                       tempC: nil, dewPointC: nil, humidityPct: nil, windKmh: nil, gustKmh: nil, visibilityM: nil, seeing: nil, transparency: nil) }
}

@Test func noWindowReasonExplainsShortDarkness() {
    let site = Site(name: "S", latitude: 54.0, longitude: -1.5, elevationM: 100, timeZoneID: "Europe/London", bortle: 5)
    let t0 = utc(2026, 6, 20, 23, 0)
    let r = Planner.noWindowReason(darkHours: reasonHours([0, 0], from: t0), darkStart: t0, darkEnd: t0.addingTimeInterval(2 * 3600), rule: GoRule(), site: site)
    #expect(r == "Only 2.0 h of darkness; the rule needs 3 h.")
}

@Test func noWindowReasonExplainsCloudNeverBelowLimit() {
    let site = Site(name: "S", latitude: 54.0, longitude: -1.5, elevationM: 100, timeZoneID: "Europe/London", bortle: 5)
    let t0 = utc(2026, 9, 24, 21, 0)
    let r = Planner.noWindowReason(darkHours: reasonHours([90, 60, 75, 100, 80, 95, 70, 88], from: t0), darkStart: t0, darkEnd: t0.addingTimeInterval(8 * 3600), rule: GoRule(), site: site)
    #expect(r == "Cloud never below 60% during darkness; the rule allows 25%.")
}

@Test func noWindowReasonExplainsShortClearRun() {
    let site = Site(name: "S", latitude: 54.0, longitude: -1.5, elevationM: 100, timeZoneID: "Europe/London", bortle: 5)
    let t0 = utc(2026, 9, 24, 21, 0)   // 22:00 BST
    // clear at 23:00 and 00:00 UTC only: a 2-hour run starting 00:00 BST
    let r = Planner.noWindowReason(darkHours: reasonHours([90, 10, 20, 80, 10, 95, 70, 88], from: t0), darkStart: t0, darkEnd: t0.addingTimeInterval(8 * 3600), rule: GoRule(), site: site)
    #expect(r == "Longest clear run is 2 h from 23:00; the rule needs 3 h.")
}

/// 4 October 2026: darkness began at 21:07 and the hours from 21:00 were clear, so the reason read
/// "Longest clear run is 3 h from 21:00; the rule needs 3 h." under "No clear window tonight."
@Test func noWindowReasonMeasuresTheRunInsideDarkness() {
    let site = Site(name: "S", latitude: 54.0, longitude: -1.5, elevationM: 100, timeZoneID: "Europe/London", bortle: 5)
    let t0 = utc(2026, 10, 4, 20, 0)   // 21:00 BST
    let hrs = reasonHours([10, 10, 10, 90, 90, 90, 90, 90], from: t0)
    let ds = t0.addingTimeInterval(7 * 60), de = t0.addingTimeInterval(8 * 3600)
    #expect(Planner.windows(hours: hrs, darkStart: ds, darkEnd: de, rule: GoRule()).isEmpty)
    #expect(Planner.noWindowReason(darkHours: hrs, darkStart: ds, darkEnd: de, rule: GoRule(), site: site)
            == "Longest clear run is 2.9 h from 21:07; the rule needs 3 h.")
}

@Test func noWindowReasonNeverRoundsARunUpToTheRule() {
    let site = Site(name: "S", latitude: 54.0, longitude: -1.5, elevationM: 100, timeZoneID: "Europe/London", bortle: 5)
    let t0 = utc(2026, 10, 4, 20, 0)
    let hrs = reasonHours([10, 10, 10, 90, 90, 90, 90, 90], from: t0)
    // 2 h 58 min is 2.97 h, which one decimal place would print as the rule's own 3 h.
    let r = Planner.noWindowReason(darkHours: hrs, darkStart: t0.addingTimeInterval(2 * 60), darkEnd: t0.addingTimeInterval(8 * 3600), rule: GoRule(), site: site)
    #expect(r == "Longest clear run is 2.9 h from 21:02; the rule needs 3 h.")
}

// MARK: - v0.3 bright nights (the test site; nights chosen from a probe of summer 2026)

private let brightTestSite = Site(name: "Test site", latitude: 54.0, longitude: -1.5, elevationM: 100, timeZoneID: "Europe/London", bortle: 5)
private let dwarfMini = FieldOfView(widthDeg: 2.1, heightDeg: 1.2)

/// Evening of `day` at the test site with every hour from 18:00 UTC at `cloud` percent.
private func brightNight(_ month: Int, _ day: Int, cloud: Int) throws -> (Night, Forecast) {
    let night = try Ephemeris.night(localDate: utc(2026, month, day, 12, 0), site: brightTestSite)
    let t0 = utc(2026, month, day, 18, 0)
    let fc = Forecast(fetchedAt: t0, latitude: brightTestSite.latitude, longitude: brightTestSite.longitude,
                      hours: (0..<14).map { hour(t0, $0, cloud: cloud) }, seeingSource: nil)
    return (night, fc)
}
private var brightOn: BrightSettings { var b = BrightSettings(); b.enabled = true; return b }

@Test func brightPlanOnAJulyNightWithTheMoonUp() throws {
    let (night, fc) = try brightNight(7, 30, cloud: 5)   // Moon 98 % and Saturn near 20 degrees mid-window
    let p = Planner.plan(night: night, forecast: fc, catalog: Catalog(objects: []), constellations: [], site: brightTestSite, fov: dwarfMini, rule: GoRule(), bright: brightOn)
    #expect(p.mode == .bright)
    #expect(p.qualifies && p.primary != nil)
    #expect(p.brightTargets.first?.id == "moon")
    #expect(p.brightTargets.allSatisfy { $0.peakAltDeg >= Planner.brightTargetFloorDeg })
    #expect(p.targets.isEmpty && p.best.isEmpty)
}

@Test func favouritesSurviveABrightNight() throws {
    let (night, fc) = try brightNight(7, 30, cloud: 5)
    let p = Planner.plan(night: night, forecast: fc, catalog: Catalog(objects: []), constellations: [], stars: try BrightStars.bundled(),
                         site: brightTestSite, fov: dwarfMini, rule: GoRule(), bright: brightOn, favourites: ["planet-saturn", "HIP91262"])
    #expect(p.mode == .bright)
    #expect(p.favourites.map(\.id) == ["planet-saturn", "HIP91262"])   // Saturn and Vega
}

@Test func brightModeOffKeepsTheDarkResult() throws {
    let (night, fc) = try brightNight(7, 30, cloud: 5)
    let p = Planner.plan(night: night, forecast: fc, catalog: Catalog(objects: []), constellations: [], site: brightTestSite, fov: dwarfMini, rule: GoRule(), bright: nil)
    #expect(p.mode == .dark && !p.qualifies)
    #expect(p.brightTargets.isEmpty)
}

@Test func brightPlanNeedsClearHours() throws {
    let (night, fc) = try brightNight(7, 30, cloud: 90)
    let p = Planner.plan(night: night, forecast: fc, catalog: Catalog(objects: []), constellations: [], site: brightTestSite, fov: dwarfMini, rule: GoRule(), bright: brightOn)
    #expect(p.mode == .bright && !p.qualifies)
}

@Test func brightPlanNeedsATargetUp() throws {
    let (night, fc) = try brightNight(6, 15, cloud: 5)   // nothing at 15 degrees in the nautical window
    let p = Planner.plan(night: night, forecast: fc, catalog: Catalog(objects: []), constellations: [], site: brightTestSite, fov: dwarfMini, rule: GoRule(), bright: brightOn)
    #expect(p.mode == .bright && !p.qualifies)
    let ns = try #require(night.nauticalStart), ne = try #require(night.nauticalEnd)
    #expect(!Planner.anyBrightTargetUp(from: ns, to: ne, site: brightTestSite))
}

@Test func darkPlanWinsWhenTheDarkRuleIsMet() throws {
    let (night, fc) = try brightNight(9, 24, cloud: 5)
    let p = Planner.plan(night: night, forecast: fc, catalog: Catalog(objects: []), constellations: [], site: brightTestSite, fov: dwarfMini, rule: GoRule(), bright: brightOn)
    #expect(p.mode == .dark && p.qualifies)
}

@Test func brightScoreIgnoresTheMoonPenalty() throws {
    let (night, fc) = try brightNight(7, 30, cloud: 5)
    let p = Planner.plan(night: night, forecast: fc, catalog: Catalog(objects: []), constellations: [], site: brightTestSite, fov: dwarfMini, rule: GoRule(), bright: brightOn)
    let ns = try #require(night.nauticalStart), ne = try #require(night.nauticalEnd)
    let penalised = Planner.score(ScoreInputs(darkHours: p.darkHours, windows: p.windows, darkness: (ns, ne), moonIllumination: 1, moonAboveFraction: 1, maxCloudPct: 25))
    #expect(p.score - penalised == 15)   // the Moon is the target, so its whole 15-point term is kept
}

@Test func noWindowReasonInBrightMode() {
    let t0 = utc(2026, 6, 27, 22, 0)
    let clouds = Planner.noWindowReason(darkHours: reasonHours([90, 90], from: t0), darkStart: t0, darkEnd: t0.addingTimeInterval(2 * 3600),
                                        rule: GoRule(minHours: 1), site: brightTestSite, mode: .bright)
    #expect(clouds == "Cloud never below 90% during nautical darkness; the bright rule allows 25%.")
    let none = Planner.noWindowReason(darkHours: reasonHours([5, 5], from: t0), darkStart: t0, darkEnd: t0.addingTimeInterval(2 * 3600),
                                      rule: GoRule(minHours: 1), site: brightTestSite, mode: .bright, brightTargetsUp: false)
    #expect(none == "No Moon or planet 15° up during nautical darkness.")
}

@Test func brightReasonMatchesTheRule() throws {
    // 20 June at the test site: 1.56 h of nautical darkness. One clear hour that straddles a bound is not a 1 h run.
    let night = try Ephemeris.night(localDate: utc(2026, 6, 20, 12, 0), site: brightTestSite)
    let ns = try #require(night.nauticalStart), ne = try #require(night.nauticalEnd)
    let t0 = Date(timeIntervalSince1970: floor(ns.timeIntervalSince1970 / 3600) * 3600)   // the hour containing nautical dusk
    let hrs = reasonHours([5, 90, 90], from: t0)
    let r = Planner.noWindowReason(darkHours: hrs, darkStart: ns, darkEnd: ne, rule: GoRule(minHours: 1), site: brightTestSite, mode: .bright)
    #expect(r != nil && !(r!.contains("is 1.0 h") || r!.contains("is 1 h")))
    #expect(r!.contains("needs 1.0 h") || r!.hasPrefix("No Moon or planet"))
}

@Test func brightReasonNeverRoundsARunUpToTheRule() throws {
    // 30 July at the test site: the Moon stands above the floor in the middle of nautical darkness.
    let night = try Ephemeris.night(localDate: utc(2026, 7, 30, 12, 0), site: brightTestSite)
    let ns = try #require(night.nauticalStart), ne = try #require(night.nauticalEnd)
    let mid = ns.addingTimeInterval(ne.timeIntervalSince(ns) / 2)
    let t0 = Date(timeIntervalSince1970: floor(mid.timeIntervalSince1970 / 3600) * 3600)
    try #require(!Planner.brightTargets(at: t0.addingTimeInterval(1800), site: brightTestSite).isEmpty)
    // One clear hour, with the span starting two minutes into it: a 0.97 h run against a 1 h rule.
    let r = Planner.noWindowReason(darkHours: reasonHours([5, 90, 90], from: t0), darkStart: t0.addingTimeInterval(120), darkEnd: t0.addingTimeInterval(3 * 3600),
                                   rule: GoRule(minHours: 1), site: brightTestSite, mode: .bright)
    #expect(r == "Longest clear run with a target up is 0.9 h from \(Copy.hhmm(t0.addingTimeInterval(120), site: brightTestSite)); the bright rule needs 1.0 h.")
}

@Test func weekRowOnABrightNightCountsOnlyHoursWithATargetUp() throws {
    let (night, fc) = try brightNight(6, 15, cloud: 5)   // clear all night, but nothing at 15 degrees in the nautical window
    let p = Planner.plan(night: night, forecast: fc, catalog: Catalog(objects: []), constellations: [], site: brightTestSite, fov: dwarfMini, rule: GoRule(), bright: brightOn)
    #expect(p.mode == .bright && !p.qualifies)
    #expect(Copy.weekVerdict(p, rule: GoRule(), bright: brightOn, site: brightTestSite) == "No clear window")
}

@Test func brightFallbackKeepsTheMoon() throws {
    // Inverness at midsummer: no nautical darkness, so the bright plan is the fallback; the Moon tile must stay truthful.
    let inverness = Site(name: "Inverness", latitude: 57.48, longitude: -4.22, elevationM: 20, timeZoneID: "Europe/London", bortle: 4)
    let night = try Ephemeris.night(localDate: utc(2026, 6, 27, 12, 0), site: inverness)
    #expect(!night.hasNauticalDarkness)
    let t0 = utc(2026, 6, 27, 18, 0)
    let fc = Forecast(fetchedAt: t0, latitude: inverness.latitude, longitude: inverness.longitude, hours: (0..<14).map { hour(t0, $0, cloud: 5) }, seeingSource: nil)
    let p = Planner.plan(night: night, forecast: fc, catalog: Catalog(objects: []), constellations: [], site: inverness, fov: dwarfMini, rule: GoRule(), bright: brightOn)
    #expect(p.mode == .bright && !p.qualifies)
    #expect(p.moonIllumination > 0.5)   // 27 June 2026 is two days before full
}

/// Thin high cloud counts for half; low and mid count in full; never worse than the source's total (owner's UAT, 30 September 2026).
@Test func highCloudCountsForHalf() {
    #expect(CloudCover.effective(total: 40, low: nil, mid: nil, high: nil) == 40)       // no layers: the total
    #expect(CloudCover.effective(total: 40, low: 0, mid: 0, high: 40) == 20)            // a veil of cirrus
    #expect(CloudCover.effective(total: 100, low: 0, mid: 0, high: 100) == 50)          // overcast cirrus still fails 25%
    #expect(CloudCover.effective(total: 40, low: 40, mid: 0, high: 0) == 40)            // low cloud in full
    #expect(CloudCover.effective(total: 25, low: 20, mid: 20, high: 0) == 25)           // never above the source's total
    #expect(CloudCover.effective(total: 60, low: 20, mid: 0, high: 40) == 36)           // 1 − 0.8 × 0.8
}

@Test func aNightUnderHighCloudQualifies() {
    let dark = (t0, t0.addingTimeInterval(6 * 3600))
    let hours = (0..<6).map { i in
        HourlyConditions(time: t0.addingTimeInterval(Double(i) * 3600), cloudTotal: 40, cloudLow: 0, cloudMid: 0, cloudHigh: 40,
                         tempC: nil, dewPointC: nil, humidityPct: nil, windKmh: nil, gustKmh: nil, visibilityM: nil, seeing: nil, transparency: nil)
    }
    // 40% total fails a 25% rule; as thin high cloud it counts as 20% and passes.
    #expect(Planner.windows(hours: hours, darkStart: dark.0, darkEnd: dark.1, rule: rule).map(\.hours) == [6])
    #expect(Planner.windows(hours: hours.map { var h = $0; h.cloudLow = 40; h.cloudHigh = 0; return h },
                            darkStart: dark.0, darkEnd: dark.1, rule: rule).isEmpty)
}
