import SwiftUI
import NightwatchUI
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
        Group {
            if store.config.menuBarFilledStars, MenuBarStars.filled(plan: store.plan, isStale: store.isStale) {
                // Solid stars when tonight is worth imaging (this branch, 1.9): the template image takes the menu bar's own colour.
                Image(systemName: "star.fill")
                    .resizable().scaledToFit().frame(width: 10, height: 10)
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "star.fill").resizable().scaledToFit().frame(width: 6, height: 6).offset(x: 6, y: -4)
                    }
                    .overlay(alignment: .bottomLeading) {
                        Image(systemName: "star.fill").resizable().scaledToFit().frame(width: 4, height: 4).offset(x: -5, y: 4)
                    }
                    .frame(width: 18, height: 16)
            } else {
                Image(systemName: store.iconName)
            }
        }
        // VoiceOver: tonight's verdict once, whatever the picture holds.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.menuBarLabel(store.snapshot(), now: Date()))
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
                .frame(width: TextScale.pt(360))
                .textSized(store.config.textSize)
                .interfaceLanguage(store.language)
        } label: {
            // The label is the status-bar icon and is always rendered at launch; the popover
            // content above is lazy and only builds once opened, so boot() must start here.
            MenuBarLabel(store: store, boot: boot)
                .environment(\.locale, L10n.locale)
        }
        .menuBarExtraStyle(.window)

        Window(L10n.text("Targets"), id: "targets") { TargetsView().environmentObject(store).interfaceLanguage(store.language) }   // sized inside, see TargetsView.body
            .defaultSize(width: 980, height: 640).defaultPosition(.center)
        // Not rebuilt on a change, so choosing a size in Settings does not throw the page back to its top.
        Window(L10n.text("Settings"), id: "settings") { SettingsView().environmentObject(store).scaledText().interfaceLanguage(store.language) }
            .defaultSize(width: 520, height: 560).defaultPosition(.center)
        Window(L10n.text("Welcome to Nightwatch"), id: "welcome") { WelcomeView().environmentObject(store).scaledText().id(store.config.textSize).interfaceLanguage(store.language) }   // rebuilt on a change, as textSized does
            .windowResizability(.contentSize).defaultPosition(.center)
        Window(L10n.text("About Nightwatch"), id: "about") { AboutView().environmentObject(store).textSized(store.config.textSize).interfaceLanguage(store.language) }
            .defaultSize(width: 420, height: 640).defaultPosition(.center)
        Window(L10n.text("What the numbers mean"), id: "numbers") { NumbersView().textSized(store.config.textSize).interfaceLanguage(store.language) }
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
            case .plan: store.openPlan()
            case .target(let id):
                // Both lists, so a Moon or planet id finds its group on either kind of night; TargetsView selects it only
                // when it is in tonight's list, else it opens the section.
                // A favourite the magnitude cut left out can be in the popover's best three: it is found among the favourites.
                let group = store.plan.flatMap { p in (p.targets + p.brightTargets + p.favourites.map(\.target)).first { $0.id == id }?.group }
                store.targetsRequest = TargetsRequest(section: .group(group ?? .nebulae), siteID: nil, targetID: id)
            case .search(let text): store.targetsRequest = TargetsRequest(section: nil, siteID: nil, search: text)
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
        store.locationNeverAsked = { [location] in location.neverAsked }
        store.locationServicesOff = { [location] in location.servicesOff }
        // A first launch asks for location from the welcome's own button, with the reason beside it, not at once.
        // Not awaited: while macOS asks, this can wait a minute, and the scheduler must not. Observing from this Mac, the
        // first refresh waits for the fix instead, so it never forecasts (or alerts) for a saved site in the meantime.
        // Never uninvited (1.6.2): where macOS has not asked yet, nothing here brings up its prompt. The welcome's button
        // and the row in Settings ask, each beside the reason.
        let fixPending = store.config.activeSiteName == nil && store.config.welcomed && !location.neverAsked
        if fixPending {
            store.awaitingFix = true   // a popover opened meanwhile must not refresh for a saved site either
            Task { @MainActor in
                store.autoSite = await location.requestOnce(); store.awaitingFix = false
                await store.refresh(force: false)
            }
        }
        // So "This Mac's location" is ready in Settings. Only when macOS has already asked: someone who typed a place in
        // the welcome is never met by a location prompt at a later launch; the row in Settings asks when it is clicked.
        else if store.config.welcomed, !location.neverAsked { Task { @MainActor in store.autoSite = await location.requestOnce() } }
        if !fixPending { await store.refresh(force: false) }
        let s = Scheduler { [location] in
            Task { @MainActor in
                // Retry location until there is a site, but never before the welcome has explained why it is asked for.
                if store.site == nil, store.config.welcomed, !location.neverAsked, let fix = await location.requestOnce() { store.autoSite = fix }
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
