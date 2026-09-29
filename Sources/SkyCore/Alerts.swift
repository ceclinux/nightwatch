import Foundation

public struct AlertSettings: Codable, Equatable, Sendable {
    public var headsUp = true
    public var tomorrowPreview = true
    public var preWindowMinutes = 30
    public var cancelOnDowngrade = true
    public var quietStartHour = 0
    public var quietEndHour = 7
    /// v0.5: hold back the heads-up and the nudge when Open-Meteo is not clear enough inside the window. Off by default.
    public var requireAgreement = false
    public init() {}
    enum CodingKeys: String, CodingKey { case headsUp, tomorrowPreview, preWindowMinutes, cancelOnDowngrade, quietStartHour, quietEndHour, requireAgreement }
    /// Each key optional, so a config written before a key existed keeps every other alert setting (v0.5 added requireAgreement).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AlertSettings()
        headsUp = try c.decodeIfPresent(Bool.self, forKey: .headsUp) ?? d.headsUp
        tomorrowPreview = try c.decodeIfPresent(Bool.self, forKey: .tomorrowPreview) ?? d.tomorrowPreview
        preWindowMinutes = try c.decodeIfPresent(Int.self, forKey: .preWindowMinutes) ?? d.preWindowMinutes
        cancelOnDowngrade = try c.decodeIfPresent(Bool.self, forKey: .cancelOnDowngrade) ?? d.cancelOnDowngrade
        quietStartHour = try c.decodeIfPresent(Int.self, forKey: .quietStartHour) ?? d.quietStartHour
        quietEndHour = try c.decodeIfPresent(Int.self, forKey: .quietEndHour) ?? d.quietEndHour
        requireAgreement = try c.decodeIfPresent(Bool.self, forKey: .requireAgreement) ?? d.requireAgreement
    }
}

public struct AlertState: Codable, Equatable, Sendable {
    /// `doubted`: the two forecasts split after a heads-up or go, and the "less certain" message went out.
    public enum Stage: String, Codable, Sendable { case idle, previewSent, headsUpSent, goSent, doubted, cancelled, done }
    public var nightKey: String
    public var stage: Stage
    /// The plan mode the current stage was reached under; nil in files from 0.3.0 and earlier.
    public var mode: PlanMode?
    /// The go nudge went out tonight, and the "Less certain" message went out tonight (v0.6.3). Optional, so older files decode.
    public var goFired: Bool?
    public var doubtSent: Bool?
    /// "Not tonight" on the heads-up (#57): nothing more is sent for this night.
    public var silenced: Bool?
    public init(nightKey: String, stage: Stage, mode: PlanMode? = nil, goFired: Bool? = nil, doubtSent: Bool? = nil, silenced: Bool? = nil) {
        self.nightKey = nightKey; self.stage = stage; self.mode = mode; self.goFired = goFired; self.doubtSent = doubtSent; self.silenced = silenced
    }
}

public struct AlertNotification: Equatable, Sendable {
    public enum Kind: Sendable { case headsUp, tomorrowPreview, go, cancel, lessCertain, aurora }
    public let kind: Kind
    public let title: String
    public let body: String
    /// A heads-up carrying Tonight's plan (#57): its night, so Open plan and Not tonight act on that night only.
    public var planNight: String? = nil
}

public enum AlertEngine {
    static let staleAfter: TimeInterval = 6 * 3600

    public static func inQuietHours(_ date: Date, site: Site, settings: AlertSettings) -> Bool {
        let h = site.calendar.component(.hour, from: date)
        let a = settings.quietStartHour, b = settings.quietEndHour
        if a == b { return false }
        return a < b ? (h >= a && h < b) : (h >= a || h < b)
    }

