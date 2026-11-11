import Testing
import Foundation
import SkyCore
@testable import PhoneCore

@Test func aClearNightReadsAsTheMacReadsIt() throws {
    let p = try plans()
    let fc = forecast(fetchedAt: utc(2026, 9, 23, 9))
    let model = TonightModel.make(plan: p.tonight, tomorrow: p.tomorrow, forecast: fc, site: sheffield, config: .default)
    #expect(model.snapshot.headline == "Clear window tonight")
    #expect(model.snapshot.window != nil)
    #expect(model.snapshot.bars.isEmpty == false)
    #expect(model.siteName == "Sheffield")
    #expect(model.source == "Apple Weather")
    #expect(model.markURL == "https://example.invalid/mark.png")
    #expect(model.legalURL == "https://example.invalid/legal")
    #expect(model.snapshot.weatherLegalURL == "https://example.invalid/legal")
}

@Test func aDullNightSaysSoAndKeepsTheReason() throws {
    let p = try plans(cloud: 90)
    let fc = forecast(fetchedAt: utc(2026, 9, 23, 9), cloud: 90)
    let model = TonightModel.make(plan: p.tonight, tomorrow: p.tomorrow, forecast: fc, site: sheffield, config: .default)
    #expect(model.snapshot.headline == Copy().noWindow)
    #expect(model.snapshot.window == nil)
}

@Test func anOpenMeteoForecastCarriesNoAppleMark() throws {
    let p = try plans()
    let fc = forecast(fetchedAt: utc(2026, 9, 23, 9), source: "Open-Meteo")
    let model = TonightModel.make(plan: p.tonight, tomorrow: p.tomorrow, forecast: fc, site: sheffield, config: .default)
    #expect(model.source == "Open-Meteo")
    #expect(model.markURL == nil && model.legalURL == nil)   // no Apple data shown, so no Apple mark
}

@Test func theTilesFollowThePopover() throws {
    let p = try plans()
    let tiles = TonightTiles.make(plan: p.tonight, site: sheffield)
    // "20:23–05:25": two clock times with an en dash.
    #expect(tiles.dark.range(of: #"^\d\d:\d\d-\d\d:\d\d$"#, options: .regularExpression) != nil)
    #expect(tiles.wind == "10 km/h")
    #expect(tiles.dewLabel == "Dew risk")   // 9 °C never reaches frost
    #expect(tiles.moon == "Down" || tiles.moon.hasSuffix("%"))
}

@Test func aFreezingNightSaysFrostInsteadOfDew() throws {
    var fc = forecast(fetchedAt: utc(2026, 9, 23, 9))
    fc.hours = fc.hours.map { var h = $0; h.tempC = -2; return h }
    let night = try Ephemeris.night(localDate: utc(2026, 9, 23, 12), site: sheffield)
    let plan = Planner.plan(night: night, forecast: fc, catalog: try Catalog.bundled(), constellations: try Constellations.bundled(), site: sheffield,
                            fov: FieldOfView(widthDeg: 2.1, heightDeg: 1.2), rule: GoRule())
    #expect(TonightTiles.make(plan: plan, site: sheffield).dewLabel == "Frost likely")
}
