import Foundation

public struct HourlyConditions: Codable, Equatable, Sendable {
    public var time: Date
    public var cloudTotal: Int
    public var cloudLow: Int?
    public var cloudMid: Int?
    public var cloudHigh: Int?
    public var tempC: Double?
    public var dewPointC: Double?
    public var humidityPct: Int?
    public var windKmh: Double?
    public var gustKmh: Double?
    public var visibilityM: Double?
    public var seeing: Int?
    public var transparency: Int?
    /// The chance of rain or snow in this hour, 0 to 100 (#180); nil from a forecast cached by an earlier version or a source without one.
    public var rainChancePct: Int? = nil
    /// Aerosol optical depth at 550 nm in this hour (#183): how much smoke, dust and pollution the air carries. Nil without
    /// the air-quality forecast: a failed request, or a forecast cached by an earlier version.
    public var aerosolDepth: Double? = nil

    public init(time: Date, cloudTotal: Int, cloudLow: Int?, cloudMid: Int?, cloudHigh: Int?, tempC: Double?, dewPointC: Double?,
                humidityPct: Int?, windKmh: Double?, gustKmh: Double?, visibilityM: Double?, seeing: Int?, transparency: Int?) {
        self.time = time; self.cloudTotal = cloudTotal; self.cloudLow = cloudLow; self.cloudMid = cloudMid; self.cloudHigh = cloudHigh
        self.tempC = tempC; self.dewPointC = dewPointC; self.humidityPct = humidityPct; self.windKmh = windKmh; self.gustKmh = gustKmh
        self.visibilityM = visibilityM; self.seeing = seeing; self.transparency = transparency
    }

    /// Cloud as the go rule judges it: see `CloudCover.effective`.
    public var effectiveCloud: Int { CloudCover.effective(total: cloudTotal, low: cloudLow, mid: cloudMid, high: cloudHigh) }
}

public enum CloudCover {
    /// Thin high cloud counts for half (owner's UAT, 30 September 2026): stacking and noise reduction work through a veil
    /// of cirrus, while low and mid cloud block the sky. The layers are combined as if they overlapped at random, and the
    /// result is never worse than the source's own total. Without layers it is the total.
    /// ponytail: a fixed half weight for high cloud; a setting, or thickness from another source, if it misjudges.
    public static let highCloudWeight = 0.5
    public static func effective(total: Int, low: Int?, mid: Int?, high: Int?) -> Int {
        guard let low, let mid, let high else { return total }
        func clear(_ pct: Int, _ weight: Double = 1) -> Double { 1 - weight * Double(min(max(pct, 0), 100)) / 100 }
        let weighted = Int((100 * (1 - clear(low) * clear(mid) * clear(high, highCloudWeight))).rounded())
        return min(total, weighted)
    }
}

/// One hour of a second source's cloud: all the agreement line compares. The layers let it judge high cloud the way the
/// go rule does; a forecast saved before they were kept has none, and is judged on its total.
public struct HourlyCloud: Codable, Equatable, Sendable {
    public var time: Date
    public var cloudTotal: Int
    public var cloudLow: Int?
    public var cloudMid: Int?
    public var cloudHigh: Int?
    public init(time: Date, cloudTotal: Int, cloudLow: Int? = nil, cloudMid: Int? = nil, cloudHigh: Int? = nil) {
        self.time = time; self.cloudTotal = cloudTotal; self.cloudLow = cloudLow; self.cloudMid = cloudMid; self.cloudHigh = cloudHigh
    }
}

/// Open-Meteo's cloud beside Apple Weather's, for the agreement line (v0.5). Never drives the verdict; never logged.
public struct SecondOpinion: Codable, Equatable, Sendable {
    public var source: String
    public var hours: [HourlyCloud]
    public init(source: String, hours: [HourlyCloud]) { self.source = source; self.hours = hours }
}

public struct Forecast: Codable, Equatable, Sendable {
    public var fetchedAt: Date
    public var latitude: Double
    public var longitude: Double
    public var hours: [HourlyConditions]
    public var seeingSource: String?
    /// "Apple Weather" or "Open-Meteo": which service supplied the cloud, wind and dew-point hours.
    public var cloudSource: String?
    /// Apple's attribution mark and legal page, present only when cloudSource is Apple Weather.
    public var attributionMarkURL: String?
    public var attributionLegalURL: String?
    /// Open-Meteo's cloud when Apple Weather is primary (v0.5); nil on unsigned builds and for dark sites.
    public var secondOpinion: SecondOpinion?
    public init(fetchedAt: Date, latitude: Double, longitude: Double, hours: [HourlyConditions], seeingSource: String?,
                cloudSource: String? = nil, attributionMarkURL: String? = nil, attributionLegalURL: String? = nil, secondOpinion: SecondOpinion? = nil) {
        self.fetchedAt = fetchedAt; self.latitude = latitude; self.longitude = longitude; self.hours = hours; self.seeingSource = seeingSource
        self.cloudSource = cloudSource; self.attributionMarkURL = attributionMarkURL; self.attributionLegalURL = attributionLegalURL
        self.secondOpinion = secondOpinion
    }
}

