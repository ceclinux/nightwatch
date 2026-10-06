import Testing
import Foundation
@testable import SkyCore

private func plan(score: Int, qualifies: Bool) -> NightPlan {
    let night = try! Ephemeris.night(localDate: utc(2026, 9, 23, 12, 0), site: Site(name: "S", latitude: 53.38, longitude: -1.47, elevationM: 100, timeZoneID: "Europe/London", bortle: 5))
    let w = qualifies ? ClearWindow(start: night.darkStart!, end: night.darkStart!.addingTimeInterval(4 * 3600)) : nil
    return NightPlan(night: night, windows: w.map { [$0] } ?? [], primary: w, score: score, qualifies: qualifies, moonIllumination: 0.3,
                     moonRise: nil, moonSet: nil, darkHours: [], targets: [], best: [], seeingAvailable: false)
}
private func site(_ id: String, km: Double) -> DarkSite {
    DarkSite(id: id, name: id, kind: "park", coordinate: Coordinate(latitude: 53, longitude: -2), distanceKm: km, bearingDeg: 0, band: .dark, bortle: nil, source: nil, isComputed: false)
}

@Test func bestAwayNeedsTwentyPointMargin() {
    let home = plan(score: 40, qualifies: false)
    let a = SitePlan(id: "a", site: site("a", km: 30), score: 59, primary: nil, qualifies: true, forecastMissing: false)
    let b = SitePlan(id: "b", site: site("b", km: 60), score: 60, primary: nil, qualifies: true, forecastMissing: false)
    #expect(SiteComparison.bestAway(home: home, sites: [a]) == nil)
    #expect(SiteComparison.bestAway(home: home, sites: [a, b])?.id == "b")
}

@Test func bestAwayIgnoresMissingForecastsAndNonQualifying() {
    let home = plan(score: 10, qualifies: false)
    let missing = SitePlan(id: "m", site: site("m", km: 10), score: 0, primary: nil, qualifies: false, forecastMissing: true)
    let noWindow = SitePlan(id: "n", site: site("n", km: 10), score: 70, primary: nil, qualifies: false, forecastMissing: false)
    #expect(SiteComparison.bestAway(home: home, sites: [missing, noWindow]) == nil)
}

@Test func sortedByScoreThenDistanceMissingLast() {
    let s = [SitePlan(id: "far", site: site("far", km: 90), score: 80, primary: nil, qualifies: true, forecastMissing: false),
             SitePlan(id: "near", site: site("near", km: 20), score: 80, primary: nil, qualifies: true, forecastMissing: false),
             SitePlan(id: "miss", site: site("miss", km: 5), score: 95, primary: nil, qualifies: false, forecastMissing: true),
             SitePlan(id: "low", site: site("low", km: 10), score: 30, primary: nil, qualifies: false, forecastMissing: false)]
    #expect(SiteComparison.sorted(s).map(\.id) == ["near", "far", "low", "miss"])
}

/// The nearest site with a clear window tonight (Dark sites page): a nearer one beats a higher score, since the point is
/// the shortest drive to clear sky. A site with no window, or no forecast, is never it.
@Test func nearestClearIsTheShortestDriveToAClearWindow() {
    func sp(_ id: String, km: Double, score: Int, clear: Bool, missing: Bool = false) -> SitePlan {
        SitePlan(id: id, site: site(id, km: km), score: score, primary: nil, qualifies: clear, forecastMissing: missing)
    }
    let gisburn = sp("gisburn", km: 27, score: 78, clear: true), buckden = sp("buckden", km: 18, score: 71, clear: true)
    let slaidburn = sp("slaidburn", km: 30, score: 44, clear: false), burnsall = sp("burnsall", km: 14, score: 38, clear: false)
    let unfetched = sp("unfetched", km: 5, score: 0, clear: false, missing: true)
    let all = [gisburn, buckden, slaidburn, burnsall, unfetched]
    #expect(SiteComparison.sorted(all).first?.id == "gisburn")                       // by score, the farther site leads
    #expect(SiteComparison.nearestClear(all)?.id == "buckden")
    #expect(SiteComparison.nearestClear([slaidburn, burnsall, unfetched]) == nil)    // nothing clear: the page says so
    #expect(SiteComparison.nearestClear([]) == nil)
    // Two clear sites the same distance away: the better night.
    #expect(SiteComparison.nearestClear([sp("a", km: 20, score: 60, clear: true), sp("b", km: 20, score: 75, clear: true)])?.id == "b")
    // "Nearest clear" order: clear sites by distance, then the rest by distance, then those with no forecast.
    #expect(SiteComparison.sorted(all, by: .nearestClear).map(\.id) == ["buckden", "gisburn", "burnsall", "slaidburn", "unfetched"])
    #expect(SiteComparison.sorted(all, by: .score) == SiteComparison.sorted(all))
    #expect(SiteSort.allCases.map(\.rawValue) == ["Score", "Nearest clear"])
}

