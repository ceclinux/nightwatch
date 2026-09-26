import Foundation

public struct GoRule: Codable, Equatable, Sendable {
    public var minHours: Double
    public var maxCloudPct: Int
    public var minAltitudeDeg: Double
    public init(minHours: Double = 3, maxCloudPct: Int = 25, minAltitudeDeg: Double = 30) {
        self.minHours = minHours; self.maxCloudPct = maxCloudPct; self.minAltitudeDeg = minAltitudeDeg
    }
}

public struct ClearWindow: Codable, Equatable, Sendable {
    public var start: Date
    public var end: Date
    public init(start: Date, end: Date) { self.start = start; self.end = end }
    public var hours: Double { end.timeIntervalSince(start) / 3600 }
    public var midpoint: Date { start.addingTimeInterval(end.timeIntervalSince(start) / 2) }
    /// True when any part of the hour from `t` falls inside the window. Windows are clipped to darkness, so a clear hour
    /// that starts before darkness is still part of the window.
    public func overlapsHour(startingAt t: Date) -> Bool { start < t.addingTimeInterval(3600) && t < end }
}

public struct ScoreInputs {
    public var darkHours: [HourlyConditions]
    public var windows: [ClearWindow]
    public var darkness: (Date, Date)?
    public var moonIllumination: Double
    public var moonAboveFraction: Double
    public var maxCloudPct: Int
    public init(darkHours: [HourlyConditions], windows: [ClearWindow], darkness: (Date, Date)?, moonIllumination: Double, moonAboveFraction: Double, maxCloudPct: Int = 25) {
        self.darkHours = darkHours; self.windows = windows; self.darkness = darkness
        self.moonIllumination = moonIllumination; self.moonAboveFraction = moonAboveFraction
        self.maxCloudPct = maxCloudPct
    }
}

public enum DewRisk: String, Codable, Sendable {
    case low, medium, high
    public var displayName: String { rawValue.capitalized }
}

public enum LimitingKind: String, Codable, Sendable { case cloud, moon, seeing, transparency, wind, dew }

/// One score term that lost more than a third of its weight, in words for the reason line.
public struct LimitingFactor: Codable, Equatable, Sendable {
    public let kind: LimitingKind
    public let text: String
    public let pointsLost: Double
}

/// The score's terms, shared by `score` and `limitingFactors` so the reason line always explains the number shown.
struct ScoreTerms {
    var cloud: Double, cloudWeight: Double
    var moon: Double
    var seeing: Double?, transparency: Double?        // points earned of 7.5 each; nil without 7Timer data
    var windPenalty: Double, avgWind: Double?
    var dewPenalty: Double, dew: DewRisk?
}

public enum Planner {
    /// Hourly samples that overlap the night's darkness. A sample at time t covers [t, t + 1 h).
    public static func darkHours(_ hours: [HourlyConditions], night: Night) -> [HourlyConditions] {
        guard let ds = night.darkStart, let de = night.darkEnd else { return [] }
        return hours.filter { $0.time.addingTimeInterval(3600) > ds && $0.time < de }.sorted { $0.time < $1.time }
    }

    /// Maximal runs of consecutive hourly samples inside darkness with cloud at or under the rule, at least `minHours` long.
    public static func windows(hours: [HourlyConditions], darkStart: Date, darkEnd: Date, rule: GoRule) -> [ClearWindow] {
        let dark = hours.filter { $0.time.addingTimeInterval(3600) > darkStart && $0.time < darkEnd }.sorted { $0.time < $1.time }
        var out: [ClearWindow] = []
        var run: [HourlyConditions] = []
        func flush() {
            guard let f = run.first, let l = run.last else { return }
            let w = ClearWindow(start: max(f.time, darkStart), end: min(l.time.addingTimeInterval(3600), darkEnd))
            if w.hours >= rule.minHours { out.append(w) }
            run = []
        }
        for h in dark {
            let clear = h.cloudTotal <= rule.maxCloudPct
            let contiguous = run.last.map { h.time.timeIntervalSince($0.time) == 3600 } ?? true
            if clear && contiguous { run.append(h) } else { flush(); if clear { run = [h] } }
        }
        flush()
        return out
    }

    /// Smallest temperature minus dew point over the hours: under 2 °C High, under 4 °C Medium, else Low; nil with no data.
    public static func dewRisk(_ hours: [HourlyConditions]) -> DewRisk? {
        let spreads = hours.compactMap { h -> Double? in guard let t = h.tempC, let d = h.dewPointC else { return nil }; return t - d }
        guard let m = spreads.min() else { return nil }
        return m < 2 ? .high : (m < 4 ? .medium : .low)
    }

