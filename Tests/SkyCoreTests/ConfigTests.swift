import Testing
import Foundation
@testable import SkyCore

@Test func presetsLoad() throws {
    let p = try TelescopePresets.bundled()
    #expect(p.count == 5)
    let draco = try #require(p.first { $0.id == "draco" })
    #expect(draco.widthDeg == 1.65 && draco.heightDeg == 1.24)
    #expect(p.first { $0.id == "dwarf-mini" }?.widthDeg == 2.1)
}

@Test func defaultConfigIsSane() {
    let c = Config.default
    #expect(c.sites.isEmpty && c.activeSiteName == nil)
    #expect(c.fov == FieldOfView(widthDeg: 2.1, heightDeg: 1.2))
    #expect(c.goRule == GoRule())
    #expect(c.notifyEnabled && !c.loginItem)
}

@Test func roundTripsThroughDisk() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let url = dir.appendingPathComponent("config.json")
    var c = Config.default
    c.sites = [Site(name: "Home", latitude: 53.38, longitude: -1.47, elevationM: 100, timeZoneID: "Europe/London", bortle: 5)]
    c.activeSiteName = "Home"
    try ConfigStore.save(c, to: url)
    #expect(try ConfigStore.load(from: url) == c)
    #expect(try ConfigStore.load(from: dir.appendingPathComponent("missing.json")) == Config.default)
}

@Test func activeSiteResolution() {
    var c = Config.default
    let home = Site(name: "Home", latitude: 1, longitude: 2, elevationM: 0, timeZoneID: "UTC", bortle: 4)
    let auto = Site(name: "Current location", latitude: 9, longitude: 9, elevationM: 0, timeZoneID: "UTC", bortle: 5)
    c.sites = [home]
    #expect(c.activeSite(auto: auto) == auto)
    #expect(c.activeSite(auto: nil) == home)
    c.activeSiteName = "Home"
    #expect(c.activeSite(auto: auto) == home)
    c.sites = []; c.activeSiteName = nil
    #expect(c.activeSite(auto: nil) == nil)
}

@Test func saveThroughSymlinkKeepsTheLink() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let realURL = dir.appendingPathComponent("real").appendingPathComponent("config.json")
    try ConfigStore.save(Config.default, to: realURL)

    let linkURL = dir.appendingPathComponent("link.json")
    try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: realURL)

    var modified = Config.default
    modified.notifyEnabled = false
    try ConfigStore.save(modified, to: linkURL)

    #expect(try FileManager.default.attributesOfItem(atPath: linkURL.path)[.type] as? FileAttributeType == .typeSymbolicLink)
    #expect(try ConfigStore.load(from: realURL).notifyEnabled == false)
}

@Test func decodesPartialFileWithDefaults() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("config.json")
    let json = #"{"flavour":"plain","goRule":{"minHours":2,"maxCloudPct":40,"minAltitudeDeg":30}}"#
    try json.write(to: url, atomically: true, encoding: .utf8)

    let c = try ConfigStore.load(from: url)   // "flavour", removed in 0.7.0, is ignored
    #expect(c.goRule.minHours == 2)
    var expected = Config.default
    expected.goRule = GoRule(minHours: 2, maxCloudPct: 40, minAltitudeDeg: 30)
    expected.welcomed = true   // a config file that already exists belongs to someone who is already set up (v0.6.7)
    #expect(c == expected)
}

@Test func malformedFileThrows() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("config.json")
    try "{not json".write(to: url, atomically: true, encoding: .utf8)
    #expect(throws: (any Error).self) { try ConfigStore.load(from: url) }
}

@Test func darkSiteSettingsDefaultAndDecode() throws {
    #expect(Config.default.darkSites == DarkSiteSettings())
    #expect(DarkSiteSettings().radiusKm == 50 && DarkSiteSettings().unit == .km && DarkSiteSettings().enabled)
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("config.json")
    try Data(#"{"darkSites":{"radiusKm":80,"unit":"mi"}}"#.utf8).write(to: url)
    let c = try ConfigStore.load(from: url)
    #expect(c.darkSites.radiusKm == 80 && c.darkSites.unit == .mi && c.darkSites.enabled)
}

@Test func danglingSymlinkThrows() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let link = dir.appendingPathComponent("config.json")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: dir.appendingPathComponent("gone/config.json"))
    #expect(throws: (any Error).self) { try ConfigStore.load(from: link) }
}

