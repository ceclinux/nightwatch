import Foundation
import SkyCore

let sheffield = Site(name: "Sheffield", latitude: 53.38, longitude: -1.47, elevationM: 100, timeZoneID: "Europe/London", bortle: 5)

func utc(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: mi))!
}

/// A forecast covering four days from `from`, every hour at the same cloud cover: 5 % is a clear night, 90 % a dull one.
func forecast(fetchedAt: Date, from: Date = utc(2026, 9, 22), cloud: Int = 5, source: String? = "Apple Weather",
              site: Site = sheffield) -> Forecast {
    let hours = (0..<96).map { i in
        HourlyConditions(time: from.addingTimeInterval(Double(i) * 3600), cloudTotal: cloud, cloudLow: cloud, cloudMid: 0, cloudHigh: 0,
                         tempC: 9, dewPointC: 4, humidityPct: 70, windKmh: 10, gustKmh: 14, visibilityM: 20_000, seeing: 2, transparency: 2)
    }
    return Forecast(fetchedAt: fetchedAt, latitude: site.latitude, longitude: site.longitude, hours: hours, seeingSource: "7Timer",
                    cloudSource: source, attributionMarkURL: source == "Apple Weather" ? "https://example.invalid/mark.png" : nil,
                    attributionLegalURL: source == "Apple Weather" ? "https://example.invalid/legal" : nil, secondOpinion: nil)
}

struct Plans {
    var night: Night
    var tonight: NightPlan
    var tomorrow: NightPlan
}

/// Tonight's and tomorrow's plans for the evening of 23 September 2026, worked out by SkyCore's own planner.
func plans(cloud: Int = 5, fetchedAt: Date = utc(2026, 9, 23, 9), site: Site = sheffield) throws -> Plans {
    let fc = forecast(fetchedAt: fetchedAt, cloud: cloud, site: site)
    let night = try Ephemeris.night(localDate: utc(2026, 9, 23, 12), site: site)
    let next = try Ephemeris.night(localDate: utc(2026, 9, 24, 12), site: site)
    let catalog = try Catalog.bundled()
    let cons = try Constellations.bundled()
    let rule = GoRule(), fov = FieldOfView(widthDeg: 2.1, heightDeg: 1.2)
    let t = Planner.plan(night: night, forecast: fc, catalog: catalog, constellations: cons, site: site, fov: fov, rule: rule)
    let n = Planner.plan(night: next, forecast: fc, catalog: catalog, constellations: cons, site: site, fov: fov, rule: rule)
    return Plans(night: night, tonight: t, tomorrow: n)
}