    static func terms(_ s: ScoreInputs) -> ScoreTerms? {
        guard let (ds, de) = s.darkness, de > ds, !s.darkHours.isEmpty else { return nil }
        let clearHours = Double(s.darkHours.filter { $0.cloudTotal <= s.maxCloudPct }.count)
        let clearFraction = min(1, clearHours / Double(s.darkHours.count))
        let primaryHours = s.windows.map(\.hours).max() ?? 0
        let contiguity = clearHours > 0 ? min(1, primaryHours / clearHours) : 0
        let seeingSamples = s.darkHours.compactMap(\.seeing)
        let transSamples = s.darkHours.compactMap(\.transparency)
        let hasSeeing = !seeingSamples.isEmpty && !transSamples.isEmpty
        let cloudWeight = hasSeeing ? 60.0 : 75.0
        var seeing: Double?, transparency: Double?
        if hasSeeing {
            let avgS = Double(seeingSamples.reduce(0, +)) / Double(seeingSamples.count)
            let avgT = Double(transSamples.reduce(0, +)) / Double(transSamples.count)
            seeing = 7.5 * (1 - (avgS - 1) / 7); transparency = 7.5 * (1 - (avgT - 1) / 7)
        }
        let winds = s.darkHours.compactMap(\.windKmh)
        let avgWind = winds.isEmpty ? nil : winds.reduce(0, +) / Double(winds.count)
        let dew = dewRisk(s.darkHours)
        return ScoreTerms(cloud: cloudWeight * clearFraction * (0.5 + 0.5 * contiguity), cloudWeight: cloudWeight,
                          moon: 15 * (1 - s.moonIllumination * s.moonAboveFraction),
                          seeing: seeing, transparency: transparency,
                          windPenalty: min(1, max(0, ((avgWind ?? 0) - 10) / 30)) * 5, avgWind: avgWind,   // none under 10 km/h, full at 40
                          dewPenalty: dew == .high ? 5 : (dew == .medium ? 2.5 : 0), dew: dew)
    }

    /// 0–100. Cloud 60 (75 without seeing data), Moon 15, seeing + transparency 15, wind and dew 10.
    public static func score(_ s: ScoreInputs) -> Int {
        guard let t = terms(s) else { return 0 }
        let total = t.cloud + t.moon + ((t.seeing ?? 0) + (t.transparency ?? 0)) + (10 - t.windPenalty - t.dewPenalty)   // summed in the 0.3.1 order
        return max(0, min(100, Int(total.rounded())))
    }

    /// Each term that lost more than a third of its weight, most points lost first. On a bright plan the Moon term is
    /// never lost (the plan passes moonIllumination 0), so the Moon is never blamed.
    public static func limitingFactors(_ s: ScoreInputs) -> [LimitingFactor] {
        guard let t = terms(s) else { return [] }
        var out: [LimitingFactor] = []
        func add(_ k: LimitingKind, _ text: String, lost: Double, of weight: Double) {
            if lost > weight / 3 { out.append(LimitingFactor(kind: k, text: text, pointsLost: lost)) }
        }
        add(.cloud, "patchy cloud", lost: t.cloudWeight - t.cloud, of: t.cloudWeight)
        add(.moon, "a \(Int((s.moonIllumination * 100).rounded()))% moon", lost: 15 - t.moon, of: 15)
        if let v = t.seeing { add(.seeing, "poor seeing", lost: 7.5 - v, of: 7.5) }
        if let v = t.transparency { add(.transparency, "poor transparency", lost: 7.5 - v, of: 7.5) }
        if let w = t.avgWind { add(.wind, String(format: "wind at %.0f km/h", w), lost: t.windPenalty, of: 5) }
        if let d = t.dew { add(.dew, "\(d == .high ? "high" : "medium") dew risk", lost: t.dewPenalty, of: 5) }
        return out.sorted { $0.pointsLost > $1.pointsLost }
    }
}

public struct FieldOfView: Codable, Equatable, Sendable {
    public var widthDeg: Double
    public var heightDeg: Double
    public init(widthDeg: Double, heightDeg: Double) { self.widthDeg = widthDeg; self.heightDeg = heightDeg }
}

public enum FrameFit: String, Codable, Sendable { case fits, small, mosaic }

