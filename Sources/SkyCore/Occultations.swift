import Foundation
import CAstronomyEngine

/// One star or planet going behind the Moon: when it disappears and reappears, and at which edge of the Moon.
public struct OccultationContact: Codable, Equatable, Sendable {
    public let name: String
    public let disappears: Date
    public let reappears: Date
    /// True at the Moon's sunlit edge; false at its dark edge, where the star snaps out of view.
    public let disappearsAtLitEdge: Bool
    public let reappearsAtLitEdge: Bool
    /// The star's height when it disappears.
    public let altDeg: Double
}

/// The Moon passing in front of a planet, a bright star or the Pleiades, as seen from one site (#115, owner-approved
/// mock-up, 2 October 2026: "I'd like to see Saturn or the Pleiades going behind the Moon").
public struct Occultation: Codable, Equatable, Sendable {
    /// "pleiades", "planet-saturn" or a bright star's ID.
    public let id: String
    /// "the Pleiades", "Saturn", "Regulus".
    public let object: String
    public let contacts: [OccultationContact]
    public let moonIllumination: Double
    public let moonAltDeg: Double
    public let moonAzDeg: Double
    public var start: Date { contacts.map(\.disappears).min() ?? .distantPast }
    public var end: Date { contacts.map(\.reappears).max() ?? .distantPast }
}

public enum Occultations {
    /// The six brightest Pleiades, J2000 (Hipparcos): a pass across the cluster shows as these going behind one by one.
    static let pleiades: [(name: String, ra: Double, dec: Double)] = [
        ("Alcyone", 3.791411, 24.105139), ("Atlas", 3.819361, 24.053361), ("Electra", 3.747917, 24.113333),
        ("Maia", 3.763778, 24.367778), ("Merope", 3.772111, 23.948333), ("Taygeta", 3.753472, 24.467222),
    ]
    /// Planets worth watching: Uranus and Neptune are not naked-eye objects.
    static let planets: [Planet] = [.mercury, .venus, .mars, .jupiter, .saturn]

    struct Body { let group: String; let object: String; let name: String; let planet: Planet?; let ra: Double; let dec: Double }

    static func bodies(stars: [BrightStar]) -> [Body] {
        pleiades.map { Body(group: "pleiades", object: "the Pleiades", name: $0.name, planet: nil, ra: $0.ra, dec: $0.dec) }
            // The Moon never strays more than about 6.5° from the ecliptic, parallax included, so only stars near it can be covered.
            + stars.filter { abs(eclipticLatitude(ra: $0.raHours, dec: $0.decDeg)) < 7 }
                .map { Body(group: $0.id, object: $0.name, name: $0.name, planet: nil, ra: $0.raHours, dec: $0.decDeg) }
            + planets.map { Body(group: "planet-\($0.rawValue)", object: $0.displayName, name: $0.displayName, planet: $0, ra: 0, dec: 0) }
    }

