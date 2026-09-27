import Foundation

/// The app's user-facing sentences, in plain English. The Discworld wording and its setting were removed in 0.7.0
/// (owner, 26 September 2026: the App Store forbids third-party protected material, rule 5.2.1).
public struct Copy: Sendable {
    public init() {}

    public var refresh: String { "Refresh" }
    public var noWindow: String { "No clear window tonight." }
    public var cancelTitle: String { "Cancelled. Clouds moving in" }
    public var lessCertainTitle: String { "Less certain. Forecasts disagree" }
    public func offlineSince(_ time: String) -> String { "Offline since \(time)" }
    public func goTitle(windowStart: String) -> String { "Clear from \(windowStart)" }
    public func headsUpTitle(windowStart: String, hours: Double) -> String {
        String(format: "Clear skies tonight from %@ · %.1f h", windowStart, hours)
    }
    public func tomorrowTitle(hours: Double) -> String { String(format: "Tomorrow night looks clear · %.1f h", hours) }

    // Bright nights (v0.3).
    public func brightHeadsUpTitle(windowStart: String, targets: [RankedTarget]) -> String {
        "Bright night tonight from \(windowStart) · \(Copy.brightList(targets))"
    }
    public func brightGoTitle(windowStart: String) -> String { "Bright night. Clear from \(windowStart)" }
    public func brightTomorrowTitle(hours: Double) -> String { String(format: "Tomorrow looks bright and clear · %.1f h", hours) }
    /// "Moon 62%, Saturn": the Moon with its illumination, planets by name, in the plan's order.
    public static func brightList(_ targets: [RankedTarget]) -> String {
        targets.map { $0.id == "moon" ? "Moon \($0.subtitle.prefix { $0 != " " })" : $0.name }.joined(separator: ", ")
    }

    /// `agreement`: append Open-Meteo's line (v0.5); the tomorrow preview passes false.
    public func notificationBody(plan: NightPlan, site: Site, agreement: Bool = true) -> String {
        let line = agreement ? plan.agreement.map { " " + Copy.agreementText($0, site: site) + "." } ?? "" : ""
        if plan.mode == .bright { return Copy.brightList(plan.brightTargets) + " well placed." + line }
        var parts: [String] = []
        if let set = plan.moonSet { parts.append("Moon sets \(Copy.hhmm(set, site: site))") }
        else if plan.moonIllumination < 0.1 { parts.append("No Moon") }
        else { parts.append("Moon \(Int((plan.moonIllumination * 100).rounded()))%") }
        if !plan.best.isEmpty { parts.append(plan.best.map(\.name).joined(separator: ", ") + " well placed") }
        return parts.joined(separator: ". ") + "." + line
    }

    /// "Held back by a 97% moon and high dew risk": the two biggest losses, or nil when nothing limits the score.
    public static func heldBack(_ factors: [LimitingFactor]) -> String? {
        factors.isEmpty ? nil : "Held back by " + factors.prefix(2).map(\.text).joined(separator: " and ")
    }

    /// The bezel's screen-reader sentence (spec §7).
    public static func bezelLabel(_ plan: NightPlan, site: Site) -> String {
        guard let w = plan.primary else { return "Sky score \(plan.score) of 100. No clear window." }
        var s = "Sky score \(plan.score) of 100. Clear from \(hhmm(w.start, site: site)) to \(hhmm(w.end, site: site))"
        if let h = plan.darkHours.min(by: { $0.cloudTotal < $1.cloudTotal }) { s += ", clearest hour \(hhmm(h.time, site: site)) at \(max(0, 100 - h.cloudTotal))% clear" }
        return s + "."
    }

    public static func moonText(_ m: MoonTonight, site: Site) -> String {
        switch m {
        case .sets(let t): "Sets \(hhmm(t, site: site))"
        case .rises(let t): "Rises \(hhmm(t, site: site))"
        case .upAllNight: "Up all night"
        case .down: "Down tonight"
        }
    }

    public static func hoursAgo(_ from: Date, now: Date) -> String { "\(Int(now.timeIntervalSince(from) / 3600)) h ago" }

