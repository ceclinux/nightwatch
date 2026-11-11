import Foundation
import SkyCore

/// The six tiles under tonight's verdict, worked out the way the Mac's popover does it (same SkyCore helpers), as text
/// ready to draw. Nil: nothing to say (no seeing data, say), and the tile shows a dash.
public struct TonightTiles: Equatable, Sendable {
    public var dark: String
    public var moon: String
    public var moonLine: String?
    public var seeing: String?
    public var wind: String?
    /// "Frost likely" when the night drops to 0 °C, else "Dew risk".
    public var dewLabel: String
    public var dew: String?
    public var dewHint: String?
    public var transparency: String?
    /// The time whose NASA Moon picture the tile shows: the middle of the darkness (else now).
    public var moonAt: Date?

    public static func make(plan: NightPlan, site: Site) -> TonightTiles {
        var t = makeRaw(plan: plan, site: site)
        t.dark = t.dark.plainDashes; t.moon = t.moon.plainDashes; t.moonLine = t.moonLine?.plainDashes
        t.seeing = t.seeing?.plainDashes; t.wind = t.wind?.plainDashes; t.dew = t.dew?.plainDashes
        t.dewHint = t.dewHint?.plainDashes; t.transparency = t.transparency?.plainDashes
        return t
    }

    static func makeRaw(plan: NightPlan, site: Site) -> TonightTiles {
        let dark = plan.darkSpan.map { "\(Copy.hhmm($0.start, site: site))-\(Copy.hhmm($0.end, site: site))" } ?? "None"
        let moon = Planner.moonTonight(plan)
        let pct = "\(Int((plan.moonIllumination * 100).rounded()))%"
        let winds = plan.darkHours.compactMap(\.windKmh)
        let dew = Planner.dewRisk(plan.darkHours)
        let frost = plan.darkHours.compactMap(\.tempC).min().map { $0 <= 0 } ?? false
        return TonightTiles(
            dark: dark,
            moon: moon == .down ? "Down" : pct,
            moonLine: moon.flatMap { $0 == .down ? "tonight" : Copy.moonText($0, site: site) },
            seeing: Copy.seeingText(plan.darkHours),
            wind: winds.isEmpty ? nil : String(format: "%.0f km/h", winds.reduce(0, +) / Double(winds.count)),
            dewLabel: frost ? "Frost likely" : "Dew risk",
            dew: dew?.displayName,
            dewHint: dew == .high ? "Dew heater advised" : nil,
            transparency: Copy.transparencyText(plan.darkHours),
            moonAt: plan.darkSpan.map { Date(timeIntervalSince1970: ($0.start.timeIntervalSince1970 + $0.end.timeIntervalSince1970) / 2) })
    }
}

/// How old a forecast is, in words: "just now", "12 min ago", "3 hours ago". The page shows it so a stale answer is never
/// mistaken for a fresh one (offline in a dead zone, or a refresh that failed).
public struct ForecastAge: Equatable, Sendable {
    public let seconds: TimeInterval

    public init(fetchedAt: Date, now: Date) { seconds = max(0, now.timeIntervalSince(fetchedAt)) }

    public var text: String {
        let m = Int(seconds / 60)
        if m < 2 { return "just now" }
        if m < 60 { return "\(m) min ago" }
        let h = m / 60
        if h < 48 { return h == 1 ? "1 hour ago" : "\(h) hours ago" }
        let d = h / 24
        return "\(d) days ago"
    }

    public func isOlder(than interval: TimeInterval) -> Bool { seconds > interval }
}

/// Everything the Tonight page draws, built once per refresh from the plan SkyCore works out. The verdict, bezel, bars,
/// best three and the source line are SkyCore's own `WidgetSnapshot` (the Mac's widget draws from the same type), so the
/// wording is the Mac's wording.
public struct TonightModel: Equatable, Sendable {
    public var snapshot: WidgetSnapshot
    public var tiles: TonightTiles
    /// "Apple Weather" or "Open-Meteo": which service drove the verdict.
    public var source: String
    /// Apple's mark and legal page, supplied only when Apple Weather answered: the footer shows the mark, and the mark is the link.
    public var markURL: String?
    public var legalURL: String?
    public var fetchedAt: Date
    /// "TONIGHT · MALHAM TARN" and "Tue 13 Oct · Bortle 3": the header the Mac's popover has.
    public var overline: String
    public var dateLine: String
    /// "BEST TONIGHT" (or "UP TONIGHT" when nothing is recommended), the picks, and a note when there are none.
    public var picksHeading: String
    public var picks: [TargetPick]
    public var picksNote: String?
    /// The best-placed constellation tonight, for the faint figure behind the verdict on a night with no clear window.
    public var figureID: String?
    /// The site's time zone, so the page can mark the current hour on the night's arc.
    public var timeZoneID: String

    public var siteName: String { snapshot.siteName }

    public static func make(plan: NightPlan, tomorrow: NightPlan?, forecast: Forecast, site: Site, config: Config,
                            aurora: AuroraStatus? = nil, copy: Copy = Copy()) -> TonightModel {
        let source = forecast.cloudSource ?? "Open-Meteo"
        var snap = WidgetSnapshot.make(plan: plan, tomorrow: tomorrow, fetchedAt: forecast.fetchedAt, site: site, rule: config.goRule,
                                       bright: config.brightNights, alerts: config.alerts, copy: copy, source: source,
                                       aurora: aurora, auroraSettings: config.aurora)
        snap.weatherLegalURL = forecast.attributionLegalURL
        snap.headline = snap.headline.plainDashes; snap.window = snap.window?.plainDashes; snap.windowShort = snap.windowShort?.plainDashes
        snap.reason = snap.reason?.plainDashes; snap.agreement = snap.agreement?.plainDashes; snap.bezelLabel = snap.bezelLabel.plainDashes
        snap.barsLabel = snap.barsLabel.plainDashes; snap.tomorrow = snap.tomorrow?.plainDashes; snap.notifyShort = snap.notifyShort?.plainDashes
        snap.updated = snap.updated?.plainDashes
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_GB"); day.timeZone = TimeZone(identifier: site.timeZoneID) ?? .current
        day.dateFormat = "EEE d MMM"
        let when = plan.darkSpan?.start ?? forecast.fetchedAt
        // Deep-sky picks on a dark night; the Moon and planets on a bright one, as the Mac's popover does.
        let chosen = plan.mode == .bright ? plan.brightTargets : plan.best
        let note: String? = plan.mode == .bright && plan.brightTargets.isEmpty ? "No Moon or planet in a clear window tonight."
            : plan.mode == .dark && plan.best.isEmpty ? "\(plan.targets.count) objects above the horizon during darkness. No clear window, so nothing is recommended." : nil
        return TonightModel(snapshot: snap, tiles: TonightTiles.make(plan: plan, site: site), source: source,
                            markURL: forecast.attributionMarkURL, legalURL: forecast.attributionLegalURL, fetchedAt: forecast.fetchedAt,
                            overline: "TONIGHT · \(site.name.uppercased())", dateLine: Copy.nightLine(dayText: day.string(from: when), site: site, bright: plan.mode == .bright),
                            picksHeading: chosen.isEmpty ? "UP TONIGHT" : "BEST TONIGHT",
                            picks: chosen.map { TargetPick.make($0, site: site, fov: config.fov) }, picksNote: note?.plainDashes,
                            figureID: plan.targets.first { $0.group == .constellations }?.id, timeZoneID: site.timeZoneID)
    }
}
