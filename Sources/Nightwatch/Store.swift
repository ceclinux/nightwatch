import WidgetKit
import Foundation
import SkyCore
import SwiftUI

@MainActor
final class Store: ObservableObject {
    /// The one store: the app's scene and Siri's actions (#53) both use it, so an action run at launch finds it at once.
    static let shared = Store()
    @Published var config: Config = .default
    @Published var plan: NightPlan?
    @Published var tomorrow: NightPlan?
    /// The week ahead page: tonight, tomorrow and the nights after, as far as the forecast reaches.
    @Published var week: [WeekNight] = []
    /// Tonight at home while observing from somewhere else, for the dark-site cards' comparison; the same as `plan` at home.
    @Published var homePlan: NightPlan?
    /// A newer release on GitHub, when there is one (v0.6.7).
    @Published var availableUpdate: ReleaseCheck.Latest?
    /// Asks Location Services for one fix; set at launch, used by the welcome's "Use this Mac's location".
    var requestLocationFix: (() async -> Site?)?
    @Published var events: [SkyEvent] = []
    @Published var forecast: Forecast?
    @Published var alertState: AlertState?
    @Published var autoSite: Site?
    @Published var lastError: String?
    /// 0.6.x settings synced by a link the sandbox cannot follow (0.7.0): the welcome offers to import the file.
    @Published var linkedSettings: URL?
    /// Why the 0.6.x settings could not be copied in (0.7.0); the welcome shows it, since the welcome then appears.
    @Published var importError: String?
    @Published var refreshing = false
    /// config.json exists but would not decode: saves are refused so the user's file is never overwritten.
    @Published var configLoadFailed = false
    @Published var darkSites: [DarkSite] = []
    @Published var sitePlans: [SitePlan] = []
    @Published var bestAway: SitePlan?
    /// Set by the popover so the Targets window opens on a section, scrolled to a dark-site card.
    @Published var targetsRequest: TargetsRequest? = nil
    /// The next run of moonless nights (#62), worked out again only when the night or the site changes.
    @Published var moonlessRun: MoonlessRun?
    private var moonlessFor: String?
    var booting = false                // set synchronously by boot() so a second label .task cannot boot twice
    var awaitingFix = false            // boot is waiting for this Mac's location: no refresh for a saved site meanwhile
    var scheduler: Scheduler?          // not @Published: doesn't drive UI, just needs stable storage across boot()
    var auroraScheduler: Scheduler?
    /// Last AuroraWatch UK status fetched (only while aurora alerts are on and the Sun is down).
    @Published var aurora: AuroraStatus?
    private var auroraState: AuroraAlertState?
    private var lastAuroraFetch: Date?

    nonisolated static let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Nightwatch", isDirectory: true)
    static let siteCacheDir = cacheDir.appendingPathComponent("sites", isDirectory: true)
    private let fetcher: Fetcher = URLSessionFetcher()
    private let catalog: Catalog
    let constellations: [Constellation]
    private let stars: [BrightStar]
    private let showers: [MeteorShower]
    private let certified: [CertifiedSite]
    private let grids: [LPGrid]
    func suggestedBortle(at c: Coordinate) -> Int? { DarkSites.suggestedBortle(at: c, grids: grids) }
    private var comets: [CometElements] = []
    private var tle: TLE?
    private var configModDate: Date?
    private var auxAttempts: [String: Date] = [:]   // last download ATTEMPT per aux feed, keyed "comets"/"iss"
    private var darkSitesGeneration = 0             // bumped per recomputeDarkSites run; a superseded run stops and never publishes

    var distanceUnit: DistanceUnit { config.darkSites.unit }

    init() {
        catalog = (try? Catalog.bundled()) ?? Catalog(objects: [])
        constellations = (try? Constellations.bundled()) ?? []
        stars = (try? BrightStars.bundled()) ?? []
        showers = (try? MeteorShowers.bundled()) ?? []
        certified = (try? DarkSites.bundledCertified()) ?? []
        grids = LPGrids.bundled()
        try? FileManager.default.createDirectory(at: Store.cacheDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: Store.siteCacheDir, withIntermediateDirectories: true)
        switch LegacyImport.run(from: LegacyImport.legacyDirectory, legacyCaches: LegacyImport.legacyCaches, to: StateFiles.directory) {
        case .linked(let url): linkedSettings = url        // the welcome offers to import it through a file picker
        case .failed(let path): importError = "Could not copy your earlier settings from \(path). Set Nightwatch up again, or copy that file into Settings by hand."
        case .imported, .nothing: break
        }
        StateFiles.migrate(from: Store.cacheDir)
        forecast = Store.read("forecast.json")
        plan = Store.read("plan.json")             // content in the popover before the first fetch
        alertState = Store.readFile(StateFiles.url(StateFiles.alerts)) ?? Store.read(StateFiles.alerts)   // Caches only if the move failed
        aurora = Store.read("aurora.json")
        auroraState = Store.readFile(StateFiles.url(StateFiles.aurora)) ?? Store.read(StateFiles.aurora)
        comets = Store.read("comets.json") ?? []
        tle = Store.read("iss-tle.json")
        auxAttempts = Store.read("aux-attempts.json") ?? [:]
        if catalog.objects.isEmpty { lastError = "Catalogue missing: run scripts/fetch-data.sh and rebuild." }
        loadConfig()
        startSettingsSync()
    }

