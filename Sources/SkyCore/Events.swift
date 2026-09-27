import Foundation

public struct MeteorShower: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let startMonth: Int, startDay: Int, endMonth: Int, endDay: Int, peakMonth: Int, peakDay: Int
    public let zhr: Int
    public let raHours: Double
    public let decDeg: Double
    public let parent: String
    public let velocityKms: Int
}

public enum MeteorShowers {
    public static func bundled() throws -> [MeteorShower] {
        guard let url = Bundle.module.url(forResource: "meteor-showers", withExtension: "json", subdirectory: "Resources/events") else {
            throw CatalogError.missingResource("meteor-showers")
        }
        return try JSONDecoder().decode([MeteorShower].self, from: Data(contentsOf: url))
    }

    /// Day-of-year comparison that wraps across the new year.
    static func inRange(month: Int, day: Int, shower s: MeteorShower) -> Bool {
        let d = month * 100 + day, a = s.startMonth * 100 + s.startDay, b = s.endMonth * 100 + s.endDay
        return a <= b ? (d >= a && d <= b) : (d >= a || d <= b)
    }

    public static func active(on date: Date, calendar: Calendar, showers: [MeteorShower]) -> [MeteorShower] {
        let c = calendar.dateComponents([.month, .day], from: date)
        return showers.filter { inRange(month: c.month!, day: c.day!, shower: $0) }
    }

    public static func isPeak(_ s: MeteorShower, on date: Date, calendar: Calendar) -> Bool {
        let c = calendar.dateComponents([.month, .day], from: date)
        return c.month == s.peakMonth && c.day == s.peakDay
    }
}

public enum SkyEventKind: String, Codable, Sendable { case meteorShower, lunarEclipse, solarEclipse, conjunction, comet, issPass }

public struct SkyEvent: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let kind: SkyEventKind
    public let title: String
    public var detail: String
    public let time: Date
    public let endTime: Date?
    public let raHours: Double?
    public let decDeg: Double?
    public init(id: String, kind: SkyEventKind, title: String, detail: String, time: Date, endTime: Date?, raHours: Double?, decDeg: Double?) {
        self.id = id; self.kind = kind; self.title = title; self.detail = detail; self.time = time; self.endTime = endTime
        self.raHours = raHours; self.decDeg = decDeg
    }
    /// When to look (v1.0.1): a shower's best hour, the ISS's peak, a comet's or a pair's highest point. Nil: `time`.
    public var best: Date? = nil
    /// The event page's rows, e.g. ("Radiant", "Taurus, highest at 02:10, 52° up").
    public var facts: [EventFact] = []
    /// True when `best` (or `time`) is in a clear hour of tonight's forecast, false in a cloudy one, nil outside it.
    public var clear: Bool? = nil
    /// A conjunction's separation, and whether both bodies fit in the user's frame (`Events.fits`).
    public var separationDeg: Double? = nil
    public var fits: Bool? = nil
    /// The time to show: `best`, else `time`.
    public var when: Date { best ?? time }
}

extension SkyEvent {
    /// The fields added in 1.0.1 fall back to their defaults, so an event saved by an earlier version still loads.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id); kind = try c.decode(SkyEventKind.self, forKey: .kind)
        title = try c.decode(String.self, forKey: .title); detail = try c.decode(String.self, forKey: .detail)
        time = try c.decode(Date.self, forKey: .time); endTime = try c.decodeIfPresent(Date.self, forKey: .endTime)
        raHours = try c.decodeIfPresent(Double.self, forKey: .raHours); decDeg = try c.decodeIfPresent(Double.self, forKey: .decDeg)
        best = try c.decodeIfPresent(Date.self, forKey: .best)
        facts = try c.decodeIfPresent([EventFact].self, forKey: .facts) ?? []
        clear = try c.decodeIfPresent(Bool.self, forKey: .clear)
        separationDeg = try c.decodeIfPresent(Double.self, forKey: .separationDeg)
        fits = try c.decodeIfPresent(Bool.self, forKey: .fits)
    }
}

