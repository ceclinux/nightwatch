import Foundation

/// The Eyes and binoculars group (#63, owner-approved mock-up, 29 September 2026): what can be seen tonight without a
/// telescope, for someone with a camera and lens, binoculars or a first telescope.
public enum EyeView: String, Sendable { case nakedEye = "Naked eye", binoculars = "Binoculars" }

public enum EyeViews {
    /// The faintest star the eye sees at each Bortle class (the scale's own naked-eye limiting magnitudes).
    static let nakedEyeLimit: [Int: Double] = [1: 7.6, 2: 7.1, 3: 6.6, 4: 6.1, 5: 5.6, 6: 5.1, 7: 4.6, 8: 4.1, 9: 4.0]
    /// Sky brightness in mag/arcsec² at each class: the middle of the meter ranges commonly paired with the scale (Wikipedia's
    /// Bortle scale table, a secondary source; class 8 is "under 18", class 9 is not given, so 17.75 and 17.5 are ours).
    static let skyBrightness: [Int: Double] = [1: 21.88, 2: 21.68, 3: 21.45, 4: 21.05, 5: 19.78, 6: 18.88, 7: 18.25, 8: 17.75, 9: 17.5]
    /// How much fainter than the sky, in mag/arcsec², an extended object may be and still show. Binoculars: the literature's
    /// rule of thumb of 5% of the sky's brightness, 3.25 (Torres Lapasio, "On the Prediction of Visibility for Deep-Sky
    /// Objects"). The naked eye: 2.6, set on the catalogue's own rows so that at Bortle 5 M31 (22.30) and M42 (21.96) show
    /// while M33 (22.81), which the Bortle scale calls undetectable by eye in class 5, and NGC 7000 (22.83) do not.
    static let nakedEyeMargin = 2.6, binocularMargin = 3.25
    /// An emission nebula (OpenNGC "HII") shines mostly in hydrogen-alpha red, which the dark-adapted eye barely sees, and the
    /// catalogue gives only its blue magnitude; binoculars show one only this bright (our threshold, not a published one:
    /// it keeps NGC 7000 and drops the Crescent, NGC 6888, which needs a filter).
    static let emissionBinocularLimit = 6.0
    /// Binoculars reach about magnitude 8, and an object under 5′ is a point rather than something to see.
    static let binocularLimit = 8.0, binocularMinArcmin = 5.0

    /// Mean surface brightness in mag/arcsec²: the light spread over the ellipse a × b (Torres Lapasio, Eq. 1, with 8.89
    /// converting mag/arcmin² to mag/arcsec²). A target without a short axis is taken as round.
    public static func surfaceBrightness(magnitude m: Double, majorArcmin a: Double, minorArcmin b: Double?) -> Double {
        m + 2.5 * log10(Double.pi / 4 * a * (b ?? a)) + 8.89
    }

    /// How `t` can be seen from a sky of `bortle`, or nil when it needs a telescope. The Moon always; planets by brightness.
    /// Nebulae and galaxies by their surface brightness against the sky, since a large faint object spreads its light too
    /// thin to see whatever its total magnitude. Star clusters by total magnitude, since their stars show one by one.
    /// Left out: deep sky the Moon washes out tonight, supernova remnants (the Veil needs an O-III filter), and stars and
    /// constellations, every one of which is a naked-eye sight, so listing them would bury the rest.
    public static func view(_ t: RankedTarget, bortle: Int) -> EyeView? {
        let b = min(9, max(1, bortle)), limit = nakedEyeLimit[b]!, sky = skyBrightness[b]!
        if t.id == "moon" { return .nakedEye }
        guard let m = t.magnitude else { return nil }
        switch t.group {
        case .planets:
            return m <= limit ? .nakedEye : (m <= binocularLimit ? .binoculars : nil)
        case .clusters where t.typeName != "Cluster with nebula":
            guard !t.moonWashed else { return nil }
            if m <= limit { return .nakedEye }
            return m <= binocularLimit && (t.sizeArcmin ?? 0) >= binocularMinArcmin ? .binoculars : nil
        case .nebulae, .galaxies, .clusters:
            guard !t.moonWashed, t.typeName != "Supernova remnant", let a = t.sizeArcmin, a > 0 else { return nil }
            let sb = surfaceBrightness(magnitude: m, majorArcmin: a, minorArcmin: t.minorArcmin)
            if m <= limit, sb <= sky + nakedEyeMargin { return .nakedEye }
            let faintest = t.subtitle.hasPrefix("HII ") ? emissionBinocularLimit : binocularLimit
            return m <= faintest && a >= binocularMinArcmin && sb <= sky + binocularMargin ? .binoculars : nil
        default:
            return nil
        }
    }

    /// Events anyone can watch without a telescope: meteors, the space station, conjunctions, a lunar eclipse. Comets are
    /// left out (their brightness is not known here) and a solar eclipse is never suggested for the eye.
    /// A conjunction with Uranus or Neptune is left out: neither is a naked-eye planet.
    public static func includes(_ e: SkyEvent) -> Bool {
        if e.kind == .conjunction { return !["Uranus", "Neptune"].contains { e.title.contains($0) } }
        return [.meteorShower, .issPass, .lunarEclipse].contains(e.kind)
    }
}

extension Copy {
    /// What it looks like, not how to photograph it: "A faint smudge to the eye", "A fuzzy ball in binoculars".
    public static func eyeLook(_ t: RankedTarget, _ v: EyeView) -> String {
        let eye = v == .nakedEye
        if t.id == "moon" { return "Its seas to the eye; craters along the shadow line in binoculars" }
        switch t.group {
        case .planets: return eye ? "A bright star that does not twinkle" : "A small steady point in binoculars"
        case .galaxies: return eye ? "A faint smudge to the eye" : "A small oval glow in binoculars"
        case .clusters where t.typeName == "Globular cluster": return eye ? "A fuzzy star to the eye" : "A fuzzy ball in binoculars"
        case .clusters: return eye ? "A misty patch to the eye" : "A spray of stars in binoculars"
        default: return eye ? "A misty glow to the eye" : "A small grey patch in binoculars"
        }
    }
}
