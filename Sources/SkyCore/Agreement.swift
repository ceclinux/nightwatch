import Foundation

/// What the second opinion (Open-Meteo) says about tonight, under the same go rule (v0.5 spec §3.2).
public enum Agreement: Codable, Equatable, Sendable {
    case agree
    case cloudFrom(Date)
    case clearFrom(Date)
    case noWindow
    case agreeNoWindow
    case clearRun(Date, Date)
}

extension Planner {
    /// nil when there is no second opinion, no darkness, or the second source lacks an hour the comparison needs.
    public static func agreement(plan: NightPlan, second: SecondOpinion?, rule: GoRule) -> Agreement? {
        guard let second, let span = plan.darkSpan, !plan.darkHours.isEmpty else { return nil }
        let cloud = Dictionary(second.hours.map { ($0.time, $0) }, uniquingKeysWith: { a, _ in a })
        guard plan.darkHours.allSatisfy({ cloud[$0.time] != nil }) else { return nil }
        let hours = plan.darkHours.map { h in
            let c = cloud[h.time]!
            return HourlyConditions(time: h.time, cloudTotal: c.cloudTotal, cloudLow: c.cloudLow, cloudMid: c.cloudMid, cloudHigh: c.cloudHigh, tempC: nil, dewPointC: nil,
                             humidityPct: nil, windKmh: nil, gustKmh: nil, visibilityM: nil, seeing: nil, transparency: nil)
        }
        if let w = plan.primary {
            let inside = hours.filter { w.overlapsHour(startingAt: $0.time) }
            guard inside.contains(where: { $0.effectiveCloud > rule.maxCloudPct }) else { return .agree }
            if let run = windows(hours: inside, darkStart: w.start, darkEnd: w.end, rule: rule).first {
                // Cloud after the run has started is the news; cloud only before it means Open-Meteo clears later.
                if let later = inside.first(where: { $0.time >= run.start && $0.effectiveCloud > rule.maxCloudPct }) {
                    return .cloudFrom(max(later.time, w.start))
                }
                return .clearFrom(max(run.start, w.start))
            }
            // Nothing clear enough inside Apple's window: say where Open-Meteo is clear, if anywhere tonight. Not on a bright
            // plan: a bright run also needs a target 15° up, which cloud alone cannot show.
            if plan.mode == .bright { return .noWindow }
            if let elsewhere = windows(hours: hours, darkStart: span.start, darkEnd: span.end, rule: rule).max(by: { $0.hours < $1.hours }) {
                return .clearRun(elsewhere.start, elsewhere.end)
            }
            return .noWindow
        }
        guard plan.mode == .dark else { return nil }   // a bright run also needs a target 15° up: not suggested from cloud alone
        guard let best = windows(hours: hours, darkStart: span.start, darkEnd: span.end, rule: rule).max(by: { $0.hours < $1.hours }) else {
            return .agreeNoWindow
        }
        return .clearRun(best.start, best.end)
    }

    /// The opt-in "Alert only when Open-Meteo agrees" holds an alert back when Open-Meteo is not clear enough inside the window
    /// (`.noWindow`, or clear only elsewhere, `.clearRun`); no second opinion never blocks.
    public static func agreementHolds(_ a: Agreement?) -> Bool {
        switch a { case .noWindow?, .clearRun?: false; default: true }
    }
}