public struct EventFact: Codable, Equatable, Sendable {
    public let label: String
    public let value: String
    public init(_ label: String, _ value: String) { self.label = label; self.value = value }
}

public enum Events {
    /// Tonight's darkness, or sunset to sunrise when there is none.
    static func darkness(_ night: Night) -> (start: Date, end: Date) {
        (night.darkStart ?? night.sunset, night.darkEnd ?? night.sunrise)
    }

    /// Nautical dusk to dawn, or darkness when there is none: planets and comets are often best in twilight.
    static func twilight(_ night: Night) -> (start: Date, end: Date) {
        (night.nauticalStart ?? night.darkStart ?? night.sunset, night.nauticalEnd ?? night.darkEnd ?? night.sunrise)
    }

    /// Both bodies of a pair fit in one frame: their separation, plus the Moon's radius when one is the Moon (its far limb
    /// must fit too), within the frame's longer side less a tenth for margin.
    public static func fits(separationDeg sep: Double, fov: FieldOfView, includesMoon: Bool) -> Bool {
        sep + (includesMoon ? 0.26 : 0) <= max(fov.widthDeg, fov.heightDeg) * 0.9
    }

    /// The highest point of a fixed sky position between `from` and `to`, sampled every 15 minutes.
    static func highest(raHours: Double, decDeg: Double, from: Date, to: Date, site: Site) -> (time: Date, alt: Double) {
        var best = (time: from, alt: -90.0)
        var t = from
        while t <= to {
            let alt = Ephemeris.altAz(raHours: raHours, decDeg: decDeg, at: t, site: site).alt
            if alt > best.alt { best = (t, alt) }
            t = t.addingTimeInterval(900)
        }
        return best
    }

