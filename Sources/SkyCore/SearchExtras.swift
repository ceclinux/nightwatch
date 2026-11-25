import Foundation

/// What a Targets search finds in the catalogue that the night's list leaves out (#250): a card for each, so it can be opened and given a
/// heart. One that is up for half the window (only the list's magnitude cut left it out) is an ordinary card; the rest are greyed with the
/// first night they are well placed. The views ask on every clock tick, so the last answer is kept.
public final class SearchExtras {
    /// A broad word ("galaxy") matches thousands: the brightest few are enough to find one by.
    public static let limit = 12
    private var key = ""
    private var kept: [FavouriteTarget] = []
    private var listKey = ""
    private var list: [DeepSkyObject] = []
    /// The nights ahead, kept from one keystroke to the next: working a night out costs far more than tracking a target across it.
    private var nightsKey = ""
    private var nights: [Int: Night?] = [:]
    public init() {}

    /// Every catalogue match that is not in the night's list, whatever its group: the search hint counts them.
    public func notListed(query: String, ranked: [RankedTarget], catalog: Catalog, nightKey: String) -> [DeepSkyObject] {
        guard !query.allSatisfy(\.isWhitespace) else { return [] }
        let k = "\(query)|\(nightKey)|\(ranked.count)"
        if k != listKey {
            let listed = Set(ranked.map(\.id))
            list = catalog.objects(matching: query).filter { !listed.contains($0.id) }
            listKey = k
        }
        return list
    }

    /// The group of every match the night's list leaves out, one entry a match, for the search hint's counts: the catalogue's, and
    /// Pluto, Ceres and the Lagrange points (`MinorBody`), which are in no catalogue.
    public func unlistedGroups(query: String, ranked: [RankedTarget], catalog: Catalog, nightKey: String) -> [TargetGroup] {
        let listed = Set(ranked.map(\.id))
        return notListed(query: query, ranked: ranked, catalog: catalog, nightKey: nightKey).map(\.group)
            + MinorBody.matching(query).filter { !listed.contains($0.id) }.map { _ in TargetGroup.planets }
    }

    public func cards(query: String, group: TargetGroup, ranked: [RankedTarget], catalog: Catalog, plan: NightPlan, site: Site,
                      fov: FieldOfView, rule: GoRule) -> [FavouriteTarget] {
        guard !query.allSatisfy(\.isWhitespace) else { return [] }
        let k = "\(query)|\(group)|\(plan.night.key)|\(plan.mode)|\(String(describing: plan.primary))|\(site)|\(fov)|\(rule)|\(ranked.count)"
        if k != key {
            let found = notListed(query: query, ranked: ranked, catalog: catalog, nightKey: plan.night.key).filter { $0.group == group }
            let nk = "\(plan.night.key)|\(site.latitude),\(site.longitude),\(site.timeZoneID)"
            if nk != nightsKey { nights = [:]; nightsKey = nk }
            let night: (Int) -> Night? = { i in
                if let n = self.nights[i] { return n }
                let n = try? Ephemeris.night(localDate: site.calendar.date(byAdding: .day, value: i, to: plan.night.localDate)!, site: site)
                self.nights[i] = n
                return n
            }
            kept = Planner.searchExtras(found, plan: plan, site: site, fov: fov, rule: rule, night: night)
            if group == .planets {
                let listed = Set(ranked.map(\.id))
                kept += Planner.searchExtras(MinorBody.matching(query).filter { !listed.contains($0.id) }, plan: plan, site: site, fov: fov,
                                             rule: rule, night: night)
            }
            key = k
        }
        return kept
    }
}

extension Planner {
    /// `found`: one group's catalogue matches that the night's list leaves out.
    /// `night(i)`: the night i days after the plan's.
    static func searchExtras(_ found: [DeepSkyObject], plan: NightPlan, site: Site, fov: FieldOfView, rule: GoRule,
                             limit: Int = SearchExtras.limit, night: (Int) -> Night?) -> [FavouriteTarget] {
        let matches = found.sorted { ($0.magnitude ?? 99) < ($1.magnitude ?? 99) }.prefix(limit)
        guard !matches.isEmpty else { return [] }
        let window = plan.primary ?? plan.darkSpan
        let span = window ?? ClearWindow(start: plan.night.sunset, end: plan.night.sunrise)
        let moon = Ephemeris.moon(at: span.midpoint, site: site)
        let moonUp = moon.position.altDeg > 0 && moon.illumination > 0.1
        return matches.compactMap { o in
            guard let b = build(.object(o), window: span, site: site, fov: fov, rule: rule, moon: moon, moonUp: moonUp) else { return nil }
            if window != nil, b.fraction >= 0.5 { return FavouriteTarget(target: b.target, notTonight: nil) }
            let next = nextWellPlaced(raHours: o.raHours, decDeg: o.decDeg, site: site, minAlt: rule.minAltitudeDeg, night: night)
            return FavouriteTarget(target: b.target, notTonight: Copy.nextWellPlaced(next, decDeg: o.decDeg, site: site, minAlt: rule.minAltitudeDeg))
        }
    }

