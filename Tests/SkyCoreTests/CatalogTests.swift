import Testing
import Foundation
@testable import SkyCore

@Test func parsesSampleRows() throws {
    let csv = String(decoding: try fixture("ngc-sample.csv"), as: UTF8.self)
    let objs = try Catalog.parse(csv: csv)
    let m31 = try #require(objs.first { $0.id == "NGC0224" })
    #expect(m31.messier == 31)
    #expect(m31.group == .galaxies)
    #expect(abs(m31.raHours - 0.712) < 0.01)
    #expect(abs(m31.decDeg - 41.27) < 0.05)
    #expect((m31.majAxisArcmin ?? 0) > 100)
    #expect(m31.displayName.hasPrefix("M31"))
    let nan = try #require(objs.first { $0.id == "NGC7000" })
    #expect(nan.group == .nebulae)
    #expect(nan.commonName?.contains("North America") == true)
    let ring = try #require(objs.first { $0.id == "NGC6720" })
    #expect(ring.group == .nebulae && ring.messier == 57)
    let dbl = try #require(objs.first { $0.id == "NGC0869" })
    #expect(dbl.group == .clusters)
    #expect(objs.first { $0.id == "IC0001" } == nil)   // double star, no group
    let pleiades = try #require(objs.first { $0.id == "Mel022" })
    #expect(pleiades.messier == 45 && pleiades.group == .clusters)
}

@Test func bundledCatalogLoads() throws {
    let cat = try Catalog.bundled()
    #expect(cat.objects.count > 5000)
    #expect(cat.objects.filter { $0.messier != nil }.count >= 100)
}

@Test func bundledConstellationsLoad() throws {
    let cs = try Constellations.bundled()
    #expect(cs.count == 88)
    #expect(Set(cs.map(\.id)).count == cs.count)
    let ori = try #require(cs.first { $0.id == "Ori" })
    #expect(ori.name == "Orion")
    #expect(!ori.lines.isEmpty)
    #expect(ori.raHours >= 0 && ori.raHours < 24)
    let ser = try #require(cs.first { $0.id == "Ser" })
    #expect(ser.name == "Serpens")
    #expect(ser.lines.count >= 2)
}

/// The owner's artwork (v0.6.2): every catalogue constellation has a figure and a star-plot layer, and nothing extra.
@Test func everyConstellationHasArtwork() throws {
    let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../Resources/Constellations").standardized
    let files = Set(try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".heic") })   // Finder's .DS_Store is not art
    let ids = Set(try Constellations.bundled().map(\.id))
    #expect(ids.count == 88)
    #expect(files == Set(ids.flatMap { ["\($0)-figure.heic", "\($0)-plot.heic"] }))
}

@Test func catalogueIDsAreSpacedWithoutLeadingZeros() {
    func o(_ id: String, messier: Int? = nil) -> DeepSkyObject {
        DeepSkyObject(id: id, commonName: nil, messier: messier, typeCode: "Neb", group: .nebulae, raHours: 0, decDeg: 0,
                      majAxisArcmin: nil, minAxisArcmin: nil, magnitude: nil, constellation: "Cyg")
    }
    #expect(o("IC1340").catalogueID == "IC 1340")
    #expect(o("NGC0281").catalogueID == "NGC 281")
    #expect(o("NGC7000").catalogueID == "NGC 7000")
    #expect(o("NGC1976", messier: 42).catalogueID == "M42")
    #expect(o("IC1340").displayName == "IC 1340")
    // Addendum catalogues: one "{catalogue} {number}" pattern; ESO, PGC and UGC numbers are fixed-format and kept whole.
    #expect(o("C009").catalogueID == "C9")   // Caldwell entries in the addendum read as the Caldwell number, unspaced
    #expect(o("B033").catalogueID == "B 33")
    #expect(o("Mel071").catalogueID == "Mel 71")
    #expect(o("Cl399").catalogueID == "Cl 399")
    #expect(o("MWSC3171").catalogueID == "MWSC 3171")
    #expect(o("ESO056-115").catalogueID == "ESO 056-115")
    #expect(o("IC0186A").catalogueID == "IC 186A")
}

/// All 109 Caldwell objects are findable: OpenNGC tags most as "C 043" among the identifiers, and the addendum names the
/// four it lacks C009, C014, C041 and C099. The NGC number stays the catalogue ID; the C number joins the name.
@Test func everyCaldwellObjectIsNumberedOnce() throws {
    let tagged = try Catalog.bundled().objects.filter { $0.caldwell != nil }
    #expect(tagged.count == 109)
    #expect(Set(tagged.compactMap(\.caldwell)) == Set(1...109))
    let c43 = try #require(tagged.first { $0.caldwell == 43 })
    #expect(c43.id == "NGC7814" && c43.catalogueID == "NGC 7814" && c43.displayName == "NGC 7814 · C43 · Little Sombrero Galaxy")
    let c20 = try #require(tagged.first { $0.caldwell == 20 })
    #expect(c20.catalogueID == "NGC 7000" && c20.displayName == "NGC 7000 · C20 · North America Nebula · Sh 2-117")
    let c14 = try #require(tagged.first { $0.caldwell == 14 })
    #expect(c14.catalogueID == "C14" && c14.displayName == "C14 · Double Cluster")
    let m31 = try #require(try Catalog.bundled().objects.first { $0.messier == 31 })   // Messier names are unchanged
    #expect(m31.catalogueID == "M31" && m31.displayName == "M31 · NGC 224 · Andromeda Galaxy")
    #expect(DeepSkyObject.caldwellNumber(name: "C+12") == nil && DeepSkyObject.caldwellNumber(name: "Cl399") == nil)
}

