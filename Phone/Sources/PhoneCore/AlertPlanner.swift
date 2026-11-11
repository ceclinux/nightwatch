import Foundation
import SkyCore

/// One alert queued for the phone's notification centre to deliver at `fireDate`. `stateAfter` is the alert engine's state
/// once it has gone out, so the next refresh knows it need not be sent again.
public struct ScheduledAlert: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var fireDate: Date
    public var kind: String
    public var title: String
    public var body: String
    public var stateAfter: AlertState
}

/// What the app remembers between refreshes: the engine's state as of the last refresh, and what it queued.
public struct AlertLedger: Codable, Equatable, Sendable {
    public var state: AlertState?
    public var scheduled: [ScheduledAlert]

    public init(state: AlertState? = nil, scheduled: [ScheduledAlert] = []) { self.state = state; self.scheduled = scheduled }
}

/// The Mac checks its alerts at each due moment because it is running. A phone is not, so the same engine (`AlertEngine`,
/// which holds every rule and every word of the alerts) is run ahead of time: at each moment an alert falls due, with
/// the forecast as it is now, and what it would send is queued. The queue is rebuilt from scratch at every refresh, so a
/// new forecast replaces it, and a forecast that turns before an alert is delivered simply means that alert never goes.
///
/// Nothing is queued from a forecast more than six hours old at the moment it would fire (the engine's own rule). So an
/// iPhone that has not been opened since lunchtime sends no heads-up that evening, unless a background refresh has run,
/// and the Settings page says so.
public enum AlertPlanner {
    public struct Result: Equatable, Sendable {
        /// Due right now: post it at once.
        public var immediate: AlertNotification?
        public var ledger: AlertLedger
    }

    public static func plan(now: Date, ledger: AlertLedger, tonight: NightPlan, tomorrow: NightPlan?, settings: AlertSettings,
                            forecastFetchedAt: Date, site: Site, copy: Copy = Copy()) -> Result {
        // What was queued for a moment already past went out, so the engine need not send it again.
        var state = ledger.state
        for a in ledger.scheduled.sorted(by: { $0.fireDate < $1.fireDate }) where a.fireDate <= now { state = a.stateAfter }

        let first = AlertEngine.step(now: now, tonight: tonight, tomorrow: tomorrow, state: state, settings: settings,
                                     forecastFetchedAt: forecastFetchedAt, site: site, copy: copy)
        var chain = first.state
        var queued: [ScheduledAlert] = []
        for due in AlertEngine.dueTimes(tonight: tonight, settings: settings).filter({ $0 > now }).sorted() {
            let r = AlertEngine.step(now: due, tonight: tonight, tomorrow: tomorrow, state: chain, settings: settings,
                                     forecastFetchedAt: forecastFetchedAt, site: site, copy: copy)
            chain = r.state
            if let n = r.notification {
                let kind = name(n.kind)
                queued.append(ScheduledAlert(id: "\(tonight.night.key).\(kind)", fireDate: due, kind: kind, title: n.title, body: n.body,
                                             stateAfter: r.state))
            }
        }
        return Result(immediate: first.notification, ledger: AlertLedger(state: first.state, scheduled: queued))
    }

    static func name(_ kind: AlertNotification.Kind) -> String {
        switch kind {
        case .headsUp: "headsUp"
        case .tomorrowPreview: "tomorrowPreview"
        case .go: "go"
        case .cancel: "cancel"
        case .lessCertain: "lessCertain"
        case .aurora: "aurora"
        }
    }
}