public struct RankedTarget: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let subtitle: String
    public let group: TargetGroup
    public let raHours: Double
    public let decDeg: Double
    public let sizeArcmin: Double?
    public let magnitude: Double?
    public let fit: FrameFit
    public let peakAltDeg: Double
    public let peakTime: Date
    public let moonSepDeg: Double
    public let moonWashed: Bool
    public let visibleFraction: Double
    /// The part of the ranking window with the target at or above the minimum altitude (30-minute resolution).
    public var viewable: ClearWindow? = nil
    /// Nine evenly spaced altitudes across `viewable`, first at its start and last at its end.
    public var altitudeSamples: [Double] = []
    /// Size over the field of view's longer side, capped at 1; nil when the size is unknown.
    public var frameFill: Double? = nil
    /// "Emission nebula", "Planet", "Constellation".
    public var typeName: String = ""
    /// "NGC 7000", "M42", "Jupiter", "Moon", "Cygnus".
    public var catalogueID: String = ""
    public var commonName: String? = nil
    /// The Caldwell number, for the card line and search; the catalogue ID stays the NGC or IC number.
    public var caldwell: Int? = nil

    /// The card's line under the catalogue ID: "C43 · Galaxy", "C20 · North America Nebula", "Andromeda Galaxy".
    public var cardLine: String {
        [caldwell.map { "C\($0)" }, commonName ?? typeName].compactMap { $0 }.joined(separator: " · ")
    }

    /// The Targets search, ignoring case. A catalogue number ("C43", "C 43", "NGC7814", "m 31") must begin one of the name's
    /// " · " parts once spaces are removed, so "C43" does not find NGC 4303; a bare number ("7814") must begin one part's
    /// digits. Anything else ("veil", "north america", "Peg") is found anywhere in the name or subtitle. Empty matches all.
    public func matches(_ query: String) -> Bool {
        let q = query.filter { !$0.isWhitespace }.lowercased()
        guard !q.isEmpty else { return true }
        let letters = q.prefix { $0.isLetter }, number = q.dropFirst(letters.count)
        guard let first = number.first, first.isNumber else {
            return [name, subtitle].contains { $0.localizedCaseInsensitiveContains(query.trimmingCharacters(in: .whitespaces)) }
        }
        let parts = name.components(separatedBy: " · ").map { $0.filter { !$0.isWhitespace }.lowercased() }
        if letters.isEmpty { return parts.contains { $0.drop { $0.isLetter }.hasPrefix(q) } }
        return parts.contains { $0.hasPrefix(q) }
    }

    /// Hidden while Include Moon-washed is off. Shared by the Targets grid and its search hint so the two cannot disagree.
    public func hiddenByMoon(includeMoonWashed: Bool) -> Bool { moonWashed && !includeMoonWashed }
    /// Hidden while Fits my field of view is on.
    public func hiddenByFit(fitsOnly: Bool) -> Bool { fitsOnly && fit != .fits }
}

/// `.bright` when the dark rule could not be met and bright-night mode supplied the plan instead.
public enum PlanMode: String, Codable, Sendable { case dark, bright }

public struct NightPlan: Codable, Equatable, Sendable {
    public let night: Night
    public let windows: [ClearWindow]
    public let primary: ClearWindow?
    public let score: Int
    public let qualifies: Bool
    public let moonIllumination: Double
    public let moonRise: Date?
    public let moonSet: Date?
    public let darkHours: [HourlyConditions]
    public let targets: [RankedTarget]
    public let best: [RankedTarget]
    public let seeingAvailable: Bool
    public var mode: PlanMode = .dark
    /// Moon and planets up during the primary window on a bright night; empty in dark mode.
    public var brightTargets: [RankedTarget] = []
    /// The score terms that held tonight back, biggest loss first; empty without a clear window.
    public var limiting: [LimitingFactor] = []
    /// The share of hourly samples in the plan's darkness with the Moon up; nil when there is no darkness.
    public var moonUpFraction: Double? = nil
    /// Open-Meteo's view of tonight under the same rule (v0.5); nil without a second opinion.
    public var agreement: Agreement? = nil
}

extension Planner {
    public static func frameFit(sizeArcmin: Double?, fov: FieldOfView) -> FrameFit {
        guard let s = sizeArcmin, s >= 5 else { return .small }
        let deg = s / 60
        if deg <= max(fov.widthDeg, fov.heightDeg) { return .fits }
        return .mosaic
    }

    /// Sample a window every 30 minutes: the fraction of samples at or above `minAlt`, the peak and its time, and the viewable
    /// span from the first sample above to the last, run on to the window's end when the last sample is above.
    /// ponytail: 30-minute resolution at the span's interior edges; sample finer if the timeline ever looks coarse.
    static func track(raHours: Double, decDeg: Double, window: ClearWindow, site: Site, minAlt: Double) -> (fraction: Double, peakAlt: Double, peakTime: Date, viewable: ClearWindow?) {
        var t = window.start
        var above = 0, n = 0
        var peak = -90.0, peakTime = window.start
        var first: Date?, last: Date?, lastSample = window.start
        while t <= window.end {
            let alt = Ephemeris.altAz(raHours: raHours, decDeg: decDeg, at: t, site: site).alt
            n += 1
            if alt >= minAlt { above += 1; if first == nil { first = t }; last = t }
            if alt > peak { peak = alt; peakTime = t }
            lastSample = t
            t = t.addingTimeInterval(1800)
        }
        let viewable = first.map { ClearWindow(start: $0, end: last! == lastSample ? window.end : last!) }
        return (n == 0 ? 0 : Double(above) / Double(n), peak, peakTime, viewable)
    }

