import Testing
import Foundation
@testable import SkyCore

private func target(_ id: String, name: String, group: TargetGroup, fit: FrameFit = .fits, washed: Bool = false,
                    caldwell: Int? = nil, commonName: String? = nil, typeName: String = "Galaxy") -> RankedTarget {
    var r = RankedTarget(id: id, name: name, subtitle: "G in Peg", group: group, raHours: 0, decDeg: 0, sizeArcmin: 4, magnitude: 10.6,
                         fit: fit, peakAltDeg: 50, peakTime: Date(timeIntervalSince1970: 0), moonSepDeg: 11, moonWashed: washed, visibleFraction: 1)
    r.caldwell = caldwell; r.commonName = commonName; r.typeName = typeName
    return r
}

private let c43 = target("NGC7814", name: "NGC 7814 · C43", group: .galaxies, fit: .small, washed: true, caldwell: 43)

@Test func searchMatchesWithOrWithoutSpaces() {
    for q in ["C43", "c43", "C 43", "NGC7814", "ngc 7814", "7814", "", "  "] { #expect(c43.matches(q), "\(q)") }
    for q in ["C44", "M31", "NGC 7815"] { #expect(!c43.matches(q), "\(q)") }
    // A Caldwell number must not find the NGC and IC numbers that share its digits (the review's catch).
    let m61 = target("NGC4303", name: "M61 · NGC 4303", group: .galaxies)
    for q in ["C43", "C 43", "c4"] { #expect(!m61.matches(q), "\(q)") }
    #expect(m61.matches("4303") && m61.matches("M61") && m61.matches("ngc 43"))
    let veil = target("NGC6992", name: "NGC 6992 · C33 · Eastern Veil", group: .nebulae, commonName: "Eastern Veil")
    #expect(veil.matches("veil") && veil.matches("eastern veil") && veil.matches("C33") && veil.matches("Peg"))   // words: anywhere
    let little = target("NGC7814", name: "NGC 7814 · C43 · Little Sombrero Galaxy", group: .galaxies, caldwell: 43, commonName: "Little Sombrero Galaxy")
    #expect(little.matches("sombrero") && little.matches("little sombrero") && little.matches("C43"))
}

@Test func cardLineCarriesTheCaldwellNumber() {
    #expect(c43.cardLine == "C43 · Galaxy")
    #expect(target("NGC7000", name: "NGC 7000 · C20 · North America Nebula", group: .nebulae, caldwell: 20,
                   commonName: "North America Nebula").cardLine == "C20 · North America Nebula")
    #expect(target("NGC0224", name: "M31", group: .galaxies, commonName: "Andromeda Galaxy").cardLine == "Andromeda Galaxy")
}

/// The owner searched for C43 under a full Moon and found nothing: say why instead of showing an empty grid.
@Test func searchHintExplainsHiddenMatches() {
    let m31 = target("NGC0224", name: "M31 · NGC 224", group: .galaxies)
    func hint(_ q: String, _ g: TargetGroup, fitsOnly: Bool = false, washed: Bool = false, in ts: [RankedTarget] = [c43, m31]) -> String? {
        Copy.searchHint(query: q, targets: ts, group: g, fitsOnly: fitsOnly, includeMoonWashed: washed)
    }
    #expect(hint("C43", .galaxies) == "1 Moon-washed match hidden: turn on Include Moon-washed.")
    #expect(hint("C43", .galaxies, washed: true) == nil)                                     // shown, nothing to explain
    #expect(hint("C43", .galaxies, fitsOnly: true, washed: true) == "1 match hidden by Fits my field of view.")
    #expect(hint("C43", .nebulae) == "Also in Galaxies (1).")
    #expect(hint("NGC", .galaxies) == "1 Moon-washed match hidden: turn on Include Moon-washed.")   // M31 shows; C43 is hidden
    let c20 = target("NGC7000", name: "NGC 7000 · C20", group: .nebulae, washed: true, caldwell: 20)
    #expect(hint("C", .clusters, in: [c43, c20]) == "Also in Nebulae (1), Galaxies (1).")
    #expect(hint("C4", .galaxies, washed: false, in: [c43, target("x", name: "C4 · NGC 7023", group: .galaxies, washed: true)])
            == "2 Moon-washed matches hidden: turn on Include Moon-washed.")
    // Both filters hide it, so both are named.
    #expect(hint("C43", .galaxies, fitsOnly: true) == "1 Moon-washed match hidden: turn on Include Moon-washed. 1 match hidden by Fits my field of view.")
    #expect(hint("", .galaxies) == nil)
    #expect(hint("zzz", .galaxies) == nil)
}

@Test func cardLabelNamesTheCaldwellNumber() {
    var t = c43; t.catalogueID = "NGC 7814"
    #expect(Copy.cardLabel(t, lit: false, nearMoon: false, site: Site(name: "x", latitude: 54, longitude: -1, elevationM: 0,
                                                                     timeZoneID: "Europe/London", bortle: 4)).hasPrefix("NGC 7814 C43, "))
}

/// Plans cached before Caldwell numbers existed have no "caldwell" key and must still load.
@Test func aCachedTargetWithoutACaldwellNumberDecodes() throws {
    var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(c43)) as! [String: Any]
    json.removeValue(forKey: "caldwell")
    let old = try JSONDecoder().decode(RankedTarget.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(old.caldwell == nil && old.name == c43.name)
}
