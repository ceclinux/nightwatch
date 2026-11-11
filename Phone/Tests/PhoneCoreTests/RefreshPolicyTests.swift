import Testing
import Foundation
import SkyCore
@testable import PhoneCore

private let now = utc(2026, 9, 23, 20)

private func decide(age: TimeInterval, source: String? = "Apple Weather", force: Bool = false, pause: PrimaryPause = PrimaryPause(),
                    connectivity: Connectivity = Connectivity(), forecastSite: Site = sheffield) -> RefreshDecision {
    let fc = forecast(fetchedAt: now.addingTimeInterval(-age), source: source, site: forecastSite)
    return RefreshPolicy.decision(now: now, forecast: fc, site: sheffield, pause: pause, force: force, connectivity: connectivity)
}

@Test func noConnectionAlwaysMeansOffline() {
    #expect(decide(age: 5 * 3600, connectivity: .offline) == .offline)
    #expect(RefreshPolicy.decision(now: now, forecast: nil, site: sheffield, pause: PrimaryPause(), force: true, connectivity: .offline) == .offline)
}

@Test func noForecastOrAnotherSitesForecastFetches() {
    #expect(RefreshPolicy.decision(now: now, forecast: nil, site: sheffield, pause: PrimaryPause(), force: false, connectivity: Connectivity()) == .fetch)
    let elsewhere = Site(name: "Malham", latitude: 54.1, longitude: -2.16, elevationM: 380, timeZoneID: "Europe/London", bortle: 3)
    #expect(decide(age: 60, forecastSite: elsewhere) == .fetch)
}

@Test func aForecastIsFreshForThirtyMinutes() {
    #expect(decide(age: 10 * 60) == .useSaved)
    #expect(decide(age: 30 * 60) == .useSaved)
    #expect(decide(age: 31 * 60) == .fetch)
}

@Test func askingForARefreshAlwaysFetches() {
    #expect(decide(age: 60, force: true) == .fetch)
    #expect(decide(age: 60, force: true, connectivity: Connectivity(isExpensive: true, isConstrained: true)) == .fetch)
}

@Test func openMeteoFallbackIsReplacedSoonOnceAppleWeatherHasAnswered() {
    var pause = PrimaryPause()
    pause.record(answered: true, now: now.addingTimeInterval(-3600))
    #expect(decide(age: 6 * 60, source: "Open-Meteo", pause: pause) == .fetch)
    #expect(decide(age: 6 * 60, source: "Open-Meteo") == .useSaved)   // Apple Weather has never answered: keep the thirty minutes
    #expect(decide(age: 6 * 60, source: "Apple Weather", pause: pause) == .useSaved)
}

@Test func lowDataModeStretchesTheWaitToTwoHours() {
    let low = Connectivity(isConstrained: true)
    #expect(decide(age: 90 * 60, connectivity: low) == .useSaved)
    #expect(decide(age: 3 * 3600, connectivity: low) == .fetch)
    // Cellular or a hotspot alone does not stretch it: the forecast is a few kilobytes.
    #expect(decide(age: 40 * 60, connectivity: Connectivity(isExpensive: true)) == .fetch)
}

@Test func optionalDownloadsWaitForACheapConnection() {
    #expect(Connectivity().allowsOptionalDownloads)
    #expect(!Connectivity(isExpensive: true).allowsOptionalDownloads)
    #expect(!Connectivity(isConstrained: true).allowsOptionalDownloads)
    #expect(!Connectivity.offline.allowsOptionalDownloads)
}

@Test func wifiIsJudgedByTheWifiLinkEvenWhenCellularIsAvailableBesideIt() {
    let busyDefault = Connectivity.Path(isOnline: true, isExpensive: true, isConstrained: false)   // iOS: expensive because cellular is on offer
    let cleanWifi = Connectivity.Path(isOnline: true, isExpensive: false, isConstrained: false)
    #expect(Connectivity.resolve(defaultPath: busyDefault, wifi: cleanWifi).allowsOptionalDownloads)
    // A hotspot or a Low Data Mode network says so on its own Wi-Fi link.
    #expect(Connectivity.resolve(defaultPath: busyDefault, wifi: Connectivity.Path(isOnline: true, isExpensive: true, isConstrained: false)).allowsOptionalDownloads == false)
    #expect(Connectivity.resolve(defaultPath: busyDefault, wifi: Connectivity.Path(isOnline: true, isExpensive: false, isConstrained: true)).allowsOptionalDownloads == false)
    // No Wi-Fi: cellular is costly.
    #expect(Connectivity.resolve(defaultPath: busyDefault, wifi: nil).allowsOptionalDownloads == false)
    #expect(Connectivity.resolve(defaultPath: busyDefault, wifi: Connectivity.Path(isOnline: false, isExpensive: false, isConstrained: false)).allowsOptionalDownloads == false)
}
