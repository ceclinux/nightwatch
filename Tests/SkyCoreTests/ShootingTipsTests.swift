import Testing
import Foundation
@testable import SkyCore

private let site = Site(name: "Test site", latitude: 54.0, longitude: -1.5, elevationM: 100, timeZoneID: "Europe/London", bortle: 5)
private func target(_ id: String, _ group: TargetGroup, _ type: String) -> RankedTarget {
    var t = RankedTarget(id: id, name: id, subtitle: "", group: group, raHours: 0, decDeg: 0, sizeArcmin: 10, magnitude: 8, fit: .fits,
                         peakAltDeg: 70, peakTime: utc(2026, 9, 26, 0, 30), moonSepDeg: 60, moonWashed: false, visibleFraction: 1)
    t.typeName = type
    t.viewable = ClearWindow(start: utc(2026, 9, 25, 22, 0), end: utc(2026, 9, 26, 3, 0))
    return t
}

@Test func dwarfTipsFollowTheManualAndTheWindow() {
    let tip = ShootingTips.tip(for: target("NGC0281", .nebulae, "Emission nebula"), presetID: "dwarf-mini", presetName: "DwarfLab DWARF Mini", stackMinutes: 180, site: site)
    #expect(tip.title == "How to shoot this with your DwarfLab DWARF Mini")
    #expect(tip.rows.first { $0.label == "Filter" }?.text.hasPrefix("Duo-Band") == true)
    #expect(tip.rows.first { $0.label == "Exposure" }?.text == "15–60 s per frame at gain 60–80.")
    #expect(tip.rows.first { $0.label == "Frames" }?.text == "200–400 recommended. At 30 s a frame, for example, 360 frames fill the 3 h it is up tonight.")
    #expect(tip.rows.last?.text == "Start at 23:00, when it is clear and high enough; it is best at 01:30.")
    #expect(tip.source == "Settings from DWARFLAB's user manual.")
    let galaxy = ShootingTips.tip(for: target("NGC0224", .galaxies, "Galaxy"), presetID: "dwarf-3", presetName: "DwarfLab DWARF 3", stackMinutes: 90, site: site)
    #expect(galaxy.rows.first { $0.label == "Filter" }?.text.hasPrefix("Astro") == true)
    #expect(galaxy.rows.first { $0.label == "Frames" }?.text == "200–400 recommended. At 30 s a frame, for example, 180 frames fill the 1.5 h it is up tonight.")
    #expect(galaxy.rows.first { $0.label == "Filter" }?.text.contains("spans the whole spectrum") == true)
}

@Test func seestarSwitchesItsFilterByTheKindOfLight() {
    let em = ShootingTips.tip(for: target("NGC7000", .nebulae, "Emission nebula"), presetID: "seestar-s50", presetName: "ZWO Seestar S50", stackMinutes: 60, site: site)
    #expect(em.rows.first { $0.label == "Filter" }?.text.hasPrefix("Light-pollution filter on") == true)
    #expect(em.rows.first { $0.label == "Frames" }?.text.contains("about 360 frames") == true)
    let cl = ShootingTips.tip(for: target("M13", .clusters, "Globular cluster"), presetID: "seestar-s50", presetName: "ZWO Seestar S50", stackMinutes: 60, site: site)
    #expect(cl.rows.first { $0.label == "Filter" }?.text.hasPrefix("Light-pollution filter off") == true)
}

@Test func noNumbersWithoutAVerifiedSource() {
    let planet = ShootingTips.tip(for: target("planet-saturn", .planets, "Planet"), presetID: "dwarf-mini", presetName: "DwarfLab DWARF Mini", stackMinutes: 180, site: site)
    #expect(planet.source == nil && !planet.rows.contains { $0.label == "Exposure" })
    let noWindow = ShootingTips.tip(for: target("NGC0281", .nebulae, "Emission nebula"), presetID: "dwarf-mini", presetName: "DwarfLab DWARF Mini", stackMinutes: nil, site: site)
    #expect(noWindow.rows.first { $0.label == "Frames" }?.text == "200–400 recommended.")
    let custom = ShootingTips.tip(for: target("NGC0281", .nebulae, "Nebula"), presetID: nil, presetName: nil, stackMinutes: 120, site: site)
    #expect(custom.title == "How to shoot this with your telescope" && custom.source == nil)
    #expect(custom.rows.first { $0.label == "Filter" }?.text.contains("if it glows red") == true)
    let dwarfUnknown = ShootingTips.tip(for: target("NGC0281", .nebulae, "Nebula"), presetID: "dwarf-mini", presetName: "DwarfLab DWARF Mini", stackMinutes: 60, site: site)
    #expect(dwarfUnknown.rows.first { $0.label == "Filter" }?.text.contains("; Astro if it is a reflection") == true)   // the filter's own name, capitalised
}

