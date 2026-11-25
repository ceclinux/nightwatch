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
            .hasSuffix("no clear window, up in darkness from 20:00 to 03:00, highest at 00:00, 50 degrees up, \(Copy.peakWay(t, site: site))"))
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

// Eyes and binoculars (#63): only what the eye or binoculars can show, by surface brightness against the site's sky.
private func eyeTarget(_ id: String, _ group: TargetGroup, mag: Double?, size: Double?, minor: Double? = nil, type: String = "",
                       washed: Bool = false) -> RankedTarget {
    var r = RankedTarget(id: id, name: id, subtitle: "", group: group, raHours: 0, decDeg: 0, sizeArcmin: size, magnitude: mag, fit: .fits,
                         peakAltDeg: 60, peakTime: Date(), moonSepDeg: 90, moonWashed: washed, visibleFraction: 1)
    r.typeName = type; r.minorArcmin = minor
    return r
}

@Test func surfaceBrightnessMatchesThePublishedExample() {
    // Torres Lapasio: the Crab Nebula, 6′ × 4′ at magnitude 8.4, is 20.5 mag/arcsec².
    #expect(abs(EyeViews.surfaceBrightness(magnitude: 8.4, majorArcmin: 6, minorArcmin: 4) - 20.5) < 0.05)
}

@Test func eyesAndBinocularsFollowPublishedVisibilityOnTheCatalogue() throws {
    // The app's own OpenNGC rows, not typed-in sizes (review, 29 September 2026), against published visibility.
    let catalog = try Catalog.bundled()
    func row(_ id: String) throws -> RankedTarget {
        let o = try #require(catalog.objects.first { $0.id == id })
        var r = RankedTarget(id: o.id, name: o.displayName, subtitle: "\(o.typeCode) in \(o.constellation)", group: o.group, raHours: o.raHours,
                             decDeg: o.decDeg, sizeArcmin: o.majAxisArcmin, magnitude: o.magnitude, fit: .fits, peakAltDeg: 60, peakTime: Date(),
                             moonSepDeg: 90, moonWashed: false, visibleFraction: 1)
        r.typeName = Catalog.typeNames[o.typeCode] ?? o.typeCode; r.minorArcmin = o.minAxisArcmin
        return r
    }
    func view(_ id: String, _ bortle: Int) throws -> EyeView? { EyeViews.view(try row(id), bortle: bortle) }
    #expect(try view("NGC0224", 5) == .nakedEye)       // M31: "visible to the naked eye … with moderate light pollution"
    #expect(try view("NGC1976", 5) == .nakedEye)       // M42: "visible to the naked eye even from areas affected by light pollution"
    #expect(try view("NGC0598", 5) == .binoculars)     // M33: undetectable by eye in Bortle class 5
    #expect(try view("NGC0598", 2) == .nakedEye)
    #expect(try view("NGC7000", 5) == .binoculars)     // "normally it cannot be seen with the unaided eye"
    #expect(try view("IC5070", 5) == nil && view("IC5070", 2) == nil)
    #expect(try view("NGC6888", 5) == nil && view("NGC6888", 2) == nil)   // the Crescent needs a filter
    #expect(try view("NGC6853", 5) == .binoculars)     // M27: "easily visible in binoculars"
    #expect(try view("NGC6960", 1) == nil)             // the Veil needs an O-III filter
    #expect(try view("NGC6205", 5) == .binoculars && view("NGC6205", 2) == .nakedEye)   // M13
    #expect(try view("NGC0869", 5) == .nakedEye)       // the Double Cluster
    #expect(try view("NGC5457", 5) == nil)             // M101: too faint per square arcsecond for a suburban sky
    let nan = try row("NGC7000")
    #expect(nan.sizeArcmin == 120 && nan.minorArcmin == 100)   // OpenNGC's 120 × 30, corrected
}