    /// Loads config.json. A file that exists but will not decode (or a dangling symlink) is never overwritten:
    /// it is copied to config.json.bad beside it and saves are refused until Reset config in Settings.
    /// On failure the in-memory config is kept (the default at launch, the last good one on a reload).
    private func loadConfig() {
        let url = ConfigStore.defaultURL
        configModDate = Store.configModDate()
        do {
            config = try ConfigStore.load(from: url)
            configLoadFailed = false
            // No settings file, but a forecast from an earlier run: someone who used 0.6.6 or earlier without ever
            // changing a setting. They are already set up, so no welcome. Saved at once, because the forecast is a cache
            // that a cleaner may delete, and the welcome must not come back when it does (v0.6.9).
            if !config.welcomed, !FileManager.default.fileExists(atPath: url.path),
               FileManager.default.fileExists(atPath: Store.url("forecast.json").path) {
                config.welcomed = true
                try? ConfigStore.save(config, to: url)
                configModDate = Store.configModDate()
            }
        } catch {
            configLoadFailed = true
            if let d = try? Data(contentsOf: url) { try? d.write(to: url.appendingPathExtension("bad"), options: .atomic) }
            lastError = "Could not read \(url.path): \(error.localizedDescription) A copy is at config.json.bad. Settings will not be saved until you fix the file or use Reset config in Settings."
        }
    }

    /// Modification time of the file the config path resolves to (through a synced-folder symlink).
    private static func configModDate() -> Date? {
        try? FileManager.default.attributesOfItem(atPath: ConfigStore.defaultURL.resolvingSymlinksInPath().path)[.modificationDate] as? Date
    }

    /// Clears `configLoadFailed` by writing defaults. (A later load that decodes, e.g. after the user fixes the file
    /// by hand, also clears it: memory then matches the file, so saving can no longer lose anything.)
    // MARK: Settings sync (#49)

    private let cloud = NSUbiquitousKeyValueStore.default

