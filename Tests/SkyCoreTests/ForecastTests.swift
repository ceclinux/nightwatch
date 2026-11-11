import Testing
import Foundation
@testable import SkyCore

func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

@Test func openMeteoParsesSeventyTwoHoursInUTC() throws {
    let data = try fixture("openmeteo.json")
    let hours = try OpenMeteo.parse(data)
    #expect(hours.count == 72)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    let offset = json["utc_offset_seconds"] as! Double
    let firstLocal = (json["hourly"] as! [String: Any])["time"] as! [String]
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd'T'HH:mm"; f.timeZone = TimeZone(identifier: "UTC")
    let expected = f.date(from: firstLocal[0])!.addingTimeInterval(-offset)
    #expect(hours[0].time == expected)
    #expect(hours[1].time.timeIntervalSince(hours[0].time) == 3600)
    #expect(hours[0].cloudTotal >= 0 && hours[0].cloudTotal <= 100)
    #expect(hours[0].visibilityM != nil)
    #expect(hours[0].seeing == nil)
    #expect(hours[0].rainChancePct == nil)   // a reply saved before #180 has no rain chance, and still parses
}

// Rain after the window (#180): Open-Meteo's hourly chance of rain, a gap in it left as unknown.
@Test func openMeteoReadsTheChanceOfRain() throws {
    let json = #"""
    {"utc_offset_seconds": 0, "hourly": {"time": ["2026-11-20T20:00", "2026-11-20T21:00", "2026-11-20T22:00"],
     "cloud_cover": [10, 20, 90], "precipitation_probability": [0, 34.6, null]}}
    """#
    let hours = try OpenMeteo.parse(Data(json.utf8))
    #expect(hours.map(\.rainChancePct) == [0, 35, nil])
}

@Test func openMeteoUrlHasRequiredVariables() {
    let u = OpenMeteo.url(latitude: 53.38, longitude: -1.47, days: 3).absoluteString
    #expect(u.hasPrefix("https://api.open-meteo.com/v1/forecast?"))
    for v in ["cloud_cover", "cloud_cover_low", "cloud_cover_mid", "cloud_cover_high", "dew_point_2m", "temperature_2m", "relative_humidity_2m", "wind_speed_10m", "wind_gusts_10m", "visibility", "precipitation_probability"] {
        #expect(u.contains(v))
    }
    #expect(u.contains("timezone=auto"))
    #expect(u.contains("forecast_days=3"))
}

@Test func sevenTimerUrlIsHttps() {
    #expect(SevenTimer.url(latitude: 53.38, longitude: -1.47).absoluteString.hasPrefix("https://www.7timer.info/bin/api.pl?"))
}

@Test func sevenTimerParsesInitAndTimepoints() throws {
    let data = try fixture("seventimer.json")
    let samples = try SevenTimer.parse(data)
    #expect(samples.count == 24)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    let initString = json["init"] as! String
    let f = DateFormatter(); f.dateFormat = "yyyyMMddHH"; f.timeZone = TimeZone(identifier: "UTC")
    let initDate = f.date(from: initString)!
    let firstTimepoint = ((json["dataseries"] as! [[String: Any]])[0]["timepoint"] as! Double)
    #expect(samples[0].time == initDate.addingTimeInterval(firstTimepoint * 3600))
    #expect((1...8).contains(samples[0].seeing))
    #expect((1...8).contains(samples[0].transparency))
}

@Test func mergeHoldsSeeingForThreeHoursOnly() {
    let t0 = Date(timeIntervalSince1970: 1_790_000_000)
    let hours = (0..<6).map { i in
        HourlyConditions(time: t0.addingTimeInterval(Double(i) * 3600), cloudTotal: 10, cloudLow: nil, cloudMid: nil, cloudHigh: nil,
                         tempC: nil, dewPointC: nil, humidityPct: nil, windKmh: nil, gustKmh: nil, visibilityM: nil, seeing: nil, transparency: nil)
    }
    let seeing = [SeeingSample(time: t0, seeing: 3, transparency: 2)]
    let merged = ForecastService.merge(hours: hours, seeing: seeing)
    #expect(merged[0].seeing == 3)
    #expect(merged[2].seeing == 3)
    #expect(merged[3].seeing == nil)
    #expect(merged[2].transparency == 2)
}

struct StubFetcher: Fetcher {
    let byHost: [String: Data]
    func get(_ url: URL) async throws -> Data {
        guard let d = byHost[url.host ?? ""] else { throw URLError(.badURL) }
        return d
    }
}

@Test func fetchSurvivesSevenTimerFailure() async throws {
    let om = try fixture("openmeteo.json")
    let f = StubFetcher(byHost: ["api.open-meteo.com": om])
    let site = Site(name: "S", latitude: 53.38, longitude: -1.47, elevationM: 100, timeZoneID: "Europe/London", bortle: 5)
    let fc = try await ForecastService.fetch(site: site, fetcher: f, now: Date(), primary: nil)
    #expect(fc.hours.count == 72)
    #expect(fc.seeingSource == nil)
}

@Test func fetchMergesSevenTimerWhenPresent() async throws {
    let f = StubFetcher(byHost: ["api.open-meteo.com": try fixture("openmeteo.json"), "www.7timer.info": try fixture("seventimer.json")])
    let site = Site(name: "S", latitude: 53.38, longitude: -1.47, elevationM: 100, timeZoneID: "Europe/London", bortle: 5)
    let fc = try await ForecastService.fetch(site: site, fetcher: f, now: Date(), primary: nil)
    #expect(fc.seeingSource == "7Timer")
    #expect(fc.hours.contains { $0.seeing != nil })
}

private func fakeHours(_ n: Int, cloud: Int) -> [HourlyConditions] {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    return (0..<n).map { HourlyConditions(time: t0.addingTimeInterval(Double($0) * 3600), cloudTotal: cloud, cloudLow: nil, cloudMid: nil, cloudHigh: nil,
                                          tempC: nil, dewPointC: nil, humidityPct: nil, windKmh: nil, gustKmh: nil, visibilityM: nil, seeing: nil, transparency: nil) }
}

@Test func fetchPrefersPrimaryCloudSourceAndKeepsAttribution() async throws {
    let f = StubFetcher(byHost: ["api.open-meteo.com": try fixture("openmeteo.json"), "www.7timer.info": try fixture("seventimer.json")])
    let site = Site(name: "S", latitude: 53.38, longitude: -1.47, elevationM: 100, timeZoneID: "Europe/London", bortle: 5)
    let primary: CloudProvider = { _, _ in CloudResult(hours: fakeHours(5, cloud: 7), source: "Apple Weather", markURL: "https://x/mark.png", legalURL: "https://x/legal") }
    let fc = try await ForecastService.fetch(site: site, fetcher: f, now: Date(), primary: primary)
    #expect(fc.cloudSource == "Apple Weather")
    #expect(fc.hours.count == 5 && fc.hours.allSatisfy { $0.cloudTotal == 7 })
    #expect(fc.attributionMarkURL == "https://x/mark.png" && fc.attributionLegalURL == "https://x/legal")
}

@Test func fetchFallsBackToOpenMeteoWhenPrimaryFails() async throws {
    let f = StubFetcher(byHost: ["api.open-meteo.com": try fixture("openmeteo.json")])
    let site = Site(name: "S", latitude: 53.38, longitude: -1.47, elevationM: 100, timeZoneID: "Europe/London", bortle: 5)
    let failing: CloudProvider = { _, _ in throw URLError(.notConnectedToInternet) }
    let fc = try await ForecastService.fetch(site: site, fetcher: f, now: Date(), primary: failing)
    #expect(fc.cloudSource == "Open-Meteo")
    #expect(fc.hours.count == 72)
    #expect(fc.attributionMarkURL == nil)
    let empty: CloudProvider = { _, _ in CloudResult(hours: [], source: "Apple Weather") }
    let fc2 = try await ForecastService.fetch(site: site, fetcher: f, now: Date(), primary: empty)
    #expect(fc2.cloudSource == "Open-Meteo")
}

@Test func cachedForecastWithoutSourceFieldsStillDecodes() throws {
    let json = #"{"fetchedAt":"2026-09-24T12:00:00Z","latitude":54.0,"longitude":-1.5,"hours":[],"seeingSource":null}"#
    let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
    let fc = try d.decode(Forecast.self, from: Data(json.utf8))
    #expect(fc.cloudSource == nil && fc.attributionMarkURL == nil)
}

final class RecordingFetcher: Fetcher, @unchecked Sendable {
    let byHost: [String: Data]
    private(set) var hosts: [String] = []
    init(byHost: [String: Data]) { self.byHost = byHost }
    func get(_ url: URL) async throws -> Data {
        hosts.append(url.host ?? "")
        guard let d = byHost[url.host ?? ""] else { throw URLError(.badURL) }
        return d
    }
}

@Test func fetchKeepsOpenMeteoAsSecondOpinionWhenPrimaryAnswers() async throws {
    let f = StubFetcher(byHost: ["api.open-meteo.com": try fixture("openmeteo.json")])
    let site = Site(name: "S", latitude: 53.38, longitude: -1.47, elevationM: 100, timeZoneID: "Europe/London", bortle: 5)
    let primary: CloudProvider = { _, _ in CloudResult(hours: fakeHours(5, cloud: 7), source: "Apple Weather") }
    let fc = try await ForecastService.fetch(site: site, fetcher: f, now: Date(), primary: primary)
    let second = try #require(fc.secondOpinion)
    #expect(second.source == "Open-Meteo")
    #expect(second.hours.count == 72)
    #expect(fc.hours.allSatisfy { $0.cloudTotal == 7 })   // the primary still drives
}

@Test func noSecondOpinionWhenOpenMeteoIsAlreadyPrimary() async throws {
    let f = StubFetcher(byHost: ["api.open-meteo.com": try fixture("openmeteo.json")])
    let site = Site(name: "S", latitude: 53.38, longitude: -1.47, elevationM: 100, timeZoneID: "Europe/London", bortle: 5)
    let failing: CloudProvider = { _, _ in throw URLError(.notConnectedToInternet) }
    #expect(try await ForecastService.fetch(site: site, fetcher: f, now: Date(), primary: failing).secondOpinion == nil)
    #expect(try await ForecastService.fetch(site: site, fetcher: f, now: Date(), primary: nil).secondOpinion == nil)
}

@Test func failedSecondFetchLeavesTheForecastIntact() async throws {
    let f = StubFetcher(byHost: [:])   // Open-Meteo unreachable
    let site = Site(name: "S", latitude: 53.38, longitude: -1.47, elevationM: 100, timeZoneID: "Europe/London", bortle: 5)
    let primary: CloudProvider = { _, _ in CloudResult(hours: fakeHours(5, cloud: 7), source: "Apple Weather") }
    let fc = try await ForecastService.fetch(site: site, fetcher: f, now: Date(), primary: primary)
    #expect(fc.hours.count == 5)
    #expect(fc.secondOpinion == nil)
}

@Test func fetchWithoutSecondOpinionMakesOneOpenMeteoCallAtMost() async throws {
    let f = RecordingFetcher(byHost: ["api.open-meteo.com": try fixture("openmeteo.json")])
    let site = Site(name: "S", latitude: 53.38, longitude: -1.47, elevationM: 100, timeZoneID: "Europe/London", bortle: 5)
    let primary: CloudProvider = { _, _ in CloudResult(hours: fakeHours(5, cloud: 7), source: "Apple Weather") }
    let fc = try await ForecastService.fetch(site: site, fetcher: f, now: Date(), primary: primary, secondOpinion: false)
    #expect(fc.secondOpinion == nil)
    #expect(f.hosts.filter { $0 == "api.open-meteo.com" }.isEmpty)
}

@Test func zeroFourForecastDecodes() throws {
    let json = #"{"fetchedAt":0,"latitude":54.0,"longitude":-1.5,"hours":[],"seeingSource":null,"cloudSource":"Apple Weather"}"#
    let fc = try JSONDecoder().decode(Forecast.self, from: Data(json.utf8))
    #expect(fc.secondOpinion == nil && fc.cloudSource == "Apple Weather")
}

@Test func secondOpinionRequestIncludesTheDayBefore() async throws {
    // Open-Meteo starts at 00:00 local, so a patrol just after midnight needs yesterday's evening hours for tonight's darkness.
    let f = RecordingURLFetcher(byHost: ["api.open-meteo.com": try fixture("openmeteo.json")])
    let site = Site(name: "S", latitude: 53.38, longitude: -1.47, elevationM: 100, timeZoneID: "Europe/London", bortle: 5)
    let primary: CloudProvider = { _, _ in CloudResult(hours: fakeHours(5, cloud: 7), source: "Apple Weather") }
    _ = try await ForecastService.fetch(site: site, fetcher: f, now: Date(), primary: primary)
    let om = try #require(f.urls.first { $0.host == "api.open-meteo.com" })
    #expect(om.query?.contains("past_days=1") == true)
    #expect(OpenMeteo.url(latitude: 53.38, longitude: -1.47, days: 3).query?.contains("past_days") == false)   // the primary request is unchanged
}

final class RecordingURLFetcher: Fetcher, @unchecked Sendable {
    let byHost: [String: Data]
    private(set) var urls: [URL] = []
    init(byHost: [String: Data]) { self.byHost = byHost }
    func get(_ url: URL) async throws -> Data {
        urls.append(url)
        guard let d = byHost[url.host ?? ""] else { throw URLError(.badURL) }
        return d
    }
}

@Test func primaryPauseLeavesAppleWeatherAloneForFiveMinutesAndRetriesSoonOnceItHasAnswered() {
    var p = PrimaryPause()
    let t = Date(timeIntervalSince1970: 0)
    #expect(!p.paused(now: t))
    p.record(answered: false, now: t)
    #expect(p.paused(now: t.addingTimeInterval(299)))
    #expect(!p.paused(now: t.addingTimeInterval(300)))
    #expect(p.maxAge(fromPrimary: false) == 30 * 60)   // never answered: a build with no Apple Weather keeps its cache
    p.record(answered: true, now: t.addingTimeInterval(300))
    #expect(!p.paused(now: t.addingTimeInterval(301)))
    #expect(p.maxAge(fromPrimary: true) == 30 * 60)
    #expect(p.maxAge(fromPrimary: false) == 5 * 60)    // it has answered here: a fallback forecast is replaced soon
}
