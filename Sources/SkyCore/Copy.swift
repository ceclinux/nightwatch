import Foundation

/// The app's user-facing sentences, in plain English. The Discworld wording and its setting were removed in 0.7.0
/// (owner, 26 September 2026: the App Store forbids third-party protected material, rule 5.2.1).
public struct Copy: Sendable {
    public init() {}

    public var refresh: String { L10n.text("Refresh") }
    public var noWindow: String { L10n.text("No clear window tonight.") }
    public var cancelTitle: String { L10n.text("Cancelled. Clouds moving in") }
    public var lessCertainTitle: String { L10n.text("Less certain. Forecasts disagree") }
    public func offlineSince(_ time: String) -> String { L10n.format("Offline since \(time)") }
    public func goTitle(windowStart: String) -> String { L10n.format("Clear from \(windowStart)") }
    public func headsUpTitle(windowStart: String, hours: Double) -> String {
        String(format: L10n.text("Clear skies tonight from %@ · %.1f h"), windowStart, hours)
    }
    public func tomorrowTitle(hours: Double) -> String { String(format: L10n.text("Tomorrow night looks clear · %.1f h"), hours) }

    // Bright nights (v0.3).
    public func brightHeadsUpTitle(windowStart: String, targets: [RankedTarget]) -> String {
        L10n.format("Bright night tonight from \(windowStart) · \(Copy.brightList(targets))")
    }
    public func brightGoTitle(windowStart: String) -> String { L10n.format("Bright night. Clear from \(windowStart)") }
    public func brightTomorrowTitle(hours: Double) -> String { String(format: L10n.text("Tomorrow looks bright and clear · %.1f h"), hours) }
    /// "Moon 62%, Saturn": the Moon with its illumination, planets by name, in the plan's order.
    public static func brightList(_ targets: [RankedTarget]) -> String {
        targets.map { $0.id == "moon" ? L10n.format("Moon \($0.subtitle.prefix { $0 != " " })") : L10n.text($0.name) }.joined(separator: ", ")
    }

    /// `agreement`: append the second opinion (v0.5), in the popover's words when it disagrees ("A second forecast sees cloud
    /// from 00:00, so this window is less certain than usual."); the tomorrow preview passes false.
    public func notificationBody(plan: NightPlan, site: Site, agreement: Bool = true, alerts: AlertSettings = AlertSettings()) -> String {
        let line = agreement ? secondOpinionLine(plan: plan, site: site, alerts: alerts) : ""
        if plan.mode == .bright { return Copy.brightList(plan.brightTargets) + L10n.text(" well placed.") + line }
        var parts: [String] = []
        if let set = plan.moonSet { parts.append(L10n.format("Moon sets \(Copy.hhmm(set, site: site))")) }
        else if plan.moonIllumination < 0.1 { parts.append(L10n.text("No Moon")) }
        else { parts.append(L10n.format("Moon \(Int((plan.moonIllumination * 100).rounded()))%")) }
        if !plan.best.isEmpty { parts.append(plan.best.map(\.name).joined(separator: ", ") + L10n.text(" well placed")) }
        return parts.joined(separator: ". ") + "." + line
    }

    /// The second opinion as a notification ends, with its leading space; "" without one. Shared by every body that carries it.
    public func secondOpinionLine(plan: NightPlan, site: Site, alerts: AlertSettings) -> String {
        if let advice = Copy.advice(plan, site: site, alerts: alerts) { return " " + advice.sentence }
        return plan.agreement.map { " " + Copy.agreementText($0, site: site) + "." } ?? ""
    }

    /// "Held back by a 97% moon and high dew risk": the two biggest losses, or nil when nothing limits the score.
    public static func heldBack(_ factors: [LimitingFactor]) -> String? {
        factors.isEmpty ? nil : L10n.text("Held back by ") + factors.prefix(2).map(\.text).joined(separator: L10n.text(" and "))
    }

