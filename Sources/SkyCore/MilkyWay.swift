import Foundation

/// The Milky Way for a camera and wide lens (#114, owner-approved mock-up, 2 October 2026): its core in Sagittarius, and the
/// band through Cygnus, which is the view from Britain, where the core never clears the hills.
public enum MilkyWay {
    /// A landscape target, shot low over the horizon, so 10° raised by the site's horizon rather than the go rule's height,
    /// which is meant for deep-sky imaging (owner: "use 10°").
    public static let floorDeg = 10.0
    static let coreRA = 17.7611, coreDec = -29.0078       // Sagittarius A*
    static let cygnusRA = 20.3705, cygnusDec = 40.2567    // Sadr, γ Cyg, in the middle of the Cygnus band
    /// About 40° of sky in the picture, from the survey that the rest of the app shows.
    static let sizeArcmin = 1600.0

    public static func isMilkyWay(_ id: String) -> Bool { id.hasPrefix("milky-way-") }

    /// The core and the Cygnus band, each tracked across `window` against the floor; the caller lists those with a viewable
    /// span. `moonWashed`: a Moon bright enough to drown the band is up.
    public static func targets(window: ClearWindow, site: Site, moonWashed: Bool) -> [RankedTarget] {
        func make(_ id: String, _ name: String, card: String, subtitle: String, ra: Double, dec: Double) -> RankedTarget {
            let tr = Planner.track(raHours: ra, decDeg: dec, window: window, site: site, minAlt: floorDeg)
            return Planner.described(RankedTarget(id: id, name: name, subtitle: subtitle, group: .nebulae, raHours: ra, decDeg: dec,
                                                  sizeArcmin: sizeArcmin, magnitude: nil, fit: .mosaic, peakAltDeg: tr.peakAlt,
                                                  peakTime: tr.peakTime, moonSepDeg: 90, moonWashed: moonWashed, visibleFraction: tr.fraction),
                                     viewable: tr.viewable, site: site, typeName: L10n.text("Milky Way"), catalogueID: card)
        }
        return [make("milky-way-core", L10n.text("The Milky Way's core"), card: L10n.text("The Milky Way's core"), subtitle: L10n.text("Galactic centre in Sgr"),
                     ra: coreRA, dec: coreDec),
                make("milky-way-cygnus", site.latitude >= 0 ? L10n.text("The summer Milky Way through Cygnus") : L10n.text("The Milky Way through Cygnus"),
                     card: L10n.text("The Milky Way in Cygnus"), subtitle: L10n.text("Milky Way in Cyg"), ra: cygnusRA, dec: cygnusDec)]
    }

    /// Why the core is missing from a site where it never clears the floor on any night, for its card, shown dimmed in its
    /// season (May to August) so people know why (owner: "show it dimmed"). Nil where it does clear it, and out of season.
    public static func coreNeverClears(site: Site, on date: Date) -> String? {
        guard (5...8).contains(site.calendar.component(.month, from: date)) else { return nil }
        let top = 90 - abs(site.latitude - coreDec)   // at its highest, due south (or north, south of 29° S)
        let south = site.latitude > coreDec
        guard top < site.floorDeg(azimuthDeg: south ? 180 : 0, minAlt: floorDeg) else { return nil }
        if top < 0.5 { return L10n.text("Never rises from here. It climbs higher further south: about 21° at 40° N, 31° at 30° N.") }
        if top < floorDeg {
            return L10n.format("Never above \(Int(top.rounded()))° from here: too low even for a landscape shot, which needs it about 10° up. ")
                + L10n.text("It climbs higher further south: about 21° at 40° N, 31° at 30° N.")
        }
        return L10n.format("Never clears your horizon from here: at its highest it is \(Int(top.rounded()))° up, behind your horizon in the \(south ? L10n.text("south") : L10n.text("north")).")
    }
}
