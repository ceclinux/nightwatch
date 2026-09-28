import Testing
import Foundation
@testable import SkyCore

private let dwarfMini = FieldOfView(widthDeg: 2.1, heightDeg: 1.2)

private func septemberNight() throws -> (Night, ClearWindow) {
    let night = try Ephemeris.night(localDate: utc(2026, 9, 23, 12, 0), site: sheffield)
    return (night, ClearWindow(start: try #require(night.darkStart), end: try #require(night.darkEnd)))
}

private func object(_ id: String, ra: Double, dec: Double, mag: Double) -> DeepSkyObject {
    DeepSkyObject(id: id, commonName: nil, messier: nil, typeCode: "G", group: .galaxies, raHours: ra, decDeg: dec,
                  majAxisArcmin: 3, minAxisArcmin: 2, magnitude: mag, constellation: "Cyg")
}

private func favourites(_ ids: [String], catalog: Catalog = Catalog(objects: []), ranked: [RankedTarget] = [], window: ClearWindow?,
                        night: Night) throws -> [FavouriteTarget] {
    Planner.favouriteTargets(ids, ranked: ranked, catalog: catalog, constellations: [], stars: try BrightStars.bundled(),
                             window: window, night: night, site: sheffield, fov: dwarfMini, rule: GoRule())
}

@Test func theBrightStarListLoads() throws {
    let stars = try BrightStars.bundled()
    #expect(stars.count == 49)
    #expect(Set(stars.map(\.id)).count == stars.count)
    #expect(stars.allSatisfy { $0.magnitude <= 2.0 && (0..<24).contains($0.raHours) && abs($0.decDeg) <= 90 })
    let capella = try #require(stars.first { $0.name == "Capella" })
    #expect(capella.id == "HIP24608" && capella.designation == "α Aur")
    #expect(abs(capella.raHours - 5.278) < 0.01 && abs(capella.decDeg - 46.0) < 0.05)
}

@Test func brightStarsAreRankedInTheirOwnGroup() throws {
    let (_, window) = try septemberNight()
    let ranked = Planner.rank(catalog: Catalog(objects: []), constellations: [], stars: try BrightStars.bundled(), window: window,
                              site: sheffield, fov: dwarfMini, rule: GoRule())
    let deneb = try #require(ranked.first { $0.catalogueID == "Deneb" })   // near the zenith on a September night
    #expect(deneb.group == .stars && deneb.typeName == "Star" && deneb.cardName == "α Cyg" && !deneb.moonWashed)
    #expect(ranked.contains { $0.catalogueID == "Canopus" } == false)       // never rises at 53° N
    #expect(Planner.best(from: ranked).allSatisfy { $0.group != .stars })   // stars only reach the popover as a favourite
}

@Test func favouritesKeepTheirOrderAndSayWhyTheyAreNotUsable() throws {
    let (night, window) = try septemberNight()
    let faint = object("FAINT", ra: 20.7, dec: 45, mag: 13.5)            // Deneb's place: high all night, but past the list's cut
    let ranked = Planner.rank(catalog: Catalog(objects: [faint]), constellations: [], stars: try BrightStars.bundled(), window: window,
                              site: sheffield, fov: dwarfMini, rule: GoRule())
    #expect(!ranked.contains { $0.id == "FAINT" })
    let f = try favourites(["HIP30438", "nothing-by-this-id", "FAINT", "HIP102098"], catalog: Catalog(objects: [faint]), ranked: ranked,
                           window: window, night: night)
    #expect(f.map(\.id) == ["HIP30438", "FAINT", "HIP102098"])            // Canopus, the faint one, Deneb; the unknown ID is dropped
    #expect(f[0].notTonight == "Below 30° in tonight's window")
    #expect(f[1].notTonight == nil)                                       // a favourite is kept whatever its magnitude
    #expect(f[2].notTonight == nil && f[2].target == ranked.first { $0.id == "HIP102098" })
}

@Test func aFavouriteUpForUnderHalfTheWindowSaysSo() throws {
    let (night, window) = try septemberNight()
    var found = false
    for ra in stride(from: 0.0, to: 24.0, by: 0.5) {
        let o = object("P", ra: ra, dec: 10, mag: 8)
        let b = try #require(Planner.build(.object(o), window: window, site: sheffield, fov: dwarfMini, rule: GoRule(),
                                           moon: Ephemeris.moon(at: window.midpoint, site: sheffield), moonUp: false))
        guard b.fraction > 0, b.fraction < 0.5 else { continue }
        let f = try favourites(["P"], catalog: Catalog(objects: [o]), window: window, night: night)
        #expect(f.first?.notTonight == "Above 30° for under half of tonight's window")
        found = true
        break
    }
    #expect(found)
}

@Test func withoutDarknessEveryFavouriteIsGreyed() throws {
    let (night, _) = try septemberNight()
    let f = try favourites(["HIP102098", "planet-saturn", "moon"], window: nil, night: night)
    #expect(f.count == 3 && f.allSatisfy { $0.notTonight == "No astronomical darkness tonight" })
}