    /// The bezel's screen-reader sentence (spec §7).
    public static func bezelLabel(_ plan: NightPlan, site: Site) -> String {
        guard let w = plan.primary else { return L10n.format("Sky score \(plan.score) of 100. No clear window.") }
        var s = L10n.format("Sky score \(plan.score) of 100. Clear from \(hhmm(w.start, site: site)) to \(hhmm(w.end, site: site))")
        if let h = plan.darkHours.min(by: { $0.effectiveCloud < $1.effectiveCloud }) { s += L10n.format(", clearest hour \(hhmm(h.time, site: site)) at \(max(0, 100 - h.effectiveCloud))% clear") }
        return s + "."
    }

    public static func moonText(_ m: MoonTonight, site: Site) -> String {
        switch m {
        case .sets(let t): L10n.format("Sets \(hhmm(t, site: site))")
        case .rises(let t): L10n.format("Rises \(hhmm(t, site: site))")
        case .upAllNight: L10n.text("Up all night")
        case .down: L10n.text("Down tonight")
        }
    }

    public static func hoursAgo(_ from: Date, now: Date) -> String { L10n.format("\(Int(now.timeIntervalSince(from) / 3600)) h ago") }

    /// What a Targets search found, leading the header so it is plain the search ran: the count in this group, the matches
    /// the two switches would hide (shown last while searching), and matches in other groups (the search covers only the
    /// group on screen). Nil with no search.
    public static func searchHint(query: String, targets: [RankedTarget], group: TargetGroup, fitsOnly: Bool, includeMoonWashed: Bool) -> String? {
        guard !query.allSatisfy(\.isWhitespace) else { return nil }   // the grid's test for "no search", newlines included
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let found = targets.filter { $0.matches(query) }
        let here = found.filter { $0.group == group }
        var parts = [here.isEmpty ? L10n.format("No match for “\(q)” in \(group.displayName) tonight.")
                                  : L10n.format("\(here.count) \(here.count == 1 ? L10n.text("match") : L10n.text("matches")) for “\(q)” in \(group.displayName).")]
        // Counted per switch: a match both Moon-washed and outside the field of view is named by both.
        let washed = here.filter { $0.hiddenByMoon(includeMoonWashed: includeMoonWashed) }.count
        if washed > 0 { parts.append(L10n.format("\(washed) Moon-washed, shown last.")) }
        let unfit = here.filter { $0.hiddenByFit(fitsOnly: fitsOnly) }.count
        if unfit > 0 { parts.append(L10n.format("\(unfit) not fitting your field of view, shown last.")) }
        let elsewhere = TargetGroup.allCases.filter { $0 != group }.compactMap { g -> String? in
            let n = found.filter { $0.group == g }.count
            return n == 0 ? nil : "\(g.displayName) (\(n))"
        }
        if !elsewhere.isEmpty { parts.append(L10n.format("Also in \(elsewhere.joined(separator: ", ")).")) }
        return parts.joined(separator: " ")
    }

    /// "NGC 6992 Eastern Veil, viewable from 00:00 to 03:28, best at 00:00, 57 degrees up" (spec §7).
    /// The card's whole sentence, chips and magnitude included, because the label replaces the card's contents for a screen reader.
    public static func cardLabel(_ t: RankedTarget, lit: Bool, nearMoon: Bool, site: Site) -> String {
        let name = [t.catalogueID, t.cardNote, t.cardName].compactMap { $0 }.joined(separator: " ")   // as the card reads
        var parts = [name]
        if let m = t.magnitude { parts.append(String(format: L10n.text("magnitude %.1f"), m)) }
        parts.append(frameChip(t))
        if t.moonWashed { parts.append(L10n.text("Moon-washed")) } else if nearMoon { parts.append(L10n.text("Near Moon")) }
        if !lit {
            // No clear window: when it is up in darkness anyway, as the card now shows (owner, 28 September 2026).
            if let v = t.viewable {
                parts.append(L10n.format("no clear window, up in darkness from \(hhmm(v.start, site: site)) to \(hhmm(v.end, site: site)), highest at \(hhmm(t.peakTime, site: site)), \(Int(t.peakAltDeg.rounded())) degrees up"))
            } else { parts.append(L10n.text("no clear window, too low in darkness tonight")) }
        }
        else if let v = t.viewable {
            parts.append(L10n.format("viewable from \(hhmm(v.start, site: site)) to \(hhmm(v.end, site: site)), best at \(hhmm(t.peakTime, site: site)), \(Int(t.peakAltDeg.rounded())) degrees up"))
        } else { parts.append(L10n.text("viewable outside the clear window")) }
        return parts.joined(separator: ", ")
    }

