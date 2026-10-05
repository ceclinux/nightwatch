import Foundation

public struct TelescopePreset: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let widthDeg: Double
    public let heightDeg: Double
    public let source: String
    /// The maker's battery life in hours, for Tonight's plan's power-bank note (#57); nil for a camera, which swaps batteries.
    public var batteryHours: Double? = nil
    public var fov: FieldOfView { FieldOfView(widthDeg: widthDeg, heightDeg: heightDeg) }
}

public enum TelescopePresets {
    /// Loaded once; empty if the bundled file were ever missing.
    public static let shared: [TelescopePreset] = (try? bundled()) ?? []
    public static func bundled() throws -> [TelescopePreset] {
        guard let url = Bundle.module.url(forResource: "telescopes", withExtension: "json", subdirectory: "Resources/presets") else {
            throw CatalogError.missingResource("telescopes")
        }
        return try JSONDecoder().decode([TelescopePreset].self, from: Data(contentsOf: url))
    }
}

public struct Config: Codable, Equatable, Sendable {
    public var sites: [Site] = []
    public var activeSiteName: String? = nil          // nil = automatic location when available
    /// The site "Back to …" returns to and dark sites are compared with (v0.6.5). nil: the first saved site, else this Mac.
    public var homeSiteName: String? = nil
    /// Home is this Mac's location (starred in Settings), whatever is saved.
    public var homeIsThisMac = false
    /// A dark site being tried from the Targets window: active while set, never added to `sites` unless kept (v0.6.5).
    public var visiting: Site? = nil
    /// The first-run welcome has been completed (v0.6.7). A config written before it existed counts as welcomed.
    public var welcomed = false
    /// Look for a newer release on GitHub once a day (v0.6.7).
    public var checkForUpdates = true
    public var fov = FieldOfView(widthDeg: 2.1, heightDeg: 1.2)
    public var fovPresetID: String? = "dwarf-mini"
    public var goRule = GoRule()
    public var alerts = AlertSettings()
    public var loginItem = false
    public var notifyEnabled = true
    public var darkSites = DarkSiteSettings()
    public var brightNights = BrightSettings()
    public var aurora = AuroraSettings()
    /// Target IDs the user has hearted (v1.0.1), in the order they were added: "NGC7814", "HIP24608", "planet-saturn", "Ori".
    public var favourites: [String] = []
    /// Tonight's plan (#57): when the night's session must end, and whether Targets shows the plan.
    public var stopBy = StopBy()
    public var showPlan = true
    /// Tonight's plan choices by night key ("2026-09-29"); synced with the rest of the settings (#49).
    public var planChoices: [String: PlanChoices] = [:]

    public init() {}

    public mutating func toggleFavourite(_ id: String) {
        if let i = favourites.firstIndex(of: id) { favourites.remove(at: i) } else { favourites.append(id) }
    }
    public static let `default` = Config()

    /// A visited dark site wins; then a named saved site; otherwise the automatic fix; otherwise the first saved site.
    public func activeSite(auto: Site?) -> Site? {
        if let v = visiting { return v }
        if let n = activeSiteName, let s = sites.first(where: { $0.name == n }) { return s }
        return auto ?? sites.first
    }

    /// The starred site; unstarred, the first saved site; with none saved, this Mac's location.
    public func homeSite(auto: Site?) -> Site? {
        if homeIsThisMac { return auto ?? sites.first }
        if let n = homeSiteName, let s = sites.first(where: { $0.name == n }) { return s }
        return sites.first ?? auto
    }

    /// Observing somewhere other than home, so the app offers "Back to …". On Automatic with this Mac as home it is never
    /// away, however far the fix moves.
    public func isAway(auto: Site?) -> Bool {
        if homeIsThisMac, visiting == nil, activeSiteName == nil { return false }
        guard let a = activeSite(auto: auto), let h = homeSite(auto: auto) else { return false }
        return !Config.samePlace(a, h)
    }

