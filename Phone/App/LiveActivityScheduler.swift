import ActivityKit
import Foundation
import PhoneCore
import PhoneWidgetUI

/// ActivityKit behind PhoneCore's protocol. The one card tonight: scheduled to start when the clear window opens (iOS 26 and later),
/// or started at once when the app finds the window already open, and marked stale by the system when it closes. Every refresh
/// reconciles it, so a new forecast corrects it and a worse one removes it. A card the app is not running to correct stays as it was.
struct LiveActivityScheduler: LiveActivityScheduling {
    /// The per-device switch in Settings (on until turned off).
    var isEnabled: @Sendable () -> Bool = { UserDefaults.standard.object(forKey: "liveActivityOn") as? Bool ?? true }

    func reconcile(_ wanted: ClearWindowCard?) async {
        let card = isEnabled() ? wanted : nil
        var kept = false
        for held in Activity<ClearWindowAttributes>.activities {
            let a = held.attributes
            let same = card.map { abs(a.windowStart.timeIntervalSince($0.windowStart)) < 1 && abs(a.windowEnd.timeIntervalSince($0.windowEnd)) < 1
                                  && a.siteName == $0.siteName } ?? false
            if let card, same, !kept, held.activityState != .ended, held.activityState != .dismissed {
                kept = true
                await held.update(ActivityContent(state: Self.state(card), staleDate: card.windowEnd))
            } else {
                await held.end(nil, dismissalPolicy: .immediate)
            }
        }
        if let card, !kept { start(card) }
    }

    private static func state(_ c: ClearWindowCard) -> ClearWindowAttributes.ContentState {
        .init(score: c.score, headline: c.headline, forecastAt: c.forecastAt)
    }

    private func start(_ card: ClearWindowCard) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = ClearWindowAttributes(siteName: card.siteName, windowStart: card.windowStart, windowEnd: card.windowEnd)
        let content = ActivityContent(state: Self.state(card), staleDate: card.windowEnd)
        do {
            if card.windowStart <= Date() {
                _ = try Activity.request(attributes: attributes, content: content, pushType: nil)   // the window is open now
                NSLog("Nightwatch card started for \(card.windowEnd)")
            } else if #available(iOS 26.0, *) {
                let alert = AlertConfiguration(title: "Clear window now", body: "Score \(card.score) at \(card.siteName)", sound: .default)
                _ = try Activity.request(attributes: attributes, content: content, pushType: nil, style: .standard,
                                         alertConfiguration: alert, start: card.windowStart)
                NSLog("Nightwatch card scheduled for \(card.windowStart)")
            }   // before iOS 26 a card cannot be scheduled: it starts the next time the app runs inside the window
        } catch { NSLog("Nightwatch card failed: \(String(reflecting: error))") }
    }

    /// `-testLiveActivity`: one card starting in 30 s and open for 60 s, for watching the Lock Screen. Never used in a release path.
    static func test() async {
        let now = Date()
        await LiveActivityScheduler(isEnabled: { true }).reconcile(ClearWindowCard(
            siteName: "Test site", windowStart: now.addingTimeInterval(30), windowEnd: now.addingTimeInterval(90), score: 78,
            headline: "Clear window tonight", forecastAt: now))
    }
}