@Test func eyesAndBinocularsKeepTheMoonPlanetsAndStarsRules() {
    #expect(EyeViews.view(eyeTarget("M42w", .nebulae, mag: 4, size: 65, washed: true), bortle: 5) == nil)
    #expect(EyeViews.view(eyeTarget("moon", .planets, mag: nil, size: 31), bortle: 9) == .nakedEye)
    #expect(EyeViews.view(eyeTarget("planet-neptune", .planets, mag: 7.8, size: nil), bortle: 5) == .binoculars)
    #expect(EyeViews.view(eyeTarget("HIP1", .stars, mag: 0.5, size: nil), bortle: 5) == nil)
    let m31 = eyeTarget("M31", .galaxies, mag: 3.44, size: 177.8, minor: 69.7, type: "Galaxy")
    let m13 = eyeTarget("M13", .clusters, mag: 5.8, size: 20, type: "Globular cluster")
    #expect(Copy.eyeLook(m31, .nakedEye) == "A faint smudge to the eye")
    #expect(Copy.eyeLook(m13, .binoculars) == "A fuzzy ball in binoculars")
}

// What the numbers mean (#59): every term the popover and target cards show has a plain entry.
@Test func everyTermOnScreenIsExplained() {
    let titles = NumbersGuide.entries.map(\.title).joined(separator: " ").lowercased()
    for term in ["sky score", "go rule", "clear window", "dark", "moon", "seeing", "transparency", "wind", "dew", "haze or smoke", "rain possible", "bortle", "eq tilt", "labels"] {
        #expect(titles.contains(term), "no entry for \(term)")
    }
    let text = NumbersGuide.entries.map(\.body).joined(separator: " ")
    for shown in ["Held back by", "of frame", "Small in frame", "Mosaic", "Moon-washed", "Near Moon", "Naked eye", "Binoculars", "arcseconds"] {
        #expect(text.contains(shown), "\(shown) is not explained")
    }
    #expect(Set(NumbersGuide.entries.map(\.id)).count == NumbersGuide.entries.count)
    // The sky score says which way is better and keeps its weights to itself; nobody but a developer says "chips" (owner, 29 September 2026).
    let score = NumbersGuide.entries.first { $0.id == "score" }!.body
    #expect(score.contains("the higher, the better") && !score.contains("points") && !score.contains("(15)"))
    #expect(!text.lowercased().contains("chip") && !titles.contains("chip"))
    // The figures quoted are the app's own.
    let rule = GoRule()
    #expect(text.contains("at least \(Int(rule.minHours)) hours") && text.contains("\(rule.maxCloudPct)%") && text.contains("\(Int(rule.minAltitudeDeg))° up"))
    #expect(text.contains("a \(Planner.rainRiskPct)% chance or more"))
    #expect(text.contains("an aerosol optical depth of \(Planner.hazeDepth) or more"))
}

@Test func eyesAndBinocularsEventsLeaveOutFaintPlanets() {
    func e(_ kind: SkyEventKind, _ title: String) -> SkyEvent {
        SkyEvent(id: title, kind: kind, title: title, detail: "", time: Date(), endTime: nil, raHours: nil, decDeg: nil)
    }
    #expect(EyeViews.includes(e(.conjunction, "Moon near Jupiter")) && !EyeViews.includes(e(.conjunction, "Moon near Neptune")))
    #expect(EyeViews.includes(e(.meteorShower, "Orionids")) && !EyeViews.includes(e(.solarEclipse, "Partial solar eclipse")))
}

// Siri's "Find the Crescent Nebula in Nightwatch" (#72): on 27 October 2026, with no clear window and the Moon at 95%, NGC 6888 was not in tonight's
// ranked list, so the search found nothing and the window stayed on Tonight's plan. The catalogue answers it whether or not it is up tonight.
@Test func theCatalogueAnswersASearchTonightsListCannot() throws {
    let catalog = try Catalog.bundled()
    #expect(catalog.objects(matching: "Crescent Nebula").map(\.id) == ["NGC6888"])
    #expect(catalog.objects(matching: "NGC 6888").map(\.id) == ["NGC6888"])
    #expect(catalog.objects(matching: "C27").map(\.id) == ["NGC6888"])
    #expect(catalog.objects(matching: "M31").map(\.id) == ["NGC0224"])
    #expect(catalog.objects(matching: "   ").isEmpty && catalog.objects(matching: "zzzz nothing").isEmpty)
}

