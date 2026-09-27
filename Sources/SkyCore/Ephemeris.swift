import CAstronomyEngine
import Foundation

/// When the Sun neither sets nor rises within 24 h of local noon, `sunset` and `sunrise` are not real
/// events: they bracket the local day (noon to noon + 24 h). Polar day has no darkness; polar night does.
public struct Night: Codable, Equatable, Sendable {
    public let key: String
    public let localDate: Date
    public let sunset: Date
    public let sunrise: Date
    public let darkStart: Date?
    public let darkEnd: Date?
    public var hasDarkness: Bool { darkStart != nil && darkEnd != nil }
    public var nauticalStart: Date? = nil
    public var nauticalEnd: Date? = nil
    public var hasNauticalDarkness: Bool { nauticalStart != nil && nauticalEnd != nil }
}

public enum Planet: String, CaseIterable, Codable, Sendable {
    case mercury, venus, mars, jupiter, saturn, uranus, neptune
    var body: astro_body_t {
        switch self {
        case .mercury: BODY_MERCURY
        case .venus: BODY_VENUS
        case .mars: BODY_MARS
        case .jupiter: BODY_JUPITER
        case .saturn: BODY_SATURN
        case .uranus: BODY_URANUS
        case .neptune: BODY_NEPTUNE
        }
    }
    public var displayName: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

public struct BodyPosition: Sendable, Equatable {
    public let raHours: Double
    public let decDeg: Double
    public let altDeg: Double
    public let azDeg: Double
    public let magnitude: Double?
}

public struct MoonState: Sendable, Equatable {
    public let illumination: Double
    public let position: BodyPosition
    public let rise: Date?
    public let set: Date?
}

public enum EclipseKind: String, Codable, Sendable { case penumbral, partial, annular, total }
public struct LunarEclipse: Sendable, Equatable {
    public let peak: Date; public let kind: EclipseKind; public let obscuration: Double
    /// The partial phase's start and end, or the penumbral phase's when there is no partial phase.
    public var begin: Date? = nil; public var end: Date? = nil
}
public struct SolarEclipse: Sendable, Equatable {
    public let peak: Date; public let kind: EclipseKind; public let obscuration: Double
    public let partialBegin: Date?; public let partialEnd: Date?
}

public enum EphemerisError: Error { case noSunEvent }

public enum Ephemeris {
    /// The Sun's descent below `altDeg` after `after` and its return above it, both before `before`; nil when either is missing.
    private static func sunCrossings(altDeg: Double, obs: astro_observer_t, after: astro_time_t, before: astro_time_t) -> (Date, Date)? {
        let down = Astronomy_SearchAltitude(BODY_SUN, obs, DIRECTION_SET, after, 1.0, altDeg)
        guard down.status == ASTRO_SUCCESS, down.time.ut < before.ut else { return nil }
        let up = Astronomy_SearchAltitude(BODY_SUN, obs, DIRECTION_RISE, Astronomy_AddDays(down.time, afterCrossing), 1.0, altDeg)
        guard up.status == ASTRO_SUCCESS, up.time.ut <= before.ut + 1e-6 else { return nil }
        return (down.time.date, up.time.date)
    }

    /// Searching for the return crossing from the exact instant of the downward one can hand back that same
    /// instant when the Sun barely dips below the threshold (54° N at the June solstice gave a zero-length
    /// nautical night), so the rise search starts one minute later. A window shorter than a minute is therefore
    /// not reported, which costs nothing: a sub-minute dark window has no observing value.
    private static let afterCrossing = 1.0 / 1440

    /// The night that begins on the local calendar date containing `localDate` at `site`.
    /// The night Nightwatch plans for at `now`: the one in progress until its sunrise, then the coming evening's (v1.0.1).
    /// The earlier rule, the night of the calendar day nine hours before, kept a finished night on show until 09:00, with
    /// its hours already gone from the forecast (seen in the App Review recording, 27 September 2026).
    public static func currentNight(now: Date, site: Site) throws -> Night {
        let previous = try night(localDate: site.calendar.date(byAdding: .day, value: -1, to: now)!, site: site)
        return now < previous.sunrise ? previous : try night(localDate: now, site: site)
    }

