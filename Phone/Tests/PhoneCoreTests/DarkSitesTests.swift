import Testing
import Foundation
import SkyCore
@testable import PhoneCore

final class LookupCalls: @unchecked Sendable { var places = 0, names = 0; var forecastSites: [String] = [] }

@MainActor private func darkStore(_ calls: LookupCalls, radiusKm: Double = 100, openPage: Bool = true) -> PhoneStore {
    let lookups = DarkLookups(placeName: { _ in calls.names += 1; return "Kettlewell" },
                              publicPlace: { c, _, _ in calls.places += 1; return PublicPlace(latitude: c.latitude, longitude: c.longitude, name: "Car park") })
    let s = PhoneStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("dark-\(UUID().uuidString)"),
                       provider: { site, now, _ in calls.forecastSites.append(site.name); return forecast(fetchedAt: now, site: site) }, scheduler: FakeScheduler(),
                       clock: { utc(2026, 9, 23, 12) }, occultations: false, darkLookups: lookups)
    s.config.sites = [sheffield]
    s.config.activeSiteName = "Sheffield"
    s.config.darkSites.radiusKm = radiusKm
    s.darkSitesPage(open: openPage)   // forecasts are fetched only while the page is open
    return s
}

@MainActor @Test func darkSitesNearASiteHaveAPlanEachAndComputedSpotsBecomeNamedCarParks() async throws {
    let calls = LookupCalls()
    let s = darkStore(calls)
    await s.refresh()
    await s.darkSitesFinished()
    #expect(s.darkSites.isEmpty == false)
    #expect(s.sitePlans.count == min(3, s.darkSites.count))
    #expect(s.darkSites.allSatisfy { $0.distanceKm <= 100.5 })
    for spot in s.darkSites where spot.isComputed { #expect(spot.name == "Car park near Kettlewell") }
    #expect(calls.places > 0 && calls.names > 0)
}

@MainActor @Test func aCostlyConnectionDoesNoLookupsAndFetchesNoForecasts() async {
    let calls = LookupCalls()
    let s = darkStore(calls, openPage: false)
    await s.refresh(force: true, connectivity: Connectivity(isOnline: true, isExpensive: true, isConstrained: false))
    s.darkSitesPage(open: true)                    // opening the page on a costly connection must still do no lookups
    await s.darkSitesFinished()
    #expect(s.darkSitesSkipped)
    #expect(calls.places == 0 && calls.names == 0)
    #expect(s.sitePlans.allSatisfy { $0.forecastMissing })
}

@MainActor @Test func turningDarkSitesOffClearsTheList() async {
    let s = darkStore(LookupCalls())
    await s.refresh()
    await s.darkSitesFinished()
    s.setDarkSites { $0.enabled = false }
    await s.darkSitesFinished()
    #expect(s.darkSites.isEmpty && s.sitePlans.isEmpty && s.bestAway == nil)
}

@MainActor @Test func visitingASiteObservesFromItWithoutSavingItAndGoingHomeEndsIt() async throws {
    let s = darkStore(LookupCalls())
    await s.refresh()
    await s.darkSitesFinished()
    let spot = try #require(s.darkSites.first)
    s.visit(spot)
    #expect(s.site?.name == spot.name)
    #expect(s.config.sites.count == 1)                 // not saved
    #expect(s.isAway)
    s.goHome()
    #expect(s.site?.name == "Sheffield")
    #expect(s.isAway == false)
}

@MainActor @Test func atHomeTheHomePlanIsTheOneInViewAndNothingExtraIsFetched() async {
    let calls = LookupCalls()
    let s = darkStore(calls)
    await s.refresh()
    await s.darkSitesFinished()
    #expect(s.homePlan?.score == s.planning?.tonight.score)
    #expect(calls.forecastSites.filter { $0 == "Sheffield" }.count == 1)    // the page's own forecast, and no second one for home
}

@MainActor @Test func awayHomesForecastIsFetchedOnceAndKept() async throws {
    let calls = LookupCalls()
    let s = darkStore(calls)
    await s.refresh()
    await s.darkSitesFinished()
    let spot = try #require(s.darkSites.first)
    s.visit(spot)
    try await Task.sleep(for: .seconds(2))
    await s.darkSitesFinished()
    #expect(s.isAway)
    #expect(s.homePlan != nil)
    await s.refresh(force: true)
    await s.darkSitesFinished()
    #expect(calls.forecastSites.filter { $0 == "Sheffield" }.count == 2)    // the first page, and one fetch for home that the second run reused
}

@MainActor @Test func awayOnACostlyConnectionLeavesTheHomeLineOut() async {
    let s = darkStore(LookupCalls(), openPage: false)
    s.config.visiting = Site(name: "Somewhere", latitude: 54.2, longitude: -2.1, elevationM: 0, timeZoneID: "Europe/London", bortle: 2)
    await s.refresh(force: true, connectivity: Connectivity(isOnline: true, isExpensive: true, isConstrained: false))
    s.darkSitesPage(open: true)
    await s.darkSitesFinished()
    #expect(s.homePlan == nil)
}

@MainActor @Test func withTheDarkSitesPageClosedNoForecastIsFetchedForThem() async {
    let calls = LookupCalls()
    let s = darkStore(calls, openPage: false)
    await s.refresh()
    await s.darkSitesFinished()
    #expect(s.darkSites.isEmpty == false)                                   // the list is there
    #expect(calls.forecastSites.filter { $0 != "Sheffield" }.isEmpty)       // but nothing was asked of the forecast service for it
}

@MainActor @Test func openingThePageFetchesTheNearestThreeOnceAndReopeningUsesTheCache() async {
    let calls = LookupCalls()
    let s = darkStore(calls, openPage: false)
    await s.refresh()
    await s.darkSitesFinished()
    s.darkSitesPage(open: true)
    await s.darkSitesFinished()
    let fetched = calls.forecastSites.filter { $0 != "Sheffield" }
    #expect(fetched.count == min(3, s.darkSites.count))
    s.darkSitesPage(open: false)
    s.darkSitesPage(open: true)
    await s.darkSitesFinished()
    #expect(calls.forecastSites.filter { $0 != "Sheffield" }.count == fetched.count)    // within 30 minutes: nothing new
}
