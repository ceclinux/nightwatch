import Testing
import Foundation
import SkyCore
@testable import PhoneCore

final class FakeKeyValueStore: KeyValueStoring, @unchecked Sendable {
    var values: [String: Data] = [:]
    var writes = 0
    private var handler: (@Sendable () -> Void)?
    func data(forKey key: String) -> Data? { values[key] }
    func set(_ data: Data?, forKey key: String) { values[key] = data; writes += 1 }
    func synchronize() {}
    func observeExternalChanges(_ handler: @escaping @Sendable () -> Void) -> AnyObject { self.handler = handler; return self }
    /// What another device does: put a copy in and tell the others.
    func changeFromElsewhere(_ data: Data) { values[SettingsSync.key] = data; handler?() }
}

private func site(_ name: String) -> Site { Site(name: name, latitude: 54, longitude: -2, elevationM: 100, timeZoneID: "Europe/London", bortle: 3) }

private func payload(_ config: Config, at date: Date, joined: Bool = true) -> Data {
    SettingsSync.encode(SettingsSync.outgoing(config, at: date, joined: joined))!
}

private func freshDefaults() -> UserDefaults {
    let d = UserDefaults(suiteName: "phonecore-\(UUID().uuidString)")!
    return d
}

@MainActor private final class Rig {
    var config: Config
    let kv = FakeKeyValueStore()
    let defaults = freshDefaults()
    var now = utc(2026, 10, 13, 12)
    var slept: [TimeInterval] = []
    var coordinator: SettingsSyncCoordinator!
    init(config: Config = .default) {
        self.config = config
        coordinator = SettingsSyncCoordinator(store: kv, defaults: defaults, clock: { [unowned self] in self.clockNow },
                                              sleep: { [unowned self] s in await self.fakeSleep(s) },
                                              readConfig: { [unowned self] in self.config }, writeConfig: { [unowned self] c in self.config = c })
    }
    nonisolated var clockNow: Date { MainActor.assumeIsolated { now } }
    func fakeSleep(_ s: TimeInterval) async { slept.append(s); now = now.addingTimeInterval(s) }
    func remote() -> SettingsSync.Payload? { kv.values[SettingsSync.key].flatMap(SettingsSync.decode) }
}

@MainActor @Test func aNewPhoneTakesTheMacsSitesAndJoins() {
    var mac = Config.default
    mac.sites = [site("Malham"), site("Sutton Bank")]
    mac.favourites = ["M31"]
    let rig = Rig()
    rig.kv.values[SettingsSync.key] = payload(mac, at: utc(2026, 10, 13, 11))
    rig.coordinator.start(localModified: nil)
    #expect(rig.config.sites.map(\.name) == ["Malham", "Sutton Bank"])
    #expect(rig.config.favourites == ["M31"])
    #expect(rig.coordinator.joined)
    // It has joined, so it may now answer; the copy it sends still carries the Mac's sites.
    #expect(rig.remote()?.config.sites.map(\.name) == ["Malham", "Sutton Bank"])
}

@MainActor @Test func aNewPhoneWithNothingInICloudSendsNothingAtLaunch() {
    let rig = Rig()
    rig.coordinator.start(localModified: nil)
    #expect(rig.kv.writes == 0)   // iCloud's copy may simply not have arrived yet: this is how a newcomer once emptied every Mac
    #expect(!rig.coordinator.joined)
}

@MainActor @Test func aPhoneThatHasSyncedBeforeSendsItsSettingsWhenICloudIsEmpty() {
    var c = Config.default; c.sites = [site("Home")]
    let rig = Rig(config: c)
    rig.coordinator.joined = true
    rig.coordinator.start(localModified: utc(2026, 10, 1))
    #expect(rig.remote()?.config.sites.map(\.name) == ["Home"])
}

@MainActor @Test func aSiteAddedOnThePhoneIsSent() {
    let rig = Rig()
    rig.coordinator.joined = true
    rig.config.sites = [site("Garden")]
    rig.coordinator.send()
    #expect(rig.remote()?.config.sites.map(\.name) == ["Garden"])
}

@MainActor @Test func aPhoneThatHasNotJoinedHoldsItsChangesBackUntilTheWaitIsOver() async {
    let rig = Rig()
    rig.config.sites = [site("Garden")]
    rig.coordinator.start(localModified: nil)
    rig.coordinator.send()
    #expect(rig.kv.writes == 0)   // held back
    await rig.coordinator.pendingSend?.value
    #expect(rig.slept.count == 1 && rig.slept[0] > 0 && rig.slept[0] <= SettingsSyncCoordinator.joinWait)
    #expect(rig.remote()?.config.sites.map(\.name) == ["Garden"])
}

@MainActor @Test func aChangeFromAnotherDeviceIsMergedAndTheChoicesOfThisOneKept() {
    var phone = Config.default
    phone.sites = [site("Malham")]
    phone.activeSiteName = "Malham"
    phone.welcomed = true
    let rig = Rig(config: phone)
    rig.coordinator.joined = true
    rig.coordinator.start(localModified: utc(2026, 10, 13, 9))
    var mac = phone
    mac.sites = [site("Malham"), site("Sutton Bank")]
    mac.activeSiteName = "Sutton Bank"   // where the Mac is observing from: not the phone's business
    mac.welcomed = false
    rig.kv.changeFromElsewhere(payload(mac, at: utc(2026, 10, 13, 12)))
    // The change arrives on the main actor a moment later.
    rig.coordinator.receive()
    #expect(rig.config.sites.map(\.name) == ["Malham", "Sutton Bank"])
    #expect(rig.config.activeSiteName == "Malham")
    #expect(rig.config.welcomed)
}

@MainActor @Test func aCopyThatWillNotDecodeIsLeftAlone() {
    var c = Config.default; c.sites = [site("Home")]
    let rig = Rig(config: c)
    rig.coordinator.joined = true
    rig.kv.values[SettingsSync.key] = Data("from a newer version".utf8)
    rig.coordinator.start(localModified: utc(2026, 10, 1))
    #expect(rig.config.sites.map(\.name) == ["Home"])
    #expect(rig.kv.writes == 0)
}
