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

    /// `agreement`: append the second opinion (v0.5), in the popover's words when it disagrees ("A second forecast sees cloud
    /// from 00:00, so this window is less certain than usual."); the tomorrow preview passes false.
    public func notificationBody(plan: NightPlan, site: Site, agreement: Bool = true, alerts: AlertSettings = AlertSettings()) -> String {
        let line = agreement ? secondOpinionLine(plan: plan, site: site, alerts: alerts) : ""
        if plan.mode == .bright { return Copy.brightList(plan.brightTargets) + " well placed." + line }
        var parts: [String] = []
        if let set = plan.moonSet { parts.append("Moon sets \(Copy.hhmm(set, site: site))") }
        else if plan.moonIllumination < 0.1 { parts.append("No Moon") }
        else { parts.append("Moon \(Int((plan.moonIllumination * 100).rounded()))%") }
        if !plan.best.isEmpty { parts.append(plan.best.map(\.name).joined(separator: ", ") + " well placed") }
        return parts.joined(separator: ". ") + "." + line
    }

    /// The second opinion as a notification ends, with its leading space; "" without one. Shared by every body that carries it.
    public func secondOpinionLine(plan: NightPlan, site: Site, alerts: AlertSettings) -> String {
        if let advice = Copy.advice(plan, site: site, alerts: alerts) { return " " + advice.sentence }
        return plan.agreement.map { " " + Copy.agreementText($0, site: site) + "." } ?? ""
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

    /// What a Targets search found, leading the header so it is plain the search ran: the count in this group, the matches
    /// the two switches would hide (shown last while searching), and matches in other groups (the search covers only the
    /// group on screen). Nil with no search.
    public static func searchHint(query: String, targets: [RankedTarget], group: TargetGroup, fitsOnly: Bool, includeMoonWashed: Bool) -> String? {
        guard !query.allSatisfy(\.isWhitespace) else { return nil }   // the grid's test for "no search", newlines included
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let found = targets.filter { $0.matches(query) }
        let here = found.filter { $0.group == group }
        var parts = [here.isEmpty ? "No match for “\(q)” in \(group.displayName) tonight."
                                  : "\(here.count) \(here.count == 1 ? "match" : "matches") for “\(q)” in \(group.displayName)."]
        // Counted per switch: a match both Moon-washed and outside the field of view is named by both.
        let washed = here.filter { $0.hiddenByMoon(includeMoonWashed: includeMoonWashed) }.count
        if washed > 0 { parts.append("\(washed) Moon-washed, shown last.") }
        let unfit = here.filter { $0.hiddenByFit(fitsOnly: fitsOnly) }.count
        if unfit > 0 { parts.append("\(unfit) not fitting your field of view, shown last.") }
        let elsewhere = TargetGroup.allCases.filter { $0 != group }.compactMap { g -> String? in
            let n = found.filter { $0.group == g }.count
            return n == 0 ? nil : "\(g.displayName) (\(n))"
        }
        if !elsewhere.isEmpty { parts.append("Also in \(elsewhere.joined(separator: ", ")).") }
        return parts.joined(separator: " ")
    }

    /// "NGC 6992 Eastern Veil, viewable from 00:00 to 03:28, best at 00:00, 57 degrees up" (spec §7).
    /// The card's whole sentence, chips and magnitude included, because the label replaces the card's contents for a screen reader.
    public static func cardLabel(_ t: RankedTarget, lit: Bool, nearMoon: Bool, site: Site) -> String {
        let name = [t.catalogueID, t.cardNote, t.cardName].compactMap { $0 }.joined(separator: " ")   // as the card reads
        var parts = [name]
        if let m = t.magnitude { parts.append(String(format: "magnitude %.1f", m)) }
        parts.append(frameChip(t))
        if t.moonWashed { parts.append("Moon-washed") } else if nearMoon { parts.append("Near Moon") }
        if !lit {
            // No clear window: when it is up in darkness anyway, as the card now shows (owner, 28 September 2026).
            if let v = t.viewable {
                parts.append("no clear window, up in darkness from \(hhmm(v.start, site: site)) to \(hhmm(v.end, site: site)), highest at \(hhmm(t.peakTime, site: site)), \(Int(t.peakAltDeg.rounded())) degrees up")
            } else { parts.append("no clear window, too low in darkness tonight") }
        }
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

    /// When the second opinion disagrees, one plain line that says what it means instead of a bare fact about Open-Meteo
    /// (owner, 28 September 2026: no box, no dot, no coloured text, so the popover keeps its simplicity). With no window and
    /// Open-Meteo clear, when to check again; with a window, that it is less certain. The verdict still comes from Apple
    /// Weather alone, and a clear night is a notification, not a guarantee. nil when they agree.
    public struct Advice: Equatable, Sendable {
        /// The popover's and widgets' line: "Less certain: a second forecast sees cloud from 00:00."
        public let line: String
        /// The notifications' sentence: "A second forecast sees cloud from 00:00, so this window is less certain than usual."
        public let sentence: String
    }

    public static func advice(_ plan: NightPlan, site: Site, alerts: AlertSettings, now: Date = Date()) -> Advice? {
        guard let a = plan.agreement, agreementWarns(a) else { return nil }
        func range(_ x: Date, _ y: Date) -> String { "\(hhmm(x, site: site))–\(hhmm(y, site: site))" }
        if plan.primary == nil, case .clearRun(let x, let y) = a {
            // Nothing to check once Open-Meteo's run is over: the plan only changes at the next refresh.
            guard now < y else { return nil }
            // Check again at the nudge time before Open-Meteo's run: the same lead the user chose for the nudge.
            let check = x.addingTimeInterval(-Double(alerts.preWindowMinutes) * 60)
            let sees = "a second forecast sees \(range(x, y)) clear."
            return Advice(line: (check > now ? "Check again at \(hhmm(check, site: site))" : "Check the sky now") + ": " + sees,
                          sentence: "A second forecast sees \(range(x, y)) clear.")
        }
        let sees: String = switch a {
        case .cloudFrom(let t): "sees cloud from \(hhmm(t, site: site))"
        case .clearFrom(let t): "sees it clear only from \(hhmm(t, site: site))"
        case .clearRun(let x, let y): "sees it clear \(range(x, y)) instead"
        case .noWindow, .agree, .agreeNoWindow: "sees no clear window"
        }
        return Advice(line: "Less certain: a second forecast \(sees).",
                      sentence: "A second forecast \(sees), so this window is less certain than usual.")
    }

    /// "Sun 27 Sep": the one way a date is written in the interface (owner, 28 September 2026).
    public static func dayMonth(_ date: Date, site: Site) -> String {
        let f = DateFormatter(); f.timeZone = site.timeZone; f.dateFormat = "EEE d MMM"; f.locale = Locale(identifier: "en_GB")
        return f.string(from: date)
    }

    public static func hhmm(_ date: Date, site: Site) -> String {
        let f = DateFormatter(); f.timeZone = site.timeZone; f.dateFormat = "HH:mm"; f.locale = Locale(identifier: "en_GB")
        return f.string(from: date)
    }

    // Tonight's plan (#57, owner-approved mock-up, 29 September 2026).
    static let ordinalWords = ["first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth"]
    static let countWords = ["no", "one", "two", "three", "four", "five", "six", "seven", "eight"]
    /// "first" for slot 0.
    public static func ordinal(_ i: Int) -> String { i < ordinalWords.count ? ordinalWords[i] : "number \(i + 1)" }

    /// "5 h", "1 h 40 min", "40 min".
    public static func duration(_ seconds: TimeInterval) -> String {
        let m = Int((seconds / 60).rounded()), h = m / 60, r = m % 60
        return h == 0 ? "\(r) min" : (r == 0 ? "\(h) h" : "\(h) h \(r) min")
    }

    /// "20:40–03:10".
    public static func span(_ from: Date, _ to: Date, site: Site) -> String { "\(hhmm(from, site: site))–\(hhmm(to, site: site))" }

    /// The strip's summary: "Clear 20:40–03:10 · three targets, 5 h", with "stop by 00:30" when that ends it first.
    public static func planHeader(_ s: SessionPlan, window: ClearWindow, site: Site) -> String {
        let n = s.slots.count
        let count = "\(n < countWords.count ? countWords[n] : String(n)) target\(n == 1 ? "" : "s"), \(duration(s.hours * 3600))"
        let stop = s.end < window.end ? " · stop by \(hhmm(s.end, site: site))" : ""
        return "Clear \(span(window.start, window.end, site: site))\(stop) · \(count)"
    }

    /// A slot's second line: "Crescent Nebula, in Cygnus".
    public static func slotName(_ t: RankedTarget, constellations: [Constellation]) -> String {
        let abbr = t.subtitle.components(separatedBy: " in ").last ?? ""
        guard let c = constellations.first(where: { $0.id == abbr }) else { return t.cardName }
        return "\(t.cardName), in \(c.name)"
    }

    /// A slot's third line: "Best 21:20, so first · Duo-Band · 200 × 30 s"; a favourite or added target says so instead.
    public static func slotDetail(_ slot: PlanSlot, index: Int, presetID: String?, site: Site) -> String {
        let best = hhmm(slot.target.peakTime, site: site)
        let why = switch slot.reason {
        case .bestPlaced: "Best \(best), so \(ordinal(index))"
        case .favourite: "Favourite · best \(best)"
        case .added: "Added by you · best \(best)"
        }
        return ShootingTips.planKit(slot.target, presetID: presetID).map { "\(why) · \($0)" } ?? why
    }

    /// "01:40–03:10: 1 h 30 min left, too short for another stack." Nil without a leftover.
    public static func planLeftover(_ s: SessionPlan, site: Site) -> String? {
        guard let l = s.leftover else { return nil }
        let left = "\(span(l.start, l.end, site: site)): \(duration(l.end.timeIntervalSince(l.start))) left"
        return s.leftoverTooShort ? "\(left), too short for another stack." : "\(left), with nothing else up long enough to add."
    }

    /// The power-bank note (owner, 29 September 2026: the battery is not a limit, but say when a plan outlasts it).
    public static func planBattery(_ s: SessionPlan, telescope: String) -> String? {
        guard let b = s.outlastsBatteryHours else { return nil }
        return "This plan runs \(duration(s.hours * 3600)), longer than a \(telescope) battery (about \(duration(b * 3600))): you may need a power bank or a spare battery."
    }

    /// A target card in the plan: "In the plan, 1st".
    public static func inPlan(_ index: Int) -> String {
        let n = index + 1, suffix = (n % 100 / 10 == 1) ? "th" : (["th", "st", "nd", "rd"] + Array(repeating: "th", count: 6))[n % 10]
        return "In the plan, \(n)\(suffix)"
    }

    /// The heads-up with a plan: "Start with the Crescent Nebula at 20:40, then the Bubble Nebula at 22:20." and, only when
    /// dew is likely during the plan, "Fit the dew heater: dew likely after 23:00."
    public static func headsUpPlan(_ s: SessionPlan, plan: NightPlan, site: Site) -> String {
        func name(_ t: RankedTarget) -> String { t.commonName.map { "the \($0)" } ?? t.catalogueID }
        var text = s.slots.prefix(2).enumerated().map { i, slot in
            "\(i == 0 ? "Start with" : "then") \(name(slot.target)) at \(hhmm(slot.start, site: site))"
        }.joined(separator: ", ") + "."
        let dew = plan.darkHours.first { h in
            guard h.time >= s.slots[0].start.addingTimeInterval(-1800), h.time < s.end, let t = h.tempC, let d = h.dewPointC else { return false }
            return t - d < 2
        }
        if let d = dew { text += " Fit the dew heater: dew likely after \(hhmm(max(d.time, s.slots[0].start), site: site))." }
        return text
    }

    // Siri and Spotlight (#53). Spoken answers from the cached forecast, naming its source as the widget does.
    static func siriSource(_ s: WidgetSnapshot) -> String? { s.source.map { "Forecast from \($0)." } }

    /// A clause as a sentence: its own full stop, never two.
    static func sentence(_ s: String) -> String { s.hasSuffix(".") ? s : s + "." }

    /// "Sky Score": "Sky score 72 at Home. Clear window tonight. 20:40–03:10 · 6.5 h. Held back by a 40% moon. Forecast
    /// from Apple Weather." On a night without a window the reason and "Tomorrow 21:10–01:40." follow instead.
    public static func siriTonight(_ s: WidgetSnapshot?) -> String {
        guard let s else { return "Nightwatch has no forecast yet. Open it once to set where you observe." }
        return (["Sky score \(s.score) at \(s.siteName)", s.headline, s.window, s.reason, s.tomorrow].compactMap { $0 }.map(sentence)
                + [siriSource(s)].compactMap { $0 }).joined(separator: " ")
    }

    /// "Best Targets Tonight": Tonight's plan when there is one, else the popover's best three ("M31, best 00:40 · 64° up").
    public static func siriBest(_ s: WidgetSnapshot?, session: SessionPlan?, site: Site?) -> String {
        guard let s else { return siriTonight(nil) }
        if let session, let site {
            let list = session.slots.map { "\($0.target.commonName ?? $0.target.catalogueID) at \(hhmm($0.start, site: site))" }
            return "Tonight's plan: " + list.joined(separator: ", then ") + "."
        }
        guard !s.targets.isEmpty else { return [sentence(s.headline), "No targets are suggested tonight."].joined(separator: " ") }
        // `best` already reads "Best 00:40 · 64° up"; lower-cased after the name.
        return "Tonight's best targets: " + s.targets.map { "\($0.name), \($0.best.prefix(1).lowercased() + $0.best.dropFirst())" }
            .joined(separator: "; ") + "."
    }

    /// "Events Tonight": up to three, with whether it will be clear then.
    public static func siriEvents(_ events: [SkyEvent]) -> String {
        guard !events.isEmpty else { return "No events tonight." }
        return events.prefix(3).map { e in
            [e.title + ".", e.clear.map { $0 ? "Clear then." : "Cloudy then." }].compactMap { $0 }.joined(separator: " ")
        }.joined(separator: " ")
    }

    public func scoreBand(_ score: Int) -> String {
        switch score { case 80...: "Excellent"; case 50..<80: "Fair"; case 20..<50: "Poor"; default: "Overcast" }
    }
}
