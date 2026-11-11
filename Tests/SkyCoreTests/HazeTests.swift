import Testing
import Foundation
@testable import SkyCore

// Haze or smoke on a clear night (#183): aerosol optical depth from Open-Meteo's air-quality service, averaged through
// the clear window, and one line when it is deep enough to dim faint targets.

private let testSite = Site(name: "Test site", latitude: 54.0, longitude: -1.5, elevationM: 100, timeZoneID: "Europe/London", bortle: 5)
private let t0 = utc(2026, 11, 20, 17, 0)   // a November night in GMT, so UTC is local

/// 17:00 … 07:00: cloudy until 20:00, clear 20:00–02:00, cloudy after.
private let cloud = [90, 90, 90, 10, 10, 10, 10, 10, 10, 90, 90, 90, 90, 90, 90]
private func hours(depth: (Int) -> Double?, rainAt: Int? = nil, cloud c: [Int] = cloud) -> [HourlyConditions] {
    c.enumerated().map { i, cl in
        var h = HourlyConditions(time: t0.addingTimeInterval(Double(i) * 3600), cloudTotal: cl, cloudLow: nil, cloudMid: nil, cloudHigh: nil,
                                 tempC: nil, dewPointC: nil, humidityPct: nil, windKmh: nil, gustKmh: nil, visibilityM: nil, seeing: nil, transparency: nil)
        h.aerosolDepth = depth(i)
        h.rainChancePct = i == rainAt ? 60 : 0
        return h
    }
}
private func plan(_ hours: [HourlyConditions]) throws -> NightPlan {
    let night = try Ephemeris.night(localDate: utc(2026, 11, 20, 12, 0), site: testSite)
    return Planner.plan(night: night, forecast: Forecast(fetchedAt: t0, latitude: testSite.latitude, longitude: testSite.longitude, hours: hours, seeingSource: nil),
                        catalog: Catalog(objects: []), constellations: [], site: testSite, fov: FieldOfView(widthDeg: 2.1, heightDeg: 1.2), rule: GoRule())
}

@Test func theAirQualityRequestAsksForAerosolDepthWithYesterdayEvening() {
    let u = AirQuality.url(latitude: 53.38, longitude: -1.47)
    #expect(u.host == "air-quality-api.open-meteo.com" && u.path == "/v1/air-quality")
    let q = u.query ?? ""
    for part in ["latitude=53.3800", "longitude=-1.4700", "hourly=aerosol_optical_depth", "timezone=auto", "forecast_days=3", "past_days=1"] {
        #expect(q.contains(part), "missing \(part)")
    }
}