/// Hours from a primary cloud service, with the attribution it requires.
public struct CloudResult: Sendable {
    public var hours: [HourlyConditions]
    public var source: String
    public var markURL: String?
    public var legalURL: String?
    public init(hours: [HourlyConditions], source: String, markURL: String? = nil, legalURL: String? = nil) {
        self.hours = hours; self.source = source; self.markURL = markURL; self.legalURL = legalURL
    }
}
public typealias CloudProvider = @Sendable (Site, Date) async throws -> CloudResult

public protocol Fetcher: Sendable {
    func get(_ url: URL) async throws -> Data
}

/// The service answered, and said no. Keeps the status, and the service's own reason when it gives one, so a daily request limit
/// reads as that and not as a missing connection.
public struct HTTPFailure: Error, Equatable, Sendable, LocalizedError {
    public let status: Int
    public let reason: String?
    public init(status: Int, reason: String?) { self.status = status; self.reason = reason }
    /// Too many requests from this address (Open-Meteo says "Daily API request limit exceeded" with a 429).
    public var isRateLimit: Bool { status == 429 }
    public var errorDescription: String? {
        if isRateLimit { return L10n.text("The forecast service has refused more requests from this connection today. It usually resets overnight; Nightwatch will try again in 30 minutes.") }
        return L10n.format("The forecast service answered with an error (\(status))") + (reason.map { ": \($0)" } ?? ".")
    }
}

public struct URLSessionFetcher: Fetcher {
    /// Names the app and its real version, as AuroraWatch UK's API terms ask ("set the HTTP User-Agent header to match the
    /// name of your app"), so every service can see who is calling.
    public static let userAgent = "Nightwatch/\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev") (https://github.com/rsutcliffe/nightwatch)"
    public var timeout: TimeInterval
    public init(timeout: TimeInterval = 20) { self.timeout = timeout }
    public func get(_ url: URL) async throws -> Data {
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.setValue(URLSessionFetcher.userAgent, forHTTPHeaderField: "User-Agent")
        RequestTally.record(url)
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let reason = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["reason"] as? String
            throw HTTPFailure(status: http.statusCode, reason: reason)
        }
        return data
    }
}

public enum ForecastError: Error { case malformed(String) }

public enum OpenMeteo {
    static let variables = ["cloud_cover", "cloud_cover_low", "cloud_cover_mid", "cloud_cover_high", "dew_point_2m", "temperature_2m",
                            "relative_humidity_2m", "wind_speed_10m", "wind_gusts_10m", "visibility", "precipitation_probability"]

    /// `pastDays`: also return that many days before today. The second opinion asks for 1: Open-Meteo starts at 00:00 local,
    /// so a patrol just after midnight would otherwise lack the evening hours of tonight's darkness.
    public static func url(latitude: Double, longitude: Double, days: Int, pastDays: Int = 0) -> URL {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            .init(name: "latitude", value: String(format: "%.4f", latitude)),
            .init(name: "longitude", value: String(format: "%.4f", longitude)),
            .init(name: "hourly", value: variables.joined(separator: ",")),
            .init(name: "timezone", value: "auto"),
            .init(name: "forecast_days", value: String(days))
        ] + (pastDays > 0 ? [.init(name: "past_days", value: String(pastDays))] : [])
        return c.url!
    }

    private struct Payload: Decodable {
        let utc_offset_seconds: Double
        let hourly: Hourly
        struct Hourly: Decodable {
            let time: [String]
            let cloud_cover: [Int?]
            let cloud_cover_low: [Int?]?
            let cloud_cover_mid: [Int?]?
            let cloud_cover_high: [Int?]?
            let dew_point_2m: [Double?]?
            let temperature_2m: [Double?]?
            let relative_humidity_2m: [Int?]?
            let wind_speed_10m: [Double?]?
            let wind_gusts_10m: [Double?]?
            let visibility: [Double?]?
            let precipitation_probability: [Double?]?
        }
    }

    public static func parse(_ data: Data) throws -> [HourlyConditions] {
        let p = try JSONDecoder().decode(Payload.self, from: data)
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        var out: [HourlyConditions] = []
        for (i, ts) in p.hourly.time.enumerated() {
            guard let local = f.date(from: ts) else { throw ForecastError.malformed("time \(ts)") }
            func at<T>(_ a: [T?]?) -> T? { guard let a, i < a.count else { return nil }; return a[i] }
            var h = HourlyConditions(
                time: local.addingTimeInterval(-p.utc_offset_seconds),
                cloudTotal: at(p.hourly.cloud_cover) ?? 100,
                cloudLow: at(p.hourly.cloud_cover_low), cloudMid: at(p.hourly.cloud_cover_mid), cloudHigh: at(p.hourly.cloud_cover_high),
                tempC: at(p.hourly.temperature_2m), dewPointC: at(p.hourly.dew_point_2m), humidityPct: at(p.hourly.relative_humidity_2m),
                windKmh: at(p.hourly.wind_speed_10m), gustKmh: at(p.hourly.wind_gusts_10m), visibilityM: at(p.hourly.visibility),
                seeing: nil, transparency: nil)
            h.rainChancePct = at(p.hourly.precipitation_probability).map { Int($0.rounded()) }
            out.append(h)
        }
        return out
    }
}