    /// `count` evenly spaced altitudes across `span`.
    static func altitudes(raHours: Double, decDeg: Double, span: ClearWindow, site: Site, count: Int = 9) -> [Double] {
        let len = span.end.timeIntervalSince(span.start)
        return (0..<count).map { k in
            Ephemeris.altAz(raHours: raHours, decDeg: decDeg, at: span.start.addingTimeInterval(len * Double(k) / Double(count - 1)), site: site).alt
        }
    }

    /// Gradient brightness 0…1 per altitude sample (handover: u = (alt − 30)/(alt_peak − 30), clamped). When the peak
    /// is under 40° the floor is 10° below the peak, so low targets still grade and nothing divides by zero.
    public static func timelineStops(_ samples: [Double]) -> [Double] {
        guard let peak = samples.max() else { return [] }
        let floor = min(30, peak - 10)
        return samples.map { min(1, max(0, ($0 - floor) / (peak - floor))) }
    }

    public static func frameFill(sizeArcmin: Double?, fov: FieldOfView) -> Double? {
        guard let s = sizeArcmin else { return nil }
        return min(1, s / 60 / max(fov.widthDeg, fov.heightDeg))
    }

    /// The target with its viewable span, altitude curve and names filled in.
    static func described(_ r: RankedTarget, viewable: ClearWindow?, site: Site, typeName: String, catalogueID: String,
                          commonName: String? = nil, frameFill: Double? = nil, caldwell: Int? = nil) -> RankedTarget {
        var r = r
        r.caldwell = caldwell
        r.viewable = viewable
        r.altitudeSamples = viewable.map { altitudes(raHours: r.raHours, decDeg: r.decDeg, span: $0, site: site) } ?? []
        r.typeName = typeName; r.catalogueID = catalogueID; r.commonName = commonName; r.frameFill = frameFill
        return r
    }

    public static func rank(catalog: Catalog, constellations: [Constellation], window: ClearWindow, site: Site, fov: FieldOfView, rule: GoRule) -> [RankedTarget] {
        let moon = Ephemeris.moon(at: window.midpoint, site: site)
        let moonUp = moon.position.altDeg > 0 && moon.illumination > 0.1
        var out: [RankedTarget] = []

        for o in catalog.objects {
            // OpenNGC has no magnitude for many large nebulae and cluster-plus-nebula regions (IC1396): keep those.
            // A galaxy or plain cluster with no magnitude is almost always faint, so those still need one.
            if let m = o.magnitude { if m > 12 { continue } } else if o.group != .nebulae, o.typeCode != "Cl+N" { continue }
            let tr = track(raHours: o.raHours, decDeg: o.decDeg, window: window, site: site, minAlt: rule.minAltitudeDeg)
            guard tr.fraction >= 0.5 else { continue }
            let sep = Ephemeris.separationDeg(ra1Hours: o.raHours, dec1Deg: o.decDeg, ra2Hours: moon.position.raHours, dec2Deg: moon.position.decDeg)
            out.append(described(RankedTarget(id: o.id, name: o.displayName, subtitle: "\(o.typeCode) in \(o.constellation)", group: o.group,
                                              raHours: o.raHours, decDeg: o.decDeg, sizeArcmin: o.majAxisArcmin, magnitude: o.magnitude,
                                              fit: frameFit(sizeArcmin: o.majAxisArcmin, fov: fov), peakAltDeg: tr.peakAlt, peakTime: tr.peakTime,
                                              moonSepDeg: sep, moonWashed: moonUp && sep < 30, visibleFraction: tr.fraction),
                                 viewable: tr.viewable, site: site, typeName: Catalog.typeNames[o.typeCode] ?? o.typeCode,
                                 catalogueID: o.catalogueID, commonName: o.commonName, frameFill: frameFill(sizeArcmin: o.majAxisArcmin, fov: fov),
                                 caldwell: o.caldwell))
        }

        for p in Planet.allCases {
            let pos = Ephemeris.planet(p, at: window.midpoint, site: site)
            let tr = track(raHours: pos.raHours, decDeg: pos.decDeg, window: window, site: site, minAlt: rule.minAltitudeDeg)
            guard tr.fraction >= 0.5 else { continue }
            let sep = Ephemeris.separationDeg(ra1Hours: pos.raHours, dec1Deg: pos.decDeg, ra2Hours: moon.position.raHours, dec2Deg: moon.position.decDeg)
            out.append(described(RankedTarget(id: "planet-\(p.rawValue)", name: p.displayName, subtitle: "Planet", group: .planets,
                                              raHours: pos.raHours, decDeg: pos.decDeg, sizeArcmin: nil, magnitude: pos.magnitude, fit: .small,
                                              peakAltDeg: tr.peakAlt, peakTime: tr.peakTime, moonSepDeg: sep, moonWashed: false, visibleFraction: tr.fraction),
                                 viewable: tr.viewable, site: site, typeName: "Planet", catalogueID: p.displayName))
        }
        if moon.illumination > 0.05 {
            let tr = track(raHours: moon.position.raHours, decDeg: moon.position.decDeg, window: window, site: site, minAlt: 10)
            if tr.fraction > 0 {
                out.append(described(RankedTarget(id: "moon", name: "Moon", subtitle: "\(Int((moon.illumination * 100).rounded()))% illuminated", group: .planets,
                                                  raHours: moon.position.raHours, decDeg: moon.position.decDeg, sizeArcmin: 31, magnitude: nil,
                                                  fit: frameFit(sizeArcmin: 31, fov: fov), peakAltDeg: tr.peakAlt, peakTime: tr.peakTime,
                                                  moonSepDeg: 0, moonWashed: false, visibleFraction: tr.fraction),
                                     viewable: tr.viewable, site: site, typeName: "\(Int((moon.illumination * 100).rounded()))% illuminated",
                                     catalogueID: "Moon", frameFill: frameFill(sizeArcmin: 31, fov: fov)))
            }
        }

        for c in constellations {
            let tr = track(raHours: c.raHours, decDeg: c.decDeg, window: window, site: site, minAlt: 20)
            guard tr.fraction >= 0.5 else { continue }
            // From the constellation's centre; never Moon-washed, since a constellation spans too much sky to be washed out.
            let sep = Ephemeris.separationDeg(ra1Hours: c.raHours, dec1Deg: c.decDeg, ra2Hours: moon.position.raHours, dec2Deg: moon.position.decDeg)
            out.append(described(RankedTarget(id: c.id, name: c.name, subtitle: "Constellation", group: .constellations,
                                              raHours: c.raHours, decDeg: c.decDeg, sizeArcmin: nil, magnitude: nil, fit: .mosaic,
                                              peakAltDeg: tr.peakAlt, peakTime: tr.peakTime, moonSepDeg: sep, moonWashed: false, visibleFraction: tr.fraction),
                                 viewable: tr.viewable, site: site, typeName: "Constellation", catalogueID: c.name))
        }

        let fitOrder: [FrameFit: Int] = [.fits: 0, .small: 1, .mosaic: 2]
        return out.sorted {
            if $0.group != $1.group { return TargetGroup.allCases.firstIndex(of: $0.group)! < TargetGroup.allCases.firstIndex(of: $1.group)! }
            if $0.moonWashed != $1.moonWashed { return !$0.moonWashed }
            if fitOrder[$0.fit]! != fitOrder[$1.fit]! { return fitOrder[$0.fit]! < fitOrder[$1.fit]! }
            if $0.peakAltDeg != $1.peakAltDeg { return $0.peakAltDeg > $1.peakAltDeg }
            return ($0.magnitude ?? 99) < ($1.magnitude ?? 99)
        }
    }

