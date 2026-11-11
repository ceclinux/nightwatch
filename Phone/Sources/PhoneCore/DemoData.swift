import Foundation
import SkyCore

/// Made-up forecasts for previews, the layout renderer and a demo launch. Nothing here is shown to anyone using the real app.
public enum DemoData {
    /// A site for demonstrations. A public place, never a home.
    public static let site = Site(name: "Malham Tarn", latitude: 54.09, longitude: -2.17, elevationM: 380, timeZoneID: "Europe/London", bortle: 3)

    /// Four days of hourly conditions from `from`, every hour at the same cloud cover: 5 % is a clear night, 90 % a dull one.
    /// `source` "Apple Weather" carries a made-up mark address and legal page (the demo never fetches them).
    public static func forecast(fetchedAt: Date, from: Date, cloud: Int = 5, source: String? = "Apple Weather", site: Site = DemoData.site) -> Forecast {
        let hours = (0..<96).map { i in
            HourlyConditions(time: from.addingTimeInterval(Double(i) * 3600), cloudTotal: cloud, cloudLow: cloud, cloudMid: 0, cloudHigh: 0,
                             tempC: 6, dewPointC: 3, humidityPct: 72, windKmh: 10, gustKmh: 14, visibilityM: 20_000, seeing: 2, transparency: 2)
        }
        return Forecast(fetchedAt: fetchedAt, latitude: site.latitude, longitude: site.longitude, hours: hours, seeingSource: "7Timer",
                        cloudSource: source, attributionMarkURL: source == "Apple Weather" ? "https://demo.invalid/mark.png" : nil,
                        attributionLegalURL: source == "Apple Weather" ? "https://demo.invalid/legal" : nil, secondOpinion: nil)
    }
}