@Test func darkSiteRadiusIsClampedOnDecode() throws {
    let low = try JSONDecoder().decode(DarkSiteSettings.self, from: Data(#"{"radiusKm":0}"#.utf8))
    let high = try JSONDecoder().decode(DarkSiteSettings.self, from: Data(#"{"radiusKm":5000}"#.utf8))
    let ok = try JSONDecoder().decode(DarkSiteSettings.self, from: Data(#"{"radiusKm":120}"#.utf8))
    #expect(low.radiusKm == 5 && high.radiusKm == 300 && ok.radiusKm == 120)
}

@Test func unknownDistanceUnitDecodesAsKm() throws {
    let c = try JSONDecoder().decode(Config.self, from: Data(#"{"flavour":"plain","darkSites":{"unit":"furlongs","radiusKm":80}}"#.utf8))
    #expect(c.darkSites.unit == .km && c.darkSites.radiusKm == 80)
}

@Test func brightSettingsDefaultAndLenientDecode() throws {
    #expect(Config.default.brightNights == BrightSettings())
    #expect(!BrightSettings().enabled && BrightSettings().minHours == 1)
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("config.json")
    try Data(#"{"brightNights":{"enabled":true}}"#.utf8).write(to: url)
    let c = try ConfigStore.load(from: url)
    #expect(c.brightNights.enabled && c.brightNights.minHours == 1)
    try Data(#"{"brightNights":{"minHours":12}}"#.utf8).write(to: url)
    #expect(try ConfigStore.load(from: url).brightNights.minHours == 6)   // clamped to the Settings range
    try Data(#"{"sites":[]}"#.utf8).write(to: url)
    #expect(try ConfigStore.load(from: url).brightNights == BrightSettings())
}

// Sites (v0.6.5): home, visiting a dark site, keeping it, and going back.
private func site(_ n: String, _ lat: Double, _ lon: Double, bortle: Int = 5) -> Site {
    Site(name: n, latitude: lat, longitude: lon, elevationM: 100, timeZoneID: "Europe/London", bortle: bortle)
}
private let testSite = site("Home", 54.0, -1.5), garden = site("Back garden", 54.002, -1.504)
private let york = site("University of York - Astrocampus", 53.943, -1.060, bortle: 6)

@Test func homeIsTheStarredSiteElseTheFirstSavedElseThisMac() {
    var c = Config(); let mac = site("Here", 51.5, -0.1)
    #expect(c.homeSite(auto: mac) == mac)                       // nothing saved: this Mac's location
    c.sites = [testSite, garden]
    #expect(c.homeSite(auto: mac) == testSite)                     // not starred: the first saved site
    c.homeSiteName = "Back garden"
    #expect(c.homeSite(auto: mac) == garden)
}

@Test func visitingADarkSiteDoesNotSaveItAndGoingHomeReturns() {
    var c = Config(); c.sites = [testSite]; c.activeSiteName = "Home"
    c.visit(york)
    #expect(c.sites == [testSite] && c.activeSite(auto: nil) == york && c.isAway(auto: nil))
    c.goHome()
    #expect(c.visiting == nil && c.activeSite(auto: nil) == testSite && !c.isAway(auto: nil))
}

@Test func visitingASavedPlaceSelectsItInstead() {
    var c = Config(); c.sites = [testSite, york]; c.activeSiteName = "Home"
    c.visit(site("Astrocampus", 53.9432, -1.0605))              // within 0.001° of the saved York site
    #expect(c.visiting == nil && c.activeSiteName == york.name)
}

@Test func keepingAVisitSavesItUnderAFreeName() {
    var c = Config(); c.sites = [testSite, site("University of York - Astrocampus", 0, 0)]
    c.visit(york); c.keepVisiting()
    #expect(c.visiting == nil && c.sites.count == 3)
    #expect(c.activeSiteName == "University of York - Astrocampus (dark site)" && c.activeSite(auto: nil)?.latitude == york.latitude)
}

@Test func choosingASiteOrThisMacEndsAVisit() {
    var c = Config(); c.sites = [testSite]; c.visit(york)
    c.choose(savedName: nil)
    #expect(c.visiting == nil && c.activeSiteName == nil)
}

@Test func removingHomeOrTheActiveSiteFallsBack() {
    var c = Config(); c.sites = [testSite, garden]; c.homeSiteName = "Back garden"; c.activeSiteName = "Back garden"
    c.remove(savedName: "Back garden")
    #expect(c.sites == [testSite] && c.homeSiteName == nil && c.activeSiteName == nil)
}

@Test func homeWithNoSavedSiteGoesBackToThisMac() {
    var c = Config(); c.visit(york)
    c.goHome()
    #expect(c.visiting == nil && c.activeSiteName == nil)
}

@Test func olderConfigsDecodeWithoutTheNewKeys() throws {
    let json = #"{"sites":[{"name":"Home","latitude":54.0,"longitude":-1.5,"elevationM":100,"timeZoneID":"Europe/London","bortle":5}],"activeSiteName":"Test site"}"#
    let c = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
    #expect(c.homeSiteName == nil && c.visiting == nil && c.homeSite(auto: nil)?.name == "Home")
}

@Test func bortleLevelsHavePlainNames() {
    #expect(Bortle.name(1) == "Pristine" && Bortle.name(5) == "Suburban" && Bortle.name(9) == "Inner city")
    #expect((1...9).allSatisfy { !Bortle.name($0).isEmpty })
}

@Test func thisMacCanBeHomeAndIsNeverAwayFromItself() {
    var c = Config(); c.sites = [testSite]; c.homeIsThisMac = true
    let mac = site("Here", 51.5, -0.1), moved = site("Here", 51.52, -0.12)
    #expect(c.homeSite(auto: mac) == mac && !c.isAway(auto: moved))   // on Automatic at home: a moving fix never flickers "away"
    c.choose(savedName: "Home")
    #expect(c.isAway(auto: mac))
    c.goHome()
    #expect(c.activeSiteName == nil && c.visiting == nil)
    c.homeSiteName = "Test site"; c.homeIsThisMac = false
    #expect(c.homeSite(auto: mac) == testSite)
}

@Test func olderConfigOnAutomaticKeepsThisMacAsHome() throws {
    let json = #"{"sites":[{"name":"Dark spot","latitude":54.1,"longitude":-1.6,"elevationM":100,"timeZoneID":"Europe/London","bortle":3}]}"#
    let c = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
    #expect(c.homeIsThisMac && !c.isAway(auto: site("Here", 54.1, -1.6)))
}

@Test func keepingTheFirstVisitLeavesThisMacAsHome() {
    var c = Config(); c.visit(york); c.keepVisiting()
    #expect(c.homeIsThisMac && c.sites.count == 1)
}

@Test func keepingAVisitAvoidsNamesInAnyCase() {
    var c = Config(); c.sites = [site("university of york - astrocampus", 0, 0)]
    c.visit(york); c.keepVisiting()
    #expect(c.sites.last?.name == "University of York - Astrocampus (dark site)")
}

/// At most ten saved sites (owner, 30 September 2026); a longer synced list is kept, only adding stops.
@Test func savedSitesStopAtTen() {
    var c = Config()
    c.sites = (0..<9).map { site("Site \($0)", 50 + Double($0) * 0.1, -1) }
    #expect(c.canAddSite)
    c.visit(york); c.keepVisiting()
    #expect(c.sites.count == 10 && !c.canAddSite)
    c.visit(site("Somewhere dark", 55.2, -2.6)); c.keepVisiting()
    #expect(c.sites.count == 10 && c.visiting != nil)          // not kept: still only visiting
    c.sites.append(site("Synced eleventh", 56, -3))            // a list from another Mac or an older version
    #expect(c.sites.count == 11 && !c.canAddSite)
}
