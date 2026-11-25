import Testing
import Foundation
@testable import SkyCore

// Pluto, Ceres and the Earth–Moon L4 and L5 points (#250; owner, 25 November 2026).
private let site = Site(name: "Test site", latitude: 54.0, longitude: -1.5, elevationM: 100, timeZoneID: "Europe/London", bortle: 4)
private let frame = FieldOfView(widthDeg: 2.1, heightDeg: 1.2)

/// Degrees between two places given as right ascension in degrees and declination.
private func apart(_ ra1: Double, _ dec1: Double, _ ra2: Double, _ dec2: Double) -> Double {
    Ephemeris.separationDeg(ra1Hours: ra1 / 15, dec1Deg: dec1, ra2Hours: ra2 / 15, dec2Deg: dec2)
}

// JPL Horizons, geocentric, astrometric (read 25 November 2026): right ascension and declination in degrees, and magnitude.
@Test func plutoAndCeresAreWhereJPLHorizonsPutsThem() {
    for (date, pluto, ceres) in [(utc(2026, 12, 1, 0, 0), (306.55086, -23.58014, 14.608), (116.01372, 26.00948, 7.641)),
                                 (utc(2027, 12, 1, 0, 0), (308.39021, -23.65694, 14.638), (205.65527, -1.95750, 8.805))] {
        let p = MinorBody.pluto.place(at: date, site: site)
        // Pluto's place is of date, as the planets' are: half a degree from J2000 by precession, well inside what a 30° floor needs.
        #expect(apart(p.raHours * 15, p.decDeg, pluto.0, pluto.1) < 0.6)
        #expect(abs((p.magnitude ?? 0) - pluto.2) < 0.4)
        let c = MinorBody.ceres.place(at: date, site: site)
        let off = apart(c.raHours * 15, c.decDeg, ceres.0, ceres.1)
        print("MINOR Ceres \(date): \(String(format: "%.3f", off))° from Horizons, magnitude \(String(format: "%.2f", c.magnitude ?? 0)) against \(ceres.2)")
        #expect(off < 0.25)   // a two-body orbit, a year and a half from its epoch
        #expect(abs((c.magnitude ?? 0) - ceres.2) < 0.1)   // the H-G formula, phase term included
    }
}

@Test func theLagrangePointsLeadAndFollowTheMoonBySixtyDegrees() {
    for day in stride(from: 0, to: 28, by: 3) {
        let date = utc(2026, 12, 1, 0, 0).addingTimeInterval(Double(day) * 86_400)
        let moon = Ephemeris.moon(at: date, site: site).position
        for body in [MinorBody.l4, .l5] {
            let p = body.place(at: date, site: site)
            let sep = apart(p.raHours * 15, p.decDeg, moon.raHours * 15, moon.decDeg)
            #expect(sep > 50 && sep < 70 && p.magnitude == nil, "\(body) \(day): \(sep)")
        }
        // L4 is ahead of the Moon (further east), L5 behind.
        let ahead = MinorBody.l4.place(at: date, site: site).raHours - moon.raHours
        #expect((ahead + 24).truncatingRemainder(dividingBy: 24) < 12)
    }
}

