import Foundation

/// The week ahead (owner-approved mock-up A, 30 September 2026): each coming night's clear window, Moon and darkness, in
/// date order, so the best night of the week stands out. Nights after tomorrow are planned without targets, which keeps
/// ten nights cheap; tonight and tomorrow are the full plans the rest of the app uses.
public struct WeekNight: Equatable, Sendable {
    public let plan: NightPlan
    public let daysAhead: Int
    public init(plan: NightPlan, daysAhead: Int) { self.plan = plan; self.daysAhead = daysAhead }
}

extension Planner {
    public static let weekNights = 10

    /// Tonight and the nights after it, as far as the forecast reaches the end of each night's darkness: a night the
    /// forecast covers only in part would read as clear or cloudy by accident.
    public static func week(tonight: NightPlan, tomorrow: NightPlan?, forecast: Forecast, site: Site, fov: FieldOfView, rule: GoRule,
                            bright: BrightSettings?) -> [WeekNight] {
        guard let last = forecast.hours.map(\.time).max() else { return [] }
        var out: [WeekNight] = []
        for i in 0..<weekNights {
            let plan: NightPlan
            switch i {
            case 0: plan = tonight
            case 1:
                guard let t = tomorrow else { return out }
                plan = t
            default:
                guard let date = site.calendar.date(byAdding: .day, value: i, to: tonight.night.localDate),
                      let night = try? Ephemeris.night(localDate: date, site: site) else { return out }
                plan = Planner.plan(night: night, forecast: forecast, catalog: Catalog(objects: []), constellations: [],
                                    site: site, fov: fov, rule: rule, bright: bright)
            }
            let end = plan.night.darkEnd ?? plan.night.nauticalEnd ?? plan.night.sunrise
            guard last.addingTimeInterval(3600) >= end else { return out }
            out.append(WeekNight(plan: plan, daysAhead: i))
        }
        return out
    }

    /// The longest unbroken run of clear hours in darkness under the go rule; nil when no hour is clear.
    public static func longestClearRun(_ darkHours: [HourlyConditions], rule: GoRule) -> (start: Date, hours: Int)? {
        var best: (start: Date, hours: Int)? = nil, run: (start: Date, hours: Int)? = nil, prev: Date? = nil
        for h in darkHours.sorted(by: { $0.time < $1.time }) {
            let contiguous = prev.map { h.time.timeIntervalSince($0) == 3600 } ?? false
            if h.effectiveCloud <= rule.maxCloudPct { run = (contiguous && run != nil) ? (run!.start, run!.hours + 1) : (h.time, 1) } else { run = nil }
            if let r = run, r.hours > (best?.hours ?? 0) { best = r }
            prev = h.time
        }
        return best
    }
}

extension Copy {
    /// Seeing in arcseconds from 7Timer's bands, averaged over darkness; nil when there is none, as beyond its 72 hours.
    public static func seeingText(_ darkHours: [HourlyConditions]) -> String? {
        let seeing = darkHours.compactMap(\.seeing)
        guard !seeing.isEmpty else { return nil }
        return ["", "<0.5″", "0.5–0.75″", "0.75–1″", "1–1.25″", "1.25–1.5″", "1.5–2″", "2–2.5″", ">2.5″"][max(0, min(8, seeing.reduce(0, +) / seeing.count))]
    }

    static func hoursText(_ h: Double) -> String { String(format: "%.1f h", h).replacingOccurrences(of: ".0 h", with: " h") }

    /// "Tonight", "Tomorrow", then the weekday.
    public static func weekDay(_ n: WeekNight, site: Site) -> String {
        switch n.daysAhead {
        case 0: return "Tonight"
        case 1: return "Tomorrow"
        default:
            let f = DateFormatter(); f.locale = Locale(identifier: "en_GB"); f.timeZone = site.timeZone; f.dateFormat = "EEEE"
            return f.string(from: n.plan.night.localDate)
        }
    }

    /// "Clear 22:00–03:00 · 5 h", or the longest clear run when the night misses the rule.
    public static func weekVerdict(_ p: NightPlan, rule: GoRule, site: Site) -> String {
        if let w = p.primary {
            return (p.mode == .bright ? "Bright night · clear " : "Clear ") + "\(span(w.start, w.end, site: site)) · \(hoursText(w.hours))"
        }
        if p.darkSpan == nil { return "No astronomical darkness" }
        guard let run = Planner.longestClearRun(p.darkHours, rule: rule) else { return "No clear window" }
        return "No clear window · longest clear run \(run.hours) h from \(hhmm(run.start, site: site))"
    }

    /// "Dark 20:46–05:11 · Moon 80%, up all night · seeing 1.25–1.5″"
    public static func weekDetail(_ p: NightPlan, site: Site) -> String {
        var parts: [String] = []
        if let d = p.darkSpan { parts.append("Dark \(span(d.start, d.end, site: site))") }
        let pct = "Moon \(Int((p.moonIllumination * 100).rounded()))%"
        switch Planner.moonTonight(p) {
        case .sets(let t): parts.append("\(pct), sets \(hhmm(t, site: site))")
        case .rises(let t): parts.append("\(pct), rises \(hhmm(t, site: site))")
        case .upAllNight: parts.append("\(pct), up all night")
        case .down: parts.append("\(pct), down all night")
        case nil: parts.append(pct)
        }
        if let s = seeingText(p.darkHours) { parts.append("seeing \(s)") }
        return parts.joined(separator: " · ")
    }

    /// From three days out the cloud forecast is labelled, never hidden (owner's "Less certain" wording).
    public static func weekLead(daysAhead: Int) -> String? { daysAhead >= 3 ? "Less certain · \(daysAhead) days ahead" : nil }
}