@Test func theHintSaysATargetIsInTheCatalogueButNotUpTonight() throws {
    let catalog = try Catalog.bundled()
    let crescent = catalog.objects(matching: "Crescent Nebula")
    let hint = try #require(Copy.searchHint(query: "Crescent Nebula", targets: [], group: .nebulae, fitsOnly: false, includeMoonWashed: false, notPlanned: crescent.map(\.group)))
    #expect(hint == "No match for “Crescent Nebula” in Nebulae tonight. 1 more not in tonight's list, shown last.")
    // Matches in another group are counted there, listed tonight or not.
    let andromeda = catalog.objects(matching: "M31")
    #expect(try #require(Copy.searchHint(query: "M31", targets: [], group: .nebulae, fitsOnly: false, includeMoonWashed: false, notPlanned: andromeda.map(\.group)))
            == "No match for “M31” in Nebulae tonight. Also in Galaxies (1).")
    // With nothing to add, or a planned match, the hint is as it was.
    #expect(try #require(Copy.searchHint(query: "Crescent Nebula", targets: [], group: .nebulae, fitsOnly: false, includeMoonWashed: false)) == "No match for “Crescent Nebula” in Nebulae tonight.")
}

@Test func spokenTonightQuestionsOpenThePlan() {
    #expect(SpokenSearch.asksForTonight("tonight") && SpokenSearch.asksForTonight("What's worth imaging tonight") && SpokenSearch.asksForTonight("tonight's plan"))
    #expect(SpokenSearch.asksForTonight("plan"))
    #expect(!SpokenSearch.asksForTonight("Crescent Nebula") && !SpokenSearch.asksForTonight("M31") && !SpokenSearch.asksForTonight("Seven Sisters"))
}

@Test func aSpokenSearchOpensTheGroupOfItsBestMatch() throws {
    let catalog = try Catalog.bundled()
    func planned(_ id: String) throws -> RankedTarget {
        let o = try #require(catalog.objects.first { $0.id == id })
        var r = RankedTarget(id: o.id, name: o.displayName, subtitle: "\(o.typeCode) in \(o.constellation)", group: o.group, raHours: o.raHours, decDeg: o.decDeg,
                             sizeArcmin: o.majAxisArcmin, magnitude: o.magnitude, fit: .fits, peakAltDeg: 60, peakTime: Date(), moonSepDeg: 90, moonWashed: false, visibleFraction: 1)
        r.typeName = Catalog.typeNames[o.typeCode] ?? o.typeCode
        return r
    }
    // Up tonight: its group from the plan. Not up tonight: its group from the catalogue. Neither: nil.
    #expect(SpokenSearch.group(for: "Crescent Nebula", planned: [try planned("NGC6888")], catalogue: catalog) == .nebulae)
    #expect(SpokenSearch.group(for: "Crescent Nebula", planned: [], catalogue: catalog) == .nebulae)
    #expect(SpokenSearch.group(for: "M31", planned: [], catalogue: catalog) == .galaxies)
    #expect(SpokenSearch.group(for: "zzzz nothing", planned: [], catalogue: catalog) == nil)
}

// #250: "I wanted to search for the North American Nebula so I could put a heart on it ... but could not find a way to do so if it was not
// visible". A search now cards what the catalogue has and the night's list leaves out, greyed with when it is next well placed.
private let searchSite = Site(name: "Sheffield", latitude: 53.38, longitude: -1.47, elevationM: 100, timeZoneID: "Europe/London", bortle: 5)
private func searchPlan(_ y: Int, _ m: Int, _ d: Int) throws -> NightPlan {
    let night = try Ephemeris.night(localDate: utc(y, m, d, 12, 0), site: searchSite)
    return NightPlan(night: night, windows: [], primary: nil, score: 10, qualifies: false, moonIllumination: 0.3, moonRise: nil, moonSet: nil,
                     darkHours: [], targets: [], best: [], seeingAvailable: false)
}
private func extras(_ query: String, _ group: TargetGroup, _ plan: NightPlan, ranked: [RankedTarget] = []) throws -> [FavouriteTarget] {
    SearchExtras().cards(query: query, group: group, ranked: ranked, catalog: try Catalog.bundled(), plan: plan, site: searchSite,
                         fov: FieldOfView(widthDeg: 2.1, heightDeg: 1.2), rule: GoRule())
}

