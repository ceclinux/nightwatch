import Foundation
import CoreLocation
import WeatherKit

/// Apple WeatherKit as the primary cloud source. Needs a build signed with the
/// `com.apple.developer.weatherkit` entitlement and an embedded provisioning profile;
/// an ad-hoc build throws `xpcConnectionFailed` here and `ForecastService` falls back to Open-Meteo.
public enum WeatherKitSource {
    public static let provider: CloudProvider = { site, now in try await hours(site: site, now: now) }

    public static func hours(site: Site, now: Date) async throws -> CloudResult {
        let location = CLLocation(latitude: site.latitude, longitude: site.longitude)
        let start = now.addingTimeInterval(-3600), end = now.addingTimeInterval(238 * 3600)   // ten nights for the week ahead: Apple Weather gives up to 240 hours a request
        let forecast = try await WeatherService.shared.weather(for: location, including: .hourly(startDate: start, endDate: end))
        let hours = forecast.map { h -> HourlyConditions in
            var low: Int? = nil, mid: Int? = nil, high: Int? = nil
            if #available(macOS 15, *) {
                let a = h.cloudCoverByAltitude
                low = pct(a.low); mid = pct(a.medium); high = pct(a.high)
            }
            return HourlyConditions(time: h.date, cloudTotal: pct(h.cloudCover), cloudLow: low, cloudMid: mid, cloudHigh: high,
                                    tempC: h.temperature.converted(to: .celsius).value,
                                    dewPointC: h.dewPoint.converted(to: .celsius).value,
                                    humidityPct: pct(h.humidity),
                                    windKmh: h.wind.speed.converted(to: .kilometersPerHour).value,
                                    gustKmh: h.wind.gust?.converted(to: .kilometersPerHour).value,
                                    visibilityM: h.visibility.converted(to: .meters).value,
                                    seeing: nil, transparency: nil)
        }
        let attribution = try await WeatherService.shared.attribution
        return CloudResult(hours: hours, source: "Apple Weather",
                           markURL: attribution.combinedMarkDarkURL.absoluteString,
                           legalURL: attribution.legalPageURL.absoluteString)
    }

    private static func pct(_ fraction: Double) -> Int { Int((fraction * 100).rounded()) }
}