@Test func aerosolDepthIsReadInUTCAndAGapIsLeftOut() throws {
    let json = #"""
    {"utc_offset_seconds": 3600, "hourly": {"time": ["2026-06-30T21:00", "2026-06-30T22:00", "2026-06-30T23:00"],
     "aerosol_optical_depth": [0.12, null, 1.27]}}
    """#
    let s = try AirQuality.parse(Data(json.utf8))
    #expect(s == [AerosolSample(time: utc(2026, 6, 30, 20, 0), depth: 0.12), AerosolSample(time: utc(2026, 6, 30, 22, 0), depth: 1.27)])
}

@Test func eachHourTakesTheNearestSampleWithinHalfAnHour() {
    let h = hours(depth: { _ in nil })
    // Samples half an hour off the hour, as in a time zone such as India's, and none for the last hours.
    let samples = (0..<10).map { AerosolSample(time: t0.addingTimeInterval(Double($0) * 3600 + 1800), depth: Double($0) / 10) }
    let merged = ForecastService.merge(hours: h, aerosol: samples)
    #expect(merged[0].aerosolDepth == 0.0)
    #expect(merged[5].aerosolDepth == 0.4 || merged[5].aerosolDepth == 0.5)   // 21:30 and 22:30 are equally near 22:00
    #expect(merged[10].aerosolDepth == 0.9)                                     // exactly half an hour away still counts
    #expect(merged[11].aerosolDepth == nil && merged[14].aerosolDepth == nil)   // more than half an hour from any sample
    #expect(merged.map(\.cloudTotal) == h.map(\.cloudTotal))
}

/// An air-quality reply covering the same hours as the Open-Meteo fixture, every hour at `depth`.
private func airQuality(matching fixtureName: String, depth: Double) throws -> Data {
    let om = try JSONSerialization.jsonObject(with: try fixture(fixtureName)) as! [String: Any]
    let times = (om["hourly"] as! [String: Any])["time"] as! [String]
    return try JSONSerialization.data(withJSONObject: ["utc_offset_seconds": om["utc_offset_seconds"]!,
                                                       "hourly": ["time": times, "aerosol_optical_depth": times.map { _ in depth }]])
}

@Test func everySiteGetsAerosolDepthSoComparisonsAreFair() async throws {
    let site = Site(name: "S", latitude: 53.38, longitude: -1.47, elevationM: 100, timeZoneID: "Europe/London", bortle: 5)
    let replies = ["api.open-meteo.com": try fixture("openmeteo.json"), "air-quality-api.open-meteo.com": try airQuality(matching: "openmeteo.json", depth: 0.55)]
    let active = RecordingFetcher(byHost: replies)
    let fc = try await ForecastService.fetch(site: site, fetcher: active, now: Date(), primary: nil)
    #expect(fc.hours.count == 72 && fc.hours.allSatisfy { $0.aerosolDepth == 0.55 })
    #expect(active.hosts.contains("air-quality-api.open-meteo.com"))
    // A dark site, or home while observing elsewhere, is scored too, and haze costs score: without the same figures it
    // would look clearer than the hazy site it is compared with.
    let other = RecordingFetcher(byHost: replies)
    let compared = try await ForecastService.fetch(site: site, fetcher: other, now: Date(), primary: nil, secondOpinion: false)
    #expect(other.hosts.contains("air-quality-api.open-meteo.com"))
    #expect(compared.hours.allSatisfy { $0.aerosolDepth == 0.55 })
}

@Test func aFailedAirQualityRequestCostsOnlyTheHazeLine() async throws {
    let site = Site(name: "S", latitude: 53.38, longitude: -1.47, elevationM: 100, timeZoneID: "Europe/London", bortle: 5)
    let fc = try await ForecastService.fetch(site: site, fetcher: StubFetcher(byHost: ["api.open-meteo.com": try fixture("openmeteo.json")]), now: Date(), primary: nil)
    #expect(fc.hours.count == 72 && fc.hours.allSatisfy { $0.aerosolDepth == nil })
}

@Test func hazeIsTheAverageThroughTheClearWindow() throws {
    let window = ClearWindow(start: t0.addingTimeInterval(3 * 3600), end: t0.addingTimeInterval(9 * 3600))   // 20:00–02:00
    // Thick smoke before the window opens does not count; the six window hours average 0.5.
    let h = hours(depth: { $0 < 3 ? 2.0 : ($0 < 6 ? 0.3 : 0.7) })
    #expect(abs((Planner.haze(hours: h, window: window) ?? 0) - 0.5) < 1e-9)
    #expect(Planner.haze(hours: hours(depth: { _ in nil }), window: window) == nil)
    let p = try plan(h)
    #expect(p.primary != nil && p.hazy)
    #expect(try plan(hours(depth: { _ in Planner.hazeDepth })).hazy)             // the level itself counts
    #expect(try !plan(hours(depth: { _ in Planner.hazeDepth - 0.01 })).hazy)
    #expect(try !plan(hours(depth: { _ in nil })).hazy)                          // no figures, no line
    // No clear window: nothing to dim, nothing said.
    let cloudy = try plan(hours(depth: { _ in 1.5 }, cloud: cloud.map { _ in 90 }))
    #expect(cloudy.primary == nil && cloudy.hazeDepth == nil && !cloudy.hazy)
}

@Test func theHazeLineIsOneSentenceInThePopoverAndBeforeRainInTonightsNotifications() throws {
    var smoky = try plan(hours(depth: { _ in 1.27 }, rainAt: 10))
    #expect(Copy.haze(smoky) == "Haze or smoke: faint targets will be dim")
    let copy = Copy()
    smoky.agreement = .agree
    #expect(copy.notificationBody(plan: smoky, site: testSite)
        .hasSuffix(" Open-Meteo agrees. Haze or smoke in the air, so faint targets will be dim. Rain possible from 03:00."))
    #expect(!copy.notificationBody(plan: smoky, site: testSite, agreement: false).contains("Haze"))   // not in the tomorrow preview
    let clean = try plan(hours(depth: { _ in 0.08 }))
    #expect(Copy.haze(clean) == nil && !copy.notificationBody(plan: clean, site: testSite).contains("Haze"))
    // The heads-up carries it too.
    let due = smoky.night.sunset.addingTimeInterval(-3600 + 60)
    let headsUp = AlertEngine.step(now: due, tonight: smoky, tomorrow: nil, state: nil, settings: AlertSettings(), forecastFetchedAt: due, site: testSite, copy: copy)
    #expect(headsUp.notification?.kind == .headsUp && headsUp.notification?.body.contains("Haze or smoke in the air") == true)
}

@Test func aPlanOrForecastSavedBeforeTheHazeLineStillLoads() throws {
    let smoky = try plan(hours(depth: { _ in 1.27 }))
    let data = try JSONEncoder().encode(smoky)
    #expect(try JSONDecoder().decode(NightPlan.self, from: data).hazy)
    var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    object.removeValue(forKey: "hazeDepth")
    #expect(try !JSONDecoder().decode(NightPlan.self, from: JSONSerialization.data(withJSONObject: object)).hazy)
    let hour = #"{"time":0,"cloudTotal":10}"#
    #expect(try JSONDecoder().decode(HourlyConditions.self, from: Data(hour.utf8)).aerosolDepth == nil)
}

// Seen on screen at Niamey, 8 October 2026: the haze line under a sky score of 89, a Transparency tile reading "Good" and
// two faint targets offered. The owner's ruling: the tile, the score and the best three all follow the haze.

@Test func hazeCostsScoreInStepWithTheLightLostAndOnlyFromTheLevel() throws {
    #expect(Planner.hazePenalty(depth: nil) == 0 && Planner.hazePenalty(depth: 0.39) == 0)
    #expect(abs(Planner.hazePenalty(depth: 0.4) - 9.89) < 0.01)     // a third of the light, a third of the weight
    #expect(abs(Planner.hazePenalty(depth: 1.0) - 18.96) < 0.01)
    #expect(abs(Planner.hazePenalty(depth: 2.1) - 26.33) < 0.01)
    #expect(Planner.hazePenalty(depth: 50) <= Planner.hazeWeight)
    let clean = try plan(hours(depth: { _ in 0.1 })), smoky = try plan(hours(depth: { _ in 1.0 }))
    #expect(clean.score - smoky.score == 19)
    #expect(clean.primary == smoky.primary && smoky.qualifies)       // the verdict and the window are the cloud rule's alone
    #expect(try plan(hours(depth: { _ in nil })).score == clean.score)   // no figures: the score as it always was
}

@Test func theTransparencyTileReadsHazyAndTheReasonLineLeavesTransparencyToTheHazeLine() throws {
    func withTransparency(_ depth: Double) -> [HourlyConditions] {
        hours(depth: { _ in depth }).map { var h = $0; h.seeing = 2; h.transparency = 6; return h }   // 7Timer: "Average"
    }
    let clean = try plan(withTransparency(0.1)), smoky = try plan(withTransparency(0.8))
    #expect(Copy.transparencyText(clean) == "Average" && Copy.transparencyText(smoky) == "Hazy")
    #expect(clean.limiting.contains { $0.kind == .transparency })
    #expect(!smoky.limiting.contains { $0.kind == .transparency })
    // 7Timer calling it good does not hide the haze.
    let good = try plan(hours(depth: { _ in 0.8 }).map { var h = $0; h.seeing = 2; h.transparency = 2; return h })
    #expect(Copy.transparencyText(good.darkHours) == "Good" && Copy.transparencyText(good) == "Hazy")
}

private func target(_ id: String, _ group: TargetGroup, mag: Double?, alt: Double) -> RankedTarget {
    RankedTarget(id: id, name: id, subtitle: "", group: group, raHours: 0, decDeg: 0, sizeArcmin: 30, magnitude: mag,
                 fit: .fits, peakAltDeg: alt, peakTime: Date(timeIntervalSince1970: 0), moonSepDeg: 90, moonWashed: false, visibleFraction: 1)
}

@Test func inHazeTheBestThreeLeadWithBrightKindsAndTheBrightestOfEach() {
    // Ranked as the planner ranks: best placed first within each kind.
    let ranked = [target("faint-nebula", .nebulae, mag: 10, alt: 85), target("bright-nebula", .nebulae, mag: 4, alt: 50),
                  target("faint-galaxy", .galaxies, mag: 11, alt: 80), target("bright-galaxy", .galaxies, mag: 3.4, alt: 45),
                  target("faint-cluster", .clusters, mag: 9, alt: 75), target("bright-cluster", .clusters, mag: 1.6, alt: 40),
                  target("uranus", .planets, mag: 5.7, alt: 82), target("saturn", .planets, mag: 0.6, alt: 60)]
    #expect(Planner.best(from: ranked).map(\.id) == ["faint-nebula", "faint-galaxy", "faint-cluster"])   // a clean night: unchanged
    #expect(Planner.best(from: ranked.filter { $0.group == .planets }).map(\.id) == ["uranus"])            // best placed, as before
    #expect(Planner.best(from: ranked, hazy: true).map(\.id) == ["saturn", "bright-cluster", "bright-nebula"])
    // With no planet up, the galaxy comes back as the third, still the brightest of its kind.
    #expect(Planner.best(from: ranked.filter { $0.group != .planets }, hazy: true).map(\.id) == ["bright-cluster", "bright-nebula", "bright-galaxy"])
    // A big diffuse nebula with a bright total (the California Nebula, magnitude 6 across 145′) loses to a small bright one:
    // its light is spread too thin to survive haze.
    let spread = RankedTarget(id: "big-diffuse", name: "big-diffuse", subtitle: "", group: .nebulae, raHours: 0, decDeg: 0, sizeArcmin: 145, magnitude: 6,
                              fit: .fits, peakAltDeg: 70, peakTime: Date(timeIntervalSince1970: 0), moonSepDeg: 90, moonWashed: false, visibleFraction: 1)
    let compact = RankedTarget(id: "small-bright", name: "small-bright", subtitle: "", group: .nebulae, raHours: 0, decDeg: 0, sizeArcmin: 8, magnitude: 8,
                               fit: .fits, peakAltDeg: 40, peakTime: Date(timeIntervalSince1970: 0), moonSepDeg: 90, moonWashed: false, visibleFraction: 1)
    #expect(Planner.best(from: [spread, compact], hazy: true).map(\.id) == ["small-bright"])
    #expect(Planner.hazeBrightness(spread) > Planner.hazeBrightness(compact))
    // A planetary nebula a few arcseconds across has the highest surface brightness of all and shows as a star: it is
    // passed over while anything bigger is on the list, and offered only when it is all there is.
    let speck = RankedTarget(id: "speck", name: "speck", subtitle: "", group: .nebulae, raHours: 0, decDeg: 0, sizeArcmin: 0.03, magnitude: 11.5,
                             fit: .small, peakAltDeg: 59, peakTime: Date(timeIntervalSince1970: 0), moonSepDeg: 90, moonWashed: false, visibleFraction: 1)
    #expect(Planner.hazeBrightness(speck) < Planner.hazeBrightness(compact))
    #expect(Planner.best(from: [speck, spread, compact], hazy: true).map(\.id) == ["small-bright"])
    #expect(Planner.best(from: [speck], hazy: true).map(\.id) == ["speck"])
    // The Moon leads the planets when it is up.
    let moon = RankedTarget(id: "moon", name: "Moon", subtitle: "", group: .planets, raHours: 0, decDeg: 0, sizeArcmin: 31, magnitude: nil,
                            fit: .fits, peakAltDeg: 20, peakTime: Date(timeIntervalSince1970: 0), moonSepDeg: 0, moonWashed: false, visibleFraction: 1)
    #expect(Planner.best(from: ranked + [moon], hazy: true).first?.id == "moon")
    // A favourite still takes its slot.
    let fav = target("faint-nebula", .nebulae, mag: 10, alt: 85)
    #expect(Planner.best(from: ranked, favourites: [fav], hazy: true).map(\.id) == ["saturn", "bright-cluster", "faint-nebula"])
}

@Test func aBrightNightTakesNoNoticeOfHaze() throws {
    // Midsummer at 54° north: no astronomical darkness, so the bright plan takes over, and its targets shine through haze.
    let site = Site(name: "Test site", latitude: 54.0, longitude: -1.5, elevationM: 100, timeZoneID: "Europe/London", bortle: 5)
    let night = try Ephemeris.night(localDate: utc(2026, 6, 25, 12, 0), site: site)
    let start = utc(2026, 6, 25, 18, 0)
    let h = (0..<14).map { i -> HourlyConditions in
        var x = HourlyConditions(time: start.addingTimeInterval(Double(i) * 3600), cloudTotal: 5, cloudLow: nil, cloudMid: nil, cloudHigh: nil,
                                 tempC: nil, dewPointC: nil, humidityPct: nil, windKmh: nil, gustKmh: nil, visibilityM: nil, seeing: nil, transparency: nil)
        x.aerosolDepth = 1.5
        return x
    }
    var bright = BrightSettings(); bright.enabled = true
    let p = Planner.plan(night: night, forecast: Forecast(fetchedAt: start, latitude: site.latitude, longitude: site.longitude, hours: h, seeingSource: nil),
                         catalog: Catalog(objects: []), constellations: [], site: site, fov: FieldOfView(widthDeg: 2.1, heightDeg: 1.2), rule: GoRule(),
                         bright: bright)
    #expect(p.mode == .bright)
    #expect(p.hazeDepth == nil && !p.hazy && Copy.haze(p) == nil)
}