    public static func step(now: Date, tonight: NightPlan, tomorrow: NightPlan?, state: AlertState?, settings: AlertSettings,
                            forecastFetchedAt: Date, site: Site, copy: Copy, session: SessionPlan? = nil) -> (notification: AlertNotification?, state: AlertState) {
        var s = (state?.nightKey == tonight.night.key) ? state! : AlertState(nightKey: tonight.night.key, stage: .idle)
        if s.silenced == true { return (nil, s) }
        // Switching bright nights on or off mid-evening changes the plan, not the sky: start the night's alerts afresh
        // in the new mode rather than sending "Cancelled. Clouds moving in".
        if let m = s.mode, m != tonight.mode { s = AlertState(nightKey: tonight.night.key, stage: .idle) }
        guard now.timeIntervalSince(forecastFetchedAt) <= staleAfter else { return (nil, s) }

        let headsUpAt = tonight.night.sunset.addingTimeInterval(-3600)
        let agreed = !settings.requireAgreement || Planner.agreementHolds(tonight.agreement)
        let goAt = tonight.primary?.start.addingTimeInterval(-Double(settings.preWindowMinutes) * 60)
        var note: AlertNotification? = nil

        func window(_ p: NightPlan) -> (String, Double) {
            (Copy.hhmm(p.primary!.start, site: site), p.primary!.hours)
        }
        /// Fires go when tonight qualifies, the nudge time has passed and the window is still open; true when it fired.
        /// Forecasts agreeing again after a "Less certain" that followed a go send nothing: the go already went out.
        func goIfDue() -> Bool {
            guard let g = goAt, let w = tonight.primary, agreed, now >= g, now < w.end else { return false }
            if s.goFired == true, s.stage == .doubted { s.stage = .goSent; return true }
            s.goFired = true
            note = AlertNotification(kind: .go, title: tonight.mode == .bright ? copy.brightGoTitle(windowStart: window(tonight).0) : copy.goTitle(windowStart: window(tonight).0), body: copy.notificationBody(plan: tonight, site: site, alerts: settings))
            s.stage = .goSent
            return true
        }

        /// After a heads-up or go, the message follows both forecasts (owner ruling, 25 September 2026). Apple Weather has no
        /// window and Open-Meteo agrees, or there is no second opinion: stand down. They split (one still sees a clear run
        /// the other does not): "less certain", once, saying what each sees. A split where only Open-Meteo doubts matters
        /// only with the opt-in on, because only then does it hold the go nudge back. True when it decided the tick.
        func downgrade() -> Bool {
            guard settings.cancelOnDowngrade, s.stage != .cancelled else { return false }
            let split: String?
            if let w = tonight.primary {
                guard settings.requireAgreement, !Planner.agreementHolds(tonight.agreement), let a = tonight.agreement else { return false }
                split = "Apple Weather still sees clear from \(Copy.hhmm(w.start, site: site)). \(Copy.agreementText(a, site: site))."
            } else if let a = tonight.agreement, case .clearRun = a {
                split = "Apple Weather now sees cloud. \(Copy.agreementText(a, site: site))."
            } else {
                split = nil
            }
            if let body = split {
                // Once a night: forecasts flipping either side of the rule must not send "Less certain" on every patrol.
                if s.doubtSent != true { note = AlertNotification(kind: .lessCertain, title: copy.lessCertainTitle, body: body) }
                s.doubtSent = true
                s.stage = .doubted
            } else {
                let body = tonight.agreement == .agreeNoWindow ? "Apple Weather and Open-Meteo both see cloud." : copy.noWindow
                note = AlertNotification(kind: .cancel, title: copy.cancelTitle, body: body)
                s.stage = .cancelled
            }
            return true
        }

        switch s.stage {
        case .idle:
            // If the first tick already lands at or after goAt, go fires straight from idle and heads-up
            // is skipped: the go notification carries the same window and targets, so a heads-up a minute
            // earlier would just be a second banner for no new information.
            if !goIfDue(), now >= headsUpAt {
                if tonight.qualifies, settings.headsUp, agreed {
                    let (start, hours) = window(tonight)
                    // With Tonight's plan (#57) the heads-up says where to start; the advice sentence still follows.
                    let body = session.map { Copy.headsUpPlan($0, plan: tonight, site: site) + copy.secondOpinionLine(plan: tonight, site: site, alerts: settings) }
                        ?? copy.notificationBody(plan: tonight, site: site, alerts: settings)
                    note = AlertNotification(kind: .headsUp, title: tonight.mode == .bright ? copy.brightHeadsUpTitle(windowStart: start, targets: tonight.brightTargets) : copy.headsUpTitle(windowStart: start, hours: hours), body: body,
                                             planNight: session == nil ? nil : tonight.night.key)
                    s.stage = .headsUpSent
                } else if !tonight.qualifies, let t = tomorrow, t.qualifies, settings.tomorrowPreview {
                    note = AlertNotification(kind: .tomorrowPreview, title: t.mode == .bright ? copy.brightTomorrowTitle(hours: t.primary!.hours) : copy.tomorrowTitle(hours: t.primary!.hours), body: copy.notificationBody(plan: t, site: site, agreement: false))
                    s.stage = .previewSent
                }
                // A night that fails at sunset stays idle: the forecast can still clear later and fire go.
            }
        case .previewSent:
            // Preview already sent for tomorrow; tonight can still clear late. Go only, never a second preview or heads-up.
            _ = goIfDue()
        case .headsUpSent, .doubted, .cancelled:
            // cancelled and doubted recover straight to go when both forecasts clear again; no second heads-up
            if !downgrade() { _ = goIfDue() }
        case .goSent:
            // Once the window has closed the night is over: no cancel or "Less certain" for a window already used.
            if now >= (tonight.primary?.end ?? tonight.night.sunrise) { s.stage = .done } else { _ = downgrade() }
        case .done:
            break
        }

        if note != nil, inQuietHours(now, site: site, settings: settings) { note = nil }   // dropped, not deferred
        if s.stage != .idle, s.stage != .previewSent { s.mode = tonight.mode }
        return (note, s)
    }
}
