import Testing
import Foundation
@testable import SkyCore

@Test func theMenuBarStarsAreSolidOnlyOnAClearNightWithAFreshForecast() throws {
    // A November night at 53° N: darkness from about 17:00 to 07:00 UTC, as the haze tests use.
    let site = Site(name: "Malham", latitude: 53.38, longitude: -1.47, elevationM: 300, timeZoneID: "UTC", bortle: 3)
    let night = try Ephemeris.night(localDate: ISO8601DateFormatter().date(from: "2026-11-20T12:00:00Z")!, site: site)
    let start = ISO8601DateFormatter().date(from: "2026-11-20T17:00:00Z")!
    func plan(cloud: Int, hours: Int = 15) -> NightPlan {
        let h = (0..<hours).map { i in
            HourlyConditions(time: start.addingTimeInterval(Double(i) * 3600), cloudTotal: cloud, cloudLow: nil, cloudMid: nil, cloudHigh: nil,
                             tempC: 8, dewPointC: 6, humidityPct: nil, windKmh: nil, gustKmh: nil, visibilityM: nil, seeing: nil, transparency: nil)
        }
        let forecast = Forecast(fetchedAt: start, latitude: site.latitude, longitude: site.longitude, hours: h, seeingSource: nil)
        return Planner.plan(night: night, forecast: forecast, catalog: Catalog(objects: []), constellations: [],
                            site: site, fov: FieldOfView(widthDeg: 2.1, heightDeg: 1.2), rule: GoRule())
    }
    let clear = plan(cloud: 0)
    #expect(clear.primary != nil)
    #expect(MenuBarStars.filled(plan: clear, isStale: false))
    #expect(!MenuBarStars.filled(plan: clear, isStale: true))      // an out-of-date forecast is not tonight's answer
    let cloudy = plan(cloud: 100)
    #expect(cloudy.primary == nil)
    #expect(!MenuBarStars.filled(plan: cloudy, isStale: false))
    #expect(!MenuBarStars.filled(plan: nil, isStale: false))       // nothing worked out yet: the usual star
    #expect(!MenuBarStars.filled(plan: plan(cloud: 0, hours: 0), isStale: false))   // no hours: no window
}

@Test func theMenuBarStarsSettingIsOffUntilAskedForAndStaysOnItsMac() throws {
    #expect(Config.default.menuBarFilledStars == false)
    // A config written before the setting existed reads as off, rather than failing.
    var fields = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(Config.default)) as? [String: Any])
    fields.removeValue(forKey: "menuBarFilledStars")
    let old = try JSONDecoder().decode(Config.self, from: JSONSerialization.data(withJSONObject: fields))
    #expect(old.menuBarFilledStars == false)
    // iCloud carries the rest of the settings; each Mac keeps its own menu bar and text size.
    var mine = Config.default
    mine.menuBarFilledStars = true
    mine.textSize = .large
    let sent = SettingsSync.outgoing(mine, at: Date(timeIntervalSince1970: 0))
    #expect(sent.config.menuBarFilledStars == false && sent.config.textSize == .standard)
    let merged = SettingsSync.merge(remote: sent, local: Config.default)
    #expect(merged.menuBarFilledStars == false)
}
