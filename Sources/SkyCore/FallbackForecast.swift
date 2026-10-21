import Foundation

/// MET Norway's Locationforecast 2.0 (`complete`), the third source when Apple Weather and Open-Meteo cannot be read. No key; it needs an identifying
/// User-Agent (`URLSessionFetcher` sends one), credit under CC BY 4.0, and asks for no repeat request before the reply's `Expires` time.
public enum MetNorway {
    public static func url(latitude: Double, longitude: Double) -> URL {
        var c = URLComponents(string: "https://api.met.no/weatherapi/locationforecast/2.0/complete")!
        c.queryItems = [.init(name: "lat", value: String(format: "%.4f", latitude)), .init(name: "lon", value: String(format: "%.4f", longitude))]
        return c.url!
    }

    /// Hourly conditions. The service is hourly for about three days and wider after that, so each step is held until the next one. Wind comes in
    /// metres a second (to km/h); there is no visibility, so a fog fraction stands in for it (20 km clear, down to 500 m in fog); a step with no
    /// gust leaves it unknown.
    public static func parse(_ data: Data) throws -> [HourlyConditions] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let props = root["properties"] as? [String: Any], let series = props["timeseries"] as? [[String: Any]] else { throw ForecastError.malformed("met.no") }
        let iso = ISO8601DateFormatter()
        struct Step { var time: Date; var d: [String: Double] }
        let steps: [Step] = series.compactMap { e in
            guard let t = (e["time"] as? String).flatMap({ iso.date(from: $0) }),
                  let d = ((e["data"] as? [String: Any])?["instant"] as? [String: Any])?["details"] as? [String: Double],
                  d["cloud_area_fraction"] != nil else { return nil }
            return Step(time: t, d: d)
        }.sorted { $0.time < $1.time }
        guard !steps.isEmpty else { throw ForecastError.malformed("met.no empty") }
        func pct(_ v: Double?) -> Int? { v.map { Int($0.rounded()) } }
        var out: [HourlyConditions] = []
        for (i, s) in steps.enumerated() {
            let hours = i + 1 < steps.count ? max(1, Int((steps[i + 1].time.timeIntervalSince(s.time) / 3600).rounded())) : 1
            let fog = s.d["fog_area_fraction"]
            for h in 0..<hours {
                out.append(HourlyConditions(time: s.time.addingTimeInterval(Double(h) * 3600), cloudTotal: pct(s.d["cloud_area_fraction"]) ?? 0,
                                            cloudLow: pct(s.d["cloud_area_fraction_low"]), cloudMid: pct(s.d["cloud_area_fraction_medium"]),
                                            cloudHigh: pct(s.d["cloud_area_fraction_high"]), tempC: s.d["air_temperature"], dewPointC: s.d["dew_point_temperature"],
                                            humidityPct: pct(s.d["relative_humidity"]), windKmh: s.d["wind_speed"].map { $0 * 3.6 },
                                            gustKmh: s.d["wind_speed_of_gust"].map { $0 * 3.6 },
                                            visibilityM: fog.map { max(500, 20_000 * (1 - $0 / 100)) }, seeing: nil, transparency: nil))
            }
        }
        return out
    }
}

/// 7Timer's astronomy product as a last-resort cloud source. Its cloud cover is a 1 to 9 scale in bands (1 is 0 to 6 percent, 9 is 94 to 100), in
/// 3-hour steps for three days, so each sample is held for three hours at the middle of its band. It knows nothing of low, middle or high cloud,
/// dew point or wind, which are left unknown.
public enum SevenTimerCloud {
    /// The middle of each band, indexed by cloudcover minus one.
    static let bandMiddle = [3, 12, 25, 37, 50, 62, 75, 87, 97]

    private struct Payload: Decodable {
        let `init`: String
        let dataseries: [Entry]
        struct Entry: Decodable { let timepoint: Double; let cloudcover: Int; let seeing: Int?; let transparency: Int?; let temp2m: Double? }
    }

