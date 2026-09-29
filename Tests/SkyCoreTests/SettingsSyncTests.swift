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

    let sent = SettingsSync.outgoing(a, at: Date(timeIntervalSince1970: 1_000)).config
    #expect(!sent.loginItem && sent.activeSiteName == nil && sent.visiting == nil && !sent.homeIsThisMac && !sent.welcomed)
    #expect(sent.sites == a.sites && sent.homeSiteName == "Kielder" && sent.fovPresetID == "draco" && sent.favourites == ["NGC6888"])

    var b = Config()
    b.loginItem = false
    b.activeSiteName = "Kielder"
    b.welcomed = true
    let merged = SettingsSync.merge(remote: sent, local: b)
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