    /// Within 0.001° in latitude and longitude, as dark-site adoption has always matched a saved site.
    public static func samePlace(_ a: Site, _ b: Site) -> Bool {
        abs(a.latitude - b.latitude) <= 0.001 && abs(a.longitude - b.longitude) <= 0.001
    }

    /// Observe from a dark site. A saved site at the same place is selected instead; nothing is saved.
    public mutating func visit(_ s: Site) {
        if let saved = sites.first(where: { Config.samePlace($0, s) }) { choose(savedName: saved.name) } else { visiting = s }
    }

    /// At most ten saved sites (owner, 30 September 2026): a longer list crowds Settings. A synced or older list with more
    /// keeps them all; only adding stops until one is removed.
    public static let maxSites = 10
    public var canAddSite: Bool { sites.count < Config.maxSites }

    /// Save the visited site, under a name no other saved site has ("X", then "X (dark site)", "X (dark site 2)", …).
    public mutating func keepVisiting() {
        guard var v = visiting, canAddSite else { return }
        if sites.isEmpty, homeSiteName == nil { homeIsThisMac = true }   // keeping a first site must not quietly move home
        let taken = Set(sites.map { $0.name.lowercased() }), base = v.name
        var n = 1
        while taken.contains(v.name.lowercased()) { v.name = n == 1 ? "\(base) (dark site)" : "\(base) (dark site \(n))"; n += 1 }
        sites.append(v)
        choose(savedName: v.name)
    }

    /// Observe from a saved site by name, or from this Mac's location with nil; ends any visit.
    public mutating func choose(savedName: String?) {
        visiting = nil
        activeSiteName = savedName
    }

    /// Back to home: its name when it is a saved site, else this Mac's location.
    public mutating func goHome() {
        if homeIsThisMac { choose(savedName: nil); return }
        let home = homeSite(auto: nil)
        choose(savedName: home.flatMap { h in sites.contains(where: { $0.name == h.name }) ? h.name : nil })
    }

    public mutating func remove(savedName: String) {
        sites.removeAll { $0.name == savedName }
        if homeSiteName == savedName { homeSiteName = nil }
        if activeSiteName == savedName { activeSiteName = nil }
    }

    enum CodingKeys: String, CodingKey {
        case sites, activeSiteName, homeSiteName, homeIsThisMac, visiting, welcomed, checkForUpdates, fov, fovPresetID, goRule, alerts, loginItem, notifyEnabled, darkSites, brightNights, aurora, favourites, stopBy, showPlan, planChoices
    }

    /// Missing keys fall back to the same defaults as `init()`, so a config file written by an
    /// older version (fewer fields) still decodes instead of throwing.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sites = try c.decodeIfPresent([Site].self, forKey: .sites) ?? []
        activeSiteName = try c.decodeIfPresent(String.self, forKey: .activeSiteName)
        homeSiteName = try c.decodeIfPresent(String.self, forKey: .homeSiteName)
        // A config from before v0.6.5 that was on Automatic keeps this Mac as home, so saved dark sites do not become it.
        homeIsThisMac = try c.decodeIfPresent(Bool.self, forKey: .homeIsThisMac) ?? (homeSiteName == nil && activeSiteName == nil && !sites.isEmpty)
        visiting = try c.decodeIfPresent(Site.self, forKey: .visiting)
        welcomed = try c.decodeIfPresent(Bool.self, forKey: .welcomed) ?? true   // an existing config: already set up
        checkForUpdates = try c.decodeIfPresent(Bool.self, forKey: .checkForUpdates) ?? true
        fov = try c.decodeIfPresent(FieldOfView.self, forKey: .fov) ?? FieldOfView(widthDeg: 2.1, heightDeg: 1.2)
        fovPresetID = try c.decodeIfPresent(String.self, forKey: .fovPresetID) ?? "dwarf-mini"
        goRule = try c.decodeIfPresent(GoRule.self, forKey: .goRule) ?? GoRule()
        alerts = try c.decodeIfPresent(AlertSettings.self, forKey: .alerts) ?? AlertSettings()
        loginItem = try c.decodeIfPresent(Bool.self, forKey: .loginItem) ?? false
        notifyEnabled = try c.decodeIfPresent(Bool.self, forKey: .notifyEnabled) ?? true
        darkSites = try c.decodeIfPresent(DarkSiteSettings.self, forKey: .darkSites) ?? DarkSiteSettings()
        brightNights = try c.decodeIfPresent(BrightSettings.self, forKey: .brightNights) ?? BrightSettings()
        aurora = try c.decodeIfPresent(AuroraSettings.self, forKey: .aurora) ?? AuroraSettings()
        favourites = try c.decodeIfPresent([String].self, forKey: .favourites) ?? []
        stopBy = try c.decodeIfPresent(StopBy.self, forKey: .stopBy) ?? StopBy()
        showPlan = try c.decodeIfPresent(Bool.self, forKey: .showPlan) ?? true
        planChoices = (try? c.decodeIfPresent([String: PlanChoices].self, forKey: .planChoices)) ?? [:]
    }
}

