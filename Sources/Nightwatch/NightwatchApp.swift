import SwiftUI
import SkyCore
import UserNotifications

/// Receives the widget's nightwatch:// links (v0.6). A click can launch the app, so links that arrive before boot() has set
/// the handler wait in `pending`.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static var pending: [URL] = []
    static var onURL: ((URL) -> Void)? {
        didSet { if let h = onURL { pending.forEach(h); pending = [] } }
    }
    func application(_ application: NSApplication, open urls: [URL]) { urls.forEach(Self.handle) }
    /// A link now, or once boot() has set the handler (Siri's Show Target can arrive first too).
    static func handle(_ url: URL) { if let h = onURL { h(url) } else { pending.append(url) } }

    /// A notification button (#57). A click can launch the app, so buttons that arrive before boot() sets the handler wait.
    private static var pendingActions: [(String, String?)] = []
    static var onAction: ((String, String?) -> Void)? {
        didSet { if let h = onAction { pendingActions.forEach { h($0.0, $0.1) }; pendingActions = [] } }
    }
    /// `id`: the button; `night`: the night the notification was about.
    static func action(_ id: String, night: String?) { if let h = onAction { h(id, night) } else { pendingActions.append((id, night)) } }
    func applicationWillFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        Notifier.registerActions()
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let id = response.actionIdentifier, night = response.notification.request.content.userInfo["night"] as? String
        await MainActor.run { AppDelegate.action(id, night: night) }
    }
}

/// The status-bar icon. It is always alive, so it is where a Targets request from outside a window (the widget) opens
/// the window; a menu-bar agent app is never active, so it activates first.
struct MenuBarLabel: View {
    @ObservedObject var store: Store
    let boot: () async -> Void
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Image(systemName: store.iconName)
            .task {
                if store.showWelcome { NSApp.activate(); openWindow(id: "welcome") }   // first launch only, before the rest of boot
                await boot()
            }
            .onChange(of: store.targetsRequest) { _, r in
                guard r != nil else { return }
                NSApp.activate()
                openWindow(id: "targets")
            }
    }
}

@main
struct NightwatchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = Store.shared
    private let location = LocationProvider()

    var body: some Scene {
        MenuBarExtra {
            TonightView()
                .environmentObject(store)
                .frame(width: 360)
        } label: {
            // The label is the status-bar icon and is always rendered at launch; the popover
            // content above is lazy and only builds once opened, so boot() must start here.
            MenuBarLabel(store: store, boot: boot)
        }
        .menuBarExtraStyle(.window)

        Window("Targets", id: "targets") { TargetsView().environmentObject(store) }
            .defaultSize(width: 980, height: 640).defaultPosition(.center)
        Window("Settings", id: "settings") { SettingsView().environmentObject(store) }
            .defaultSize(width: 520, height: 560).defaultPosition(.center)
        Window("Welcome to Nightwatch", id: "welcome") { WelcomeView().environmentObject(store) }
            .windowResizability(.contentSize).defaultPosition(.center)
        Window("About Nightwatch", id: "about") { AboutView().environmentObject(store) }
            .defaultSize(width: 420, height: 420).defaultPosition(.center)
        Window("What the numbers mean", id: "numbers") { NumbersView() }
            .defaultSize(width: 780, height: 620).defaultPosition(.center)
    }

    @MainActor
    private func boot() async {
        guard store.scheduler == nil, !store.booting else { return }
        store.booting = true
        AppDelegate.onURL = { [store] url in
            // A web link from the widget (Apple Weather's legal page) opens in the browser, whichever way macOS routes it.
            if url.scheme == "https" || url.scheme == "http" { NSWorkspace.shared.open(url); return }
            guard let link = WidgetLink(url: url) else { return }
            switch link {
            case .targets: store.targetsRequest = TargetsRequest(section: nil, siteID: nil)
            case .target(let id):
                // Both lists, so a Moon or planet id finds its group on either kind of night; TargetsView selects it only
                // when it is in tonight's list, else it opens the section.
                // A favourite the magnitude cut left out can be in the popover's best three: it is found among the favourites.
                let group = store.plan.flatMap { p in (p.targets + p.brightTargets + p.favourites.map(\.target)).first { $0.id == id }?.group }
                store.targetsRequest = TargetsRequest(section: .group(group ?? .nebulae), siteID: nil, targetID: id)
            }
        }
        AppDelegate.onAction = { [store] id, night in
            if id == Notifier.openPlan { store.openPlan() }
            if id == Notifier.notTonight, let night { store.silence(night: night) }
        }
        location.onSite = { [store] site in Task { @MainActor in store.autoSite = site; await store.refresh(force: false) } }
        // A first launch asks for notifications as the welcome closes, after it has said what they are for.
        if store.config.welcomed { await Notifier.requestAuthorisation() }
        store.requestLocationFix = { [location] in await location.requestOnce() }
        // A first launch asks for location from the welcome's own button, with the reason beside it, not at once.
        // Not awaited: while macOS asks, this can wait a minute, and the scheduler must not. Observing from this Mac, the
        // first refresh waits for the fix instead, so it never forecasts (or alerts) for a saved site in the meantime.
        let fixPending = store.config.activeSiteName == nil && store.config.welcomed
        if fixPending {
            store.awaitingFix = true   // a popover opened meanwhile must not refresh for a saved site either
            Task { @MainActor in
                store.autoSite = await location.requestOnce(); store.awaitingFix = false
                await store.refresh(force: false)
            }
        }
        else if store.config.welcomed { Task { @MainActor in store.autoSite = await location.requestOnce() } }   // so "This Mac's location" is ready in Settings
        if !fixPending { await store.refresh(force: false) }
        let s = Scheduler { [location] in
            Task { @MainActor in
                // Retry location until there is a site, but never before the welcome has explained why it is asked for.
                if store.site == nil, store.config.welcomed, let fix = await location.requestOnce() { store.autoSite = fix }
                await store.refresh(force: false)
                await store.checkForUpdate()   // at most once a day; attemptDue gates it
            }
        }
        s.start()
        store.scheduler = s
        let a = Scheduler(interval: 5 * 60, identifier: "io.github.rsutcliffe.nightwatch.aurora") { Task { @MainActor in await store.pollAurora() } }
        a.start()
        store.auroraScheduler = a
        await store.pollAurora()
        await store.checkForUpdate()
    }
}
