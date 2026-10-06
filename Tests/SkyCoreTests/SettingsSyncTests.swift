import Testing
import Foundation
@testable import SkyCore

private func site(_ name: String) -> Site {
    Site(name: name, latitude: 55.23, longitude: -2.58, elevationM: 200, timeZoneID: "Europe/London", bortle: 2)
}

@Test func syncCarriesSharedSettingsAndKeepsEachMacsOwn() {
    var a = Config()
    a.sites = [site("Kielder"), site("Dartmoor")]
    a.homeSiteName = "Kielder"
    a.fovPresetID = "draco"
    a.favourites = ["NGC6888"]
    a.goRule.maxCloudPct = 30
    a.loginItem = true
    a.activeSiteName = "Dartmoor"
    a.visiting = site("Spot")
    a.homeIsThisMac = true
    a.welcomed = true

    let payload = SettingsSync.outgoing(a, at: Date(timeIntervalSince1970: 1_000)), sent = payload.config
    #expect(!sent.loginItem && sent.activeSiteName == nil && sent.visiting == nil && !sent.welcomed)
    #expect(sent.sites == a.sites && sent.homeSiteName == "Kielder" && sent.fovPresetID == "draco" && sent.favourites == ["NGC6888"])
    #expect(sent.homeIsThisMac)                                        // all of home travels (owner, 5 October 2026)

    var b = Config()
    b.loginItem = false
    b.activeSiteName = "Kielder"
    b.welcomed = true
    let merged = SettingsSync.merge(remote: payload, local: b)
    #expect(merged.sites == a.sites && merged.goRule.maxCloudPct == 30 && merged.fovPresetID == "draco")
    #expect(!merged.loginItem && merged.activeSiteName == "Kielder" && merged.visiting == nil && merged.welcomed)
}

@Test func syncPayloadRoundTripsAndTheNewerCopyWins() throws {
    var c = Config(); c.favourites = ["M31"]
    let p = SettingsSync.outgoing(c, at: Date(timeIntervalSince1970: 1_000))
    #expect(SettingsSync.decode(try #require(SettingsSync.encode(p))) == p)
    #expect(SettingsSync.decode(Data("not json".utf8)) == nil)
    let t = Date(timeIntervalSince1970: 1_000)
    #expect(SettingsSync.remoteWins(remoteSavedAt: t, localSavedAt: nil))
    #expect(SettingsSync.remoteWins(remoteSavedAt: t, localSavedAt: t.addingTimeInterval(-1)))
    #expect(!SettingsSync.remoteWins(remoteSavedAt: t, localSavedAt: t))
}

/// Home is one setting for every Mac (owner, 5 October 2026). It was half shared: the starred saved site travelled, but
/// "This Mac's location" as home did not, so a Mac at home could be told it was away from a site starred on another.
@Test func homeIsSharedByEveryMac() {
    var a = Config()
    a.sites = [site("Kielder"), site("Dartmoor")]
    a.homeSiteName = "Kielder"
    var b = a
    b.activeSiteName = "Dartmoor"                                      // where this Mac observes from stays its own

    // Starring "This Mac's location" on one Mac makes it home on the other too: each then uses its own location.
    a.homeIsThisMac = true
    b = SettingsSync.merge(remote: SettingsSync.outgoing(a, at: Date()), local: b)
    #expect(b.homeIsThisMac && b.activeSiteName == "Dartmoor")

    // Starring a saved site on one Mac makes it home on the other, in place of that Mac's own location.
    a.homeSiteName = "Dartmoor"; a.homeIsThisMac = false
    b = SettingsSync.merge(remote: SettingsSync.outgoing(a, at: Date()), local: b)
    #expect(!b.homeIsThisMac && b.homeSiteName == "Dartmoor" && b.activeSiteName == "Dartmoor")
}

/// A Mac still on 1.3.1 or earlier always sends "home is not this Mac's location", whatever its own choice. Its copy
/// must not knock that choice off a Mac that has it, so only a sender that shares home is believed about it.
@Test func anOlderMacsCopyLeavesThisMacAsHomeAlone() throws {
    var here = Config()
    here.sites = [site("Kielder")]
    here.homeIsThisMac = true
    let old = try #require(SettingsSync.decode(Data(#"{"savedAt":"2026-10-05T12:00:00Z","config":{"sites":[],"homeSiteName":"Kielder","homeIsThisMac":false}}"#.utf8)))
    #expect(old.sharesHome != true)
    let merged = SettingsSync.merge(remote: old, local: here)
    #expect(merged.homeIsThisMac && merged.homeSiteName == "Kielder")
    #expect(SettingsSync.outgoing(here, at: Date()).sharesHome == true)
}