@Test func aSearchCardsWhatTheNightsListLeavesOutWithWhenItIsNextWellPlaced() throws {
    // Midsummer in Sheffield has no astronomical darkness, so nothing is listed: the Andromeda Galaxy is greyed with the night it returns.
    let june = try searchPlan(2026, 6, 21)
    let m31 = try #require(try extras("M31", .galaxies, june).first)
    let reason = try #require(m31.notTonight)
    #expect(m31.target.id == "NGC0224" && reason.hasPrefix("Next well placed from "))
    // The date is the first such night, to the day: the same answer as trying every night in turn.
    let o = try #require(try Catalog.bundled().objects.first { $0.id == "NGC0224" })
    let next = try #require(Planner.nextWellPlaced(raHours: o.raHours, decDeg: o.decDeg, after: june.night, site: searchSite, minAlt: 30))
    func placed(_ i: Int) throws -> Bool {
        let n = try Ephemeris.night(localDate: searchSite.calendar.date(byAdding: .day, value: i, to: june.night.localDate)!, site: searchSite)
        guard let s = n.darkStart, let e = n.darkEnd else { return false }
        return Planner.track(raHours: o.raHours, decDeg: o.decDeg, window: ClearWindow(start: s, end: e), site: searchSite, minAlt: 30).fraction >= 0.5
    }
    let first = try #require(try (1...364).first { try placed($0) })
    #expect(next.localDate == searchSite.calendar.date(byAdding: .day, value: first, to: june.night.localDate))
    #expect(reason == Copy.nextWellPlaced(next, decDeg: o.decDeg, site: searchSite, minAlt: 30))
    // The Lagoon Nebula reaches 12° at best from 53° north.
    #expect(try extras("M8", .nebulae, june).first { $0.target.id == "NGC6523" }?.notTonight == "Never clears 30° from here")
}

@Test func aSearchedTargetThatIsUpTonightIsAnOrdinaryCardAndOneAlreadyListedIsNotRepeated() throws {
    let september = try searchPlan(2026, 9, 21)
    let m31 = try #require(try extras("M31", .galaxies, september).first)
    #expect(m31.notTonight == nil && m31.target.visibleFraction >= 0.5)
    #expect(try extras("M31", .galaxies, september, ranked: [m31.target]).isEmpty)
    #expect(try extras("M31", .nebulae, september).isEmpty && extras("  ", .galaxies, september).isEmpty)
}

@Test func aBroadSearchCardsOnlyTheBrightestFew() throws {
    let found = try extras("galaxy", .galaxies, try searchPlan(2026, 6, 21))
    #expect(found.count == SearchExtras.limit)
    #expect(found.contains { $0.target.id == "NGC0224" })
}

@Test func aSharplessNumberFindsItsNebulaHoweverItIsTyped() throws {
    let catalog = try Catalog.bundled()
    for typed in ["Sh2-101", "sh2 101", "Sh 2-101", "SH2101"] { #expect(catalog.objects(matching: typed).map(\.id) == ["Sh2-101"], "\(typed)") }
    #expect(catalog.objects(matching: "Sh2-117").map(\.id) == ["NGC7000"])   // the North America Nebula, by its Sharpless number
    #expect(catalog.objects(matching: "Sh2-25").map(\.id).contains("NGC6523"))   // the Lagoon; a number is matched from its start, as "NGC 22" is
    #expect(catalog.objects(matching: "sh2-155").map(\.id) == ["C009"])
    #expect(catalog.objects(matching: "Sh2-281").map(\.id) == ["NGC1976"])   // the Orion Nebula, by position
    #expect(catalog.objects(matching: "Sh2-279").map(\.id) == ["NGC1977"])
    // A bare number is still an NGC, IC, Messier or Caldwell number: every Sharpless name starts "2-".
    #expect(!catalog.objects(matching: "21").contains { $0.id.hasPrefix("Sh2-") })
    #expect(catalog.objects(matching: "2175").map(\.id) == ["NGC2175"])       // and not by the "Sh 2-252" it also carries
}