    /// The notify switch in Settings › Alerts: "Notify at HH:MM" for the nudge before the window, unless quiet hours would drop that nudge.
    public static func notifyLabel(_ plan: NightPlan?, site: Site, settings: AlertSettings) -> String {
        notifyTime(plan, site: site, settings: settings).map { L10n.format("Notify at \($0)") } ?? L10n.text("Notify when clear")
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
        case .fits: t.frameFill.map { L10n.format("Fills \(max(1, Int(($0 * 100).rounded())))% of frame") } ?? L10n.text("Fits frame")
        case .small: L10n.text("Small in frame")
        case .mosaic: L10n.text("Mosaic")
        }
    }

    /// The v0.5 agreement line.
    public static func agreementText(_ a: Agreement, site: Site) -> String {
        switch a {
        case .agree: L10n.text("Open-Meteo agrees")
        case .cloudFrom(let t): L10n.format("Open-Meteo sees cloud from \(hhmm(t, site: site))")
        case .clearFrom(let t): L10n.format("Open-Meteo sees it clear from \(hhmm(t, site: site))")
        case .noWindow: L10n.text("Open-Meteo sees no clear window")
        case .agreeNoWindow: L10n.text("Open-Meteo agrees: no clear window")
        case .clearRun(let a, let b): L10n.format("Open-Meteo has a clear run \(hhmm(a, site: site))–\(hhmm(b, site: site))")
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
            let sees = L10n.format("a second forecast sees \(range(x, y)) clear.")
            return Advice(line: (check > now ? L10n.format("Check again at \(hhmm(check, site: site))") : L10n.text("Check the sky now")) + ": " + sees,
                          sentence: L10n.format("A second forecast sees \(range(x, y)) clear."))
        }
        let sees: String = switch a {
        case .cloudFrom(let t): L10n.format("sees cloud from \(hhmm(t, site: site))")
        case .clearFrom(let t): L10n.format("sees it clear only from \(hhmm(t, site: site))")
        case .clearRun(let x, let y): L10n.format("sees it clear \(range(x, y)) instead")
        case .noWindow, .agree, .agreeNoWindow: L10n.text("sees no clear window")
        }
        return Advice(line: L10n.format("Less certain: a second forecast \(sees)."),
                      sentence: L10n.format("A second forecast \(sees), so this window is less certain than usual."))
    }

    /// "Sun 27 Sep": the one way a date is written in the interface (owner, 28 September 2026).
    public static func dayMonth(_ date: Date, site: Site) -> String {
        let f = DateFormatter(); f.timeZone = site.timeZone; f.locale = L10n.locale
        f.dateFormat = L10n.language == .simplifiedChinese ? "M月d日 EEE" : "EEE d MMM"
        return f.string(from: date)
    }

    public static func hhmm(_ date: Date, site: Site) -> String {
        let f = DateFormatter(); f.timeZone = site.timeZone; f.dateFormat = "HH:mm"; f.locale = Locale(identifier: "en_GB")
        return f.string(from: date)
    }

    /// What VoiceOver says for the menu-bar icon (1.5): "Nightwatch, Clear window tonight 21:07–06:43 · 9.6 h, sky score
    /// 93, Malham", and the forecast's age when it is too old to trust. The icon alone told it only the symbol's name.
    public static func menuBarLabel(_ s: WidgetSnapshot?, now: Date) -> String {
        guard let s else { return L10n.text("Nightwatch, no forecast yet") }
        let headline = s.headline.hasSuffix(".") ? String(s.headline.dropLast()) : s.headline
        return (["Nightwatch", headline + (s.window.map { " \($0)" } ?? ""), L10n.format("sky score \(s.score)"), s.siteName] + [s.staleText(now: now)].compactMap { $0 })
            .joined(separator: ", ")
    }

    /// A time on this Mac's own clock, for when the Mac did something ("Updated 13:15"): it is read against the menu-bar
    /// clock, which differs from the site's when observing from another time zone. The night's times use `hhmm(_:site:)`.
    public static func clockTime(_ date: Date, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter(); f.timeZone = timeZone; f.dateFormat = "HH:mm"; f.locale = Locale(identifier: "en_GB")
        return f.string(from: date)
    }

    // Tonight's plan (#57, redesigned at the owner's UAT, 29 September 2026).

    /// "5 h", "1 h 40 min", "40 min".
    public static func duration(_ seconds: TimeInterval) -> String {
        let m = Int((seconds / 60).rounded()), h = m / 60, r = m % 60
        return h == 0 ? L10n.format("\(r) min") : (r == 0 ? L10n.format("\(h) h") : L10n.format("\(h) h \(r) min"))
    }

    /// "20:40–03:10".
    public static func span(_ from: Date, _ to: Date, site: Site) -> String { "\(hhmm(from, site: site))–\(hhmm(to, site: site))" }

    /// The plan page's summary: "Clear 21:40–02:10 · 4.5 h · Moon 78%", with "finish by 00:30" when that ends it first.
    public static func planSummary(_ s: SessionPlan, plan: NightPlan, site: Site) -> String {
        let full = plan.primary ?? s.window
        let stop = s.window.end < full.end ? L10n.format(" · finish by \(hhmm(s.window.end, site: site))") : ""
        return L10n.format("Clear \(span(full.start, full.end, site: site))\(stop) · \(duration(s.window.end.timeIntervalSince(s.window.start))) · Moon \(Int((plan.moonIllumination * 100).rounded()))%")
    }

    /// A plan row's detail: "Up 21:40–02:10 · best 21:50 at 79° · Duo-Band · 200 × 30 s", after "Added for this night" for
    /// a target that is not a favourite.
    public static func planDetail(_ item: PlanItem, presetID: String?, site: Site) -> String {
        let t = item.target
        var parts = item.added ? [L10n.text("Added for this night")] : []
        if let v = t.viewable { parts.append("\(site.horizon == nil ? L10n.text("Up") : L10n.text("Clear of your horizon")) \(span(v.start, v.end, site: site))") }
        parts.append(L10n.format("best \(hhmm(t.peakTime, site: site)) at \(Int(t.peakAltDeg.rounded()))°"))
        if let kit = ShootingTips.planKit(t, presetID: presetID) { parts.append(kit) }
        let text = parts.joined(separator: " · ")
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// "Best at the same time as the Crescent Nebula", or with two or more, "…as the Crescent Nebula and M31". Nil without a clash.
    public static func planClash(_ item: PlanItem) -> String? {
        guard !item.clashes.isEmpty else { return nil }
        let names = item.clashes.map { $0.commonName.map { L10n.format("the \($0)") } ?? $0.catalogueID }
        let list = names.count == 1 ? names[0] : names.dropLast().joined(separator: ", ") + L10n.text(" and ") + names.last!
        return L10n.format("Best at the same time as \(list)")
    }

    /// A target card in the plan: "In the plan, 1st".
    public static func inPlan(_ index: Int) -> String {
        let n = index + 1, suffix = (n % 100 / 10 == 1) ? "th" : (["th", "st", "nd", "rd"] + Array(repeating: "th", count: 6))[n % 10]
        if L10n.language == .simplifiedChinese { return L10n.format("In the plan, item \(n)") }
        return "In the plan, \(n)\(suffix)"
    }

    /// The heads-up with a plan: "Your plan: the North America Nebula, best at 21:50, then the Eastern Veil, best at 22:30."
    /// and, only when dew is likely while the plan's targets are up, "Fit the dew heater: dew likely after 23:00." Nil with
    /// nothing in the plan.
    /// A site's horizon for its Settings row: "Horizon: 45° S, SW · 40° SE", the directions higher than open sky (`openDeg`,
    /// the go rule's height), highest first; "Horizon: open sky" when none is. Lower ones change nothing (Site.floorDeg).
    public static func horizonSummary(_ site: Site, openDeg: Double) -> String {
        guard let h = site.horizon, h.count == 8 else { return L10n.text("Horizon: open sky") }
        let groups = Dictionary(grouping: h.indices.filter { h[$0] > openDeg }, by: { h[$0] }).sorted { $0.key > $1.key }
        guard !groups.isEmpty else { return L10n.text("Horizon: open sky") }
        return L10n.text("Horizon: ") + groups.map { deg, idx in "\(Int(deg))° " + idx.sorted().map { Site.horizonDirections[$0] }.joined(separator: ", ") }
            .joined(separator: " · ")
    }

    /// The terrain box's heading: "Hills reach 7° to the NW, 6° to the N, NE and W", the highest two heights.
    public static func terrainSummary(_ terrain: [Double]) -> String {
        let rounded = terrain.map { Int($0.rounded()) }
        guard let top = rounded.max(), top > 0 else { return L10n.text("No hills above the horizon around here") }
        let heights = Array(Set(rounded.filter { $0 > 0 })).sorted(by: >).prefix(2)
        return L10n.text("Hills reach ") + heights.map { h in
            let dirs = rounded.indices.filter { rounded[$0] == h }.map { Site.horizonDirections[$0] }
            return L10n.format("\(h)° to the ") + ListFormatter.localizedString(byJoining: dirs)
        }.joined(separator: ", ")
    }

    /// The heads-up's "Also tonight" line (owner, 1 October 2026, from the competitor review): up to two events the
    /// Events page has in tonight's clear sky, so a clear night with an ISS pass or a shower's peak says so. Showers only
    /// at their peak and comets never: both are on the list for weeks, which would put the same line on every heads-up.
    public static func alsoTonight(_ events: [SkyEvent], night: Night, site: Site) -> String? {
        let picks = events.filter { e in
            e.clear == true && !e.behindHorizon && e.when >= night.sunset && e.when < night.sunrise && e.kind != .comet && (e.kind != .meteorShower || e.atPeak)
        }.sorted { $0.when < $1.when }.prefix(2)
        guard !picks.isEmpty else { return nil }
        return L10n.text("Also tonight: ") + picks.map { L10n.format("\($0.kind == .meteorShower ? $0.title + L10n.text(" at peak") : $0.title) at \(hhmm($0.when, site: site))") }
            .joined(separator: ", ") + "."
    }

    public static func headsUpPlan(_ s: SessionPlan, plan: NightPlan, site: Site) -> String? {
        guard let first = s.items.first else { return nil }
        func name(_ t: RankedTarget) -> String { t.commonName.map { L10n.format("the \($0)") } ?? t.catalogueID }
        var text = L10n.text("Your plan: ") + s.items.prefix(2).map { L10n.format("\(name($0.target)), best at \(hhmm($0.target.peakTime, site: site))") }
            .joined(separator: L10n.text(", then ")) + "."
        let from = (first.target.viewable?.start ?? s.window.start).addingTimeInterval(-1800)
        let dew = plan.darkHours.first { h in
            guard h.time >= from, h.time < s.window.end, let t = h.tempC, let d = h.dewPointC else { return false }
            return t - d < 2
        }
        if let d = dew { text += L10n.format(" Fit the dew heater: dew likely after \(hhmm(max(d.time, s.window.start), site: site)).") }
        return text
    }

    /// The Targets header's Moon line (#62): "Next moonless run: Thu 8 – Mon 19 Oct · new Moon Sun 11 Oct", or during a run
    /// "Moonless tonight, and until Mon 19 Oct." ("Moonless tonight." when tonight is the last).
    public static func moonlessRun(_ r: MoonlessRun, site: Site) -> String {
        let last = dayMonth(r.last.localDate, site: site)
        if r.includesTonight {
            return r.last.key == r.first.key ? L10n.text("Moonless tonight.") : L10n.format("Moonless tonight, and until \(last).")
        }
        var first = dayMonth(r.first.localDate, site: site)
        if r.first.key == r.last.key { first = last }
        else if L10n.language == .english, first.suffix(3) == last.suffix(3) { first = String(first.dropLast(4)) }   // "Thu 8 – Mon 19 Oct": one month named once
        let range = r.first.key == r.last.key ? first : "\(first) – \(last)"
        return L10n.format("Next moonless run: \(range)") + (r.newMoon.map { L10n.format(" · new Moon \(dayMonth($0, site: site))") } ?? "")
    }

    /// "Your first clear window with Nightwatch: 21:10–01:40." Said once, ever (#64, owner-approved mock-up).
    public static func firstClear(_ w: ClearWindow, site: Site) -> String {
        L10n.format("Your first clear window with Nightwatch: \(span(w.start, w.end, site: site)).")
    }

    // Siri and Spotlight (#53). Spoken answers from the cached forecast, naming its source as the widget does.
    static func siriSource(_ s: WidgetSnapshot) -> String? { s.source.map { L10n.format("Forecast from \($0).") } }

    /// A clause as a sentence: its own full stop, never two.
    static func sentence(_ s: String) -> String { s.hasSuffix(".") ? s : s + "." }

    /// "Sky Score": "Sky score 72 at Home. Clear window tonight. 20:40–03:10 · 6.5 h. Held back by a 40% moon. Forecast
    /// from Apple Weather." On a night without a window the reason and "Tomorrow 21:10–01:40." follow instead.
    public static func siriTonight(_ s: WidgetSnapshot?) -> String {
        guard let s else { return L10n.text("Nightwatch has no forecast yet. Open it once to set where you observe.") }
        return ([L10n.format("Sky score \(s.score) at \(s.siteName)"), s.headline, s.window, s.reason, s.tomorrow].compactMap { $0 }.map(sentence)
                + [siriSource(s)].compactMap { $0 }).joined(separator: " ")
    }

    /// "Best Targets Tonight": Tonight's plan when there is one, else the popover's best three ("M31, best 00:40 · 64° up").
    public static func siriBest(_ s: WidgetSnapshot?, session: SessionPlan?, site: Site?) -> String {
        guard let s else { return siriTonight(nil) }
        if let session, let site, !session.items.isEmpty {
            let list = session.items.map { L10n.format("\($0.target.commonName ?? $0.target.catalogueID) at \(hhmm($0.target.peakTime, site: site))") }
            return L10n.text("Tonight's plan: ") + list.joined(separator: L10n.text(", then ")) + "."
        }
        // On a cloudy night with a clear one tomorrow, say so, as the Targets window does (owner's UAT, 29 September 2026).
        guard !s.targets.isEmpty else {
            let tomorrow = s.tomorrow.map { L10n.format("Tomorrow night looks clear \($0.replacingOccurrences(of: L10n.text("Tomorrow "), with: "")).") }
            return ([sentence(s.headline), L10n.text("No targets are suggested tonight.")] + [tomorrow].compactMap { $0 }).joined(separator: " ")
        }
        // `best` already reads "Best 00:40 · 64° up"; lower-cased after the name.
        return L10n.text("Tonight's best targets: ") + s.targets.map { "\($0.name), \($0.best.prefix(1).lowercased() + $0.best.dropFirst())" }
            .joined(separator: "; ") + "."
    }

    /// "Events Tonight": up to three, with whether it will be clear then.
    public static func siriEvents(_ events: [SkyEvent]) -> String {
        guard !events.isEmpty else { return L10n.text("No events tonight.") }
        return events.prefix(3).map { e in
            [e.title + ".", e.clear.map { $0 ? L10n.text("Clear then.") : L10n.text("Cloudy then.") }].compactMap { $0 }.joined(separator: " ")
        }.joined(separator: " ")
    }

    public func scoreBand(_ score: Int) -> String {
        switch score { case 80...: L10n.text("Excellent"); case 50..<80: L10n.text("Fair"); case 20..<50: L10n.text("Poor"); default: L10n.text("Overcast") }
    }
}
