import SwiftUI
import UserNotifications
import BackgroundTasks
import SkyCore
import PhoneCore
import PhoneUI
import PhoneWidgetUI
import WidgetKit

/// The real iCloud key-value store, behind PhoneCore's protocol.
final class CloudStore: KeyValueStoring {
    private let kv = NSUbiquitousKeyValueStore.default
    func data(forKey key: String) -> Data? { kv.data(forKey: key) }
    func set(_ data: Data?, forKey key: String) { if let data { kv.set(data, forKey: key) } else { kv.removeObject(forKey: key) } }
    func synchronize() { kv.synchronize() }
    func observeExternalChanges(_ handler: @escaping @Sendable () -> Void) -> AnyObject {
        NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: kv, queue: .main) { _ in handler() }
    }
}

/// iOS decides when this runs (rarely more than a few times a day, and not at all in Low Power Mode), so alerts also rely on
/// the app being opened. It refreshes the forecast and requeues the alerts.
/// Shows an alert as a banner even while the app is open: without this iOS keeps it quiet in the foreground.
final class AlertPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AlertPresenter()
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent n: UNNotification) async -> UNNotificationPresentationOptions {
        NSLog("Nightwatch delivered %@", n.request.identifier)
        return [.banner, .list, .sound]
    }
}

let refreshTaskID = "io.github.rsutcliffe.nightwatch.phone.refresh"

func scheduleBackgroundRefresh() {
    let r = BGAppRefreshTaskRequest(identifier: refreshTaskID)
    r.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
    try? BGTaskScheduler.shared.submit(r)
}

@main
struct NightwatchPhoneApp: App {
    @StateObject private var store: PhoneStore
    @StateObject private var connectivity = ConnectivityMonitor()

