import Testing
import Foundation
@testable import SkyCore

private let t0 = Date(timeIntervalSince1970: 1_790_000_000)
private func hour(_ i: Int, cloud: Int = 5, wind: Double? = 5, temp: Double? = 10, dew: Double? = 2, seeing: Int? = 2, transp: Int? = 2) -> HourlyConditions {
    HourlyConditions(time: t0.addingTimeInterval(Double(i) * 3600), cloudTotal: cloud, cloudLow: nil, cloudMid: nil, cloudHigh: nil,
                     tempC: temp, dewPointC: dew, humidityPct: nil, windKmh: wind, gustKmh: nil, visibilityM: nil, seeing: seeing, transparency: transp)
}
private func inputs(_ hours: [HourlyConditions], moon: Double = 0, above: Double = 0) -> ScoreInputs {
    let dark = (t0, t0.addingTimeInterval(Double(hours.count) * 3600))
    return ScoreInputs(darkHours: hours, windows: Planner.windows(hours: hours, darkStart: dark.0, darkEnd: dark.1, rule: GoRule()),
                       darkness: dark, moonIllumination: moon, moonAboveFraction: above)
}

@Test func dewRiskThresholds() {
    #expect(Planner.dewRisk([hour(0, temp: 5, dew: 3.1)]) == .high)      // spread 1.9
    #expect(Planner.dewRisk([hour(0, temp: 5, dew: 3)]) == .medium)      // spread 2
    #expect(Planner.dewRisk([hour(0, temp: 5, dew: 1.1)]) == .medium)    // spread 3.9
    #expect(Planner.dewRisk([hour(0, temp: 5, dew: 1)]) == .low)         // spread 4
    #expect(Planner.dewRisk([hour(0, temp: nil, dew: nil)]) == nil)
}

@Test func moonLimitedNight() {
    let f = Planner.limitingFactors(inputs((0..<6).map { hour($0) }, moon: 0.97, above: 1))
    #expect(f.first?.kind == .moon)
    #expect(f.first?.text == "a 97% moon")
    #expect(Copy.heldBack(f) == "Held back by a 97% moon")
}

@Test func dewLimitedNight() {
    let f = Planner.limitingFactors(inputs((0..<6).map { hour($0, temp: 4, dew: 3) }))
    #expect(f.map(\.kind) == [.dew])
    #expect(f[0].text == "high dew risk")
}

@Test func twoFactorsJoinWithAnd() {
    let f = Planner.limitingFactors(inputs((0..<6).map { hour($0, temp: 4, dew: 3) }, moon: 0.97, above: 1))
    #expect(Copy.heldBack(f) == "Held back by a 97% moon and high dew risk")
}

@Test func cleanNightHasNoFactors() {
    let f = Planner.limitingFactors(inputs((0..<6).map { hour($0) }))
    #expect(f.isEmpty)
    #expect(Copy.heldBack(f) == nil)
}

// The reason line and the tiles are read side by side, so a factor is worded from what its tile shows (owner, 4 October 2026:
// "Held back by poor transparency" beside a Transparency tile reading "Good").
@Test func transparencyTheTileCallsGoodIsNotBlamed() {
    let hours = (0..<6).map { hour($0, transp: $0 % 2 == 0 ? 3 : 4) }   // averages 3.5: over a third of its points lost
    let f = Planner.limitingFactors(inputs(hours))
    #expect(Copy.transparencyText(hours) == "Good")
    #expect(!f.contains { $0.kind == .transparency })
    #expect(Copy.heldBack(f) == nil)
}

@Test func transparencyIsNamedInTheTilesWord() {
    let hours = (0..<6).map { hour($0, transp: 5) }
    let f = Planner.limitingFactors(inputs(hours))
    #expect(Copy.transparencyText(hours) == "Average")
    #expect(Copy.transparencyText([hour(0, transp: nil)]) == nil)
    #expect(f.map(\.text) == ["average transparency"])
    #expect(Copy.heldBack(f) == "Held back by average transparency")
}

@Test func seeingIsNamedWithTheTilesFigure() {
    let hours = (0..<6).map { hour($0, seeing: 6) }
    let f = Planner.limitingFactors(inputs(hours))
    #expect(f.map(\.text) == ["seeing at 1.5–2″"])
    #expect(f[0].text.hasSuffix(Copy.seeingText(hours)!))
}

/// The guide calls about 1″ excellent, so a night whose Seeing tile reads 1″ or better is not "held back" by it, even
/// though the score, which falls in a straight line across 7Timer's eight bands, has taken a third of its points.
@Test func seeingTheGuideCallsExcellentIsNotBlamed() {
    let hours = (0..<6).map { hour($0, seeing: $0 % 2 == 0 ? 3 : 4) }   // averages 3.5: the tile reads 0.75–1″
    let f = Planner.limitingFactors(inputs(hours))
    #expect(Copy.seeingText(hours) == "0.75–1″")
    #expect(!f.contains { $0.kind == .seeing })
    #expect(Copy.heldBack(f) == nil)
    // One band worse, and it is named with the tile's figure as before.
    let softer = (0..<6).map { hour($0, seeing: 4) }
    #expect(Planner.limitingFactors(inputs(softer)).map(\.text) == ["seeing at 1–1.25″"])
}

@Test func limitingFactorsIgnoreMissingData() {
    let f = Planner.limitingFactors(inputs((0..<6).map { hour($0, wind: nil, temp: nil, dew: nil, seeing: nil, transp: nil) }))
    #expect(!f.contains { [.dew, .seeing, .transparency, .wind].contains($0.kind) })
}

@Test func scoreUnchangedByTheRefactor() {
    // Pinned from 0.3.1 for the same inputs: the refactor must not move the score.
    #expect(Planner.score(inputs((0..<6).map { hour($0) })) == 98)          // 60 + 15 + 12.86 + 10
    #expect(Planner.score(inputs((0..<6).map { hour($0, temp: 4, dew: 3) }, moon: 0.97, above: 1)) == 78)   // 60 + 0.45 + 12.86 + 5
}

@Test func brightNightNeverBlamesTheMoon() throws {
    let testSite = Site(name: "Test site", latitude: 54.0, longitude: -1.5, elevationM: 100, timeZoneID: "Europe/London", bortle: 5)
    let night = try Ephemeris.night(localDate: utc(2026, 7, 30, 12, 0), site: testSite)
    let start = utc(2026, 7, 30, 18, 0)
    let hours = (0..<14).map { HourlyConditions(time: start.addingTimeInterval(Double($0) * 3600), cloudTotal: 5, cloudLow: nil, cloudMid: nil, cloudHigh: nil,
                                                tempC: nil, dewPointC: nil, humidityPct: nil, windKmh: nil, gustKmh: nil, visibilityM: nil, seeing: nil, transparency: nil) }
    var b = BrightSettings(); b.enabled = true
    let plan = Planner.plan(night: night, forecast: Forecast(fetchedAt: start, latitude: testSite.latitude, longitude: testSite.longitude, hours: hours, seeingSource: nil),
                            catalog: Catalog(objects: []), constellations: [], site: testSite, fov: FieldOfView(widthDeg: 2.1, heightDeg: 1.2), rule: GoRule(), bright: b)
    #expect(plan.mode == .bright)
    #expect(plan.qualifies)   // otherwise limiting is empty and the check below proves nothing
    #expect(!plan.limiting.contains { $0.kind == .moon })
}
