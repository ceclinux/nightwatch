import Foundation

/// Settings shared by every Mac signed in to the same iCloud account (#49), through iCloud key-value storage.
/// Everything in `Config` travels except what belongs to one Mac: Start at login, where this Mac is observing from right
/// now (the chosen site, or a dark site being visited) and the first-run welcome. Home travels whole (owner, 5 October
/// 2026): the starred saved site, or "This Mac's location", which each Mac then reads as its own.
public enum SettingsSync {
    /// The key-value store's key for the payload.
    public static let key = "settings"

    public struct Payload: Codable, Equatable, Sendable {
        public var savedAt: Date
        public var config: Config
        /// True from the version after 1.3.1, whose copy says truly whether home is this Mac's location. An earlier one always sent
        /// "it is not" and kept its own, so its copy is not believed about that.
        public var sharesHome: Bool?
        public init(savedAt: Date, config: Config, sharesHome: Bool? = true) { self.savedAt = savedAt; self.config = config; self.sharesHome = sharesHome }
    }

    /// What this Mac sends: its config with the per-Mac choices set to their defaults, so none leaks to another Mac.
    public static func outgoing(_ c: Config, at date: Date) -> Payload {
        Payload(savedAt: date, config: keepingLocal(of: .default, in: c, home: false))
    }

    /// Another Mac's settings with this Mac's own choices kept; and, from a Mac that does not share home, this Mac's
    /// choice of its own location as home.
    public static func merge(remote: Payload, local: Config) -> Config {
        keepingLocal(of: local, in: remote.config, home: remote.sharesHome != true)
    }

    /// At launch: take iCloud's copy when it is newer than this Mac's file (or there is no file); otherwise this Mac's
    /// settings are the newer and are sent.
    public static func remoteWins(remoteSavedAt: Date, localSavedAt: Date?) -> Bool {
        localSavedAt.map { remoteSavedAt > $0 } ?? true
    }

    public static func encode(_ p: Payload) -> Data? {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        return try? e.encode(p)
    }

    public static func decode(_ d: Data) -> Payload? {
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(Payload.self, from: d)
    }

    private static func keepingLocal(of mac: Config, in shared: Config, home: Bool) -> Config {
        var c = shared
        c.loginItem = mac.loginItem
        c.activeSiteName = mac.activeSiteName
        c.visiting = mac.visiting
        if home { c.homeIsThisMac = mac.homeIsThisMac }
        c.welcomed = mac.welcomed
        return c
    }
}