    public static func parse(_ data: Data) throws -> [HourlyConditions] {
        let p = try JSONDecoder().decode(Payload.self, from: data)
        let f = DateFormatter(); f.dateFormat = "yyyyMMddHH"; f.timeZone = TimeZone(identifier: "UTC"); f.locale = Locale(identifier: "en_US_POSIX")
        guard let start = f.date(from: p.`init`), !p.dataseries.isEmpty else { throw ForecastError.malformed("7timer") }
        return p.dataseries.flatMap { e -> [HourlyConditions] in
            let cloud = bandMiddle[min(8, max(0, e.cloudcover - 1))]
            return (0..<3).map { h in
                HourlyConditions(time: start.addingTimeInterval((e.timepoint + Double(h)) * 3600), cloudTotal: cloud, cloudLow: nil, cloudMid: nil, cloudHigh: nil,
                                 tempC: e.temp2m, dewPointC: nil, humidityPct: nil, windKmh: nil, gustKmh: nil, visibilityM: nil,
                                 seeing: e.seeing, transparency: e.transparency)
            }
        }
    }
}

/// Remembers that the first source said "too many requests", so the next fetches go straight to the fallbacks instead of asking again.
public final class RateLimitMemory: @unchecked Sendable {
    public static let shared = RateLimitMemory()
    private let lock = NSLock()
    private var until: Date?
    public init() {}
    public func block(until date: Date) { lock.lock(); until = date; lock.unlock() }
    public func isBlocked(at now: Date) -> Bool { lock.lock(); defer { lock.unlock() }; return until.map { now < $0 } ?? false }
}

/// Apple Weather, then Open-Meteo (SkyCore's `ForecastService`), then MET Norway, then 7Timer. When every source fails the first error is thrown, so the
/// page can say why the main one refused.
public enum ForecastChain {
    public static let refusalMemory = 30 * 60.0

    public static func fetch(site: Site, fetcher: Fetcher, now: Date, primary: CloudProvider? = nil, secondOpinion: Bool = true,
                             memory: RateLimitMemory = .shared) async throws -> Forecast {
        var first: Error?
        // With Open-Meteo recently refusing, skip it, unless Apple Weather is being asked (it might answer, and costs Open-Meteo nothing).
        if primary != nil || !memory.isBlocked(at: now) {
            do { return try await ForecastService.fetch(site: site, fetcher: fetcher, now: now, primary: primary,
                                                           secondOpinion: secondOpinion && !memory.isBlocked(at: now)) }
            catch {
                first = error
                if (error as? HTTPFailure)?.isRateLimit == true { memory.block(until: now.addingTimeInterval(refusalMemory)) }
            }
        }
        do { return try await metNorway(site: site, fetcher: fetcher, now: now) } catch { first = first ?? error }
        do { return try await sevenTimer(site: site, fetcher: fetcher, now: now) } catch { first = first ?? error }
        throw first ?? ForecastError.malformed("no source")
    }

    static func metNorway(site: Site, fetcher: Fetcher, now: Date) async throws -> Forecast {
        var hours = try MetNorway.parse(try await fetcher.get(MetNorway.url(latitude: site.latitude, longitude: site.longitude)))
        var seeingSource: String? = nil
        if let data = try? await fetcher.get(SevenTimer.url(latitude: site.latitude, longitude: site.longitude)),
           let samples = try? SevenTimer.parse(data), !samples.isEmpty {
            hours = ForecastService.merge(hours: hours, seeing: samples)
            seeingSource = "7Timer"
        }
        return Forecast(fetchedAt: now, latitude: site.latitude, longitude: site.longitude, hours: hours, seeingSource: seeingSource, cloudSource: "MET Norway")
    }

    static func sevenTimer(site: Site, fetcher: Fetcher, now: Date) async throws -> Forecast {
        let hours = try SevenTimerCloud.parse(try await fetcher.get(SevenTimer.url(latitude: site.latitude, longitude: site.longitude)))
        return Forecast(fetchedAt: now, latitude: site.latitude, longitude: site.longitude, hours: hours, seeingSource: "7Timer", cloudSource: "7Timer")
    }
}
