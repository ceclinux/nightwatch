import Foundation
import SkyCore

/// What the Lock Screen card for tonight's clear window says: one Live Activity, started when the window opens, going stale when it
/// closes. Worked out from tonight's plan alone, so the same rules as the alerts decide whether tonight deserves one.
public struct ClearWindowCard: Equatable, Sendable {
    public var siteName: String
    public var windowStart: Date
    public var windowEnd: Date
    public var score: Int
    public var headline: String
    /// When the forecast behind the card was fetched, shown on it: the card cannot update itself, so an old claim has to look old.
    public var forecastAt: Date
    public init(siteName: String, windowStart: Date, windowEnd: Date, score: Int, headline: String, forecastAt: Date) {
        self.siteName = siteName; self.windowStart = windowStart; self.windowEnd = windowEnd
        self.score = score; self.headline = headline; self.forecastAt = forecastAt
    }
}

/// The phone side of Live Activities. The implementation lives in the app, because ActivityKit does not exist on the Mac.
public protocol LiveActivityScheduling: Sendable {
    /// Make the Lock Screen hold exactly this card, or none for `nil`: keep a matching one (refreshing its words), end any other,
    /// and schedule this one if it is not there yet. Called at every refresh, so a new forecast corrects or removes it.
    func reconcile(_ card: ClearWindowCard?) async
}

public enum ClearWindowCardPlanner {
    /// The one card wanted right now, or nil: a dark night that meets the go rule, with a clear window that has not yet closed.
    public static func card(now: Date, plan: NightPlan, headline: String, siteName: String, forecastAt: Date) -> ClearWindowCard? {
        guard plan.mode == .dark, plan.qualifies, let w = plan.primary, w.end > now else { return nil }
        return ClearWindowCard(siteName: siteName, windowStart: w.start, windowEnd: w.end, score: plan.score,
                               headline: headline, forecastAt: forecastAt)
    }
}