@Test func releaseCheckComparesVersionsNumerically() {
    #expect(ReleaseCheck.isNewer("0.6.7", than: "0.6.6") && ReleaseCheck.isNewer("0.10.0", than: "0.9.1") && ReleaseCheck.isNewer("1.0", than: "0.9.9"))
    #expect(!ReleaseCheck.isNewer("0.6.6", than: "0.6.6") && !ReleaseCheck.isNewer("0.6.5", than: "0.6.6") && !ReleaseCheck.isNewer("0.6", than: "0.6.0"))
    let json = #"{"tag_name":"v0.6.7","html_url":"https://github.com/rsutcliffe/nightwatch/releases/tag/v0.6.7","draft":false,"prerelease":false}"#
    #expect(ReleaseCheck.parse(Data(json.utf8)) == ReleaseCheck.Latest(version: "0.6.7", url: URL(string: "https://github.com/rsutcliffe/nightwatch/releases/tag/v0.6.7")!))
    #expect(ReleaseCheck.parse(Data(#"{"tag_name":"v0.7.0","html_url":"https://x","prerelease":true}"#.utf8)) == nil)
    #expect(ReleaseCheck.parse(Data("not json".utf8)) == nil)
    let t0 = Date(), rec = ReleaseCheck.Record(checkedAt: t0, latest: nil)
    #expect(ReleaseCheck.due(nil, now: t0) && !ReleaseCheck.due(rec, now: t0.addingTimeInterval(3600)) && ReleaseCheck.due(rec, now: t0.addingTimeInterval(24 * 3600)))
}

@Test func newConfigsWelcomeButOldOnesDoNot() throws {
    #expect(!Config().welcomed && Config().checkForUpdates)
    let old = try JSONDecoder().decode(Config.self, from: Data(#"{"sites":[]}"#.utf8))
    #expect(old.welcomed && old.checkForUpdates)
}

// Copy the settings (#61): one line, the target, the telescope and the card's own numbers; none where there are no numbers.
@Test func theCopiedLineMatchesTheCardForEachPreset() {
    var nebula = target("NGC6888", .nebulae, "Emission nebula"); nebula.catalogueID = "NGC 6888"; nebula.commonName = "Crescent Nebula"
    let dwarf = ShootingTips.tip(for: nebula, presetID: "dwarf-mini", presetName: "DwarfLab DWARF Mini", stackMinutes: 180, site: site)
    #expect(dwarf.copyLine == "NGC 6888 Crescent Nebula · DwarfLab DWARF Mini: Duo-Band filter, 15–60 s at gain 60–80, 200–400 frames")
    #expect(dwarf.rows.contains { $0.text.contains("15–60 s per frame at gain 60–80") } && dwarf.rows.contains { $0.text.hasPrefix("200–400") })
    let seestar = ShootingTips.tip(for: nebula, presetID: "seestar-s50", presetName: "ZWO Seestar S50", stackMinutes: 60, site: site)
    #expect(seestar.copyLine?.hasSuffix("ZWO Seestar S50: light-pollution filter on, 10 s frames") == true)
    #expect(seestar.rows.contains { $0.text.hasPrefix("Light-pollution filter on") } && seestar.rows.contains { $0.text.hasPrefix("10 s frames") })
    let camera = ShootingTips.tip(for: nebula, presetID: "dslr-apsc-200", presetName: "APS-C camera, 200 mm lens", stackMinutes: 60, site: site)
    #expect(camera.copyLine?.hasSuffix(": dual-band or light-pollution filter, 60–120 s on a star tracker, under about 1.5 s without one") == true)
    // No numbers, no line: a custom telescope, a planet, a star.
    #expect(ShootingTips.tip(for: nebula, presetID: nil, presetName: nil, stackMinutes: 60, site: site).copyLine == nil)
    #expect(ShootingTips.tip(for: target("planet-jupiter", .planets, "Planet"), presetID: "dwarf-mini", presetName: "DwarfLab DWARF Mini",
                             stackMinutes: 60, site: site).copyLine == nil)
    #expect(ShootingTips.tip(for: target("HIP1", .stars, "Star"), presetID: "dwarf-mini", presetName: "DwarfLab DWARF Mini",
                             stackMinutes: 60, site: site).copyLine == nil)
}