    /// Why a Targets search shows less than it found: matches in this group hidden by the filters, and matches in other
    /// groups (the search covers only the group on screen). Nil when there is nothing to explain.
    public static func searchHint(query: String, targets: [RankedTarget], group: TargetGroup, fitsOnly: Bool, includeMoonWashed: Bool) -> String? {
        guard !query.allSatisfy(\.isWhitespace) else { return nil }
        let found = targets.filter { $0.matches(query) }
        let here = found.filter { $0.group == group }
        func noun(_ n: Int) -> String { n == 1 ? "match" : "matches" }
        var parts: [String] = []
        // Counted per filter: a match both Moon-washed and outside the field of view is named by both, as both hide it.
        let washed = here.filter { $0.hiddenByMoon(includeMoonWashed: includeMoonWashed) }.count
        if washed > 0 { parts.append("\(washed) Moon-washed \(noun(washed)) hidden: turn on Include Moon-washed.") }
        let unfit = here.filter { $0.hiddenByFit(fitsOnly: fitsOnly) }.count
        if unfit > 0 { parts.append("\(unfit) \(noun(unfit)) hidden by Fits my field of view.") }
        let elsewhere = TargetGroup.allCases.filter { $0 != group }.compactMap { g -> String? in
            let n = found.filter { $0.group == g }.count
            return n == 0 ? nil : "\(g.displayName) (\(n))"
        }
        if !elsewhere.isEmpty { parts.append("Also in \(elsewhere.joined(separator: ", ")).") }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// "NGC 6992 Eastern Veil, viewable from 00:00 to 03:28, best at 00:00, 57 degrees up" (spec §7).
    /// The card's whole sentence, chips and magnitude included, because the label replaces the card's contents for a screen reader.
    public static func cardLabel(_ t: RankedTarget, lit: Bool, nearMoon: Bool, site: Site) -> String {
        let name = [t.catalogueID, t.caldwell.map { "C\($0)" }, t.commonName].compactMap { $0 }.joined(separator: " ")
        var parts = [name]
        if let m = t.magnitude { parts.append(String(format: "magnitude %.1f", m)) }
        parts.append(frameChip(t))
        if t.moonWashed { parts.append("Moon-washed") } else if nearMoon { parts.append("Near Moon") }
        if !lit { parts.append("not in clear sky tonight") }
        else if let v = t.viewable {
            parts.append("viewable from \(hhmm(v.start, site: site)) to \(hhmm(v.end, site: site)), best at \(hhmm(t.peakTime, site: site)), \(Int(t.peakAltDeg.rounded())) degrees up")
        } else { parts.append("viewable outside the clear window") }
        return parts.joined(separator: ", ")
    }

    /// The notify switch in Settings › Alerts: "Notify at HH:MM" for the nudge before the window, unless quiet hours would drop that nudge.
    public static func notifyLabel(_ plan: NightPlan?, site: Site, settings: AlertSettings) -> String {
        notifyTime(plan, site: site, settings: settings).map { "Notify at \($0)" } ?? "Notify when clear"
    }
    /// The heads-up's "20:30", or nil when there is no window or it falls in quiet hours.
    public static func notifyTime(_ plan: NightPlan?, site: Site, settings: AlertSettings) -> String? {
        guard let w = plan?.primary else { return nil }
        let at = w.start.addingTimeInterval(-Double(settings.preWindowMinutes) * 60)
        return AlertEngine.inQuietHours(at, site: site, settings: settings) ? nil : hhmm(at, site: site)
    }

    /// The neutral frame chip on a Targets card (follow-on 1).
    public static func frameChip(_ t: RankedTarget) -> String {
        switch t.fit {
        case .fits: t.frameFill.map { "Fills \(max(1, Int(($0 * 100).rounded())))% of frame" } ?? "Fits frame"
        case .small: "Small in frame"
        case .mosaic: "Mosaic"
        }
    }

    /// The v0.5 agreement line.
    public static func agreementText(_ a: Agreement, site: Site) -> String {
        switch a {
        case .agree: "Open-Meteo agrees"
        case .cloudFrom(let t): "Open-Meteo sees cloud from \(hhmm(t, site: site))"
        case .clearFrom(let t): "Open-Meteo sees it clear from \(hhmm(t, site: site))"
        case .noWindow: "Open-Meteo sees no clear window"
        case .agreeNoWindow: "Open-Meteo agrees: no clear window"
        case .clearRun(let a, let b): "Open-Meteo has a clear run \(hhmm(a, site: site))–\(hhmm(b, site: site))"
        }
    }

    /// Amber dot when Open-Meteo disagrees; a tick when it agrees.
    public static func agreementWarns(_ a: Agreement) -> Bool {
        switch a { case .agree, .agreeNoWindow: false; default: true }
    }

    public static func hhmm(_ date: Date, site: Site) -> String {
        let f = DateFormatter(); f.timeZone = site.timeZone; f.dateFormat = "HH:mm"; f.locale = Locale(identifier: "en_GB")
        return f.string(from: date)
    }

    public func scoreBand(_ score: Int) -> String {
        switch score { case 80...: "Excellent"; case 50..<80: "Fair"; case 20..<50: "Poor"; default: "Overcast" }
    }
}
