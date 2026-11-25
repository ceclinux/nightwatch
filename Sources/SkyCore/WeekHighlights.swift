import Foundation

/// A clear night's highlights on The week ahead (owner, 25 November 2026, of a single clear night a week out: "what would be
/// the highlights to see on that one clear night?"). Events that belong to that night come first, since a planet or a nebula is
/// there for weeks: a meteor shower's peak, an eclipse, a close pair, the Moon covering a star. Then targets, as many as the window
/// has time to stack, none overlapping. Everything named is in the clear window and high enough to recommend. Three at most.
extension Planner {
    /// The most the line names.
    static let highlightLimit = 3
    /// Events it leads with, at most.
    static let highlightEvents = 2
    /// One target for each stretch of this many hours of clear window, and one in a shorter window: a deep-sky stack takes three
    /// to four hours (`SessionPlanner.gapHours` keeps their best times three apart).
    static let highlightStackHours = 3.5
    /// A shower's radiant below this in the window shows few of its meteors; the constellations' floor.
    static let highlightRadiantDeg = 20.0
    /// An eclipse or a close pair lower than this is in the murk; the Moon's floor.
    static let highlightLowDeg = 10.0

    /// `plan` must have been made with the catalogue, or it has no targets to offer. `occultations`: the year ahead's, as the stores hold them.
    public static func highlights(plan p: NightPlan, site: Site, fov: FieldOfView, showers: [MeteorShower] = [],
                                  occultations: [SkyEvent] = []) -> [String] {
        guard let w = p.primary else { return [] }
        func inWindow(_ d: Date) -> Bool { d >= w.start && d <= w.end }
        var events: [(time: Date, text: String)] = []

        // A comet is on the list for weeks, and a space station pass a week out would be a guess: its orbit data lasts days.
        for e in Events.showers(night: p.night, site: site, showers: showers) where e.atPeak {
            guard let ra = e.raHours, let dec = e.decDeg else { continue }
            let top = Events.highest(raHours: ra, decDeg: dec, from: w.start, to: w.end, site: site)
            if top.clear, top.alt >= highlightRadiantDeg { events.append((top.time, "\(e.title) at peak, best \(Copy.hhmm(top.time, site: site))")) }
        }
        for e in Events.eclipses(after: w.start.addingTimeInterval(-6 * 3600), site: site, withinDays: 2) where e.kind == .lunarEclipse && inWindow(e.time) {
            if Ephemeris.moon(at: e.time, site: site).position.altDeg >= highlightLowDeg {
                events.append((e.time, "\(e.title), peak \(Copy.hhmm(e.time, site: site))"))
            }
        }
        for e in Events.conjunctions(at: w.midpoint, site: site, maxSeparationDeg: 3) {
            guard let ra = e.raHours, let dec = e.decDeg else { continue }
            let top = Events.highest(raHours: ra, decDeg: dec, from: w.start, to: w.end, site: site)
            if top.clear, top.alt >= highlightLowDeg { events.append((top.time, "\(e.title), best \(Copy.hhmm(top.time, site: site))")) }
        }
        // Kept by the stores only when seen in darkness above the Moon's floor, raised by the site's horizon.
        for e in occultations where inWindow(e.when) && !e.behindHorizon {
            events.append((e.when, "\(e.title), \(Copy.hhmm(e.when, site: site))"))
        }
        var out = events.sorted { $0.time < $1.time }.prefix(highlightEvents).map(\.text)

        // A bright night's targets are the Moon and planets, there every night: its events are its highlights.
        guard p.mode != .bright else { return out }
        let wanted = min(highlightLimit - out.count, max(1, Int(w.hours / highlightStackHours)))
        let picks = SessionPlanner.suggestions(anchors: [], plan: p, excluding: [], window: w, brightest: true).prefix(wanted)
            .sorted { $0.peakTime < $1.peakTime }
        out += picks.map { t in
            let name = t.commonName.map { $0 == t.catalogueID || t.catalogueID.isEmpty ? $0 : "\($0) (\(t.catalogueID))" } ?? t.catalogueID
            return "\(name), best \(Copy.hhmm(t.peakTime, site: site))"
        }
        return out
    }
}

extension Copy {
    /// "Highlights: Geminids at peak, best 02:00 · Triangulum Galaxy (M33), best 21:00"; nil with nothing to name.
    public static func weekHighlights(_ n: WeekNight) -> String? {
        n.highlights.isEmpty ? nil : "Highlights: " + n.highlights.joined(separator: " · ")
    }
}