    /// At launch: the newer of this Mac's file and iCloud's copy wins; then other Macs' changes are merged as they arrive.
    private func startSettingsSync() {
        NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: cloud,
                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.receiveSyncedSettings() }
        }
        cloud.synchronize()
        guard !configLoadFailed else { return }
        if let p = cloud.data(forKey: SettingsSync.key).flatMap(SettingsSync.decode),
           SettingsSync.remoteWins(remoteSavedAt: p.savedAt, localSavedAt: configModDate) {
            apply(p)
        } else {
            sendSettings()
        }
    }

    private func receiveSyncedSettings() {
        guard !configLoadFailed, let p = cloud.data(forKey: SettingsSync.key).flatMap(SettingsSync.decode) else { return }
        apply(p)
    }

    /// Another Mac's settings, with this Mac's own choices kept; saved here without sending them back.
    private func apply(_ p: SettingsSync.Payload) {
        let merged = SettingsSync.merge(remote: p.config, local: config)
        guard merged != config else { return }
        config = merged
        saveConfig(send: false)
    }

    private func sendSettings() {
        guard !configLoadFailed, let d = SettingsSync.encode(SettingsSync.outgoing(config, at: Date())) else { return }
        cloud.set(d, forKey: SettingsSync.key)
        cloud.synchronize()
    }

    /// Signed in to iCloud, so settings reach this account's other Macs (Settings › App says which).
    var syncsSettings: Bool { FileManager.default.ubiquityIdentityToken != nil }

    func resetConfig() {
        configLoadFailed = false
        config = .default
        saveConfig()
    }

    private func forecastMatches(_ s: Site) -> Bool {
        forecast.map { abs($0.latitude - s.latitude) <= 0.01 && abs($0.longitude - s.longitude) <= 0.01 } ?? false
    }


    var copy: Copy { Copy() }

    /// The plan for `p`'s night with that night's choices; nil on a night with no clear window (#57, redesigned at the
    /// owner's UAT). Nil too when the plan is switched off in Settings, which then leaves the heads-up as it was.
    func session(for p: NightPlan?) -> SessionPlan? {
        guard config.showPlan, let p, let site else { return nil }
        return SessionPlanner.make(plan: p, favourites: config.favourites, choices: config.planChoices[p.night.key] ?? PlanChoices(),
                                   stopBy: config.stopBy, site: site)
    }

    /// The clear-sky notifications switch (Settings › Alerts), for Siri (#53). False when settings cannot be saved (an
    /// unreadable config.json), so the action can say nothing changed.
    func setNotifications(_ on: Bool) -> Bool {
        guard !configLoadFailed else { return false }
        config.notifyEnabled = on; saveConfig(); return true
    }

    /// Waits up to `seconds` for tonight's snapshot: an action run as the app launches arrives before the first recompute.
    func waitForSnapshot(seconds: Double = 10) async -> WidgetSnapshot? {
        let until = Date().addingTimeInterval(seconds)
        // Not booted yet, or a location fix on its way: worth waiting. No site at all: answer at once.
        while snapshot() == nil, Date() < until, site != nil || awaitingFix || scheduler == nil {
            try? await Task.sleep(for: .milliseconds(250))
        }
        return snapshot()
    }

    /// A target's name by id from the whole catalogue, for a saved Show Target shortcut on a night it is not in the list.
    func targetName(id: String) -> String? {
        if let t = plan.flatMap({ p in (p.targets + p.brightTargets + p.favourites.map(\.target)).first { $0.id == id } }) { return t.name }
        if id == "moon" { return "Moon" }
        if id.hasPrefix("planet-"), let p = Planet(rawValue: String(id.dropFirst(7))) { return p.displayName }
        if let s = stars.first(where: { $0.id == id }) { return s.name }
        if let c = constellations.first(where: { $0.id == id }) { return c.name }
        return catalog.objects.first { $0.id == id }?.displayName
    }

    /// "Open plan" on the heads-up: the Targets window on Tonight's plan.
    func openPlan() { targetsRequest = TargetsRequest(section: .plan, siteID: nil) }
    var telescope: TelescopePreset? { TelescopePresets.shared.first { $0.id == config.fovPresetID } }

    /// Puts a target in `night`'s plan or takes it out. Saved with the settings, so the choice syncs and outlasts a restart;
    /// nights before tonight are dropped as it saves.
    func setInPlan(_ id: String, _ on: Bool, night: String) {
        let now = config.planChoices[night] ?? PlanChoices()
        config.planChoices[night] = SessionPlanner.choose(id, on: on, isFavourite: config.favourites.contains(id), in: now)
        config.planChoices = SessionPlanner.pruned(config.planChoices, from: min(night, plan?.night.key ?? night))
        saveConfig()
    }

    /// "Not tonight" on the heads-up: no more clear-sky alerts for that night (an old notification never silences a newer one).
    func silence(night: String) {
        guard var s = alertState, s.nightKey == night else { return }
        s.silenced = true
        alertState = s
        Store.writeFile(s, StateFiles.url(StateFiles.alerts))
    }
    var site: Site? { config.activeSite(auto: autoSite) }
    var homeSite: Site? { config.homeSite(auto: autoSite) }
    var isAway: Bool { config.isAway(auto: autoSite) }
    /// "Home", or "my location" when home is this Mac's location.
    var homeLabel: String { config.sites.isEmpty ? "my location" : (homeSite?.name ?? "home") }
    var isStale: Bool { (forecast?.fetchedAt).map { Date().timeIntervalSince($0) > 6 * 3600 } ?? true }
    var iconName: String { Theme.icon(for: plan, stale: isStale, now: Date()) }

    /// `send`: pass the change to this account's other Macs (#49); false for a change that came from one.
    func saveConfig(send: Bool = true) {
        if configLoadFailed {
            lastError = "Not saved: \(ConfigStore.defaultURL.lastPathComponent) could not be read. Fix it, or use Reset config in Settings."
        } else {
            try? ConfigStore.save(config, to: ConfigStore.defaultURL)
            configModDate = Store.configModDate()
            if send { sendSettings() }
        }
        let siteChanged = site.map { !forecastMatches($0) } ?? false
        Task { if siteChanged { await refresh(force: true) } else { await recompute(now: Date()) } }
        checkTerrain()
    }

    // MARK: terrain (#108)

    /// The saved site whose hills are being fetched now, for the Horizon sheet's "Checking the hills…".
    @Published var terrainChecking: String?
    /// Saved sites whose check failed in this launch; tried again at the next launch, or from "Try again".
    @Published var terrainFailed: Set<String> = []
    private var terrainBusy = false

    /// Fetches the hills once for each saved site that has none, one site at a time (owner, 1 October 2026: check once,
    /// keep it with the site, sync it). Called after every save and refresh, so a site added, kept or moved here or on
    /// another Mac is checked; a site with terrain is never asked about again until it moves.
    func checkTerrain() {
        guard !terrainBusy, !configLoadFailed else { return }
        guard let next = config.sites.first(where: { $0.terrain == nil && !terrainFailed.contains($0.name) }) else { return }
        terrainBusy = true
        terrainChecking = next.name
        Task { @MainActor in
            do {
                let t = try await Terrain.fetch(site: next, fetcher: URLSessionFetcher())
                // Only if the site is still where it was when asked.
                if let i = config.sites.firstIndex(where: { $0.name == next.name && $0.latitude == next.latitude && $0.longitude == next.longitude }) {
                    config.sites[i].terrain = t
                    terrainChecking = nil
                    saveConfig()   // saves and syncs; its own checkTerrain() returns, as this one is still busy
                }
            } catch {
                terrainFailed.insert(next.name)
            }
            terrainChecking = nil
            try? await Task.sleep(for: .seconds(10))   // a breather between sites: Open-Meteo refuses quick runs
            terrainBusy = false
            checkTerrain()
        }
    }

    func retryTerrain(_ name: String) {
        terrainFailed.remove(name)
        checkTerrain()
    }

    /// Fetch when the cache is older than 30 minutes (or forced), then recompute everything.
    /// Also reloads config.json first when it changed on disk (another Mac editing it through a synced symlink),
    /// and treats a forecast for other coordinates as stale.
    func refresh(force: Bool) async {
        if let m = Store.configModDate(), m > (configModDate ?? .distantPast) { loadConfig() }
        guard !refreshing, !awaitingFix else { return }
        guard let site else {
            if !configLoadFailed { lastError = "No site. Add one in Settings or allow location access." }
            return
        }
        refreshing = true
        checkTerrain()
        let now = Date()
        if force || !forecastMatches(site) || (forecast?.fetchedAt).map({ now.timeIntervalSince($0) > 30 * 60 }) ?? true {
            do {
                forecast = try await ForecastService.fetch(site: site, fetcher: fetcher, now: now)
                Store.write(forecast, "forecast.json")
                lastError = nil
            } catch {
                lastError = "Forecast fetch failed: \(error.localizedDescription)"
            }
        }
        await refreshAuxiliary(now: now)
        await recompute(now: now)
        refreshing = false
        // The site changed while this ran (location fix, Settings, config reload) and its own refresh hit the guard above.
        if self.site != site { await refresh(force: false) }
    }

    /// Comet elements daily, ISS elements every 2 hours (CelesTrak asks for no more). The MPC file is gzip, so it goes through Gzip.decompress.
    /// Gated on the last attempt, not the last success, so a failing server is not hammered every tick.
    private func refreshAuxiliary(now: Date) async {
        if attemptDue("comets", every: 86_400, now: now), let data = try? await fetcher.get(Comets.url) {
            let unzipped = await Task.detached { Gzip.decompress(data) ?? data }.value   // off the main actor; already plain if the server sent Content-Encoding: gzip
            if let c = try? Comets.decode(unzipped) { comets = c; Store.write(c, "comets.json") }
        }
        if attemptDue("iss", every: 2 * 3600, now: now), let data = try? await fetcher.get(Satellites.issURL),
           let t = try? Satellites.parseTLE(String(decoding: data, as: UTF8.self)) {
            tle = t; Store.write(t, "iss-tle.json")
        }
    }

    /// True (and the attempt recorded) when `interval` has passed since the last attempt for `key`.
    private func attemptDue(_ key: String, every interval: TimeInterval, now: Date) -> Bool {
        guard now.timeIntervalSince(auxAttempts[key] ?? .distantPast) >= interval else { return false }
        auxAttempts[key] = now
        Store.write(auxAttempts, "aux-attempts.json")
        return true
    }

    /// The night in progress until its darkness ends, then the coming one (Ephemeris.currentNight).
    func recompute(now: Date) async {
        // Asked first: after this, everything up to the alert step runs without suspending, so two overlapping recomputes
        // can never step the alerts with an older plan or site.
        let canNotify = config.notifyEnabled ? await Notifier.authorised() : false
        guard let site, let fc = forecast else { return }
        guard forecastMatches(site) else {
            plan = nil; tomorrow = nil; week = []; events = []; darkSites = []; sitePlans = []; bestAway = nil
            lastError = "Forecast is for a different site; refreshing"
            clearWidgetSnapshot()
            return
        }
        let cal = site.calendar
        guard let night = try? Ephemeris.currentNight(now: now, site: site),
              let next = try? Ephemeris.night(localDate: cal.date(byAdding: .day, value: 1, to: night.localDate)!, site: site) else { return }
        let fov = config.fov, rule = config.goRule
        let p = Planner.plan(night: night, forecast: fc, catalog: catalog, constellations: constellations, stars: stars, site: site, fov: fov, rule: rule,
                             bright: config.brightNights, favourites: config.favourites)
        let t = Planner.plan(night: next, forecast: fc, catalog: catalog, constellations: constellations, stars: stars, site: site, fov: fov, rule: rule,
                             bright: config.brightNights, favourites: config.favourites)
        plan = p; tomorrow = t
        week = Planner.week(tonight: p, tomorrow: t, forecast: fc, site: site, fov: fov, rule: rule, bright: config.brightNights)
        scheduleCheck(at: [Ephemeris.nightEnds(night)] + AlertEngine.dueTimes(tonight: p, settings: config.alerts))
        let moonKey = "\(night.key)|\(site.latitude)|\(site.longitude)"
        if moonlessFor != moonKey { moonlessRun = MoonCalendar.nextRun(from: night, site: site); moonlessFor = moonKey }
        events = Events.markClear(buildEvents(night: night, site: site, now: now), hours: fc.hours, maxCloudPct: rule.maxCloudPct)
        Store.write(p, "plan.json")
        writeWidgetSnapshot()
        if canNotify {
            let r = AlertEngine.step(now: now, tonight: p, tomorrow: t, state: alertState, settings: config.alerts,
                                     forecastFetchedAt: fc.fetchedAt, site: site, copy: copy, session: session(for: p),
                                     events: events)
            alertState = r.state
            Store.writeFile(r.state, StateFiles.url(StateFiles.alerts))
            if let n = r.notification { Notifier.post(n) }
        }
        await recomputeHomePlan(now: now)   // after the alerts, so a slow home fetch never delays one
        await recomputeDarkSites(now: now, site: site, night: night)
    }

    /// The desktop widget's snapshot (v0.6), written into the App Group the build script names in Info.plist, then WidgetKit
    /// is asked to redraw. Builds without the widget (no Xcode, or unsigned) have no group key and write nothing.
    /// The aurora status the widget was last given, when it shows one.
    private var widgetAurora: AuroraStatus?
    private func shownAurora(_ a: AuroraStatus?) -> AuroraStatus? {
        a.flatMap { config.aurora.shows($0) ? $0 : nil }
    }
    /// AuroraWatch UK publishes every few minutes and WidgetKit rations reloads, so the widget is rewritten only when its
    /// aurora line appears, changes level or clears, and every 30 minutes while shown so its one-hour freshness never lapses.
    private func widgetAuroraNeedsRewrite(_ status: AuroraStatus) -> Bool {
        let new = shownAurora(status), old = widgetAurora
        if new?.level != old?.level { return true }
        if let n = new, let o = old { return n.updated.timeIntervalSince(o.updated) >= AuroraSettings.widgetRefresh }
        return false
    }

    /// Written after each patrol and after aurora changes the widget shows, from the current plan, forecast and aurora status.
    static let weatherMarkName = "apple-weather-mark.png"
    /// The mark URL already tried this session: a failed fetch is not retried until the next launch (no loop).
    private var triedWeatherMark: String?

    /// Tonight as the widget shows it, from the cached forecast; nil before one for this site. Siri reads it too (#53).
    func snapshot() -> WidgetSnapshot? {
        guard let plan, let tomorrow, let fc = forecast, let site, forecastMatches(site) else { return nil }
        var s = WidgetSnapshot.make(plan: plan, tomorrow: tomorrow, fetchedAt: fc.fetchedAt, site: site, rule: config.goRule,
                                    bright: config.brightNights, alerts: config.alerts, copy: copy,
                                    source: fc.cloudSource ?? "Open-Meteo", aurora: aurora, auroraSettings: config.aurora)
        s.weatherLegalURL = fc.attributionLegalURL   // with the mark, on the widget and Siri's cards
        return s
    }

    /// Apple Weather's mark as the widget keeps it (a file in the App Group), for Siri's cards (#53); nil until fetched or on
    /// an unsigned build. A card is drawn away from the app, so it needs the image itself, not a URL.
    var weatherMark: NSImage? {
        guard let mark = forecast?.attributionMarkURL,
              let group = Bundle.main.object(forInfoDictionaryKey: "NightwatchAppGroup") as? String,
              let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group),
              // Only the file for the current mark URL, as the widget checks: never an out-of-date mark.
              (try? String(contentsOf: dir.appendingPathComponent(Store.weatherMarkName + ".url"), encoding: .utf8)) == mark else { return nil }
        return NSImage(contentsOf: dir.appendingPathComponent(Store.weatherMarkName))
    }

    private func writeWidgetSnapshot() {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "NightwatchAppGroup") as? String,
              let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group),
              let fc = forecast, let snap = snapshot() else { return }
        var s = snap
        // Apple Weather's attribution (v1.0.1): the mark as a file the widget can read, fetched once per mark URL.
        if let mark = fc.attributionMarkURL, let legal = fc.attributionLegalURL {
            s.weatherLegalURL = legal
            let file = dir.appendingPathComponent(Store.weatherMarkName), stamp = dir.appendingPathComponent(Store.weatherMarkName + ".url")
            if FileManager.default.fileExists(atPath: file.path), (try? String(contentsOf: stamp, encoding: .utf8)) == mark {
                s.weatherMarkFile = Store.weatherMarkName
            } else if triedWeatherMark != mark, let url = URL(string: mark) {
                triedWeatherMark = mark
                Task { @MainActor in
                    if let data = try? await fetcher.get(url) {
                        await Task.detached {   // the disk writes off the main actor
                            try? data.write(to: file, options: .atomic)
                            try? mark.write(to: stamp, atomically: true, encoding: .utf8)
                        }.value
                    }
                    writeWidgetSnapshot()   // once more, now with the mark (or without it, if the fetch failed)
                }
            }
        }
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(s) else { return }
        try? data.write(to: dir.appendingPathComponent("widget.json"), options: .atomic)
        widgetAurora = shownAurora(aurora)
        WidgetCenter.shared.reloadAllTimelines()
        SiriIndex.update()   // Siri and Spotlight read the same night (#72)
    }

    /// After a site change and before the new site's forecast arrives, the widget shows "Open Nightwatch…" rather than the
    /// old site's night.
    private func clearWidgetSnapshot() {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "NightwatchAppGroup") as? String,
              let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { return }
        guard (try? FileManager.default.removeItem(at: dir.appendingPathComponent("widget.json"))) != nil else { return }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Polls AuroraWatch UK while aurora alerts are on and the Sun is at least 12 degrees down (every 5 minutes: their
    /// terms ask for 3 or more), then notifies through the aurora rule. On a failed fetch the last status is kept.
    func pollAurora(now: Date = Date()) async {
        guard config.aurora.enabled, let site, Ephemeris.sunAltitude(at: now, site: site) <= AuroraAlert.sunBelowDeg else { return }
        // Boot, the 5-minute timer and every wake can all land here: never ask AuroraWatch UK twice within 3 minutes.
        if now.timeIntervalSince(lastAuroraFetch ?? .distantPast) >= 180 {
            lastAuroraFetch = now
            if let data = try? await fetcher.get(AuroraWatch.url), let status = try? AuroraWatch.parse(data) {
                aurora = status
                Store.write(status, "aurora.json")
                if widgetAuroraNeedsRewrite(status) { writeWidgetSnapshot() }
            }
        }
        // Only record a level as sent when it can be: turning notifications on mid-storm then alerts for the current level.
        // Checked before the state is read, so reading, deciding and writing it never straddle a suspension: two
        // overlapping polls (a wake and the timer) must not both send the same alert.
        guard config.notifyEnabled, await Notifier.authorised() else { return }
        // The same six-hour rule as every other alert, and never another site's forecast.
        guard let site = self.site, let status = aurora, let fc = forecast, forecastMatches(site), now.timeIntervalSince(fc.fetchedAt) <= 6 * 3600,
              let key = plan?.night.key else { return }
        let r = AuroraAlert.decide(status: status, now: now, site: site, nightKey: key, hours: fc.hours, rule: config.goRule,
                                   settings: config.aurora, alerts: config.alerts, state: auroraState, copy: copy)
        auroraState = r.state
        Store.writeFile(r.state, StateFiles.url(StateFiles.aurora))
        if let n = r.notification { Notifier.post(n) }
    }

    /// Sites within the radius; forecasts for the nearest eight (30-minute cache under sites/<id>.json); plans with the home rule.
    /// Each run takes a generation number; after every await it checks it is still the newest run, so a run superseded by a
    /// settings change stops fetching and never publishes over the newer one.
    private func recomputeDarkSites(now: Date, site: Site, night: Night) async {
        darkSitesGeneration += 1
        let gen = darkSitesGeneration
        guard config.darkSites.enabled else { darkSites = []; sitePlans = []; bestAway = nil; return }
        let home = Coordinate(latitude: site.latitude, longitude: site.longitude)
        let radiusKm = config.darkSites.radiusKm, certified = certified, grids = grids
        // Up to ~700k distance checks at 300 km: off the main actor.
        let found = await Task.detached { DarkSites.sites(near: home, radiusKm: radiusKm, certified: certified, grids: grids, maxSpots: 5) }.value
        guard gen == darkSitesGeneration else { return }
        let sites = namedSpots(publicSpots(found, home: home, site: site, night: night), now: now)
        var plans: [SitePlan] = []
        for s in sites.prefix(8) {
            let cacheURL = Store.siteCacheDir.appendingPathComponent("\(s.id).json")
            var fc: Forecast? = Store.readFile(cacheURL)
            if fc.map({ now.timeIntervalSince($0.fetchedAt) > 30 * 60 }) ?? true {
                let siteAsSite = DarkSites.toSite(s, timeZoneID: site.timeZoneID)
                let fresh = try? await ForecastService.fetch(site: siteAsSite, fetcher: fetcher, now: now, secondOpinion: false)
                guard gen == darkSitesGeneration else { return }
                if let fresh { fc = fresh; Store.writeFile(fresh, cacheURL) }
            }
            // A cache over 24 h old that could not be refreshed no longer describes tonight: show "no forecast", not a plan.
            if let f = fc, now.timeIntervalSince(f.fetchedAt) > 24 * 3600 { fc = nil }
            guard let fc else { plans.append(SitePlan.missing(s)); continue }
            let p = Planner.plan(night: night, forecast: fc, catalog: Catalog(objects: []), constellations: [], site: DarkSites.toSite(s, timeZoneID: site.timeZoneID), fov: config.fov, rule: config.goRule, bright: config.brightNights)
            plans.append(SitePlan(id: s.id, site: s, score: p.score, primary: p.primary, qualifies: p.qualifies, forecastMissing: false))
        }
        guard gen == darkSitesGeneration else { return }
        darkSites = sites   // set with sitePlans so the Targets grid never sees a new list beside old plans
        sitePlans = SiteComparison.sorted(plans)
        bestAway = (homePlan ?? plan).map { SiteComparison.bestAway(home: $0, sites: plans) } ?? nil   // against home, as the cards are
        CachePruning.prune(directory: Store.siteCacheDir, keepIDs: Set(sites.map(\.id)), now: now)
    }

    /// Apple Maps' place for each computed dark spot, by spot id; "" where it has none. Kept in one place so overlapping
    /// refreshes add to it rather than overwrite each other.
    private lazy var spotPlaces: [String: String] = Store.read("spot-places.json") ?? [:]
    private var spotLookupFailedAt: Date?
    private var spotLookups: Set<String> = []   // ids being looked up now

    /// Computed dark spots carry the nearest town's name rather than coordinates (owner, 29 September 2026), looked up once
    /// from Apple Maps and kept, together with "no name here". A refresh never waits for Apple Maps: each missing name is
    /// looked up in its own task (5 s at most) and the cards are renamed when it answers. A task group here crashed in the
    /// Swift runtime on macOS 27 (TaskGroup::offer, 29 September 2026). A spot whose lookup fails keeps its coordinates,
    /// and failed lookups are tried again after an hour.
    /// ponytail: one retry clock for all spots, so a new site's spots can wait up to an hour after an unrelated failure.
    private func namedSpots(_ sites: [DarkSite], now: Date) -> [DarkSite] {
        // Every car park carries its town: two "Euro Car Parks" 6 km apart could not be told apart (owner's UAT,
        // 30 September 2026), so "Euro Car Parks near Hetton", and "Car park near Kettlewell" for an unnamed one.
        let missing = sites.filter { $0.isComputed && spotPlaces[$0.id] == nil && !spotLookups.contains($0.id) }
        if now.timeIntervalSince(spotLookupFailedAt ?? .distantPast) >= 3600 {
            for s in missing {
                spotLookups.insert(s.id)
                Task { [weak self] in
                    // do/catch, not try?: try? flattens String?? into String?, so a failed lookup was kept as "no name here".
                    let place: String?
                    do { place = try await PlaceNames.nearest(to: s.coordinate) } catch {
                        self?.spotLookups.remove(s.id); self?.spotLookupFailedAt = Date(); return
                    }
                    guard let self else { return }
                    spotLookups.remove(s.id)
                    spotPlaces[s.id] = place ?? ""
                    Store.write(spotPlaces, "spot-places.json")
                    renameSpots()
                }
            }
        }
        return sites.map(spotNamed)
    }

    private func spotNamed(_ s: DarkSite) -> DarkSite {
        guard s.isComputed else { return s }
        return spotPlaces[s.id].flatMap { DarkSites.spotName(place: $0, lead: s.name) }.map(s.named) ?? s
    }

    /// Each computed spot's public place by the spot's id (nil inside: none within reach), found once and kept.
    private lazy var spotPublic: [String: PublicPlaces.Place?] = Store.read("spot-public.json") ?? [:]
    private var publicLookups: Set<String> = []
    private var publicLookupFailedAt: Date?

    /// Computed spots moved to the nearest dark car park (owner's UAT, 29 September 2026: a pin in the middle of a moor
    /// raised whether it was public, or condoning trespass). A spot is not shown until its car park is known, and is left
    /// out when there is none; the list is worked out again once the searches finish. Failed searches are tried again
    /// after an hour.
    private func publicSpots(_ sites: [DarkSite], home: Coordinate, site: Site, night: Night) -> [DarkSite] {
        var out: [DarkSite] = [], seen = Set<String>()
        let due = Date().timeIntervalSince(publicLookupFailedAt ?? .distantPast) >= 3600
        for s in sites {
            guard s.isComputed else { out.append(s); continue }
            guard let entry = spotPublic[s.id] else {
                if due, !publicLookups.contains(s.id) { lookUpPublicPlace(for: s, site: site, night: night) }
                continue
            }
            guard let p = entry else { continue }
            let c = Coordinate(latitude: p.latitude, longitude: p.longitude)
            let id = String(format: "place-%.3f-%.3f", c.latitude, c.longitude)
            guard seen.insert(id).inserted else { continue }   // two spots can share a car park
            out.append(DarkSite(id: id, name: p.name, kind: "spot", coordinate: c, distanceKm: Geo.distanceKm(home, c),
                                bearingDeg: Geo.bearingDeg(from: home, to: c),
                                band: LPGrids.radiance(at: c, in: grids).map(DarknessBand.from) ?? s.band, bortle: nil, source: nil,
                                isComputed: true))
        }
        return DarkSites.withoutDuplicates(out).sorted { $0.distanceKm < $1.distanceKm }
    }

    private func lookUpPublicPlace(for s: DarkSite, site: Site, night: Night) {
        publicLookups.insert(s.id)
        let grids = grids
        Task { [weak self] in
            let place: PublicPlaces.Place?
            do { place = try await PublicPlaces.nearest(to: s.coordinate, band: s.band, grids: grids) } catch {
                self?.publicLookups.remove(s.id); self?.publicLookupFailedAt = Date(); return
            }
            guard let self else { return }
            publicLookups.remove(s.id)
            spotPublic[s.id] = .some(place)
            Store.write(spotPublic, "spot-public.json")
            // Once every search is back, the list again, now with the car parks.
            if publicLookups.isEmpty { await recomputeDarkSites(now: Date(), site: site, night: night) }
        }
    }

    /// A check at the next moment something falls due, not at the next half-hourly refresh: the heads-up, the go nudge,
    /// and the move to the coming night when darkness ends. Each check schedules the next. A Mac asleep at that moment
    /// is caught by the refresh on wake.
    private var nextCheck: Task<Void, Never>?
    private func scheduleCheck(at times: [Date]) {
        nextCheck?.cancel()
        guard let next = times.filter({ $0 > Date() }).min() else { return }
        let wait = next.timeIntervalSinceNow + 5
        nextCheck = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            await self?.recompute(now: Date())
        }
    }

    /// A name that arrived after the cards were built: the same sites and plans, renamed.
    private func renameSpots() {
        func renamed(_ p: SitePlan) -> SitePlan {
            SitePlan(id: p.id, site: spotNamed(p.site), score: p.score, primary: p.primary, qualifies: p.qualifies, forecastMissing: p.forecastMissing)
        }
        darkSites = darkSites.map(spotNamed)
        sitePlans = sitePlans.map(renamed)
        bestAway = bestAway.map(renamed)
    }

    /// "Observe from here" on a dark-site card: observe from it without saving it (v0.6.5). A saved site at the same place
    /// is selected instead.
    func visit(_ s: DarkSite) {
        config.visit(DarkSites.toSite(s, timeZoneID: site?.timeZoneID ?? TimeZone.current.identifier))
        saveConfig()
    }
    func keepVisiting() { config.keepVisiting(); saveConfig() }

    /// Once a day, when allowed: is there a newer Nightwatch on GitHub? Downloads do not update themselves.
    func checkForUpdate(now: Date = Date()) async {
        guard Distribution.checksForUpdates, config.checkForUpdates else { availableUpdate = nil; return }
        let last: ReleaseCheck.Record? = Store.read("update-check.json")
        showUpdate(last?.latest)   // the last answer, so the line survives a relaunch
        guard ReleaseCheck.due(last, now: now),
              let data = try? await fetcher.get(ReleaseCheck.latestURL), let latest = ReleaseCheck.parse(data) else { return }
        Store.write(ReleaseCheck.Record(checkedAt: now, latest: latest), "update-check.json")
        showUpdate(latest)
    }

    /// Shows `latest` only when it is newer than this copy, so an upgrade clears the line by itself.
    private func showUpdate(_ latest: ReleaseCheck.Latest?) {
        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        availableUpdate = latest.flatMap { ReleaseCheck.isNewer($0.version, than: current) ? $0 : nil }
    }

    /// The first-run welcome (v0.6.7): not for anyone already set up, and never while settings cannot be saved,
    /// since "Start watching" could not then record that it was shown.
    var showWelcome: Bool { !config.welcomed && !configLoadFailed }
    func goHome() { config.goHome(); saveConfig() }

    /// While away, tonight's plan at home. Home's forecast is cached for 30 minutes, as a dark site's is, and never asks for
    /// the second opinion.
    private func recomputeHomePlan(now: Date) async {
        guard isAway, let home = homeSite else { homePlan = plan; return }
        let url = Store.url("home-forecast.json")
        var fc: Forecast? = Store.readFile(url)
        if let f = fc, abs(f.latitude - home.latitude) > 0.01 || abs(f.longitude - home.longitude) > 0.01 { fc = nil }
        if fc.map({ now.timeIntervalSince($0.fetchedAt) > 30 * 60 }) ?? true, attemptDue("home-forecast", every: 10 * 60, now: now),
           let fresh = try? await ForecastService.fetch(site: home, fetcher: fetcher, now: now, secondOpinion: false) {
            fc = fresh; Store.writeFile(fresh, url)
        }
        guard let fc, now.timeIntervalSince(fc.fetchedAt) <= 24 * 3600,
              let night = try? Ephemeris.currentNight(now: now, site: home) else { homePlan = nil; return }
        homePlan = Planner.plan(night: night, forecast: fc, catalog: Catalog(objects: []), constellations: [], site: home,
                                fov: config.fov, rule: config.goRule, bright: config.brightNights)
    }

    private func buildEvents(night: Night, site: Site, now: Date) -> [SkyEvent] {
        var ev = Events.showers(night: night, site: site, showers: showers)
        ev += Events.eclipses(after: now, site: site, withinDays: 60)
        let mid = night.darkStart.map { $0.addingTimeInterval((night.darkEnd ?? $0).timeIntervalSince($0) / 2) } ?? night.sunset
        ev += Events.conjunctions(at: mid, site: site, maxSeparationDeg: 3, night: night, fov: config.fov)
        for (c, pos) in Comets.bright(comets, at: mid, limit: 12) {
            let later = Comets.position(c, at: mid.addingTimeInterval(7 * 86_400))
            if let e = Events.comet(designation: c.designation, pos: pos, later: later, night: night, site: site) { ev.append(e) }
        }
        if let tle, let passes = try? Satellites.visiblePasses(tle: tle, site: site, from: night.sunset, to: night.sunrise, minPeakElevation: 30) {
            ev += passes.map { Events.issPass($0, site: site) }
        }
        updateOccultations(site: site, now: now)
        ev += occultationsAhead.filter { $0.time >= night.sunset && $0.time < night.sunrise }
        return ev.sorted { $0.when < $1.when }
    }

    // MARK: occultations (#115)

    /// The Moon covering a planet, a bright star or the Pleiades, seen from the site in darkness over the coming year,
    /// soonest first: tonight's join the events, the rest are the Events page's "Coming up".
    @Published var occultationsAhead: [SkyEvent] = []
    private var occultationsKey: String?

    /// Works the year ahead out once a day per site, off the main thread (a second or so), then recomputes so tonight's
    /// join the events. Ends in darkness are kept; the site's horizon raises the 10° floor.
    private func updateOccultations(site: Site, now: Date) {
        let day = site.calendar.startOfDay(for: now)
        let key = "\(site.latitude),\(site.longitude),\(site.horizon ?? []),\(day.timeIntervalSince1970)"
        guard key != occultationsKey else { return }
        occultationsKey = key
        let stars = self.stars
        Task.detached(priority: .utility) { [weak self] in
            let found = Occultations.find(from: day, days: 365, site: site, stars: stars).map { Events.occultation($0, site: site) }
            await MainActor.run {
                guard let self, self.occultationsKey == key else { return }
                self.occultationsAhead = found
                Task { await self.recompute(now: Date()) }
            }
        }
    }

    // MARK: cache helpers
    static func url(_ name: String) -> URL { cacheDir.appendingPathComponent(name) }
    static func read<T: Decodable>(_ name: String) -> T? { readFile(url(name)) }
    static func write<T: Encodable>(_ value: T?, _ name: String) { writeFile(value, url(name)) }
    static func readFile<T: Decodable>(_ url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return try? d.decode(T.self, from: data)
    }
    static func writeFile<T: Encodable>(_ value: T?, _ url: URL) {
        guard let value else { return }
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        try? e.encode(value).write(to: url, options: .atomic)
    }
}

extension Store {
    /// Replaces the settings with a file the person chose (the welcome's "Import settings…", for 0.6.x settings synced by
    /// a link). The file must decode as settings. True when imported.
    func importSettings(from url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url), (try? JSONDecoder().decode(Config.self, from: data)) != nil,
              (try? data.write(to: ConfigStore.defaultURL, options: .atomic)) != nil else { return false }
        loadConfig()
        config.welcomed = true   // chosen from the welcome, so it is done, whatever a half-finished 0.6.7 file said
        linkedSettings = nil
        saveConfig()
        return true
    }
}
