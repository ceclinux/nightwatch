import Foundation

/// Settings shared by every Mac signed in to the same iCloud account (#49), through iCloud key-value storage.
/// Everything in `Config` travels except what belongs to one Mac: Start at login, where this Mac is observing from right
/// now (the chosen site, or a dark site being visited), its text size and the first-run welcome. Home travels whole (owner, 5 October
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
        /// Whether the sending Mac had taken the shared copy at least once before it sent this. False: a Mac new to sync,
        /// whose settings may be nothing but defaults. Nil: 1.5.2 or earlier, which did not say.
        public var joined: Bool?
        public init(savedAt: Date, config: Config, sharesHome: Bool? = true, joined: Bool? = true) {
            self.savedAt = savedAt; self.config = config; self.sharesHome = sharesHome; self.joined = joined
        }
    }

    /// What this Mac sends: its config with the per-Mac choices set to their defaults, so none leaks to another Mac.
    public static func outgoing(_ c: Config, at date: Date, joined: Bool = true) -> Payload {
        Payload(savedAt: date, config: keepingLocal(of: .default, in: c, home: false), joined: joined)
    }

    /// Another Mac's settings with this Mac's own choices kept; and, from a Mac that does not share home, this Mac's
    /// choice of its own location as home.
    ///
    /// Only a Mac that has taken the shared copy may replace another's settings. Until 1.5.3 any copy did, and a Mac new
    /// to sync, sending its defaults before iCloud's copy reached it, emptied the sites, favourites and settings of every
    /// other Mac (owner, 6 October 2026). `joined`: whether this Mac has taken the shared copy before.
    public static func merge(remote: Payload, local: Config, joined: Bool = true) -> Config {
        let theirs = keepingLocal(of: local, in: remote.config, home: remote.sharesHome != true)
        if !joined { return adding(local, to: theirs) }               // this Mac is the newcomer: theirs, plus what it had
        switch remote.joined {
        case true?: return theirs                                     // a synced Mac's change, removals included
        case false?: return adding(remote.config, to: local)          // a newcomer spoke before it listened: ours stands
        case nil: return adding(local, to: theirs)                    // 1.5.2 or earlier: its settings, but it removes nothing
        }
    }

    /// `base` with the sites, favourites and plan choices of `other` that it lacks. `base` keeps its order and its own
    /// copy of a site both have.
    private static func adding(_ other: Config, to base: Config) -> Config {
        var c = base
        c.sites += other.sites.filter { s in !base.sites.contains { $0.name == s.name } }
        c.favourites += other.favourites.filter { !base.favourites.contains($0) }
        c.planChoices.merge(other.planChoices) { mine, _ in mine }
        return c
    }

    /// At launch: take iCloud's copy when it is newer than this Mac's file (or there is no file); otherwise this Mac's
    /// settings are the newer and are sent. A Mac that has not joined always takes it: its file is new, not newer.
    public static func remoteWins(remoteSavedAt: Date, localSavedAt: Date?, joined: Bool = true) -> Bool {
        !joined || (localSavedAt.map { remoteSavedAt > $0 } ?? true)
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
        c.textSize = mac.textSize
        return c
    }
}