/// Aurora alerts (v0.3): AuroraWatch UK in the UK and Ireland, NOAA's forecast elsewhere (1.4), gated on the local
/// cloud forecast. Off by default.
public struct AuroraSettings: Codable, Equatable, Sendable {
    public var enabled = false
    public var threshold: AuroraLevel = .amber
    public init() {}
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        // An unknown level falls back and never fails the file; green is lifted to yellow (the picker offers yellow to red).
        threshold = max(.yellow, (try? c.decodeIfPresent(AuroraLevel.self, forKey: .threshold)) ?? .amber)
    }
    enum CodingKeys: String, CodingKey { case enabled, threshold }
}

/// Bright-night mode (v0.3): Moon and planets on nights when the dark rule cannot be met.
/// Windows are bounded by nautical twilight; 1 h minimum by owner ruling (a site at 54° N gets about 1.5 h at the solstice).
public struct BrightSettings: Codable, Equatable, Sendable {
    public var enabled = false
    public var minHours: Double = 1
    public init() {}
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        minHours = min(6, max(1, try c.decodeIfPresent(Double.self, forKey: .minHours) ?? 1))
    }
    enum CodingKeys: String, CodingKey { case enabled, minHours }
}

public struct DarkSiteSettings: Codable, Equatable, Sendable {
    public var enabled = true
    public var radiusKm: Double = 50
    public var unit: DistanceUnit = .km
    public init() {}
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        radiusKm = min(max(try c.decodeIfPresent(Double.self, forKey: .radiusKm) ?? 50, 5), 300)
        // An unknown unit (hand edit, newer version) reads as km rather than failing the whole config.
        unit = (try c.decodeIfPresent(String.self, forKey: .unit)).flatMap(DistanceUnit.init(rawValue:)) ?? .km
    }
    enum CodingKeys: String, CodingKey { case enabled, radiusKm, unit }
}

public enum ConfigStore {
    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nightwatch", isDirectory: true).appendingPathComponent("config.json")
    }

    /// Missing path: defaults. Anything at the path (attributesOfItem does not follow the final symlink, so a
    /// dangling symlink counts) must decode or this throws, so the caller never mistakes it for "no config yet".
    public static func load(from url: URL) throws -> Config {
        guard (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil else { return .default }
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return try d.decode(Config.self, from: Data(contentsOf: url))
    }

    /// Resolves `url` to its real path first so an atomic write to a synced-settings symlink
    /// replaces the symlink's target, not the symlink itself.
    public static func save(_ config: Config, to url: URL) throws {
        let target = url.resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; e.dateEncodingStrategy = .iso8601
        try e.encode(config).write(to: target, options: .atomic)
    }
}