@Test func theyAreListedWhenUpAndNeverOffered() throws {
    // December 2026 from 54° north: Ceres is in Gemini, high all night.
    let night = try Ephemeris.night(localDate: utc(2026, 12, 2, 12, 0), site: site)
    let window = ClearWindow(start: try #require(night.darkStart), end: try #require(night.darkEnd))
    let ranked = Planner.rank(catalog: try Catalog.bundled(), constellations: try Constellations.bundled(), stars: try BrightStars.bundled(),
                              window: window, site: site, fov: frame, rule: GoRule())
    let ceres = try #require(ranked.first { $0.id == "minor-ceres" })
    #expect(ceres.group == .planets && ceres.catalogueID == "Ceres" && ceres.typeName == "Dwarf planet" && ceres.isListedOnly)
    #expect(!ranked.contains { $0.id == "minor-pluto" })   // 12° up at best from here
    #expect(!Planner.best(from: ranked).contains { $0.isListedOnly })
    // With only these in the planets group, the popover still does not pick one.
    #expect(Planner.best(from: ranked.filter { $0.id.hasPrefix("minor-") }).isEmpty)
    #expect(EyeViews.view(ceres, bortle: 4) == nil)
    #expect(ShootingTips.planKit(ceres, presetID: "dwarf-mini") == nil)
    let tip = ShootingTips.tip(for: ceres, presetID: "dwarf-mini", presetName: "DwarfLab DWARF Mini", stackMinutes: 120, site: site)
    #expect(tip.rows.first { $0.label == "Proof" }?.text == "Shoot the same field on two nights: it is the point that has moved." && tip.copyLine == nil)
    // Tonight's plan never suggests one, however empty the night.
    let plan = NightPlan(night: night, windows: [window], primary: window, score: 80, qualifies: true, moonIllumination: 0.3, moonRise: nil, moonSet: nil,
                         darkHours: [], targets: ranked.filter { $0.group == .planets }, best: [], seeingAvailable: false)
    #expect(!SessionPlanner.suggestions(anchors: [], plan: plan, excluding: [], window: window).contains { $0.isListedOnly })
    #expect(!Planner.highlights(plan: plan, site: site, fov: frame).contains { $0.contains("Ceres") || $0.contains("L4") || $0.contains("L5") })
}

@Test func aSearchFindsEachWhetherOrNotItIsUp() throws {
    #expect(MinorBody.matching("Pluto") == [.pluto] && MinorBody.matching("ceres") == [.ceres])
    #expect(MinorBody.matching("L4") == [.l4] && MinorBody.matching("l 5") == [.l5])
    #expect(MinorBody.matching("lagrange") == [.l4, .l5] && MinorBody.matching("Kordylewski") == [.l4, .l5])
    #expect(MinorBody.matching("dwarf planet") == [.pluto, .ceres] && MinorBody.matching("  ").isEmpty && MinorBody.matching("M31").isEmpty)
    let night = try Ephemeris.night(localDate: utc(2026, 12, 2, 12, 0), site: site)
    let plan = NightPlan(night: night, windows: [], primary: nil, score: 10, qualifies: false, moonIllumination: 0.3, moonRise: nil, moonSet: nil,
                         darkHours: [], targets: [], best: [], seeingAvailable: false)
    let extras = SearchExtras()
    func cards(_ q: String, _ g: TargetGroup = .planets) throws -> [FavouriteTarget] {
        extras.cards(query: q, group: g, ranked: [], catalog: try Catalog.bundled(), plan: plan, site: site, fov: frame, rule: GoRule())
    }
    // Pluto reaches 12° from 54° north: listed by the search, greyed, and honest about it.
    let pluto = try #require(try cards("Pluto").first)
    #expect(pluto.target.id == "minor-pluto" && pluto.notTonight == "Never clears 30° from here")
    #expect(try cards("Pluto", .nebulae).isEmpty)
    // Ceres is up that night: an ordinary card.
    #expect(try cards("Ceres").first?.notTonight == nil)
    // A Lagrange point is either up tonight or greyed with a night within two months.
    let l4 = try #require(try cards("L4").first)
    #expect(l4.target.catalogueID == "L4" && l4.target.commonName == "Earth-Moon Lagrange point")
    #expect(l4.notTonight == nil || l4.notTonight?.hasPrefix("Next well placed from ") == true)
    #expect(Copy.nextWellPlaced(nil, decDeg: nil, site: site, minAlt: 30, span: "two months") == "Not well placed from here in the coming two months")
    // The hint counts them in Planets and Moon from any other group.
    let groups = extras.unlistedGroups(query: "Pluto", ranked: [], catalog: try Catalog.bundled(), nightKey: night.key)
    #expect(groups == [.planets])
    #expect(Copy.searchHint(query: "Pluto", targets: [], group: .nebulae, fitsOnly: false, includeMoonWashed: false, notPlanned: groups)
            == "No match for “Pluto” in Nebulae tonight. Also in Planets and Moon (1).")
    // A favourite survives: the id is one the planner knows.
    #expect(MinorBody(targetID: "minor-l5") == .l5 && MinorBody(targetID: "planet-mars") == nil)
    #expect(PlanetImages.name(forTargetID: "minor-pluto") == "pluto" && PlanetImages.url(named: "ceres") != nil && PlanetImages.name(forTargetID: "minor-l4") == nil)
    #expect(PlanetImages.name(forTargetID: "planet-mars") == "mars")
}
