import Foundation

/// One column of the clear-sky bars: an hour of the plan's darkness (v0.6: data, so the widget can draw it without a plan).
public struct ClearSkyBar: Codable, Equatable, Sendable {
    public var hour: String       // local "HH"
    public var clearPct: Int      // 100 − cloud, clamped to 0…100
    public var lit: Bool          // the hour overlaps a clear window
    public var peak: Bool         // the first of the clearest hours, when it is above 0 % clear
    public init(hour: String, clearPct: Int, lit: Bool, peak: Bool) { self.hour = hour; self.clearPct = clearPct; self.lit = lit; self.peak = peak }
}

extension Planner {
    public static func clearSkyBars(plan: NightPlan, site: Site) -> [ClearSkyBar] {
        let peak = plan.darkHours.min { $0.effectiveCloud < $1.effectiveCloud }
        return plan.darkHours.map { h in
            ClearSkyBar(hour: String(Copy.hhmm(h.time, site: site).prefix(2)), clearPct: max(0, min(100, 100 - h.effectiveCloud)),
                        lit: plan.windows.contains { $0.overlapsHour(startingAt: h.time) },
                        peak: h.time == peak?.time && h.effectiveCloud < 100)
        }
    }

    /// The plain reason under the no-window verdict: astronomical darkness and the go rule on a dark night, nautical darkness
    /// and the bright rule on a bright one. Shared by the popover and the widget.
    public static func noWindowReasonText(plan: NightPlan, rule: GoRule, bright: BrightSettings, site: Site) -> String? {
        if plan.mode == .bright {
            guard let ns = plan.night.nauticalStart, let ne = plan.night.nauticalEnd else { return nil }
            return noWindowReason(darkHours: plan.darkHours, darkStart: ns, darkEnd: ne,
                                  rule: GoRule(minHours: bright.minHours, maxCloudPct: rule.maxCloudPct, minAltitudeDeg: rule.minAltitudeDeg),
                                  site: site, mode: .bright, brightTargetsUp: anyBrightTargetUp(from: ns, to: ne, site: site))
        }
        guard let ds = plan.night.darkStart, let de = plan.night.darkEnd else { return nil }
        return noWindowReason(darkHours: plan.darkHours, darkStart: ds, darkEnd: de, rule: rule, site: site)
    }
}

extension Copy {
    /// The bars' screen-reader sentence.
    public static func barsLabel(plan: NightPlan, site: Site) -> String {
        var s = L10n.text("Clear sky by hour.")
        if let p = plan.darkHours.min(by: { $0.effectiveCloud < $1.effectiveCloud }) { s += L10n.format(" Clearest \(hhmm(p.time, site: site)) at \(max(0, 100 - p.effectiveCloud))% clear.") }
        if let w = plan.primary { s += L10n.format(" Clear window \(hhmm(w.start, site: site)) to \(hhmm(w.end, site: site)).") }
        return s
    }
}