@Test func aFavouriteTakesAPopoverSlot() {
    func t(_ id: String, _ g: TargetGroup, alt: Double, washed: Bool = false) -> RankedTarget {
        RankedTarget(id: id, name: id, subtitle: "", group: g, raHours: 0, decDeg: 0, sizeArcmin: nil, magnitude: nil, fit: .fits,
                     peakAltDeg: alt, peakTime: Date(timeIntervalSince1970: 0), moonSepDeg: 90, moonWashed: washed, visibleFraction: 1)
    }
    let ranked = [t("neb1", .nebulae, alt: 60), t("neb2", .nebulae, alt: 40), t("gal1", .galaxies, alt: 55), t("gal2", .galaxies, alt: 30),
                  t("cl1", .clusters, alt: 50), t("vega", .stars, alt: 70), t("gal3", .galaxies, alt: 80, washed: true)]
    func best(_ favs: [RankedTarget]) -> [String] { Planner.best(from: ranked, favourites: favs).map(\.id) }
    let byID = Dictionary(uniqueKeysWithValues: ranked.map { ($0.id, $0) })
    #expect(best([]) == ["neb1", "gal1", "cl1"])
    #expect(best([byID["gal2"]!]) == ["neb1", "gal2", "cl1"])                       // in place of its group's pick
    #expect(best([byID["vega"]!]) == ["neb1", "gal1", "vega"])                      // no stars pick: the last slot
    #expect(best([byID["neb1"]!]) == ["neb1", "gal1", "cl1"])                       // already there
    #expect(best([byID["gal3"]!]) == ["neb1", "gal1", "cl1"])                       // Moon-washed: no slot
    #expect(best([byID["gal2"]!, byID["neb2"]!]) == ["neb2", "gal1", "cl1"])        // the higher favourite wins
    #expect(best([t("faint", .galaxies, alt: 65)]) == ["neb1", "faint", "cl1"])     // usable though the magnitude cut left it out
}

@Test func favouritesToggleAndSurviveASave() throws {
    var c = Config()
    c.toggleFavourite("NGC7814"); c.toggleFavourite("HIP24608"); c.toggleFavourite("NGC7814")
    #expect(c.favourites == ["HIP24608"])
    let back = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(c))
    #expect(back.favourites == ["HIP24608"])
}

@Test func starsGetGuidanceWithoutNumbers() throws {
    let (_, window) = try septemberNight()
    let deneb = try #require(Planner.rank(catalog: Catalog(objects: []), constellations: [], stars: try BrightStars.bundled(), window: window,
                                          site: sheffield, fov: dwarfMini, rule: GoRule()).first { $0.catalogueID == "Deneb" })
    #expect(ShootingTips.kind(deneb) == .star)
    for preset in ["dwarf-mini", "seestar-s50", "dslr-apsc-200", nil] as [String?] {
        let tip = ShootingTips.tip(for: deneb, presetID: preset, presetName: nil, stackMinutes: 120, site: sheffield)
        #expect(tip.rows.map(\.label) == ["Use", "Exposure", "When"] && tip.source == nil)
    }
}

@Test func aNewMoonFavouriteSaysSoAndRepeatsAreDropped() throws {
    let night = try Ephemeris.night(localDate: utc(2026, 10, 10, 12, 0), site: sheffield)   // new Moon on 10 October 2026
    let window = ClearWindow(start: try #require(night.darkStart), end: try #require(night.darkEnd))
    #expect(Ephemeris.moon(at: window.midpoint, site: sheffield).illumination <= 0.05)
    let f = try favourites(["moon", "HIP102098", "moon"], window: window, night: night)
    #expect(f.map(\.id) == ["moon", "HIP102098"])
    #expect(f[0].notTonight == "New Moon tonight")
}

/// plan.json cached by 1.0.0 has no "favourites" (nor, from older versions, "limiting", "mode" and the rest): it must load.
@Test func aPlanCachedByAnEarlierVersionLoads() throws {
    let (night, window) = try septemberNight()
    var p = NightPlan(night: night, windows: [window], primary: window, score: 70, qualifies: true, moonIllumination: 0.4, moonRise: nil,
                      moonSet: nil, darkHours: [], targets: [], best: [], seeingAvailable: false)
    p.favourites = try favourites(["HIP102098"], window: window, night: night)
    var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(p)) as! [String: Any]
    for k in ["favourites", "limiting", "mode", "brightTargets", "moonUpFraction", "agreement"] { json.removeValue(forKey: k) }
    let old = try JSONDecoder().decode(NightPlan.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(old.favourites.isEmpty && old.mode == .dark && old.score == 70)
    #expect(try JSONDecoder().decode(NightPlan.self, from: JSONEncoder().encode(p)) == p)   // and a new one round-trips
}
