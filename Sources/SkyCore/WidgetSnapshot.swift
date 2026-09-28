import Foundation

/// One of the widget's best-tonight rows.
public struct WidgetTarget: Codable, Equatable, Sendable {
    public var id: String
    public var catalogueID: String
    public var name: String
    public var best: String
    public var group: TargetGroup
    public init(id: String, catalogueID: String, name: String, best: String, group: TargetGroup) {
        self.id = id; self.catalogueID = catalogueID; self.name = name; self.best = best; self.group = group
    }
}

/// Everything the desktop widget draws, as plain values (v0.6). The app writes it after each patrol; the widget only reads
/// it, so the widget can never disagree with the popover. Nothing here is new wording except `staleText`.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public var siteName: String
    public var fetchedAt: Date
    public var score: Int
    public var mode: PlanMode
    public var headline: String
    public var window: String?
    public var windowShort: String?
    public var reason: String?
    public var agreement: String?
    public var agreementWarns: Bool
    public var slots: [BezelSlot]
    public var bezelLabel: String
    public var bars: [ClearSkyBar]
    public var barsLabel: String
    public var targets: [WidgetTarget]
    public var tomorrow: String?
    /// The small widget's second line: "notify 20:30" on a clear night, "Moon 62%, Saturn" on a bright one (the canvas).
    public var notifyShort: String?
    public var brightList: String?
    /// Which service supplied the cloud hours ("Apple Weather" or "Open-Meteo"), for the large widget's footer.
    public var source: String?
    /// "Updated 21:10" in the site's time zone and 24-hour form, as the popover shows it.
    public var updated: String?
    /// Apple Weather's attribution (v1.0.1): the Weather mark, saved by the app into the App Group as this file (a widget
    /// cannot fetch it), and the legal page of other data sources. Nil unless Apple Weather supplied the forecast.
    public var weatherMarkFile: String? = nil
    public var weatherLegalURL: String? = nil
    /// AuroraWatch UK's level when aurora alerts are on and it is at or above the chosen level (v0.6.6); shown for an hour
    /// from `aurora.updated`, the popover's rule.
    public var aurora: AuroraStatus?

    public static func make(plan: NightPlan, tomorrow: NightPlan?, fetchedAt: Date, site: Site, rule: GoRule,
                            bright: BrightSettings, alerts: AlertSettings, copy: Copy, source: String? = nil,
                            aurora: AuroraStatus? = nil, auroraSettings: AuroraSettings? = nil) -> WidgetSnapshot {
        func hm(_ d: Date) -> String { Copy.hhmm(d, site: site) }
        let w = plan.primary
        let noDarkness = w == nil && !plan.night.hasDarkness && (plan.mode == .dark || !plan.night.hasNauticalDarkness)
        let headline = w != nil ? (plan.mode == .bright ? "Bright night: Moon and planets" : "Clear window tonight")
                                : (noDarkness ? "No astronomical darkness" : copy.noWindow)
        let reason: String? = w != nil ? Copy.heldBack(plan.limiting)
            : (noDarkness ? "Too far north or south for this date." : Planner.noWindowReasonText(plan: plan, rule: rule, bright: bright, site: site))
        let picks = plan.mode == .bright ? plan.brightTargets : plan.best
        return WidgetSnapshot(
            siteName: site.name, fetchedAt: fetchedAt, score: plan.score, mode: plan.mode, headline: headline,
            window: w.map { "\(hm($0.start))–\(hm($0.end)) · \(String(format: "%.1f h", $0.hours))" },
            windowShort: w.map { (plan.mode == .bright ? "Bright " : "Clear ") + "\(hm($0.start))–\(hm($0.end))" },
            reason: reason,
            agreement: Copy.advice(plan, site: site, alerts: alerts)?.line ?? plan.agreement.map { Copy.agreementText($0, site: site) },
            agreementWarns: plan.agreement.map(Copy.agreementWarns) ?? false,
            slots: Bezel.slots(darkness: plan.darkSpan, windows: plan.windows, primary: plan.primary, hours: plan.darkHours, site: site),
            bezelLabel: Copy.bezelLabel(plan, site: site),
            bars: Planner.clearSkyBars(plan: plan, site: site), barsLabel: Copy.barsLabel(plan: plan, site: site),
            targets: picks.prefix(3).map { t in
                WidgetTarget(id: t.id, catalogueID: t.catalogueID, name: t.commonName ?? t.typeName,
                             best: "Best \(hm(t.peakTime)) · \(Int(t.peakAltDeg.rounded()))° up", group: t.group)
            },
            tomorrow: w == nil && !noDarkness ? tomorrow?.primary.map { "Tomorrow \(hm($0.start))–\(hm($0.end))" } : nil,
            notifyShort: Copy.notifyTime(plan, site: site, settings: alerts).map { "notify \($0)" },
            brightList: plan.mode == .bright && !plan.brightTargets.isEmpty ? Copy.brightList(plan.brightTargets) : nil,
            source: source, updated: "Updated \(hm(fetchedAt))",
            aurora: aurora.flatMap { a in auroraSettings?.shows(a) == true ? a : nil })
    }

    /// "Aurora amber" in AuroraWatch UK's colour, or nil when there is none or it is over an hour old at `now`.
    public func auroraLine(now: Date) -> (text: String, hex: UInt32)? {
        guard let a = aurora, let end = auroraExpires, now < end else { return nil }
        return ("Aurora \(a.level.rawValue)", a.level.hex)
    }
    /// When the aurora line stops showing, so the widget can redraw then.
    public var auroraExpires: Date? { aurora.map { $0.updated.addingTimeInterval(AuroraSettings.freshFor) } }

    /// The gallery's preview: a made-up clear night at a made-up site, so the widget picker shows the real layout.
    public static let sample = WidgetSnapshot(
        siteName: "Dark Site", fetchedAt: Date(), score: 78, mode: .dark, headline: "Clear window tonight",
        window: "21:10–01:40 · 4.5 h", windowShort: "Clear 21:10–01:40", reason: "Held back by a 40% moon",
        agreement: "Open-Meteo agrees", agreementWarns: false,
        slots: Array(repeating: .cloudy, count: 10) + Array(repeating: .clear, count: 27) + Array(repeating: .partCloud, count: 11) + Array(repeating: .daylight, count: 12),
        bezelLabel: "Sky score 78", bars: [20, 35, 80, 92, 88, 76, 40, 25].enumerated().map { i, c in
            ClearSkyBar(hour: String(format: "%02d", (20 + i) % 24), clearPct: c, lit: (2...5).contains(i), peak: i == 3)
        }, barsLabel: "Clear sky by hour.",
        targets: [WidgetTarget(id: "M13", catalogueID: "M13", name: "Hercules Cluster", best: "Best 21:30 · 71° up", group: .clusters),
                  WidgetTarget(id: "M31", catalogueID: "M31", name: "Andromeda Galaxy", best: "Best 00:40 · 64° up", group: .galaxies)],
        tomorrow: nil, notifyShort: "notify 20:40", brightList: nil, source: "Open-Meteo", updated: "Updated 18:05", aurora: nil)

    /// "Forecast 7 h old" once the snapshot's forecast is more than six hours old at `now` (the alerts' stale rule); else nil.
    public func staleText(now: Date) -> String? {
        let age = now.timeIntervalSince(fetchedAt)
        return age > 6 * 3600 ? "Forecast \(Int(age / 3600)) h old" : nil
    }
}