    init() {
        let dir = URL.applicationSupportDirectory.appendingPathComponent("Nightwatch", isDirectory: true)
        // `-demo` shows made-up conditions for a public site, for screenshots and layout checks. Never used in a release.
        //   -demoNow 17:05   the app's clock starts at that time today, then runs
        //   -demoCloud 90    cloud cover for every hour (default 5)
        UNUserNotificationCenter.current().delegate = AlertPresenter.shared
        if CommandLine.arguments.contains("-testLiveActivity") { Task { await LiveActivityScheduler.test() } }   // a card in 30 s, for 60 s
        if CommandLine.arguments.contains("-testAlert") {   // one notification 20 s from launch, to see delivery on a real device
            UNUserNotificationCenter.current().getNotificationSettings { st in
                NSLog("Nightwatch notification settings: auth=\(st.authorizationStatus.rawValue) alert=\(st.alertSetting.rawValue) lock=\(st.lockScreenSetting.rawValue) center=\(st.notificationCenterSetting.rawValue) sound=\(st.soundSetting.rawValue) summary=\(st.scheduledDeliverySetting.rawValue) timeSensitive=\(st.timeSensitiveSetting.rawValue) style=\(st.alertStyle.rawValue)")
            }
            let c = UNMutableNotificationContent()
            c.title = "Test alert"; c.body = "If you can read this, Nightwatch alerts reach this device."; c.sound = .default
            Task {   // 35 s on, say what iOS says it delivered and still has pending
                try? await Task.sleep(for: .seconds(35))
                let delivered = await UNUserNotificationCenter.current().deliveredNotifications().map(\.request.identifier)
                let pending = await UNUserNotificationCenter.current().pendingNotificationRequests().map(\.identifier)
                NSLog("Nightwatch after 35 s: delivered=\(delivered) pending=\(pending)")
            }
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "now.test.\(UUID().uuidString)", content: c,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 20, repeats: false))) { NSLog("Nightwatch test alert queued: \($0.map(String.init(describing:)) ?? "ok")") }
        }
        if CommandLine.arguments.contains("-probeWeatherKit") {   // says why Apple Weather fell back, in the console
            Task {
                NSLog("WeatherKit probe started")
                let started = Date()
                let work = Task { try await WeatherKitSource.hours(site: DemoData.site, now: .now) }
                let watchdog = Task { try await Task.sleep(for: .seconds(40)); NSLog("WeatherKit probe: no answer after 40 s"); work.cancel() }
                do { let r = try await work.value; NSLog("WeatherKit OK: \(r.hours.count) hours in \(Date().timeIntervalSince(started)) s, mark \(r.markURL ?? "none")") }
                catch { NSLog("WeatherKit failed after \(Date().timeIntervalSince(started)) s: \(String(reflecting: error))") }
                watchdog.cancel()
            }
        }
        let args = CommandLine.arguments
        func value(_ flag: String) -> String? { args.firstIndex(of: flag).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } }
        let demo = args.contains("-demo")
        var shift: TimeInterval = 0
        if demo, let t = value("-demoNow")?.split(separator: ":").compactMap({ Int($0) }), t.count == 2,
           let target = Calendar.current.date(bySettingHour: t[0], minute: t[1], second: 0, of: Date()) { shift = target.timeIntervalSinceNow }
        let clock: @Sendable () -> Date = { Date(timeIntervalSinceNow: shift) }
        if demo { try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory.appendingPathComponent("nightwatch-demo")) }   // every demo launch starts clean
        let cloud = value("-demoCloud").flatMap(Int.init) ?? 5
        let demoDir = FileManager.default.temporaryDirectory.appendingPathComponent("nightwatch-demo")
        if args.contains("-demoOffline") {   // a forecast from two hours ago, and no way to fetch another
            try? FileManager.default.createDirectory(at: demoDir, withIntermediateDirectories: true)
            try? ForecastStore(url: demoDir.appendingPathComponent("forecast.json")).save(
                DemoData.forecast(fetchedAt: clock().addingTimeInterval(-7200), from: Calendar.current.startOfDay(for: clock())))
        }
        // `-demoAurora amber` (or yellow, red) makes AuroraWatch UK report that level, and turns aurora alerts on, for screenshots.
        let demoAurora = demo ? value("-demoAurora") : nil
        let feeds: @Sendable (URL) async throws -> Data = { url in
            if let level = demoAurora, url == AuroraWatch.url {
                let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
                return Data("<current_status><updated><datetime>\(f.string(from: clock()))</datetime></updated><site_status project_id=\"project:AWN\" site_id=\"site:AWN\" status_id=\"\(level)\"/></current_status>".utf8)
            }
            return try await URLSessionFetcher().get(url)
        }
        var sink: (@Sendable (WidgetSnapshot) -> Void)?
        if !demo { sink = { snapshot in WidgetShare.save(snapshot); WidgetCenter.shared.reloadAllTimelines(); TonightIndex.update(snapshot) } }
        var marks: (@Sendable (Data, String) -> Void)?   // Apple's mark for the widget, which cannot fetch it
        if !demo { marks = { mark, address in WidgetShare.saveMark(mark, for: address) } }
        let s = PhoneStore(directory: demo ? FileManager.default.temporaryDirectory.appendingPathComponent("nightwatch-demo") : dir, provider: { site, now, ask in
            if demo, let wait = value("-demoSlow").flatMap(Double.init) { try await Task.sleep(for: .seconds(wait)) }   // hold the loading screen
            if args.contains("-demoOffline") { throw URLError(.notConnectedToInternet) }
            // `-demoLive` keeps the demo site but reads real forecasts, to see the fallback sources answer.
            if demo, !args.contains("-demoLive") { return DemoData.forecast(fetchedAt: now, from: Calendar.current.startOfDay(for: now), cloud: cloud, site: site) }
            return try await ForecastChain.fetch(site: site, fetcher: URLSessionFetcher(), now: now,
                                                   primary: ask ? WeatherKitSource.provider : nil)
        }, scheduler: UserNotificationScheduler(now: clock), clock: clock,
           feeds: feeds, widgetSink: sink, markSink: marks, liveActivities: demo || args.contains("-testLiveActivity") ? nil : LiveActivityScheduler())   // a test card is left alone by the real reconcile
        if demoAurora != nil { s.config.aurora.enabled = true; s.config.aurora.threshold = .yellow }
        if demo, !args.contains("-demoEmpty") { s.addSite(DemoData.site) }
        if demo, args.contains("-demoHorizon") {   // a site with trees to the north-east and hills to the west, and the hills already looked up
            if let i = s.config.sites.firstIndex(where: { $0.name == DemoData.site.name }) {
                s.config.sites[i].horizon = [30, 45, 30, 30, 30, 30, 60, 35]
                s.config.sites[i].terrain = [12, 20, 8, 5, 10, 22, 52, 28]
                s.saveConfig(send: false)
            }
        }
        if demo, args.contains("-demoHearts") {   // heart tonight's best three, so the Plan and Favourites have something in them
            Task { @MainActor in
                await s.refresh(force: true)
                for t in (s.planning?.tonight.best ?? []).prefix(3) where !s.isFavourite(t.id) { s.toggleFavourite(t.id) }
            }
        }   // -demoEmpty shows the first-run screen
        s.attachSync(store: CloudStore())
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshTaskID, using: nil) { task in
            scheduleBackgroundRefresh()
            let work = Task { @MainActor in
                await s.refresh()
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
        IntentHost.store = s   // Siri and Shortcuts actions read this store
        _store = StateObject(wrappedValue: s)
    }

    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("redNightMode") private var red = false

    var body: some Scene {
        WindowGroup {
            if CommandLine.arguments.contains("-demoWidget") {   // the two widget sizes on the home-screen background, for screenshots
                let red = CommandLine.arguments.contains("-redNightMode") && UserDefaults.standard.bool(forKey: "redNightMode")
                VStack(spacing: 10) {
                    NightwatchWidgetView(snapshot: store.tonight?.snapshot ?? .sample, size: .small, red: red).padding(16).frame(width: 170, height: 170)
                        .background(NightwatchWidgetView.background(red: red), in: RoundedRectangle(cornerRadius: 22))
                    NightwatchWidgetView(snapshot: store.tonight?.snapshot ?? .sample, size: .medium, red: red).padding(16).frame(width: 364, height: 170)
                        .background(NightwatchWidgetView.background(red: red), in: RoundedRectangle(cornerRadius: 22))
                    NightwatchWidgetView(snapshot: store.tonight?.snapshot ?? .sample, size: .large, red: red).padding(16).frame(width: 364, height: 382)
                        .background(NightwatchWidgetView.background(red: red), in: RoundedRectangle(cornerRadius: 22))
                    // The iPad's large widget is far shorter than the iPhone's: drawn at the iPad's size.
                    NightwatchWidgetView(snapshot: store.tonight?.snapshot ?? .sample, size: .large, red: red).padding(16).frame(width: 306, height: 306)
                        .background(NightwatchWidgetView.background(red: red), in: RoundedRectangle(cornerRadius: 22))
                }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.gray.opacity(0.4))
            } else {
            RootView(store: store, connectivity: connectivity)
                .task {
                    // `-demoLandscape` turns the screen sideways for layout checks in the Simulator.
                    guard CommandLine.arguments.contains("-demoLandscape"),
                          let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
                    scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape))
                }
            }
        }
            .onChange(of: scenePhase) { _, p in if p == .background { scheduleBackgroundRefresh() } }
            .onChange(of: red) { _, on in WidgetShare.red = on; WidgetCenter.shared.reloadAllTimelines() }
    }
}