    /// Top three across groups, at most one per group, deep sky first.
    static func best(from ranked: [RankedTarget]) -> [RankedTarget] {
        var picked: [RankedTarget] = []
        for g in [TargetGroup.nebulae, .galaxies, .clusters, .planets] {
            if let t = ranked.first(where: { $0.group == g && !$0.moonWashed }) { picked.append(t) }
            if picked.count == 3 { break }
        }
        return picked
    }

    public static func plan(night: Night, forecast: Forecast, catalog: Catalog, constellations: [Constellation], site: Site, fov: FieldOfView, rule: GoRule,
                            bright: BrightSettings? = nil) -> NightPlan {
        let dark = darkHours(forecast.hours, night: night)
        var windows: [ClearWindow] = []
        if let ds = night.darkStart, let de = night.darkEnd {
            windows = Planner.windows(hours: forecast.hours, darkStart: ds, darkEnd: de, rule: rule)
        }
        let primary = windows.max { $0.hours < $1.hours }
        let moonMid = Ephemeris.moon(at: primary?.midpoint ?? night.darkStart ?? night.sunset, site: site)
        let darkness: (Date, Date)? = (night.darkStart != nil && night.darkEnd != nil) ? (night.darkStart!, night.darkEnd!) : nil
        let aboveFraction = darkness.map { moonUpFraction(from: $0.0, to: $0.1, site: site) } ?? 0
        let inputs = ScoreInputs(darkHours: dark, windows: windows, darkness: darkness,
                                 moonIllumination: moonMid.illumination, moonAboveFraction: aboveFraction, maxCloudPct: rule.maxCloudPct)
        let score = Planner.score(inputs)
        // Rank against the clear window when there is one, else against the whole of darkness so the browser
        // still shows what is up on a cloudy night. "Best tonight" only exists when a clear window exists.
        let rankingWindow = primary ?? darkness.map { ClearWindow(start: $0.0, end: $0.1) }
        let targets = rankingWindow.map { rank(catalog: catalog, constellations: constellations, window: $0, site: site, fov: fov, rule: rule) } ?? []
        var darkPlan = NightPlan(night: night, windows: windows, primary: primary, score: score, qualifies: primary != nil,
                                 moonIllumination: moonMid.illumination, moonRise: moonMid.rise, moonSet: moonMid.set,
                                 darkHours: dark, targets: targets, best: primary == nil ? [] : best(from: targets),
                                 seeingAvailable: dark.contains { $0.seeing != nil },
                                 limiting: primary == nil ? [] : limitingFactors(inputs), moonUpFraction: darkness == nil ? nil : aboveFraction)
        darkPlan.agreement = agreement(plan: darkPlan, second: forecast.secondOpinion, rule: rule)
        // Bright-night mode only takes over when the dark rule cannot be met at all tonight (too little darkness).
        if let b = bright, b.enabled, !darkPlan.qualifies {
            let darkLen = darkness.map { $0.1.timeIntervalSince($0.0) / 3600 } ?? 0
            if darkLen < rule.minHours { return brightPlan(night: night, forecast: forecast, site: site, fov: fov, rule: rule, bright: b) }
        }
        return darkPlan
    }