    /// Every occultation seen from `site` in darkness (the Sun 6° or more down) with the object at least `minAlt` up,
    /// raised by the site's horizon, between `from` and `days` later. Ten-minute steps find each close pass; each one is
    /// then searched every 15 seconds and its edges refined to a second.
    public static func find(from: Date, days: Int, site: Site, stars: [BrightStar], minAlt: Double = 10) -> [Occultation] {
        let obs = Astronomy_MakeObserver(site.latitude, site.longitude, site.elevationM)
        let list = bodies(stars: stars)
        var nextLook: [Int: Date] = [:]
        var contacts: [(body: Body, contact: OccultationContact)] = []
        var t = from
        let end = from.addingTimeInterval(Double(days) * 86_400)
        while t < end {
            let moon = equatorial(BODY_MOON, t, obs)
            let radius = moonRadius(moon.dist)
            for (i, b) in list.enumerated() where (nextLook[i] ?? .distantPast) <= t {
                let p = position(b, t, obs)
                guard separation(moon.ra, moon.dec, p.ra, p.dec) < radius + 0.3 else { continue }
                nextLook[i] = t.addingTimeInterval(3 * 3600)
                if let c = contact(b, near: t, obs: obs, site: site, minAlt: minAlt) { contacts.append((b, c)) }
            }
            t = t.addingTimeInterval(600)
        }
        // One event per object per pass: the Pleiades' stars within a few hours of each other belong together.
        var out: [Occultation] = []
        for (b, c) in contacts.sorted(by: { $0.contact.disappears < $1.contact.disappears }) {
            if let last = out.last, last.id == b.group, c.disappears.timeIntervalSince(last.end) < 3 * 3600 {
                out[out.count - 1] = Occultation(id: last.id, object: last.object, contacts: last.contacts + [c],
                                                 moonIllumination: last.moonIllumination, moonAltDeg: last.moonAltDeg, moonAzDeg: last.moonAzDeg)
            } else {
                var tt = astro_time_t(c.disappears)
                let ill = Astronomy_Illumination(BODY_MOON, tt).phase_fraction
                let m = equatorial(BODY_MOON, c.disappears, obs)
                let (alt, az) = Ephemeris.altAz(raHours: m.ra, decDeg: m.dec, at: c.disappears, site: site)
                _ = tt
                out.append(Occultation(id: b.group, object: b.object, contacts: [c], moonIllumination: ill, moonAltDeg: alt, moonAzDeg: az))
            }
        }
        return out
    }

    /// The pass starting near `t`: in and out times to the second, kept when either end is seen in darkness above the floor.
    static func contact(_ b: Body, near t: Date, obs: astro_observer_t, site: Site, minAlt: Double) -> OccultationContact? {
        func inside(_ d: Date) -> Bool {
            let m = equatorial(BODY_MOON, d, obs), p = position(b, d, obs)
            return separation(m.ra, m.dec, p.ra, p.dec) < moonRadius(m.dist)
        }
        var d = t.addingTimeInterval(-5400), was = inside(d)
        var times: [Date] = []
        // Up to four hours on: a central pass behind the full disc lasts over an hour, after an ingress up to an hour away.
        while d < t.addingTimeInterval(4 * 3600), times.count < 2 {
            let next = d.addingTimeInterval(15)
            let now = inside(next)
            if now != was {
                var lo = d, hi = next
                for _ in 0..<5 { let mid = lo.addingTimeInterval(hi.timeIntervalSince(lo) / 2); if inside(mid) == now { hi = mid } else { lo = mid } }
                if now { times = [hi] } else if !times.isEmpty { times.append(hi) }
                was = now
            }
            d = next
        }
        guard times.count == 2 else { return nil }
        func seen(_ at: Date) -> Bool {
            let p = position(b, at, obs)
            let (alt, az) = Ephemeris.altAz(raHours: p.ra, decDeg: p.dec, at: at, site: site)
            return Ephemeris.sunAltitude(at: at, site: site) <= -6 && alt >= site.floorDeg(azimuthDeg: az, minAlt: minAlt)
        }
        guard seen(times[0]) || seen(times[1]) else { return nil }
        let p = position(b, times[0], obs)
        return OccultationContact(name: b.name, disappears: times[0], reappears: times[1],
                                  disappearsAtLitEdge: litEdge(b, times[0], obs), reappearsAtLitEdge: litEdge(b, times[1], obs),
                                  altDeg: Ephemeris.altAz(raHours: p.ra, decDeg: p.dec, at: times[0], site: site).alt)
    }

    /// Whether the object meets the Moon on its sunlit half: the edge it touches lies within 90° of the direction of the Sun.
    static func litEdge(_ b: Body, _ t: Date, _ obs: astro_observer_t) -> Bool {
        let m = equatorial(BODY_MOON, t, obs), s = equatorial(BODY_SUN, t, obs), p = position(b, t, obs)
        var d = abs(positionAngle(m.ra, m.dec, p.ra, p.dec) - positionAngle(m.ra, m.dec, s.ra, s.dec)).truncatingRemainder(dividingBy: 360)
        if d > 180 { d = 360 - d }
        return d < 90
    }

