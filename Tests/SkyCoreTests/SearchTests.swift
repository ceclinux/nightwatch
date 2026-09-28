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
    // A kind of object finds every one of that kind: C43's card says "Galaxy" though its name does not.
    #expect(c43.matches("galaxy") && c43.matches("Galax") && !c43.matches("nebula"))
    #expect(target("NGC6205", name: "M13 · NGC 6205", group: .clusters, typeName: "Globular cluster").matches("globular"))
}

@Test func cardTitlesKeepTheNamePeopleKnow() {
    // The Caldwell number sits beside the ID; the name, or the kind when there is none, has its own line.
    #expect(c43.cardNote == "C43" && c43.cardName == "Galaxy")
    let c20 = target("NGC7000", name: "NGC 7000 · C20 · North America Nebula", group: .nebulae, caldwell: 20, commonName: "North America Nebula")
    #expect(c20.cardNote == "C20" && c20.cardName == "North America Nebula")
    let m31 = target("NGC0224", name: "M31", group: .galaxies, commonName: "Andromeda Galaxy")
    #expect(m31.cardNote == nil && m31.cardName == "Andromeda Galaxy")
    var c14 = target("C014", name: "C14 · Double Cluster", group: .clusters, caldwell: 14, commonName: "Double Cluster")
    c14.catalogueID = "C14"
    #expect(c14.cardNote == nil)   // the number is already the ID
}

/// The owner searched for C43 under a full Moon and missed the note under "No clear window tonight": the line now leads with
/// what the search found, and the matches the switches would hide are shown last rather than hidden.
@Test func searchHintSaysWhatTheSearchFound() {
    let m31 = target("NGC0224", name: "M31 · NGC 224", group: .galaxies)
    func hint(_ q: String, _ g: TargetGroup, fitsOnly: Bool = false, washed: Bool = false, in ts: [RankedTarget] = [c43, m31]) -> String? {
        Copy.searchHint(query: q, targets: ts, group: g, fitsOnly: fitsOnly, includeMoonWashed: washed)
    }
    #expect(hint("C43", .galaxies) == "1 match for “C43” in Galaxies. 1 Moon-washed, shown last.")
    #expect(hint("C43", .galaxies, washed: true) == "1 match for “C43” in Galaxies.")
    #expect(hint("C43", .galaxies, fitsOnly: true, washed: true) == "1 match for “C43” in Galaxies. 1 not fitting your field of view, shown last.")
    #expect(hint("C43", .nebulae) == "No match for “C43” in Nebulae tonight. Also in Galaxies (1).")
    #expect(hint(" NGC ", .galaxies) == "2 matches for “NGC” in Galaxies. 1 Moon-washed, shown last.")
    let c20 = target("NGC7000", name: "NGC 7000 · C20", group: .nebulae, washed: true, caldwell: 20)
    #expect(hint("C", .clusters, in: [c43, c20]) == "No match for “C” in Star clusters tonight. Also in Nebulae (1), Galaxies (1).")
    // Both switches would hide it, so both are named.
    #expect(hint("C43", .galaxies, fitsOnly: true) == "1 match for “C43” in Galaxies. 1 Moon-washed, shown last. 1 not fitting your field of view, shown last.")
    #expect(hint("", .galaxies) == nil && hint("  ", .galaxies) == nil && hint("\n", .galaxies) == nil)
    #expect(hint("zzz", .galaxies) == "No match for “zzz” in Galaxies tonight.")
}

/// Browsing, the switches hide; searching, every match shows with the would-be-hidden ones last.
@Test func searchShowsHiddenMatchesLast() {
    let m31 = target("NGC0224", name: "M31 · NGC 224", group: .galaxies)
    let site = Site(name: "x", latitude: 54, longitude: -1, elevationM: 0, timeZoneID: "Europe/London", bortle: 4)
    func ids(_ q: String, fitsOnly: Bool = false, washed: Bool = false) -> [String] {
        RankedTarget.cards([c43, m31], group: .galaxies, query: q, fitsOnly: fitsOnly, includeMoonWashed: washed,
                           sort: .brightness, now: Date(timeIntervalSince1970: 0), span: nil, site: site).map(\.id)
    }
    #expect(ids("") == ["NGC0224"])                          // browsing: the Moon-washed C43 is hidden
    #expect(ids("", washed: true) == ["NGC7814", "NGC0224"]) // switch on: both, in sort order
    #expect(ids("NGC") == ["NGC0224", "NGC7814"])            // searching: C43 shows, after the rest
    #expect(ids("C43") == ["NGC7814"])
    #expect(ids("C43", fitsOnly: true, washed: true) == ["NGC7814"])
    #expect(ids("zzz").isEmpty)
}

@Test func cardLabelNamesTheCaldwellNumber() {
    var t = c43; t.catalogueID = "NGC 7814"
    #expect(Copy.cardLabel(t, lit: false, nearMoon: false, site: Site(name: "x", latitude: 54, longitude: -1, elevationM: 0,
                                                                     timeZoneID: "Europe/London", bortle: 4)).hasPrefix("NGC 7814 C43 Galaxy, "))   // the kind, as the card shows, when there is no name
}

/// With no clear window the card says when the target is up in darkness anyway, and so does its sentence (owner, 28 Sep 2026).
@Test func cardLabelOnANightWithNoWindow() {
    let site = Site(name: "x", latitude: 54, longitude: -1, elevationM: 0, timeZoneID: "UTC", bortle: 4)
    var t = c43; t.catalogueID = "NGC 7814"
    t.viewable = ClearWindow(start: utc(2026, 11, 20, 20, 0), end: utc(2026, 11, 21, 3, 0))
    // The fixture peaks at 50° at 00:00 UTC.
    #expect(Copy.cardLabel(t, lit: false, nearMoon: false, site: site)
            .hasSuffix("no clear window, up in darkness from 20:00 to 03:00, highest at 00:00, 50 degrees up"))
    t.viewable = nil
    #expect(Copy.cardLabel(t, lit: false, nearMoon: false, site: site).hasSuffix("no clear window, too low in darkness tonight"))
}

/// Plans cached before Caldwell numbers existed have no "caldwell" key and must still load.
@Test func aCachedTargetWithoutACaldwellNumberDecodes() throws {
    var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(c43)) as! [String: Any]
    json.removeValue(forKey: "caldwell")
    let old = try JSONDecoder().decode(RankedTarget.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(old.caldwell == nil && old.name == c43.name)
}