    /// The share of hourly samples from `from` to `to` with the Moon above the horizon.
    static func moonUpFraction(from: Date, to: Date, site: Site) -> Double {
        var t = from, n = 0, up = 0
        while t <= to { n += 1; if Ephemeris.moon(at: t, site: site).position.altDeg > 0 { up += 1 }; t = t.addingTimeInterval(3600) }
        return n == 0 ? 0 : Double(up) / Double(n)
    }

    /// Bright targets must stand this high. Summer Moons and planets are low at British latitudes: at the middle of
    /// nautical darkness nothing reached 30 degrees on any of 94 summer nights at 54° N in 2026 (owner ruling, 24 September 2026).
    public static let brightTargetFloorDeg = 15.0
    private static let brightPlanets: [Planet] = [.mercury, .venus, .mars, .jupiter, .saturn]   // the naked-eye ones

    /// The Moon (10 % lit or more) and naked-eye planets at or above the bright floor at `at`, Moon first, then by altitude.
    public static func brightTargets(at t: Date, site: Site) -> [RankedTarget] {
        var out: [RankedTarget] = []
        let moon = Ephemeris.moon(at: t, site: site)
        if moon.illumination >= 0.10, moon.position.altDeg >= brightTargetFloorDeg {
            let lit = "\(Int((moon.illumination * 100).rounded()))% illuminated"
            out.append(described(RankedTarget(id: "moon", name: "Moon", subtitle: lit, group: .planets,
                                              raHours: moon.position.raHours, decDeg: moon.position.decDeg, sizeArcmin: 31, magnitude: nil, fit: .fits,
                                              peakAltDeg: moon.position.altDeg, peakTime: t, moonSepDeg: 0, moonWashed: false, visibleFraction: 1),
                                 viewable: nil, site: site, typeName: lit, catalogueID: "Moon"))
        }
        let planets = brightPlanets.compactMap { p -> RankedTarget? in
            let pos = Ephemeris.planet(p, at: t, site: site)
            guard pos.altDeg >= brightTargetFloorDeg else { return nil }
            let sep = Ephemeris.separationDeg(ra1Hours: pos.raHours, dec1Deg: pos.decDeg, ra2Hours: moon.position.raHours, dec2Deg: moon.position.decDeg)
            return described(RankedTarget(id: "planet-\(p.rawValue)", name: p.displayName, subtitle: "Planet", group: .planets,
                                          raHours: pos.raHours, decDeg: pos.decDeg, sizeArcmin: nil, magnitude: pos.magnitude, fit: .small,
                                          peakAltDeg: pos.altDeg, peakTime: t, moonSepDeg: sep, moonWashed: false, visibleFraction: 1),
                             viewable: nil, site: site, typeName: "Planet", catalogueID: p.displayName)
        }.sorted { $0.peakAltDeg > $1.peakAltDeg }
        return out + planets
    }

    /// True when any bright target reaches the floor at some quarter-hour in [from, to).
    public static func anyBrightTargetUp(from: Date, to: Date, site: Site) -> Bool {
        var t = from
        while t < to { if !brightTargets(at: t, site: site).isEmpty { return true }; t = t.addingTimeInterval(900) }
        return false
    }

    /// Every bright target up during `w`, each at its highest, Moon first then by altitude.
    static func brightTargets(during w: ClearWindow, site: Site, fov: FieldOfView) -> [RankedTarget] {
        var best: [String: RankedTarget] = [:]
        var t = w.start
        while t <= w.end {
            for x in brightTargets(at: t, site: site) where (best[x.id]?.peakAltDeg ?? -90) < x.peakAltDeg { best[x.id] = x }
            t = t.addingTimeInterval(1800)
        }
        return best.values.map { x in
            described(x, viewable: track(raHours: x.raHours, decDeg: x.decDeg, window: w, site: site, minAlt: brightTargetFloorDeg).viewable,
                      site: site, typeName: x.typeName, catalogueID: x.catalogueID, frameFill: x.id == "moon" ? frameFill(sizeArcmin: 31, fov: fov) : nil)
        }.sorted { ($0.id == "moon" ? 0 : 1, -$0.peakAltDeg) < ($1.id == "moon" ? 0 : 1, -$1.peakAltDeg) }
    }

