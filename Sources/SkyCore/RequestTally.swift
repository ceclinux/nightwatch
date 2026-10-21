import Foundation

/// How many requests this device has made today, by service and kind, kept so Settings can show them. The free forecast service allows a
/// fixed number of calls a day and refuses more; when that happens, this says where the calls went. Nothing leaves the device.
public enum RequestTally {
    private static let key = "nightwatch.requestTally"

    /// "api.open-meteo.com/v1/forecast" and so on.
    public static func label(for url: URL) -> String { (url.host ?? "?") + url.path }

    /// The day the counts belong to: UTC, which is when daily allowances usually start over.
    static func day(_ date: Date = Date()) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    public struct Counts: Codable, Equatable, Sendable {
        public var day: String
        public var requests: [String: Int]
        /// For the elevation service, which takes many points in one request.
        public var points: [String: Int]
    }

    public static func record(_ url: URL, now: Date = Date(), defaults: UserDefaults = .standard) {
        var c = today(now: now, defaults: defaults)
        let k = label(for: url)
        c.requests[k, default: 0] += 1
        if k.hasSuffix("/elevation"), let lat = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "latitude" })?.value {
            c.points[k, default: 0] += lat.split(separator: ",").count
        }
        if let data = try? JSONEncoder().encode(c) { defaults.set(data, forKey: key) }
    }

    public static func today(now: Date = Date(), defaults: UserDefaults = .standard) -> Counts {
        if let data = defaults.data(forKey: key), let c = try? JSONDecoder().decode(Counts.self, from: data), c.day == day(now) { return c }
        return Counts(day: day(now), requests: [:], points: [:])
    }
}