/// Text size is a matter of one Mac's display and the eyes in front of it, so it stays on that Mac.
@Test func textSizeStaysOnEachMac() throws {
    #expect(Config.default.textSize == .standard && TextSize.standard.factor == 1)
    #expect(TextSize.allCases.map(\.factor) == [1, 1.15, 1.3] && TextSize.allCases.map(\.displayName) == ["Standard", "Large", "Extra large"])
    var a = Config(); a.textSize = .extraLarge
    #expect(SettingsSync.outgoing(a, at: Date()).config.textSize == .standard)          // not sent
    var b = Config(); b.textSize = .large
    #expect(SettingsSync.merge(remote: SettingsSync.outgoing(a, at: Date()), local: b).textSize == .large)   // nor taken
    // Saved and read back; a file from before the setting, or with a size this version does not know, reads as standard.
    let e = JSONEncoder(), d = JSONDecoder()
    #expect(try d.decode(Config.self, from: e.encode(a)).textSize == .extraLarge)
    #expect(try d.decode(Config.self, from: Data(#"{"sites":[]}"#.utf8)).textSize == .standard)
    #expect(try d.decode(Config.self, from: Data(#"{"textSize":"enormous"}"#.utf8)).textSize == .standard)
}


// MARK: A Mac joining sync (owner, 6 October 2026: every saved site vanished from every Mac)

/// A Mac that has never taken the shared copy has nothing to say about it. Sent first, its settings used to replace
/// every other Mac's; now a Mac that has synced keeps its own and only gains what the newcomer has extra.
@Test func aMacThatHasNeverSyncedCannotEmptyTheOthers() {
    var mine = Config()
    mine.sites = [site("Kielder"), site("Dartmoor")]
    mine.homeSiteName = "Kielder"
    mine.favourites = ["NGC6888", "M31"]
    mine.goRule.maxCloudPct = 40
    mine.aurora.enabled = true

    let fresh = SettingsSync.outgoing(Config(), at: Date(), joined: false)   // a new Mac's defaults, sent before it heard anything
    #expect(fresh.joined == false)
    #expect(SettingsSync.merge(remote: fresh, local: mine, joined: true) == mine)

    var newcomer = Config()
    newcomer.sites = [site("Exmoor")]
    newcomer.favourites = ["M42"]
    newcomer.goRule.maxCloudPct = 10
    let merged = SettingsSync.merge(remote: SettingsSync.outgoing(newcomer, at: Date(), joined: false), local: mine, joined: true)
    #expect(merged.sites.map(\.name) == ["Kielder", "Dartmoor", "Exmoor"])
    #expect(merged.favourites == ["NGC6888", "M31", "M42"])
    #expect(merged.goRule.maxCloudPct == 40 && merged.homeSiteName == "Kielder" && merged.aurora.enabled)
}

/// The newcomer's side: it takes the shared settings and keeps the sites and favourites it already had, whichever copy
/// is the newer.
@Test func aJoiningMacTakesTheSharedSettingsAndKeepsItsOwnSites() {
    var shared = Config()
    shared.sites = [site("Kielder")]
    shared.homeSiteName = "Kielder"
    shared.favourites = ["NGC6888"]
    shared.goRule.maxCloudPct = 40
    var newcomer = Config()
    newcomer.sites = [site("Exmoor"), site("Kielder")]
    newcomer.favourites = ["M42", "NGC6888"]
    newcomer.textSize = .large

    let merged = SettingsSync.merge(remote: SettingsSync.outgoing(shared, at: Date()), local: newcomer, joined: false)
    #expect(merged.sites.map(\.name) == ["Kielder", "Exmoor"] && merged.favourites == ["NGC6888", "M42"])
    #expect(merged.goRule.maxCloudPct == 40 && merged.homeSiteName == "Kielder" && merged.textSize == .large)

    let t = Date(timeIntervalSince1970: 2_000)
    #expect(SettingsSync.remoteWins(remoteSavedAt: t, localSavedAt: t.addingTimeInterval(60), joined: false))   // its new file is not "newer"
    #expect(!SettingsSync.remoteWins(remoteSavedAt: t, localSavedAt: t.addingTimeInterval(60), joined: true))
}

/// Between Macs that have both synced nothing changes: removing a site, or Reset config, still reaches the others.
@Test func aSyncedMacsRemovalStillReachesTheOthers() {
    var a = Config()
    a.sites = [site("Kielder")]
    var b = a
    b.sites.append(site("Dartmoor"))
    b.favourites = ["M31"]
    let merged = SettingsSync.merge(remote: SettingsSync.outgoing(a, at: Date(), joined: true), local: b, joined: true)
    #expect(merged.sites.map(\.name) == ["Kielder"] && merged.favourites.isEmpty)
    #expect(SettingsSync.merge(remote: SettingsSync.outgoing(.default, at: Date(), joined: true), local: b, joined: true).sites.isEmpty)
}

/// A copy from 1.5.2 or earlier does not say whether its Mac had synced, so its settings are taken as before but it
/// cannot take a site or a favourite away.
@Test func anOlderVersionsCopyCannotRemoveSites() throws {
    var here = Config()
    here.sites = [site("Kielder")]
    here.favourites = ["M31"]
    let old = try #require(SettingsSync.decode(Data(#"{"savedAt":"2026-10-06T07:00:00Z","sharesHome":true,"config":{"sites":[],"favourites":[],"goRule":{"minHours":2,"maxCloudPct":25,"minAltitudeDeg":30}}}"#.utf8)))
    #expect(old.joined == nil)
    let merged = SettingsSync.merge(remote: old, local: here, joined: true)
    #expect(merged.sites.map(\.name) == ["Kielder"] && merged.favourites == ["M31"] && merged.goRule.minHours == 2)
}