    /// The bright-night plan: clear hours between nautical dusk and dawn that have a bright target at the floor.
    static func brightPlan(night: Night, forecast: Forecast, site: Site, fov: FieldOfView, rule: GoRule, bright: BrightSettings) -> NightPlan {
        guard let ns = night.nauticalStart, let ne = night.nauticalEnd else {
            let moon = Ephemeris.moon(at: night.darkStart ?? night.sunset, site: site)   // keep the Moon tile truthful
            return NightPlan(night: night, windows: [], primary: nil, score: 0, qualifies: false, moonIllumination: moon.illumination, moonRise: moon.rise, moonSet: moon.set,
                             darkHours: [], targets: [], best: [], seeingAvailable: false, mode: .bright, brightTargets: [])
        }
        let span = forecast.hours.filter { $0.time.addingTimeInterval(3600) > ns && $0.time < ne }.sorted { $0.time < $1.time }
        // ponytail: an hour with nothing at the floor is masked as cloudy so the existing window finder needs no second rule.
        let usable = forecast.hours.map { h -> HourlyConditions in
            let centre = min(max(h.time.addingTimeInterval(1800), ns), ne)
            guard h.time.addingTimeInterval(3600) > ns, h.time < ne, brightTargets(at: centre, site: site).isEmpty else { return h }
            var masked = h; masked.cloudTotal = Int.max; return masked
        }
        let brightRule = GoRule(minHours: bright.minHours, maxCloudPct: rule.maxCloudPct, minAltitudeDeg: rule.minAltitudeDeg)
        let windows = Planner.windows(hours: usable, darkStart: ns, darkEnd: ne, rule: brightRule)
        let primary = windows.max { $0.hours < $1.hours }
        let moon = Ephemeris.moon(at: primary?.midpoint ?? ns, site: site)
        // The Moon is the target on a bright night, so its score term is not taken away.
        let inputs = ScoreInputs(darkHours: span, windows: windows, darkness: (ns, ne), moonIllumination: 0, moonAboveFraction: 0, maxCloudPct: rule.maxCloudPct)
        let score = Planner.score(inputs)
        var p = NightPlan(night: night, windows: windows, primary: primary, score: score, qualifies: primary != nil,
                         moonIllumination: moon.illumination, moonRise: moon.rise, moonSet: moon.set,
                         darkHours: span, targets: [], best: [], seeingAvailable: span.contains { $0.seeing != nil },
                         mode: .bright, brightTargets: primary.map { brightTargets(during: $0, site: site, fov: fov) } ?? [],
                         limiting: primary == nil ? [] : limitingFactors(inputs), moonUpFraction: moonUpFraction(from: ns, to: ne, site: site))
        p.agreement = agreement(plan: p, second: forecast.secondOpinion, rule: brightRule)
        return p
    }
}

extension Planner {
    /// Why tonight has no qualifying window, in plain words, or nil when the data cannot say.
    /// The bright no-window reason, measured the way the bright rule measures: hours clipped to nautical darkness, and an
    /// hour counts only when it is clear and a target stands at the floor at its centre.
    static func brightRunReason(_ hours: [HourlyConditions], from start: Date, to end: Date, rule: GoRule, site: Site) -> String {
        var best: (start: Date, hours: Double) = (start, 0), run: (start: Date, hours: Double)? = nil, prev: Date? = nil
        for h in hours {
            let from = max(h.time, start), to = min(h.time.addingTimeInterval(3600), end)
            let centre = min(max(h.time.addingTimeInterval(1800), start), end)   // sampled exactly as brightPlan samples
            let usable = h.cloudTotal <= rule.maxCloudPct && !brightTargets(at: centre, site: site).isEmpty
            let len = max(0, to.timeIntervalSince(from)) / 3600
            let contiguous = prev.map { h.time.timeIntervalSince($0) == 3600 } ?? false
            if usable { run = (contiguous && run != nil) ? (run!.start, run!.hours + len) : (from, len) } else { run = nil }
            if let r = run, r.hours > best.hours { best = r }
            prev = h.time
        }
        if best.hours == 0 { return "No Moon or planet \(Int(brightTargetFloorDeg))° up in the clear hours of nautical darkness." }
        return String(format: "Longest clear run with a target up is %.1f h from %@; the bright rule needs %.1f h.",
                      best.hours, Copy.hhmm(best.start, site: site), rule.minHours)
    }