@Test func everyPresetAndKindCopiesWhatItsCardSays() {
    // Each copied line's numbers appear on the card it came from, for every preset and every kind of target.
    let kinds: [(TargetGroup, String, String)] = [(.nebulae, "Emission nebula", "NGC7000"), (.galaxies, "Galaxy", "NGC0224"),
                                                  (.nebulae, "Nebula", "NGC1999"), (.planets, "Moon", "moon"), (.planets, "Planet", "planet-mars"),
                                                  (.constellations, "Constellation", "Cyg"), (.stars, "Star", "HIP1")]
    let presets: [(String?, String?)] = [("dwarf-mini", "DwarfLab DWARF Mini"), ("dwarf-3", "DwarfLab DWARF 3"), ("seestar-s50", "ZWO Seestar S50"),
                                         ("dslr-apsc-200", "APS-C camera, 200 mm lens"), (nil, nil)]
    for (preset, name) in presets {
        for (group, type, id) in kinds {
            let tip = ShootingTips.tip(for: target(id, group, type), presetID: preset, presetName: name, stackMinutes: 120, site: site)
            guard let line = tip.copyLine else { continue }
            let card = tip.rows.map(\.text).joined(separator: " ").lowercased()
            let numbers = line.components(separatedBy: ": ").dropFirst().joined(separator: ": ")
            for figure in numbers.components(separatedBy: CharacterSet(charactersIn: "0123456789–/").inverted).filter({ !$0.isEmpty }) {
                #expect(card.contains(figure), "\(preset ?? "custom") \(type): \(figure) is not on the card")
            }
        }
    }
    // Which get a line at all: numbers only where the card has them.
    func line(_ preset: String?, _ group: TargetGroup, _ type: String, _ id: String) -> String? {
        ShootingTips.tip(for: target(id, group, type), presetID: preset, presetName: "x", stackMinutes: 120, site: site).copyLine
    }
    #expect(line("dwarf-3", .galaxies, "Galaxy", "NGC0224")?.hasSuffix("x: Astro filter, 15–60 s at gain 60–80, 200–400 frames") == true)
    #expect(line("dwarf-mini", .nebulae, "Nebula", "NGC1999")?.contains("Duo-Band or Astro filter") == true)
    #expect(line("dwarf-mini", .planets, "Moon", "moon")?.contains("Moon mode, about 1/250 s at gain 0") == true)
    #expect(line("seestar-s50", .nebulae, "Nebula", "NGC1999")?.contains("filter on if it glows red, off if not, 10 s frames") == true)
    #expect(line("dslr-apsc-200", .nebulae, "Emission nebula", "NGC7000")?.hasPrefix("NGC7000 · x: dual-band or light-pollution filter") == true)   // no catalogue ID: the name
    for (preset, group, type, id) in [("seestar-s50", TargetGroup.planets, "Moon", "moon"), ("dwarf-mini", .constellations, "Constellation", "Cyg"),
                                      ("dslr-apsc-200", .planets, "Moon", "moon"), ("dwarf-mini", .planets, "Planet", "planet-mars")] {
        #expect(line(preset, group, type, id) == nil)
    }
}

@Test func dracoNamesItsFiltersAndGivesNoNumbersDwarflabHasNotPublished() {
    let em = ShootingTips.tip(for: target("NGC7000", .nebulae, "Emission nebula"), presetID: "draco", presetName: "DwarfLab Draco", stackMinutes: 120, site: site)
    #expect(em.title == "How to shoot this with your DwarfLab Draco")
    #expect(em.rows.first { $0.label == "Filter" }?.text.hasPrefix("Hα + O III dual-narrowband filter") == true)
    #expect(em.rows.first { $0.label == "Exposure" }?.text.contains("not yet published") == true)
    #expect(em.rows.first { $0.label == "Frames" }?.text == "It is up and clear for 2 h tonight.")
    #expect(em.source == "Filters from DWARFLAB's Draco product page; it has published no exposure settings yet.")
    #expect(em.copyLine == nil)   // no maker numbers, so no copy icon
    let galaxy = ShootingTips.tip(for: target("NGC0224", .galaxies, "Galaxy"), presetID: "draco", presetName: "DwarfLab Draco", stackMinutes: nil, site: site)
    #expect(galaxy.rows.first { $0.label == "Filter" }?.text.hasPrefix("Astronomy filter") == true)
    #expect(!galaxy.rows.contains { $0.label == "Frames" })
    let planet = ShootingTips.tip(for: target("planet-saturn", .planets, "Planet"), presetID: "draco", presetName: "DwarfLab Draco", stackMinutes: 60, site: site)
    #expect(planet.source == nil && !planet.rows.contains { $0.label == "Exposure" })
    #expect(ShootingTips.planKit(target("NGC7000", .nebulae, "Emission nebula"), presetID: "draco") == "Hα + O III")
}

// Planets, the Moon, stars and constellations get no deep-sky kit in a plan row (owner's UAT: Saturn read "Duo-Band or Astro").
@Test func planRowsGiveNoDeepSkyKitOutsideDeepSky() {
    for id in ["planet-saturn", "moon"] {
        #expect(ShootingTips.planKit(target(id, .planets, "Planet"), presetID: "dwarf-mini") == nil)
    }
    #expect(ShootingTips.planKit(target("Capella", .stars, "Star"), presetID: "seestar-s50") == nil)
    #expect(ShootingTips.planKit(target("Cyg", .constellations, "Constellation"), presetID: "dwarf-mini") == nil)
    #expect(ShootingTips.planKit(target("NGC0224", .galaxies, "Galaxy"), presetID: "dwarf-mini") == "Astro · 200 × 30 s")
}
