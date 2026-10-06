import Foundation

public struct SitePlan: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let site: DarkSite
    public let score: Int
    public let primary: ClearWindow?
    public let qualifies: Bool
    public let forecastMissing: Bool
    public init(id: String, site: DarkSite, score: Int, primary: ClearWindow?, qualifies: Bool, forecastMissing: Bool) {
        self.id = id; self.site = site; self.score = score; self.primary = primary; self.qualifies = qualifies; self.forecastMissing = forecastMissing
    }
    /// A site with no forecast: sorts last, never qualifies, never recommended.
    public static func missing(_ site: DarkSite) -> SitePlan {
        SitePlan(id: site.id, site: site, score: 0, primary: nil, qualifies: false, forecastMissing: true)
    }
}

/// How the Dark sites page is ordered: the best night first, or the shortest drive to a clear one.
public enum SiteSort: String, CaseIterable, Sendable {
    case score = "Score"
    case nearestClear = "Nearest clear"
}

public enum SiteComparison {
    public static func sorted(_ plans: [SitePlan]) -> [SitePlan] {
        plans.sorted {
            if $0.forecastMissing != $1.forecastMissing { return !$0.forecastMissing }
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.site.distanceKm < $1.site.distanceKm
        }
    }

    /// The Dark sites page in the chosen order. "Nearest clear": the sites with a clear window by distance, then the
    /// others by distance, then those with no forecast.
    public static func sorted(_ plans: [SitePlan], by sort: SiteSort) -> [SitePlan] {
        guard sort == .nearestClear else { return sorted(plans) }
        return plans.sorted {
            if $0.forecastMissing != $1.forecastMissing { return !$0.forecastMissing }
            if $0.qualifies != $1.qualifies { return $0.qualifies }
            if $0.site.distanceKm != $1.site.distanceKm { return $0.site.distanceKm < $1.site.distanceKm }
            return $0.score > $1.score
        }
    }

    /// The nearest site with a clear window tonight: the shortest drive to clear sky, whatever its score. Of two the
    /// same distance away, the better night. nil when no site with a forecast has a window.
    public static func nearestClear(_ plans: [SitePlan]) -> SitePlan? {
        sorted(plans, by: .nearestClear).first { $0.qualifies && !$0.forecastMissing }
    }

    /// The best qualifying site whose score beats home by at least `margin`; nil when none.
    public static func bestAway(home: NightPlan, sites: [SitePlan], margin: Int = 20) -> SitePlan? {
        sorted(sites).first { !$0.forecastMissing && $0.qualifies && $0.score >= home.score + margin }
    }
}
