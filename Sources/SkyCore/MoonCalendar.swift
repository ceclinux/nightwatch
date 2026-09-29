import Foundation
import CAstronomyEngine

/// The next run of moonless nights (#62, owner-approved mock-up, 29 September 2026): hobbyists plan around the new Moon.
public struct MoonlessRun: Equatable, Sendable {
    public let first: Night
    public let last: Night
    /// The new Moon nearest the run; nil if Astronomy Engine finds none within its search.
    public let newMoon: Date?
    /// The run has already begun: tonight is moonless.
    public let includesTonight: Bool
}

public enum MoonCalendar {
    /// A night is moonless when it has astronomical darkness and the Moon is under 10% lit at its middle, or below the
    /// horizon throughout it (sampled every 30 minutes). No darkness (a British midsummer) is never moonless.
    public static func isMoonless(_ n: Night, site: Site) -> Bool {
        guard let ds = n.darkStart, let de = n.darkEnd, de > ds else { return false }
        if Ephemeris.moon(at: ds.addingTimeInterval(de.timeIntervalSince(ds) / 2), site: site).illumination < 0.10 { return true }
        var t = ds
        while t <= de {
            if Ephemeris.position(of: BODY_MOON, at: t, site: site).altDeg > 0 { return false }
            t = t.addingTimeInterval(1800)
        }
        return true
    }

    /// The first run of moonless nights from `tonight` on, looking up to `days` nights ahead; nil when there is none in reach.
    public static func nextRun(from tonight: Night, site: Site, days: Int = 60) -> MoonlessRun? {
        let cal = site.calendar
        func night(_ i: Int) -> Night? {
            i == 0 ? tonight : (try? Ephemeris.night(localDate: cal.date(byAdding: .day, value: i, to: tonight.localDate)!, site: site))
        }
        var i = 0
        while i < days, let n = night(i), !isMoonless(n, site: site) { i += 1 }
        guard i < days, let first = night(i) else { return nil }
        var last = first, j = i + 1
        while j < days + 30, let n = night(j), isMoonless(n, site: site) { last = n; j += 1 }
        let search = Astronomy_SearchMoonPhase(0, astro_time_t(first.localDate.addingTimeInterval(-15 * 86_400)), 30)
        let newMoon = search.status == ASTRO_SUCCESS ? search.time.date : nil
        return MoonlessRun(first: first, last: last, newMoon: newMoon, includesTonight: i == 0)
    }
}