    /// Pluto, Ceres or a Lagrange point a search matched and the night's list leaves out: built as a planet is, and greyed with when it
    /// is next well placed. A Lagrange point circles the sky with the Moon each month, so it is looked for night by night for two
    /// months; Pluto and Ceres, which keep their place for weeks, a week at a time for a year.
    static func searchExtras(_ bodies: [MinorBody], plan: NightPlan, site: Site, fov: FieldOfView, rule: GoRule, night: (Int) -> Night?) -> [FavouriteTarget] {
        guard !bodies.isEmpty else { return [] }
        let window = plan.primary ?? plan.darkSpan
        let span = window ?? ClearWindow(start: plan.night.sunset, end: plan.night.sunrise)
        let moon = Ephemeris.moon(at: span.midpoint, site: site)
        return bodies.compactMap { body in
            guard let b = build(.minor(body), window: span, site: site, fov: fov, rule: rule, moon: moon, moonUp: false) else { return nil }
            if window != nil, b.fraction >= 0.5 { return FavouriteTarget(target: b.target, notTonight: nil) }
            let next = nextWellPlaced(site: site, minAlt: rule.minAltitudeDeg, night: night, step: body.isLagrangePoint ? 1 : 7,
                                      days: body.isLagrangePoint ? 60 : 364) { n in
                let p = body.place(at: n.darkStart.map { $0.addingTimeInterval((n.darkEnd ?? $0).timeIntervalSince($0) / 2) } ?? n.sunset, site: site)
                return (p.raHours, p.decDeg)
            }
            // Pluto keeps its declination for years, so "never clears" can be said of it; the others move too far to say.
            let text = Copy.nextWellPlaced(next, decDeg: body == .pluto ? b.target.decDeg : nil, site: site, minAlt: rule.minAltitudeDeg,
                                           span: body.isLagrangePoint ? "two months" : "year")
            return FavouriteTarget(target: b.target, notTonight: text)
        }
    }

    /// The first night after tonight, within `days`, on which a place in the sky is above the floor for half of the darkness: the test
    /// the night's list sets. `night(i)` is the night i days on, and `place` where the thing is that night. Looked for `step` nights at a
    /// time, then to the night in the stretch before the first hit.
    /// shortcut: a spell of good nights shorter than `step` can be stepped over; a fixed place in the sky is well placed for weeks.
    static func nextWellPlaced(site: Site, minAlt: Double, night: (Int) -> Night?, step: Int = 7, days: Int = 364,
                               place: (Night) -> (raHours: Double, decDeg: Double)) -> Night? {
        func placed(_ i: Int) -> Night? {
            guard let n = night(i), let s = n.darkStart, let e = n.darkEnd else { return nil }
            let p = place(n)
            return track(raHours: p.raHours, decDeg: p.decDeg, window: ClearWindow(start: s, end: e), site: site, minAlt: minAlt).fraction >= 0.5 ? n : nil
        }
        for i in stride(from: step, through: days, by: step) where placed(i) != nil {
            for day in (i - step + 1)..<i { if let n = placed(day) { return n } }
            return placed(i)
        }
        return nil
    }

    static func nextWellPlaced(raHours: Double, decDeg: Double, site: Site, minAlt: Double, night: (Int) -> Night?) -> Night? {
        nextWellPlaced(site: site, minAlt: minAlt, night: night) { _ in (raHours, decDeg) }
    }

    public static func nextWellPlaced(raHours: Double, decDeg: Double, after tonight: Night, site: Site, minAlt: Double) -> Night? {
        nextWellPlaced(raHours: raHours, decDeg: decDeg, site: site, minAlt: minAlt) {
            try? Ephemeris.night(localDate: site.calendar.date(byAdding: .day, value: $0, to: tonight.localDate)!, site: site)
        }
    }
}

extension Copy {
    /// A searched-for target's greyed card (#250): when to come back for it, or that this site never gets it.
    /// `decDeg`: nil for something that moves too far for "never" to be said of it.
    /// `span`: how far ahead was looked.
    static func nextWellPlaced(_ night: Night?, decDeg: Double?, site: Site, minAlt: Double, span: String = "year") -> String {
        if let night {
            let f = DateFormatter(); f.timeZone = site.timeZone; f.dateFormat = "d MMM"; f.locale = Locale(identifier: "en_GB")
            return "Next well placed from \(f.string(from: night.localDate))"
        }
        // Its highest point anywhere in the year is when it crosses the meridian.
        if let decDeg, 90 - abs(site.latitude - decDeg) < minAlt { return "Never clears \(Int(minAlt.rounded()))° from here" }
        return "Not well placed from here in the coming \(span)"
    }
}
