import AppIntents
import SwiftUI
import NightwatchUI
import SkyCore

// Siri, Spotlight and Shortcuts (#53). Every answer comes from the forecast already cached: nothing is fetched at ask time,
// except by Refresh. Phrases carry no parameters: a September 2026 trial whose phrases did made the Shortcuts app crash.
// Each answer is a card as well as a sentence: Spotlight runs an action without showing its sentence (owner's test,
// 29 September 2026), and a card carries the forecast's source, Apple Weather's mark where it supplied the forecast.
// Phrases name Nightwatch first: "Is tonight clear in …" went to Apple Weather, and "Best targets in …" to a web answer.
// On macOS 27 Siri answers such questions itself (from Notes and the web) rather than running an app's phrases (owner's
// tests, 29 September 2026), so these actions are for Spotlight and Shortcuts; the phrases stay for Siri versions that use them.

/// The app's one store, so the actions read the same plan the popover shows, even when run as the app launches.
@MainActor enum IntentHost { static var store: Store { Store.shared } }

struct TonightIntent: AppIntent {
    // "Sky Score", not "Is Tonight Clear": a weather question in Spotlight also brings Siri's Apple Weather suggestion.
    static let title: LocalizedStringResource = "Sky Score"
    static let description = IntentDescription("Tonight's sky score and clear window at your site, and tomorrow's outlook.")
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let snap = await IntentHost.store.waitForSnapshot()
        return .result(dialog: "\(Copy.siriTonight(snap))", view: TonightCard(snapshot: snap, mark: IntentHost.store.weatherMark))
    }
}

struct BestTargetsIntent: AppIntent {
    static let title: LocalizedStringResource = "Best Targets Tonight"
    static let description = IntentDescription("Tonight's plan, or the best targets for your telescope tonight.")
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let store = IntentHost.store, snap = await store.waitForSnapshot()
        let text = Copy.siriBest(snap, session: store.session(for: store.plan), site: store.site)
        return .result(dialog: "\(text)", view: AnswerCard(text: text, snapshot: snap, mark: store.weatherMark))
    }
}

struct TargetEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Target"
    static let defaultQuery = TargetQuery()
    let id: String
    let name: String
    /// What Spotlight's index holds for Siri (SiriIndex.swift); empty where an action only needs the name.
    var summary = ""
    var keywords: [String] = []
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct TargetQuery: EntityStringQuery {
    @MainActor private func targets() -> [RankedTarget] {
        guard let p = IntentHost.store.plan else { return [] }
        var seen = Set<String>()
        return (p.targets + p.brightTargets + p.favourites.map(\.target)).filter { seen.insert($0.id).inserted }
    }
    /// By id from the whole catalogue, so a saved shortcut still finds its target on a night it is not in the list.
    @MainActor func entities(for identifiers: [String]) async throws -> [TargetEntity] {
        identifiers.compactMap { id in IntentHost.store.targetName(id: id).map { TargetEntity(id: id, name: $0) } }
    }
    @MainActor func entities(matching string: String) async throws -> [TargetEntity] {
        targets().filter { $0.matches(string) }.map { TargetEntity(id: $0.id, name: $0.name) }
    }
    @MainActor func suggestedEntities() async throws -> [TargetEntity] {
        Array(targets().prefix(20)).map { TargetEntity(id: $0.id, name: $0.name) }
    }
}

struct ShowTargetIntent: OpenIntent {   // also what Spotlight's result for a target runs
    static let title: LocalizedStringResource = "Show Target"
    static let description = IntentDescription("Opens a target's page in the Targets window.")
    static let openAppWhenRun = true
    @Parameter(title: "Target") var target: TargetEntity
    @MainActor func perform() async throws -> some IntentResult {
        AppDelegate.handle(WidgetLink.target(target.id).url)
        return .result()
    }
}

// `.system.searchInApp` is in the macOS 27 SDK (Xcode 27, Swift 6.4); CI's Xcode 26 builds without it.
#if compiler(>=6.4)
/// "Find the Crescent Nebula in Nightwatch" (#72). Siri on macOS 27 sends "… in <app>" to an app's in-app search and, with
/// none, answers from Apple Weather instead ("The Nightwatch app doesn't support in-app search", owner's test, 29 September
/// 2026). This takes Siri's words to the Targets window's search, which already matches names, catalogue numbers and types.
@available(macOS 27, *)
@AppIntent(schema: .system.searchInApp)
struct SearchTargetsIntent {
    static let searchScopes: [StringSearchScope] = [.general]
    var criteria: StringSearchCriteria
    @MainActor func perform() async throws -> some IntentResult {
        AppDelegate.handle(WidgetLink.search(SpokenSearch.normalise(criteria.term)).url)
        return .result()
    }
}
#endif

struct EventsTonightIntent: AppIntent {
    static let title: LocalizedStringResource = "Events Tonight"
    static let description = IntentDescription("Meteor showers, space station passes, eclipses and other events tonight.")
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let store = IntentHost.store, snap = await store.waitForSnapshot()   // events arrive with the first recompute
        let text = Copy.siriEvents(store.events)
        return .result(dialog: "\(text)", view: AnswerCard(text: text, snapshot: snap, mark: store.weatherMark))
    }
}

