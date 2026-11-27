import CAstronomyEngine
import Foundation

/// Pluto, Ceres, and the Earth–Moon L4 and L5 points (#250: "A similar problem is Pluto, Ceres, etc.", and "the Lagrange objects";
/// owner, 25 November 2026). They sit in Planets and Moon as cards that can be searched, opened and given a heart, and are never the
/// popover's pick, a plan suggestion or a week highlight (`RankedTarget.isListedOnly`). Not `Planet` cases: a planet joins the
/// conjunctions and the bright-night list, and these must not.
public enum MinorBody: String, CaseIterable, Sendable {
    case pluto, ceres, l4, l5

    public var id: String { "minor-\(rawValue)" }
    public init?(targetID: String) {
        guard targetID.hasPrefix("minor-") else { return nil }
        self.init(rawValue: String(targetID.dropFirst(6)))
    }

    /// The card's title: "Pluto", "L4".
    public var title: String {
        switch self {
        case .pluto: "Pluto"
        case .ceres: "Ceres"
        case .l4: "L4"
        case .l5: "L5"
        }
    }
    public var isLagrangePoint: Bool { self == .l4 || self == .l5 }
    /// The card's second line for a Lagrange point; Pluto and Ceres show their kind.
    public var commonName: String? { isLagrangePoint ? L10n.text("Earth-Moon Lagrange point") : nil }
    public var typeName: String { isLagrangePoint ? L10n.text("Lagrange point") : L10n.text("Dwarf planet") }
    /// What the search reads: "L4 · Earth-Moon Lagrange point", so "L4" finds it as a catalogue number does.
    public var name: String { commonName.map { "\(title) · \($0)" } ?? title }
    /// Searched as well as the name: "Kordylewski" finds the two points, "dwarf planet" the two bodies.
    public var subtitle: String { isLagrangePoint ? L10n.text("Lagrange point · Kordylewski cloud") : L10n.text("Dwarf planet") }
    /// The photograph's name in `Resources/planets`; nil for a Lagrange point, where there is nothing to picture.
    public var imageName: String? { isLagrangePoint ? nil : rawValue }

    /// Ceres's orbit, from NASA JPL's Small-Body Database (orbit 48, epoch JD 2461200.5, 9 June 2026, perihelion JD 2461599.841466614; read 25 November 2026). Its brightness is
    /// worked out apart, in `ceresMagnitude`: the comets' formula has no phase term, and for Ceres that is most of a magnitude.
    /// shortcut: a two-body orbit, which drifts from the real one, so renew these about once a year (a test holds it to a quarter of a
    /// degree against JPL Horizons at one year from the epoch).
    static let ceresOrbit = CometElements(orbitType: "A", designation: "1 Ceres", q: 2.545159361382861, e: 0.07969229514816586,
                                          periDeg: 73.29421453021587, nodeDeg: 80.24862682043221, incDeg: 10.58802780183462,
                                          perihelionYear: 2027, perihelionMonth: 7, perihelionDay: 13.341466614066,
                                          epochYear: 2026, epochMonth: 6, epochDay: 9, h: 3.34, g: 2)
    /// JPL's absolute magnitude and slope for Ceres (H 3.34, G 0.12), in the IAU's H-G formula: H + 5 log(r·Δ), less the light lost
    /// to the phase angle between the Sun and the Earth as seen from Ceres. Within 0.1 magnitude of JPL Horizons (a test holds it).
    static func ceresMagnitude(rAU r: Double, deltaAU delta: Double, at date: Date) -> Double? {
        let earth = Astronomy_HelioVector(BODY_EARTH, astro_time_t(date))
        guard earth.status == ASTRO_SUCCESS else { return nil }
        let sunEarth = sqrt(earth.x * earth.x + earth.y * earth.y + earth.z * earth.z)
        let phase = acos(max(-1, min(1, (r * r + delta * delta - sunEarth * sunEarth) / (2 * r * delta))))
        let h = 3.34, g = 0.12, t = tan(phase / 2)
        let lost = (1 - g) * exp(-3.33 * pow(t, 0.63)) + g * exp(-1.87 * pow(t, 1.22))
        return h + 5 * log10(r * delta) - 2.5 * log10(lost)
    }

    /// A sixth of the Moon's orbit, in days: how far ahead of it L4 runs, and how far behind it L5 follows.
    static let sixthOfAMonth = 27.321661 / 6

    /// Where it is at `date`: right ascension in hours, declination in degrees, and its magnitude where it has one.
    public func place(at date: Date, site: Site) -> (raHours: Double, decDeg: Double, magnitude: Double?) {
        switch self {
        case .pluto:
            let p = Ephemeris.position(of: BODY_PLUTO, at: date, site: site)
            return (p.raHours, p.decDeg, p.magnitude)
        case .ceres:
            guard let p = Comets.position(Self.ceresOrbit, at: date) else { return (0, 0, nil) }
            return (p.raHours, p.decDeg, Self.ceresMagnitude(rAU: p.rAU, deltaAU: p.deltaAU, at: date))
        case .l4, .l5:
            // 60° ahead of the Moon in its orbit is where the Moon will be a sixth of an orbit on; 60° behind, where it was. The
            // Moon's orbit is not a circle, so this is right to a few degrees, against dust clouds claimed to be several degrees wide.
            let when = date.addingTimeInterval((self == .l4 ? 1 : -1) * Self.sixthOfAMonth * 86_400)
            let p = Ephemeris.position(of: BODY_MOON, at: when, site: site)
            return (p.raHours, p.decDeg, nil)
        }
    }

    /// The bodies a search matches, by the Targets grid's own rule.
    public static func matching(_ query: String) -> [MinorBody] {
        guard !query.allSatisfy(\.isWhitespace) else { return [] }
        return allCases.filter { b in
            var r = RankedTarget(id: b.id, name: b.name, subtitle: b.subtitle, group: .planets, raHours: 0, decDeg: 0, sizeArcmin: nil, magnitude: nil,
                                 fit: .small, peakAltDeg: 0, peakTime: Date(timeIntervalSince1970: 0), moonSepDeg: 90, moonWashed: false, visibleFraction: 0)
            r.typeName = b.typeName
            return r.matches(query)
        }
    }
}