    /// "5 November"
    static func day(_ d: Date, site: Site) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB"); f.timeZone = site.timeZone; f.dateFormat = "d MMMM"
        return f.string(from: d)
    }

    /// What the Moon does to faint things at `date`.
    static func moonNote(at date: Date, site: Site, hides: String) -> String {
        let m = Ephemeris.moon(at: date, site: site)
        let lit = Int((m.illumination * 100).rounded())
        if m.position.altDeg <= 0 { return "Below the horizon at \(Copy.hhmm(date, site: site)) (\(lit)% lit)" }
        let up = "\(lit)% lit and \(Int(m.position.altDeg.rounded()))° up at \(Copy.hhmm(date, site: site))"
        return m.illumination > 0.5 ? "\(up): it will \(hides)" : up
    }

    /// The date of a shower's peak nearest `date`, and the whole days from `date` to it (negative when past).
    static func peak(_ s: MeteorShower, near date: Date, calendar cal: Calendar) -> (date: Date, days: Int) {
        let start = cal.startOfDay(for: date)
        let y = cal.component(.year, from: date)
        let candidates = [y - 1, y, y + 1].compactMap { cal.date(from: DateComponents(year: $0, month: s.peakMonth, day: s.peakDay)) }
        let p = candidates.min { abs($0.timeIntervalSince(start)) < abs($1.timeIntervalSince(start)) }!
        return (p, cal.dateComponents([.day], from: start, to: p).day!)
    }

    public static func showers(night: Night, site: Site, showers: [MeteorShower]) -> [SkyEvent] {
        let cal = site.calendar
        let dark = darkness(night)
        return MeteorShowers.active(on: night.localDate, calendar: cal, showers: showers).map { s in
            // A peak date's maximum can fall either side of midnight, so the night running into it and the night of it
            // both read "at peak tonight"; the countdown is to the first of them, the night of the day before.
            let (peakDate, days) = peak(s, near: night.localDate, calendar: cal)
            let eve = cal.date(byAdding: .day, value: -1, to: peakDate)!
            // "4–5 November", or "31 October–1 November" across a month end
            let peakNight = (cal.component(.month, from: eve) == cal.component(.month, from: peakDate) ? "\(cal.component(.day, from: eve))" : day(eve, site: site))
                + "–" + day(peakDate, site: site)
            let peakText: String
            switch days {
            case 0, 1: peakText = "At peak tonight"
            case 2: peakText = "Peak tomorrow night (\(peakNight))"
            case 3...: peakText = "Peak night \(peakNight), in \(days - 1) days"
            default: peakText = "Past its peak (night of \(peakNight))"
            }
            let top = highest(raHours: s.raHours, decDeg: s.decDeg, from: dark.start, to: dark.end, site: site)
            let where_ = Ephemeris.constellation(raHours: s.raHours, decDeg: s.decDeg).name
            let up = top.alt > 0
            var e = SkyEvent(id: "shower-\(s.id)", kind: .meteorShower, title: s.name,
                             detail: up ? "\(peakText) · radiant in \(where_), best \(Copy.hhmm(top.time, site: site))"
                                        : "\(peakText) · radiant in \(where_), below the horizon tonight",
                             time: dark.start, endTime: dark.end, raHours: s.raHours, decDeg: s.decDeg)
            e.best = up ? top.time : nil
            let speed = s.velocityKms >= 55 ? "fast" : s.velocityKms <= 30 ? "slow" : "medium"
            e.facts = [
                EventFact("Peak", days >= 0 && days <= 1 ? "Tonight, ZHR \(s.zhr)" : "Night of \(peakNight), ZHR \(s.zhr)"),
                EventFact("Radiant", up ? "\(where_), highest at \(Copy.hhmm(top.time, site: site)), \(Int(top.alt.rounded()))° up"
                                        : "\(where_), below the horizon all night"),
            ]
            // The ZHR assumes the radiant overhead and a perfectly dark sky; the rate falls with the radiant's height.
            if up {
                let rate = max(1, Int((Double(s.zhr) * sin(top.alt * .pi / 180)).rounded()))
                e.facts.append(EventFact("At peak, from here", "Up to about \(rate) an hour, under a dark, moonless sky"))
                e.facts.append(EventFact("Moon", moonNote(at: top.time, site: site, hides: "hide all but the brightest meteors")))
            }
            e.facts += [EventFact("Speed", "\(s.velocityKms) km/s (\(speed))"), EventFact("Parent", s.parent)]
            return e
        }
    }

    public static func eclipses(after date: Date, site: Site, withinDays: Int) -> [SkyEvent] {
        let limit = date.addingTimeInterval(Double(withinDays) * 86_400)
        var out: [SkyEvent] = []
        func times(_ begin: Date?, _ peak: Date, _ end: Date?) -> [EventFact] {
            [begin.map { EventFact("Begins", "\(day($0, site: site)) \(Copy.hhmm($0, site: site))") },
             EventFact("Peak", "\(day(peak, site: site)) \(Copy.hhmm(peak, site: site))"),
             end.map { EventFact("Ends", "\(day($0, site: site)) \(Copy.hhmm($0, site: site))") }].compactMap { $0 }
        }
        if let l = Ephemeris.nextLunarEclipse(after: date), l.peak <= limit {
            var e = SkyEvent(id: "lunar-\(Int(l.peak.timeIntervalSince1970))", kind: .lunarEclipse,
                             title: "\(l.kind.rawValue.capitalized) lunar eclipse", detail: "Peak obscuration \(Int((l.obscuration * 100).rounded()))%",
                             time: l.peak, endTime: l.end, raHours: nil, decDeg: nil)
            func moonAlt(_ d: Date?) -> Double { d.map { Ephemeris.moon(at: $0, site: site).position.altDeg } ?? -90 }
            let alt = moonAlt(l.peak)
            let partly = moonAlt(l.begin) > 0 || moonAlt(l.end) > 0
            let seen = alt > 0 ? "\(Int(alt.rounded()))° up"
                     : partly ? "Below the horizon at peak; the Moon is up for part of the eclipse"
                     : "Below the horizon throughout: not visible from \(site.name)"
            e.facts = times(l.begin, l.peak, l.end) + [EventFact("Moon at peak", seen)]
            if alt <= 0 { e.detail += partly ? " · partly visible here" : " · not visible here" }
            out.append(e)
        }
        if let s = Ephemeris.nextLocalSolarEclipse(after: date, site: site), s.peak <= limit {
            var e = SkyEvent(id: "solar-\(Int(s.peak.timeIntervalSince1970))", kind: .solarEclipse,
                             title: "\(s.kind.rawValue.capitalized) solar eclipse from \(site.name)", detail: "Peak obscuration \(Int((s.obscuration * 100).rounded()))%",
                             time: s.peak, endTime: s.partialEnd, raHours: nil, decDeg: nil)
            let alt = Ephemeris.sunAltitude(at: s.peak, site: site)
            e.facts = times(s.partialBegin, s.peak, s.partialEnd) + [EventFact("Sun at peak", alt > 0 ? "\(Int(alt.rounded()))° up"
                                                                          : "Below the horizon; the eclipse is seen at sunrise or sunset"),
                      EventFact("Safety", "Never look at the Sun, or point a telescope or camera at it, without a certified solar filter.")]
            out.append(e)
        }
        return out
    }

    /// Pairs among the Moon and the seven planets closer than `maxSeparationDeg` at `date`. With `night`, each gets the
    /// pair's highest point in darkness; with `fov`, whether both fit in the frame.
    public static func conjunctions(at date: Date, site: Site, maxSeparationDeg: Double, night: Night? = nil, fov: FieldOfView? = nil) -> [SkyEvent] {
        var bodies: [(String, BodyPosition)] = Planet.allCases.map { ($0.displayName, Ephemeris.planet($0, at: date, site: site)) }
        bodies.append(("Moon", Ephemeris.moon(at: date, site: site).position))
        var out: [(sep: Double, event: SkyEvent)] = []
        for i in 0..<bodies.count {
            for j in (i + 1)..<bodies.count {
                let (a, pa) = bodies[i], (b, pb) = bodies[j]
                let sep = Ephemeris.separationDeg(ra1Hours: pa.raHours, dec1Deg: pa.decDeg, ra2Hours: pb.raHours, dec2Deg: pb.decDeg)
                guard sep <= maxSeparationDeg else { continue }
                var detail = String(format: "%.1f° apart", sep)
                var e = SkyEvent(id: "conj-\(a)-\(b)", kind: .conjunction, title: "\(a) near \(b)", detail: detail, time: date, endTime: nil,
                                 raHours: pa.raHours, decDeg: pa.decDeg)
                e.separationDeg = sep
                e.facts = [EventFact("Separation", String(format: "%.1f°", sep))]
                if let f = fov {
                    let fits = Events.fits(separationDeg: sep, fov: f, includesMoon: a == "Moon" || b == "Moon")
                    e.fits = fits
                    detail += fits ? " · fits your field of view" : " · wider than your field of view"
                    e.facts.append(EventFact("Your field of view", String(format: "%g × %g°: ", f.widthDeg, f.heightDeg)
                                             + (fits ? "both fit in one frame" : "too narrow for both at once")))
                }
                if let n = night {
                    let d = twilight(n)
                    let top = highest(raHours: pa.raHours, decDeg: pa.decDeg, from: d.start, to: d.end, site: site)
                    if top.alt > 0 {
                        e.best = top.time
                        detail += " · best \(Copy.hhmm(top.time, site: site))"
                        e.facts.append(EventFact("Best", "\(Copy.hhmm(top.time, site: site)), \(Int(top.alt.rounded()))° up"))
                    } else {
                        e.facts.append(EventFact("Best", "Below the horizon at night"))
                    }
                }
                e.detail = detail
                out.append((sep, e))
            }
        }
        return out.sorted { $0.sep < $1.sep }.map(\.event)
    }

    /// A comet tonight, from its position now (`pos`) and a week later (`later`, for the trend). Nil when it never gets
    /// above `minAlt` in darkness.
    public static func comet(designation: String, pos: CometPosition, later: CometPosition?, night: Night, site: Site, minAlt: Double = 20) -> SkyEvent? {
        let d = twilight(night)
        let top = highest(raHours: pos.raHours, decDeg: pos.decDeg, from: d.start, to: d.end, site: site)
        guard top.alt > minAlt else { return nil }
        let where_ = Ephemeris.constellation(raHours: pos.raHours, decDeg: pos.decDeg).name
        var e = SkyEvent(id: "comet-\(designation)", kind: .comet, title: designation,
                         detail: String(format: "mag %.1f · in %@ · best %@, %.0f° up", pos.magnitude, where_, Copy.hhmm(top.time, site: site), top.alt),
                         time: d.start, endTime: d.end, raHours: pos.raHours, decDeg: pos.decDeg)
        e.best = top.time
        var mag = String(format: "%.1f", pos.magnitude)
        if let l = later {
            let change = l.magnitude - pos.magnitude   // smaller magnitude is brighter
            mag += abs(change) < 0.1 ? ", steady" : String(format: ", %@ (%.1f in a week)", change < 0 ? "brightening" : "fading", l.magnitude)
        }
        e.facts = [EventFact("Magnitude", mag), EventFact("Where", where_),
                   EventFact("Best", "\(Copy.hhmm(top.time, site: site)), \(Int(top.alt.rounded()))° up"),
                   EventFact("Distance", String(format: "%.2f AU from Earth, %.2f AU from the Sun", pos.deltaAU, pos.rAU)),
                   EventFact("Moon", moonNote(at: top.time, site: site, hides: "wash out its faint tail"))]
        return e
    }

    /// An ISS pass: where it appears, peaks and disappears. It is only seen while above the horizon and sunlit, so a pass
    /// that runs into Earth's shadow "fades" before it sets, and one that starts in shadow "appears" after it rises.
    public static func issPass(_ p: SatellitePass, site: Site) -> SkyEvent {
        func dir(_ az: Double?) -> String { az.map { " \(Geo.compass($0))" } ?? "" }
        let start = p.appears ?? p.rise, end = p.vanishes ?? p.set
        let emerges = start.timeIntervalSince(p.rise) > 30, fades = p.set.timeIntervalSince(end) > 30
        let first = emerges ? "Appears\(dir(p.appearsAzimuthDeg))" : "Rises\(dir(p.riseAzimuthDeg))"
        let last = fades ? "fades\(dir(p.vanishesAzimuthDeg))" : "sets\(dir(p.setAzimuthDeg))"
        let highest = "\(Int(p.maxElevationDeg.rounded()))° up in the\(dir(p.peakAzimuthDeg))"
        var e = SkyEvent(id: "iss-\(Int(p.rise.timeIntervalSince1970))", kind: .issPass, title: "ISS pass",
                         detail: "\(first) \(Copy.hhmm(start, site: site)) · \(highest) \(Copy.hhmm(p.peak, site: site)) · \(last) \(Copy.hhmm(end, site: site))",
                         time: start, endTime: end, raHours: nil, decDeg: nil)
        e.best = p.peak
        let minutes = max(1, Int((end.timeIntervalSince(start) / 60).rounded()))
        e.facts = [EventFact(emerges ? "Appears" : "Rises", "\(Copy.hhmm(start, site: site))\(dir(emerges ? p.appearsAzimuthDeg : p.riseAzimuthDeg))"
                                                          + (emerges ? ", out of Earth's shadow" : "")),
                   EventFact("Highest", "\(Copy.hhmm(p.peak, site: site)), \(highest)"),
                   EventFact(fades ? "Fades" : "Sets", "\(Copy.hhmm(end, site: site))\(dir(fades ? p.vanishesAzimuthDeg : p.setAzimuthDeg))"
                                                     + (fades ? ", into Earth's shadow" : "")),
                   EventFact("Visible for", "About \(minutes) minute\(minutes == 1 ? "" : "s")")]
        return e
    }

    /// Marks each event clear or cloudy from the forecast hour containing its `when`; nil when no hour covers it.
    public static func markClear(_ events: [SkyEvent], hours: [HourlyConditions], maxCloudPct: Int) -> [SkyEvent] {
        events.map { e in
            var e = e
            e.clear = hours.first { $0.time <= e.when && e.when < $0.time.addingTimeInterval(3600) }.map { $0.cloudTotal <= maxCloudPct }
            return e
        }
    }
}