public struct AerosolSample: Equatable, Sendable {
    public let time: Date
    public let depth: Double
    public init(time: Date, depth: Double) { self.time = time; self.depth = depth }
}

/// Aerosol optical depth for the haze line (#183): the Copernicus Atmosphere Monitoring Service's forecast, by the hour for
/// a place, from Open-Meteo's air-quality service. Keyless, CC BY 4.0, both credited in NOTICE.
public enum AirQuality {
    /// `past_days=1` for the same reason as the second opinion: the reply starts at 00:00 local, and a patrol just after
    /// midnight still needs the evening hours of tonight's darkness. Three days cover tonight and tomorrow night.
    public static func url(latitude: Double, longitude: Double) -> URL {
        var c = URLComponents(string: "https://air-quality-api.open-meteo.com/v1/air-quality")!
        c.queryItems = [
            .init(name: "latitude", value: String(format: "%.4f", latitude)),
            .init(name: "longitude", value: String(format: "%.4f", longitude)),
            .init(name: "hourly", value: "aerosol_optical_depth"),
            .init(name: "timezone", value: "auto"),
            .init(name: "forecast_days", value: "3"),
            .init(name: "past_days", value: "1")
        ]
        return c.url!
    }

    private struct Payload: Decodable {
        let utc_offset_seconds: Double
        let hourly: Hourly
        struct Hourly: Decodable { let time: [String]; let aerosol_optical_depth: [Double?] }
    }

    /// Hours with no figure are left out.
    public static func parse(_ data: Data) throws -> [AerosolSample] {
        let p = try JSONDecoder().decode(Payload.self, from: data)
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return try zip(p.hourly.time, p.hourly.aerosol_optical_depth).compactMap { ts, depth in
            guard let local = f.date(from: ts) else { throw ForecastError.malformed("time \(ts)") }
            return depth.map { AerosolSample(time: local.addingTimeInterval(-p.utc_offset_seconds), depth: $0) }
        }
    }
}

public struct SeeingSample: Equatable, Sendable {
    public let time: Date
    public let seeing: Int
    public let transparency: Int
    public init(time: Date, seeing: Int, transparency: Int) { self.time = time; self.seeing = seeing; self.transparency = transparency }
}

public enum SevenTimer {
    public static func url(latitude: Double, longitude: Double) -> URL {
        var c = URLComponents(string: "https://www.7timer.info/bin/api.pl")!
        c.queryItems = [
            .init(name: "lon", value: String(format: "%.2f", longitude)),
            .init(name: "lat", value: String(format: "%.2f", latitude)),
            .init(name: "product", value: "astro"),
            .init(name: "output", value: "json")
        ]
        return c.url!
    }

    private struct Payload: Decodable {
        let `init`: String
        let dataseries: [Entry]
        struct Entry: Decodable { let timepoint: Double; let seeing: Int; let transparency: Int }
    }

    /// `init` is the model run in UTC as YYYYMMDDHH; `timepoint` is hours after that run (observed from live data, 2026-09-23).
    public static func parse(_ data: Data) throws -> [SeeingSample] {
        let p = try JSONDecoder().decode(Payload.self, from: data)
        let f = DateFormatter()
        f.dateFormat = "yyyyMMddHH"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        guard let start = f.date(from: p.`init`) else { throw ForecastError.malformed("init \(p.`init`)") }
        return p.dataseries.map { SeeingSample(time: start.addingTimeInterval($0.timepoint * 3600), seeing: $0.seeing, transparency: $0.transparency) }
    }
}

