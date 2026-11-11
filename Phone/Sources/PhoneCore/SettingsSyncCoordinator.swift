import Foundation
import SkyCore

/// iCloud's key-value store, behind a protocol so the sync rules can be tested without iCloud. The app supplies one wrapping
/// `NSUbiquitousKeyValueStore`.
public protocol KeyValueStoring: AnyObject {
    func data(forKey key: String) -> Data?
    func set(_ data: Data?, forKey key: String)
    func synchronize()
    /// Calls `handler` whenever another device changes the store. Keep the returned token alive to keep listening.
    func observeExternalChanges(_ handler: @escaping @Sendable () -> Void) -> AnyObject
}

/// The Mac app's settings sync (#49), ported rule for rule. The sky maths and the merge are SkyCore's `SettingsSync`; this
/// is the Mac `Store`'s coordination of it, which is what keeps a new device from emptying the others:
///
/// - A device that has not **joined** (taken the shared copy at least once) never replaces another device's settings.
///   Until it has, it holds back what it would send for `joinWait`, so iCloud's copy can arrive first (on a new device
///   it is not there at launch; it arrives a little later as a change from outside).
/// - At launch the newer of this device's file and iCloud's copy wins; a copy that will not decode is a newer version's
///   and is left alone.
/// - What belongs to one device (the chosen site, the welcome flag, text size) is kept when another device's settings
///   are taken, by `SettingsSync.merge`.
@MainActor
public final class SettingsSyncCoordinator {
    public static let joinWait: TimeInterval = 60

    private let store: KeyValueStoring
    private let defaults: UserDefaults
    private let clock: @Sendable () -> Date
    private let sleep: @Sendable (TimeInterval) async -> Void
    private let readConfig: @MainActor () -> Config
    private let writeConfig: @MainActor (Config) -> Void
    private var token: AnyObject?
    private var started: Date
    private var waitingToSend = false
    /// The delayed send of a device that has not joined, kept so a test can wait for it.
    private(set) var pendingSend: Task<Void, Never>?

    public init(store: KeyValueStoring, defaults: UserDefaults = .standard, clock: @escaping @Sendable () -> Date = { Date() },
                sleep: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) },
                readConfig: @escaping @MainActor () -> Config, writeConfig: @escaping @MainActor (Config) -> Void) {
        self.store = store; self.defaults = defaults; self.clock = clock; self.sleep = sleep
        self.readConfig = readConfig; self.writeConfig = writeConfig
        started = clock()
    }

    /// Whether this device has taken the shared copy at least once. Kept on the device, outside the settings that travel.
    public var joined: Bool {
        get { defaults.bool(forKey: "settingsSyncJoined") }
        set { defaults.set(newValue, forKey: "settingsSyncJoined") }
    }

    /// At launch: the newer of this device's file and iCloud's copy wins; then other devices' changes are merged as they arrive.
    /// `localModified` is when the settings file was last written, nil if there is none.
    public func start(localModified: Date?) {
        started = clock()
        token = store.observeExternalChanges { [weak self] in
            Task { @MainActor in self?.receive() }
        }
        store.synchronize()
        let data = store.data(forKey: SettingsSync.key)
        if let p = data.flatMap(SettingsSync.decode) {
            if SettingsSync.remoteWins(remoteSavedAt: p.savedAt, localSavedAt: localModified, joined: joined) { apply(p) } else { send() }
        } else if data == nil, joined {
            send()   // nothing in iCloud, and this device has synced before: its settings are the shared copy
        }
        // Otherwise nothing is sent at launch. Not joined: iCloud's copy may simply not have arrived yet.
    }

    /// Another device changed iCloud's copy.
    public func receive() {
        guard let p = store.data(forKey: SettingsSync.key).flatMap(SettingsSync.decode) else { return }
        apply(p)
    }

    private func apply(_ p: SettingsSync.Payload) {
        let wasNew = !joined
        let local = readConfig()
        let merged = SettingsSync.merge(remote: p, local: local, joined: joined)
        joined = true
        if merged != local { writeConfig(merged) }
        // The others are told when this device kept something the copy lacks, and once when either side is new to sync.
        // Between two synced devices with equal copies nothing is sent, so the same settings cannot be passed back and forth.
        if wasNew || p.joined == false || SettingsSync.outgoing(merged, at: p.savedAt).config != p.config { send() }
    }

    /// Send this device's settings. Called after the settings change here, and from the rules above.
    public func send() {
        let wait = Self.joinWait - clock().timeIntervalSince(started)
        if !joined, wait > 0 {
            guard !waitingToSend else { return }
            waitingToSend = true
            pendingSend = Task { @MainActor in
                await sleep(wait)
                waitingToSend = false
                send()
            }
            return
        }
        guard let d = SettingsSync.encode(SettingsSync.outgoing(readConfig(), at: clock(), joined: joined)) else { return }
        store.set(d, forKey: SettingsSync.key)
        store.synchronize()
    }
}
