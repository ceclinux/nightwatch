import Testing
import Foundation
import SkyCore
@testable import PhoneCore

/// A fetcher that answers by host, and records what was asked.
final class ByHost: Fetcher, @unchecked Sendable {
    var answers: [String: Result<Data, Error>] = [:]
    var asked: [String] = []
    func get(_ url: URL) async throws -> Data {
        let host = url.host ?? ""
        asked.append(host)
        switch answers[host] { case .success(let d): return d; case .failure(let e): throw e; case nil: throw URLError(.notConnectedToInternet) }
    }
}

private let metJSON = Data("""
{"type":"Feature","properties":{"meta":{},"timeseries":[
 {"time":"2026-10-14T18:00:00Z","data":{"instant":{"details":{"air_temperature":14.3,"cloud_area_fraction":92.2,"cloud_area_fraction_high":85.9,"cloud_area_fraction_low":14.8,"cloud_area_fraction_medium":37.5,"dew_point_temperature":9.9,"fog_area_fraction":0.0,"relative_humidity":74.7,"wind_speed":6.7}}}},
 {"time":"2026-10-14T19:00:00Z","data":{"instant":{"details":{"air_temperature":13.0,"cloud_area_fraction":10.0,"cloud_area_fraction_high":0.0,"cloud_area_fraction_low":5.0,"cloud_area_fraction_medium":5.0,"dew_point_temperature":8.0,"fog_area_fraction":60.0,"relative_humidity":80.0,"wind_speed":2.0,"wind_speed_of_gust":5.0}}}},
 {"time":"2026-10-14T22:00:00Z","data":{"instant":{"details":{"air_temperature":11.0,"cloud_area_fraction":50.0,"relative_humidity":85.0,"wind_speed":1.0}}}}
]}}
""".utf8)

private let sevenJSON = Data("""
{"product":"astro","init":"2026101412","dataseries":[
 {"timepoint":3,"cloudcover":1,"seeing":3,"transparency":3,"temp2m":13},
 {"timepoint":6,"cloudcover":9,"seeing":5,"transparency":4,"temp2m":12}]}
""".utf8)

@Test func metNorwayStepsBecomeHoursWithUnitsAndMissingValuesLeftUnknown() throws {
    let h = try MetNorway.parse(metJSON)
    #expect(h.count == 5)                                                        // 18, 19, then 22 held for 20, 21, 22 as well
    #expect(h[0].cloudTotal == 92 && h[0].cloudLow == 15 && h[0].cloudHigh == 86)
    #expect(h[0].windKmh == 6.7 * 3.6 && h[0].gustKmh == nil)                    // m/s to km/h; this step has no gust
    #expect(h[1].gustKmh == 5.0 * 3.6)
    #expect(h[0].visibilityM == 20_000 && h[1].visibilityM == 8_000)             // fog 0 and 60 percent
    #expect(h[2].time == h[1].time.addingTimeInterval(3600) && h[2].cloudTotal == 10)
    #expect(h.last?.cloudTotal == 50 && h.last?.cloudLow == nil)
}

@Test func sevenTimerBandsBecomeTheirMiddleHeldForThreeHours() throws {
    let h = try SevenTimerCloud.parse(sevenJSON)
    #expect(h.count == 6)
    #expect(h[0].cloudTotal == 3 && h[3].cloudTotal == 97)                       // band 1 and band 9
    #expect(h[0].time == utc(2026, 10, 14, 15) && h[1].time == utc(2026, 10, 14, 16))
    #expect(h[0].seeing == 3 && h[0].cloudLow == nil)
}

@Test func theChainFallsThroughOpenMeteoToMetNorwayThenSevenTimerAndThrowsTheFirstErrorIfAllFail() async throws {
    let refuse = HTTPFailure(status: 429, reason: "Daily API request limit exceeded.")
    let fetcher = ByHost()
    fetcher.answers["api.open-meteo.com"] = .failure(refuse)
    fetcher.answers["api.met.no"] = .success(metJSON)
    fetcher.answers["www.7timer.info"] = .success(sevenJSON)
    var f = try await ForecastChain.fetch(site: sheffield, fetcher: fetcher, now: utc(2026, 10, 14, 18), memory: RateLimitMemory())
    #expect(f.cloudSource == "MET Norway" && f.seeingSource == "7Timer")
    #expect(f.hours.contains { $0.seeing != nil })                               // 7Timer seeing merged on top

    fetcher.answers["api.met.no"] = .failure(URLError(.timedOut))
    f = try await ForecastChain.fetch(site: sheffield, fetcher: fetcher, now: utc(2026, 10, 14, 18), memory: RateLimitMemory())
    #expect(f.cloudSource == "7Timer")

    fetcher.answers["www.7timer.info"] = .failure(URLError(.notConnectedToInternet))
    do { _ = try await ForecastChain.fetch(site: sheffield, fetcher: fetcher, now: utc(2026, 10, 14, 18), memory: RateLimitMemory()); Issue.record("should have thrown") }
    catch { #expect((error as? HTTPFailure)?.status == 429) }                     // the first source's reason, not the last's
}

@Test func afterARefusalOpenMeteoIsNotAskedAgainForThirtyMinutes() async throws {
    let fetcher = ByHost(), memory = RateLimitMemory()
    fetcher.answers["api.open-meteo.com"] = .failure(HTTPFailure(status: 429, reason: nil))
    fetcher.answers["api.met.no"] = .success(metJSON)
    fetcher.answers["www.7timer.info"] = .success(sevenJSON)
    _ = try await ForecastChain.fetch(site: sheffield, fetcher: fetcher, now: utc(2026, 10, 14, 18), memory: memory)
    #expect(fetcher.asked.filter { $0 == "api.open-meteo.com" }.count == 1)
    _ = try await ForecastChain.fetch(site: sheffield, fetcher: fetcher, now: utc(2026, 10, 14, 18, 10), memory: memory)
    #expect(fetcher.asked.filter { $0 == "api.open-meteo.com" }.count == 1)       // skipped
    _ = try await ForecastChain.fetch(site: sheffield, fetcher: fetcher, now: utc(2026, 10, 14, 18, 40), memory: memory)
    #expect(fetcher.asked.filter { $0 == "api.open-meteo.com" }.count == 2)       // asked again after half an hour
}

@MainActor @Test func aFallbackForecastPlansAndNamesItsSource() async throws {
    let clock = Clock(utc(2026, 10, 14, 19))
    let fetcher = ByHost()
    fetcher.answers["api.open-meteo.com"] = .failure(HTTPFailure(status: 429, reason: nil))
    fetcher.answers["api.met.no"] = .success(metJSON)
    fetcher.answers["www.7timer.info"] = .success(sevenJSON)
    let store = PhoneStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("fb-\(UUID().uuidString)"),
                           provider: { site, now, _ in try await ForecastChain.fetch(site: site, fetcher: fetcher, now: now, memory: RateLimitMemory()) },
                           scheduler: FakeScheduler(), clock: { clock.now }, occultations: false, darkLookups: nil)
    store.config.sites = [sheffield]; store.config.activeSiteName = "Sheffield"
    await store.refresh()
    #expect(store.tonight?.source == "MET Norway")
    #expect(store.offline == false)
}