/// Names OpenNGC lacks are filled in, so "sombrero" finds C43 (v1.0.1); OpenNGC's own names are never replaced.
@Test func missingCommonNamesAreFilledIn() throws {
    let objs = try Catalog.bundled().objects
    func o(_ id: String) throws -> DeepSkyObject { try #require(objs.first { $0.id == id }) }
    #expect(try o("NGC7814").commonName == "Little Sombrero Galaxy")
    #expect(try o("NGC4594").commonName == "Sombrero Galaxy")
    for id in Catalog.extraNames.keys { #expect(try o(id).commonName == Catalog.extraNames[id], "\(id)") }
}

// Sharpless's H II regions (CDS/VizieR VII/20): the larger, brighter ones OpenNGC lacks have rows of their own, and an object OpenNGC
// lists under another name carries its Sharpless number where SIMBAD or OpenNGC says which it is.
@Test func sharplessNebulaeJoinTheCatalogueAndKnownObjectsCarryTheirNumbers() throws {
    let c = try Catalog.bundled()
    let tulip = try #require(c.objects.first { $0.id == "Sh2-101" })
    #expect(tulip.catalogueID == "Sh 2-101" && tulip.displayName == "Sh 2-101" && tulip.group == .nebulae && tulip.typeCode == "HII")
    #expect(tulip.majAxisArcmin == 20 && tulip.magnitude == nil && tulip.sharpless == 101)
    // Turned from Sharpless's B1950 to J2000, and the constellation found from the place: the Tulip Nebula is in Cygnus.
    #expect(abs(tulip.raHours - 20.0) < 0.02 && abs(tulip.decDeg - 35.3) < 0.1 && tulip.constellation == "Cyg")
    #expect(c.objects.first { $0.id == "Sh2-261" }?.displayName == "Sh 2-261 · Lower's Nebula")
    let own = c.objects.filter { $0.id.hasPrefix("Sh2-") }
    #expect(own.count == 83 && Set(own.map(\.id)).count == 83 && own.allSatisfy { (10...300).contains($0.majAxisArcmin ?? 0) && !$0.constellation.isEmpty })
    // Known under another name: no second row, and the number joins the name.
    let lagoon = try #require(c.objects.first { $0.id == "NGC6523" })
    #expect(lagoon.sharpless == 25 && lagoon.displayName.hasSuffix(" · Sh 2-25") && !own.contains { $0.sharpless == 25 })
    let cave = try #require(c.objects.first { $0.id == "C009" })   // OpenNGC's own "SH 2-155" identifier
    #expect(cave.sharpless == 155 && cave.displayName == "C9 · Cave Nebula · Sh 2-155")
    // The Orion Nebula lies inside Sh 2-281: no second row, and the number is given to it by position.
    #expect(!own.contains { $0.sharpless == 281 } && c.objects.first { $0.messier == 42 }?.sharpless == 281)
    // The Running Man lies in the next region, Sh 2-279, which overlaps: each object keeps one number, each number one object.
    #expect(c.objects.first { $0.id == "NGC1977" }?.sharpless == 279)
    #expect(Set(Catalog.sharplessByPosition.values).count == Catalog.sharplessByPosition.count)
    #expect(Set(Catalog.sharplessByPosition.keys).isDisjoint(with: Catalog.sharplessNumbers.keys))
    #expect(Set(Catalog.sharplessByPosition.values).isDisjoint(with: Catalog.sharplessNumbers.values))
    // Every key is an object the catalogue lists, never a planetary or reflection nebula, and SIMBAD's identifications stand.
    for (name, _) in Catalog.sharplessByPosition {
        let o = c.objects.first { $0.id == name }
        #expect(o != nil && o?.typeCode != "PN" && o?.typeCode != "RfN", "\(name)")
    }
    #expect(c.objects.first { $0.id == "NGC7000" }?.sharpless == 117)
}

// With the Sharpless rows in the catalogue, the highest nebula on 2 December 2026 from 54° north was Sh 2-210: a faint region with no
// magnitude, as the popover's first pick. A Sharpless-only row is listed and searchable, never the pick while another nebula qualifies.
@Test func aSharplessOnlyRowIsNeverThePopoversPickWhileAnotherNebulaQualifies() throws {
    let site = Site(name: "Test site", latitude: 54.0, longitude: -1.5, elevationM: 100, timeZoneID: "Europe/London", bortle: 5)
    let window = ClearWindow(start: utc(2026, 12, 2, 20, 0), end: utc(2026, 12, 3, 0, 0))
    let ranked = Planner.rank(catalog: try Catalog.bundled(), constellations: try Constellations.bundled(), stars: try BrightStars.bundled(),
                              window: window, site: site, fov: FieldOfView(widthDeg: 2.1, heightDeg: 1.2), rule: GoRule())
    #expect(ranked.first { $0.group == .nebulae && !$0.moonWashed }?.id == "Sh2-210")   // still listed, and still the highest
    let best = Planner.best(from: ranked)
    #expect(best.count == 3 && !best.contains { $0.isSharplessOnly })
    let only = ranked.filter { $0.isSharplessOnly }
    #expect(Planner.best(from: only).first?.isSharplessOnly == true)   // with nothing else, it is still offered
}
