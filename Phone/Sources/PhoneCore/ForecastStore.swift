import Foundation
import SkyCore

/// The last forecast fetched, kept in a file so the app opens straight onto an answer, and keeps one when there is no signal.
public struct ForecastStore: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    public func save(_ forecast: Forecast) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(forecast).write(to: url, options: .atomic)
    }

    /// Nil when nothing is saved, or the file cannot be read (a cache, so a bad file is just a miss).
    public func load() -> Forecast? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Forecast.self, from: data)
    }

    /// The Mac's rule: a forecast is for a site when both coordinates are within 0.01°.
    public static func matches(_ forecast: Forecast, site: Site) -> Bool {
        abs(forecast.latitude - site.latitude) <= 0.01 && abs(forecast.longitude - site.longitude) <= 0.01
    }
}