    public static func night(localDate: Date, site: Site) throws -> Night {
        let cal = site.calendar
        let noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: localDate)!
        let obs = site.observer
        let f = DateFormatter()
        f.calendar = cal; f.timeZone = site.timeZone; f.dateFormat = "yyyy-MM-dd"
        let key = f.string(from: noon)
        let sunset = Astronomy_SearchRiseSetEx(BODY_SUN, obs, DIRECTION_SET, astro_time_t(noon), 1.0, 0)
        guard sunset.status == ASTRO_SUCCESS else {
            let end = noon.addingTimeInterval(86_400)
            guard sunAltitude(at: noon, site: site) < 0 else {
                // Polar day: the sun does not set within 24h of local noon, so there is no night.
                return Night(key: key, localDate: noon, sunset: noon, sunrise: end, darkStart: nil, darkEnd: nil, nauticalStart: nil, nauticalEnd: nil)
            }
            // Polar night: the Sun stays down all day. Darkness is the stretch below −18°; near the pole the Sun
            // never climbs to −18° and the whole span is dark. (At Tromsø's latitude noon is still twilight.)
            let ds = Astronomy_SearchAltitude(BODY_SUN, obs, DIRECTION_SET, astro_time_t(noon), 1.0, -18)
            let de = ds.status == ASTRO_SUCCESS ? Astronomy_SearchAltitude(BODY_SUN, obs, DIRECTION_RISE, Astronomy_AddDays(ds.time, afterCrossing), 1.0, -18) : ds
            let found = ds.status == ASTRO_SUCCESS && de.status == ASTRO_SUCCESS && de.time.date <= end
            let n12 = Astronomy_SearchAltitude(BODY_SUN, obs, DIRECTION_SET, astro_time_t(noon), 1.0, -12)
            let n12e = n12.status == ASTRO_SUCCESS ? Astronomy_SearchAltitude(BODY_SUN, obs, DIRECTION_RISE, Astronomy_AddDays(n12.time, afterCrossing), 1.0, -12) : n12
            let foundN = n12.status == ASTRO_SUCCESS && n12e.status == ASTRO_SUCCESS && n12e.time.date <= end
            return Night(key: key, localDate: noon, sunset: noon, sunrise: end,
                         darkStart: found ? ds.time.date : noon, darkEnd: found ? de.time.date : end,
                         nauticalStart: foundN ? n12.time.date : noon, nauticalEnd: foundN ? n12e.time.date : end)
        }
        let sunrise = Astronomy_SearchRiseSetEx(BODY_SUN, obs, DIRECTION_RISE, sunset.time, 1.0, 0)
        guard sunrise.status == ASTRO_SUCCESS else { throw EphemerisError.noSunEvent }
        let dark = sunCrossings(altDeg: -18, obs: obs, after: sunset.time, before: sunrise.time)
        let nautical = sunCrossings(altDeg: -12, obs: obs, after: sunset.time, before: sunrise.time)
        return Night(key: key, localDate: noon, sunset: sunset.time.date, sunrise: sunrise.time.date,
                     darkStart: dark?.0, darkEnd: dark?.1, nauticalStart: nautical?.0, nauticalEnd: nautical?.1)
    }

    /// Altitude and azimuth of a J2000 RA/Dec. Catalogue coordinates are J2000; precession to date is ignored
    /// (ponytail: under 0.4 degrees in 2026, irrelevant for a 30 degree altitude floor).
    public static func altAz(raHours: Double, decDeg: Double, at date: Date, site: Site) -> (alt: Double, az: Double) {
        var t = astro_time_t(date)
        let h = Astronomy_Horizon(&t, site.observer, raHours, decDeg, REFRACTION_NORMAL)
        return (h.altitude, h.azimuth)
    }