struct RefreshIntent: AppIntent {
    static let title: LocalizedStringResource = "Refresh Forecast"
    static let description = IntentDescription("Fetches the forecast now and works out tonight again.")
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let store = IntentHost.store
        _ = await store.waitForSnapshot()
        let before = store.forecast?.fetchedAt
        await store.refresh(force: true)
        let snap = store.snapshot()
        // A refresh already running, no site yet or a failed fetch leave the forecast as it was: say so, never "Refreshed".
        let lead = store.forecast?.fetchedAt != before && store.forecast != nil ? "Refreshed. "
            : "Could not refresh just now\(store.forecast.map { ", so this is the forecast from \(Copy.clockTime($0.fetchedAt))" } ?? ""). "
        return .result(dialog: "\(lead + Copy.siriTonight(snap))", view: TonightCard(snapshot: snap, mark: store.weatherMark))
    }
}

struct NotificationsOnIntent: AppIntent {
    static let unsaved: IntentDialog = "Nightwatch can't save its settings, so notifications are unchanged. Open Settings to fix it."
    static let title: LocalizedStringResource = "Turn On Clear-Sky Notifications"
    static let description = IntentDescription("Turns Nightwatch's clear-sky notifications on.")
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        return .result(dialog: IntentHost.store.setNotifications(true) ? "Clear-sky notifications are on." : Self.unsaved)
    }
}

struct NotificationsOffIntent: AppIntent {
    static let title: LocalizedStringResource = "Turn Off Clear-Sky Notifications"
    static let description = IntentDescription("Turns Nightwatch's clear-sky notifications off.")
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        return .result(dialog: IntentHost.store.setNotifications(false) ? "Clear-sky notifications are off." : NotificationsOnIntent.unsaved)
    }
}

struct NightwatchShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: TonightIntent(), phrases: ["\(.applicationName) sky score", "What's the sky score in \(.applicationName)"],
                    shortTitle: "Sky Score", systemImageName: "moon.stars")
        AppShortcut(intent: BestTargetsIntent(), phrases: ["\(.applicationName) tonight's plan", "\(.applicationName) best targets"],
                    shortTitle: "Tonight's Plan", systemImageName: "scope")
        AppShortcut(intent: ShowTargetIntent(), phrases: ["Show a target in \(.applicationName)"],
                    shortTitle: "Show Target", systemImageName: "sparkles")
        AppShortcut(intent: EventsTonightIntent(), phrases: ["\(.applicationName) events tonight", "\(.applicationName) sky events"],
                    shortTitle: "Events Tonight", systemImageName: "calendar")
        AppShortcut(intent: RefreshIntent(), phrases: ["Refresh \(.applicationName)", "Refresh the \(.applicationName) forecast"],
                    shortTitle: "Refresh", systemImageName: "arrow.clockwise")
        AppShortcut(intent: NotificationsOnIntent(), phrases: ["Turn on \(.applicationName) notifications"],
                    shortTitle: "Notifications On", systemImageName: "bell")
        AppShortcut(intent: NotificationsOffIntent(), phrases: ["Turn off \(.applicationName) notifications"],
                    shortTitle: "Notifications Off", systemImageName: "bell.slash")
    }
}

/// The forecast's source at a card's foot: Apple Weather's mark when it supplied the forecast (Apple requires it wherever
/// WeatherKit data is shown), else the source's name.
struct SourceLine: View {
    let snapshot: WidgetSnapshot?
    let mark: NSImage?
    var body: some View {
        if let mark, snapshot?.source == "Apple Weather" {
            let image = Image(nsImage: mark).resizable().scaledToFit().frame(height: 11)
            // The mark links to Apple's legal page, as on the widget, where the card lets it.
            if let l = snapshot?.weatherLegalURL, let url = URL(string: l) {
                Link(destination: url) { image }.accessibilityLabel("Apple Weather, legal attribution and data sources")
            } else { image.accessibilityLabel("Apple Weather") }
        } else if let src = snapshot?.source {
            Text(src).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

/// "Sky Score" and "Refresh" as a card: the bezel, the verdict and the window, as the small widget draws them.
struct TonightCard: View {
    let snapshot: WidgetSnapshot?
    let mark: NSImage?
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            if let s = snapshot {
                ScoreBezel(score: s.score, slots: s.slots, label: s.bezelLabel).frame(width: 92, height: 92)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tonight · \(s.siteName)").font(.caption).foregroundStyle(.secondary)
                    Text(s.headline).font(.headline)
                    ForEach([s.window, s.reason, s.tomorrow].compactMap { $0 }, id: \.self) {
                        Text($0).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    SourceLine(snapshot: s, mark: mark).padding(.top, 2)
                }
            } else {
                Text(Copy.siriTonight(nil)).font(.callout)
            }
        }
        .modifier(CardStyle())
    }
}

/// Tonight's plan, the best targets or the events, as a card with the forecast's source.
struct AnswerCard: View {
    let text: String
    let snapshot: WidgetSnapshot?
    let mark: NSImage?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let s = snapshot { Text("Tonight · \(s.siteName)").font(.caption).foregroundStyle(.secondary) }
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
            SourceLine(snapshot: snapshot, mark: mark)
        }
        .modifier(CardStyle())
    }
}

/// Both cards on the widget's dark ground: the bezel's white ticks and Apple's dark-background mark need it, whatever the
/// Spotlight or Shortcuts card around them looks like.
struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.padding().frame(maxWidth: .infinity, alignment: .leading)
            .background(Tokens.targetsBackground, in: RoundedRectangle(cornerRadius: 12))
            .environment(\.colorScheme, .dark)
    }
}