    public static func noWindowReason(darkHours: [HourlyConditions], darkStart: Date, darkEnd: Date, rule: GoRule, site: Site,
                                      mode: PlanMode = .dark, brightTargetsUp: Bool = true) -> String? {
        let spanName = mode == .bright ? "nautical darkness" : "darkness"
        let ruleName = mode == .bright ? "the bright rule" : "the rule"
        let darkLen = darkEnd.timeIntervalSince(darkStart) / 3600
        if darkLen < rule.minHours {
            return mode == .bright
                ? String(format: "Only %.1f h of %@; %@ needs %.1f h.", darkLen, spanName, ruleName, rule.minHours)
                : String(format: "Only %.1f h of %@; %@ needs %.0f h.", darkLen, spanName, ruleName, rule.minHours)
        }
        if mode == .bright, !brightTargetsUp {
            return "No Moon or planet \(Int(brightTargetFloorDeg))° up during nautical darkness."
        }
        let dark = darkHours.sorted { $0.time < $1.time }
        guard !dark.isEmpty else { return nil }
        let clear = dark.filter { $0.cloudTotal <= rule.maxCloudPct }
        if clear.isEmpty {
            let low = dark.map(\.cloudTotal).min() ?? 0
            return "Cloud never below \(low)% during \(spanName); \(ruleName) allows \(rule.maxCloudPct)%."
        }
        if mode == .bright { return brightRunReason(dark, from: darkStart, to: darkEnd, rule: rule, site: site) }
        var best: (start: Date, hours: Int) = (dark[0].time, 0), run: (start: Date, hours: Int)? = nil, prev: Date? = nil
        for h in dark {
            let isClear = h.cloudTotal <= rule.maxCloudPct
            let contiguous = prev.map { h.time.timeIntervalSince($0) == 3600 } ?? false
            if isClear { run = (contiguous && run != nil) ? (run!.start, run!.hours + 1) : (h.time, 1) } else { run = nil }
            if let r = run, r.hours > best.hours { best = r }
            prev = h.time
        }
        return String(format: "Longest clear run is %d h from %@; %@ needs %.0f h.", best.hours, Copy.hhmm(best.start, site: site), ruleName, rule.minHours)
    }
}

public enum MoonTonight: Equatable, Sendable { case sets(Date), rises(Date), upAllNight, down }

extension Planner {
    /// What the Moon does during the plan's darkness; nil when there is no darkness to judge by.
    public static func moonTonight(_ plan: NightPlan) -> MoonTonight? {
        guard let up = plan.moonUpFraction, let span = plan.darkSpan else { return nil }
        // Events first: the share is sampled hourly, so a Moon that rises after the last sample reads 0 % up.
        // Only an event inside darkness is shown, so a rise or set found on the neighbouring night never is.
        if let s = plan.moonSet, span.start <= s, s <= span.end { return .sets(s) }
        if let r = plan.moonRise, span.start <= r, r <= span.end { return .rises(r) }
        return up == 0 ? .down : .upAllNight
    }
}

public enum TargetSort: String, CaseIterable, Sendable { case bestNow = "Best now", altitude = "Altitude", size = "Size", brightness = "Brightness" }

extension RankedTarget {
    /// Within 15° of a Moon more than half lit that is up at some point tonight (follow-on 5). The Moon itself and
    /// constellations never count. Deep-sky targets near a Moon that is up at the window's middle are already Moon-washed,
    /// which the card shows first; this catches planets, and targets whose Moon rises or sets inside the window.
    public func isNearMoon(moonIllumination: Double, moonUpTonight: Bool) -> Bool {
        id != "moon" && group != .constellations && moonUpTonight && moonIllumination > 0.5 && moonSepDeg < 15
    }
}

extension Planner {
    /// Targets window sort. Best now: highest at `now` while `now` is inside `span`, else the ranked order. Altitude: peak
    /// altitude. Size: largest first. Brightness: lowest magnitude first. Unknown sizes and magnitudes go last; ties keep the ranked order.
    public static func sorted(_ ts: [RankedTarget], by sort: TargetSort, now: Date, span: ClearWindow?, site: Site) -> [RankedTarget] {
        func stable(_ before: (RankedTarget, RankedTarget) -> Bool) -> [RankedTarget] {
            ts.enumerated().sorted { a, b in
                before(a.element, b.element) || (!before(b.element, a.element) && a.offset < b.offset)
            }.map(\.element)
        }
        switch sort {
        case .bestNow:
            guard let s = span, s.start <= now, now <= s.end else { return ts }
            let alt = ts.map { Ephemeris.altAz(raHours: $0.raHours, decDeg: $0.decDeg, at: now, site: site).alt }
            return ts.indices.sorted { alt[$0] > alt[$1] || (alt[$0] == alt[$1] && $0 < $1) }.map { ts[$0] }
        case .altitude: return stable { $0.peakAltDeg > $1.peakAltDeg }
        case .size: return stable { ($0.sizeArcmin ?? -1) > ($1.sizeArcmin ?? -1) }
        case .brightness: return stable { ($0.magnitude ?? 99) < ($1.magnitude ?? 99) }
        }
    }
}