    // MARK: geometry

    static func equatorial(_ body: astro_body_t, _ d: Date, _ obs: astro_observer_t) -> (ra: Double, dec: Double, dist: Double) {
        var t = astro_time_t(d)
        let e = Astronomy_Equator(body, &t, obs, EQUATOR_J2000, NO_ABERRATION)
        return (e.ra, e.dec, e.dist)
    }

    static func position(_ b: Body, _ d: Date, _ obs: astro_observer_t) -> (ra: Double, dec: Double) {
        guard let p = b.planet else { return (b.ra, b.dec) }
        let e = equatorial(p.body, d, obs)
        return (e.ra, e.dec)
    }

    /// The Moon's angular radius, from its distance in AU.
    static func moonRadius(_ distAU: Double) -> Double { asin(1737.4 / (distAU * 149_597_870.7)) * 180 / .pi }

    static func separation(_ ra1: Double, _ dec1: Double, _ ra2: Double, _ dec2: Double) -> Double {
        let a = ra1 * 15 * .pi / 180, b = dec1 * .pi / 180, c = ra2 * 15 * .pi / 180, d = dec2 * .pi / 180
        return acos(min(1, max(-1, sin(b) * sin(d) + cos(b) * cos(d) * cos(a - c)))) * 180 / .pi
    }

    /// The direction from the first position to the second, degrees from north through east.
    static func positionAngle(_ ra1: Double, _ dec1: Double, _ ra2: Double, _ dec2: Double) -> Double {
        let da = (ra2 - ra1) * 15 * .pi / 180, d1 = dec1 * .pi / 180, d2 = dec2 * .pi / 180
        return atan2(sin(da), cos(d1) * tan(d2) - sin(d1) * cos(da)) * 180 / .pi
    }

    /// Ecliptic latitude (J2000 obliquity), to skip stars the Moon can never reach.
    static func eclipticLatitude(ra: Double, dec: Double) -> Double {
        let e = 23.4392911 * Double.pi / 180, a = ra * 15 * .pi / 180, d = dec * .pi / 180
        return asin(sin(d) * cos(e) - cos(d) * sin(e) * sin(a)) * 180 / .pi
    }
}

extension Occultations {
    /// Which way the Moon's sunlit edge faces at the first contact, in degrees from north through east: the direction of the
    /// Sun from the Moon's centre. With `moonIllumination` it shades the drawing to the night's phase.
    public static func brightLimbDeg(_ o: Occultation, site: Site) -> Double {
        let obs = Astronomy_MakeObserver(site.latitude, site.longitude, site.elevationM)
        let m = equatorial(BODY_MOON, o.start, obs), s = equatorial(BODY_SUN, o.start, obs)
        return (positionAngle(m.ra, m.dec, s.ra, s.dec) + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Each covered star's path across the Moon for the event's drawing, in Moon radii from its centre: x east, y north,
    /// every two minutes from 20 minutes before it goes to 20 minutes after it comes back.
    public static func tracks(_ o: Occultation, site: Site, stars: [BrightStar]) -> [(name: String, points: [(x: Double, y: Double)])] {
        let obs = Astronomy_MakeObserver(site.latitude, site.longitude, site.elevationM)
        let list = bodies(stars: stars)
        return o.contacts.compactMap { c in
            guard let b = list.first(where: { $0.name == c.name }) else { return nil }
            var pts: [(x: Double, y: Double)] = []
            var t = c.disappears.addingTimeInterval(-1200)
            while t <= c.reappears.addingTimeInterval(1200) {
                let m = equatorial(BODY_MOON, t, obs), p = position(b, t, obs), r = moonRadius(m.dist)
                pts.append(((p.ra - m.ra) * 15 * cos(m.dec * .pi / 180) / r, (p.dec - m.dec) / r))
                t = t.addingTimeInterval(120)
            }
            return (c.name, pts)
        }
    }
}