    public static func position(of body: astro_body_t, at date: Date, site: Site) -> BodyPosition {
        var t = astro_time_t(date)
        let eq = Astronomy_Equator(body, &t, site.observer, EQUATOR_OF_DATE, ABERRATION)
        let h = Astronomy_Horizon(&t, site.observer, eq.ra, eq.dec, REFRACTION_NORMAL)
        let ill = Astronomy_Illumination(body, t)
        return BodyPosition(raHours: eq.ra, decDeg: eq.dec, altDeg: h.altitude, azDeg: h.azimuth,
                            magnitude: ill.status == ASTRO_SUCCESS ? ill.mag : nil)
    }

    public static func planet(_ p: Planet, at date: Date, site: Site) -> BodyPosition {
        position(of: p.body, at: date, site: site)
    }

    public static func moon(at date: Date, site: Site) -> MoonState {
        let t = astro_time_t(date)
        let ill = Astronomy_Illumination(BODY_MOON, t)
        let pos = position(of: BODY_MOON, at: date, site: site)
        let start = Astronomy_AddDays(t, -0.5)
        let rise = Astronomy_SearchRiseSetEx(BODY_MOON, site.observer, DIRECTION_RISE, start, 1.5, 0)
        let set = Astronomy_SearchRiseSetEx(BODY_MOON, site.observer, DIRECTION_SET, start, 1.5, 0)
        return MoonState(illumination: ill.phase_fraction, position: pos,
                         rise: rise.status == ASTRO_SUCCESS ? rise.time.date : nil,
                         set: set.status == ASTRO_SUCCESS ? set.time.date : nil)
    }

    public static func sunAltitude(at date: Date, site: Site) -> Double {
        position(of: BODY_SUN, at: date, site: site).altDeg
    }

    public static func separationDeg(ra1Hours: Double, dec1Deg: Double, ra2Hours: Double, dec2Deg: Double) -> Double {
        let d2r = Double.pi / 180
        let a1 = ra1Hours * 15 * d2r, a2 = ra2Hours * 15 * d2r
        let d1 = dec1Deg * d2r, d2 = dec2Deg * d2r
        let s = sin((d2 - d1) / 2), c = sin((a2 - a1) / 2)
        let h = s * s + cos(d1) * cos(d2) * c * c
        return 2 * asin(min(1, sqrt(h))) / d2r
    }

    public static func constellation(raHours: Double, decDeg: Double) -> (symbol: String, name: String) {
        let c = Astronomy_Constellation(raHours, decDeg)
        guard c.status == ASTRO_SUCCESS, let s = c.symbol, let n = c.name else { return ("", "") }
        return (String(cString: s), String(cString: n))
    }

    public static func nextLunarEclipse(after date: Date) -> LunarEclipse? {
        let e = Astronomy_SearchLunarEclipse(astro_time_t(date))
        guard e.status == ASTRO_SUCCESS, let kind = eclipseKind(e.kind) else { return nil }
        let semi = (e.sd_partial > 0 ? e.sd_partial : e.sd_penum) * 60
        return LunarEclipse(peak: e.peak.date, kind: kind, obscuration: e.obscuration,
                            begin: e.peak.date.addingTimeInterval(-semi), end: e.peak.date.addingTimeInterval(semi))
    }

    public static func nextLocalSolarEclipse(after date: Date, site: Site) -> SolarEclipse? {
        let e = Astronomy_SearchLocalSolarEclipse(astro_time_t(date), site.observer)
        guard e.status == ASTRO_SUCCESS, let kind = eclipseKind(e.kind) else { return nil }
        // Local eclipse events are astro_eclipse_event_t { time, altitude }, peak included.
        return SolarEclipse(peak: e.peak.time.date, kind: kind, obscuration: e.obscuration,
                            partialBegin: e.partial_begin.time.date, partialEnd: e.partial_end.time.date)
    }

    private static func eclipseKind(_ k: astro_eclipse_kind_t) -> EclipseKind? {
        switch k {
        case ECLIPSE_PENUMBRAL: .penumbral
        case ECLIPSE_PARTIAL: .partial
        case ECLIPSE_ANNULAR: .annular
        case ECLIPSE_TOTAL: .total
        default: nil
        }
    }
}