public enum ForecastService {
    /// Attach the most recent 7Timer sample at or before each hour, held for at most 3 hours.
    public static func merge(hours: [HourlyConditions], seeing: [SeeingSample]) -> [HourlyConditions] {
        let sorted = seeing.sorted { $0.time < $1.time }
        return hours.map { h in
            var h = h
            if let s = sorted.last(where: { $0.time <= h.time }), h.time.timeIntervalSince(s.time) < 3 * 3600 {
                h.seeing = s.seeing
                h.transparency = s.transparency
            }
            return h
        }
    }

    /// Give each hour the aerosol depth of the sample nearest it, within half an hour: Apple Weather's hours fall on the UTC
    /// hour and the air-quality reply on the local one, which differ by 30 minutes in a time zone such as India's.
    public static func merge(hours: [HourlyConditions], aerosol: [AerosolSample]) -> [HourlyConditions] {
        hours.map { h in
            var h = h
            if let s = aerosol.min(by: { abs($0.time.timeIntervalSince(h.time)) < abs($1.time.timeIntervalSince(h.time)) }),
               abs(s.time.timeIntervalSince(h.time)) <= 1800 { h.aerosolDepth = s.depth }
            return h
        }
    }

    /// Cloud hours from `primary` (WeatherKit by default) when it answers, else Open-Meteo; 7Timer seeing merged on top either way.
    /// `secondOpinion`: also keep Open-Meteo's cloud when the primary answers (the active site only; dark sites pass false).
    /// Every site gets the aerosol depth behind the haze line (#183), since haze costs sky score and a dark site or home
    /// scored without it would look better than the site it is compared with.
    public static func fetch(site: Site, fetcher: Fetcher, now: Date, primary: CloudProvider? = WeatherKitSource.provider,
                             secondOpinion wantSecond: Bool = true) async throws -> Forecast {
        var hours: [HourlyConditions]
        var cloudSource = "Open-Meteo", markURL: String? = nil, legalURL: String? = nil
        var second: SecondOpinion? = nil
        if let primary, let r = try? await primary(site, now), !r.hours.isEmpty {
            hours = r.hours; cloudSource = r.source; markURL = r.markURL; legalURL = r.legalURL
            if wantSecond, let data = try? await fetcher.get(OpenMeteo.url(latitude: site.latitude, longitude: site.longitude, days: 11, pastDays: 1)),
               let om = try? OpenMeteo.parse(data), !om.isEmpty {
                second = SecondOpinion(source: "Open-Meteo", hours: om.map { HourlyCloud(time: $0.time, cloudTotal: $0.cloudTotal, cloudLow: $0.cloudLow, cloudMid: $0.cloudMid, cloudHigh: $0.cloudHigh) })
            }
        } else {
            hours = try OpenMeteo.parse(try await fetcher.get(OpenMeteo.url(latitude: site.latitude, longitude: site.longitude, days: 11)))
        }
        var seeingSource: String? = nil
        if let data = try? await fetcher.get(SevenTimer.url(latitude: site.latitude, longitude: site.longitude)),
           let samples = try? SevenTimer.parse(data), !samples.isEmpty {
            hours = merge(hours: hours, seeing: samples)
            seeingSource = "7Timer"
        }
        if let data = try? await fetcher.get(AirQuality.url(latitude: site.latitude, longitude: site.longitude)),
           let samples = try? AirQuality.parse(data), !samples.isEmpty {
            hours = merge(hours: hours, aerosol: samples)
        }
        return Forecast(fetchedAt: now, latitude: site.latitude, longitude: site.longitude, hours: hours, seeingSource: seeingSource,
                        cloudSource: cloudSource, attributionMarkURL: markURL, attributionLegalURL: legalURL, secondOpinion: second)
    }
}

/// Apple Weather can refuse a Mac for a while: HTTP 429 for three hours on 7 October 2026, to Apple's own Weather menu as
/// well. Asking again for each dark site only collects more refusals, so after one failure the primary is left alone for
/// five minutes and those fetches go straight to Open-Meteo. And once Apple Weather has answered on this Mac, a forecast
/// that had to come from Open-Meteo is replaced after five minutes, not thirty, so Apple Weather is back soon after it
/// answers again. A build not signed for Apple Weather never has an answer, and keeps the thirty-minute cache.
public struct PrimaryPause {
    public static let length: TimeInterval = 5 * 60
    private var failedAt: Date?
    private var hasAnswered = false
    public init() {}

    public func paused(now: Date) -> Bool { failedAt.map { now.timeIntervalSince($0) < Self.length } ?? false }

    /// What a fetch that asked the primary came back with.
    public mutating func record(answered: Bool, now: Date) {
        if answered { hasAnswered = true; failedAt = nil } else { failedAt = now }
    }

    /// How old the active site's forecast may grow before it is fetched again.
    public func maxAge(fromPrimary: Bool) -> TimeInterval { hasAnswered && !fromPrimary ? Self.length : 30 * 60 }
}
