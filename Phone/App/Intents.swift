import AppIntents
import SwiftUI
import SkyCore
import PhoneCore
import PhoneWidgetUI

// Siri, Spotlight and Shortcuts, as the Mac app has them. Every answer comes from the forecast already kept: nothing is fetched at ask time except
// by Refresh. Phrases carry no parameters: a September 2026 trial on the Mac whose phrases did made the Shortcuts app crash. Siri on the newest
// systems may answer such questions itself, so the value is Shortcuts and Spotlight. Each answer is a card as well as a sentence, naming its source.

/// The app's one store, set when the app starts, so an action run as the app launches reads the same plan the pages show.
@MainActor enum IntentHost { static var store: PhoneStore? }

private let noStore: IntentDialog = "Open Nightwatch once, and choose where you observe from."

struct TonightIntent: AppIntent {
    // "Sky Score", not "Is Tonight Clear": a weather question in Spotlight also brings Siri's Apple Weather suggestion.
    static let title: LocalizedStringResource = "Sky Score"
    static let description = IntentDescription("Tonight's sky score and clear window at your site, and tomorrow's outlook.")
    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog & ShowsSnippetView {
        let snap = await IntentHost.store?.snapshotForAnswer(), text = Copy.siriTonight(snap)
        return .result(value: text, dialog: "\(text)", view: AnswerCard(text: text, snapshot: snap))
    }
}

/// For a shortcut's If step: "if tonight is clear, text me".
struct ClearTonightIntent: AppIntent {
    static let title: LocalizedStringResource = "Clear Window Tonight"
    static let description = IntentDescription("Yes when tonight has a clear window by your go rule, no when it has not. Use it in a shortcut's If step.")
    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<Bool> & ProvidesDialog {
        let store = IntentHost.store, snap = await store?.snapshotForAnswer()
        return .result(value: store?.planning?.tonight.primary != nil, dialog: "\(Copy.siriTonight(snap))")
    }
}

struct BestTargetsIntent: AppIntent {
    static let title: LocalizedStringResource = "Best Targets Tonight"
    static let description = IntentDescription("Tonight's plan, or the best targets for your telescope tonight.")
    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog & ShowsSnippetView {
        let store = IntentHost.store, snap = await store?.snapshotForAnswer()
        let text = Copy.siriBest(snap, session: store?.session(), site: store?.site)
        return .result(value: text, dialog: "\(text)", view: AnswerCard(text: text, snapshot: snap))
    }
}

struct EventsTonightIntent: AppIntent {
    static let title: LocalizedStringResource = "Events Tonight"
    static let description = IntentDescription("Meteor showers, space station passes, eclipses and other events tonight.")
    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog & ShowsSnippetView {
        let store = IntentHost.store, snap = await store?.snapshotForAnswer()   // events arrive with the first plan
        let text = Copy.siriEvents(store?.events ?? [])
        return .result(value: text, dialog: "\(text)", view: AnswerCard(text: text, snapshot: snap))
    }
}

struct TargetEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Target"
    static let defaultQuery = TargetQuery()
    let id: String
    let name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct TargetQuery: EntityStringQuery {
    @MainActor private func targets() -> [RankedTarget] {
        guard let p = IntentHost.store?.planning?.tonight else { return [] }
        var seen = Set<String>()
        return (p.targets + p.brightTargets + p.favourites.map(\.target)).filter { seen.insert($0.id).inserted }
    }
    /// By id from the whole catalogue, so a saved shortcut still finds its target on a night it is not in the list.
    @MainActor func entities(for identifiers: [String]) async throws -> [TargetEntity] {
        identifiers.compactMap { id in IntentHost.store?.targetName(id: id).map { TargetEntity(id: id, name: $0) } }
    }
    @MainActor func entities(matching string: String) async throws -> [TargetEntity] {
        let q = SpokenSearch.normalise(string)   // Siri writes "M31" as "M3 one"
        return targets().filter { $0.matches(q) }.map { TargetEntity(id: $0.id, name: $0.name) }
    }
    @MainActor func suggestedEntities() async throws -> [TargetEntity] {
        Array(targets().prefix(20)).map { TargetEntity(id: $0.id, name: $0.name) }
    }
}

struct ShowTargetIntent: OpenIntent {   // also what Spotlight's result for a target runs
    static let title: LocalizedStringResource = "Show Target"
    static let description = IntentDescription("Opens a target's page.")
    static let openAppWhenRun = true
    @Parameter(title: "Target") var target: TargetEntity
    @MainActor func perform() async throws -> some IntentResult {
        IntentHost.store?.pendingLink = .target(target.id)
        return .result()
    }
}

struct RefreshIntent: AppIntent {
    static let title: LocalizedStringResource = "Refresh Forecast"
    static let description = IntentDescription("Fetches the forecast now and works out tonight again.")
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        guard let store = IntentHost.store else { return .result(dialog: noStore, view: AnswerCard(text: "No site yet.", snapshot: nil)) }
        _ = await store.snapshotForAnswer()
        let before = store.forecast?.fetchedAt
        await store.refresh(force: true)
        let snap = store.tonight?.snapshot
        // A failed fetch leaves the forecast as it was: say so, never "Refreshed".
        let lead = store.forecast?.fetchedAt != before && store.forecast != nil ? "Refreshed. "
            : "Could not refresh just now\(store.forecast.map { ", so this is the forecast from \(Copy.clockTime($0.fetchedAt))" } ?? ""). "
        let text = lead + Copy.siriTonight(snap)
        return .result(dialog: "\(text)", view: AnswerCard(text: text, snapshot: snap))
    }
}

struct NotificationsOnIntent: AppIntent {
    static let title: LocalizedStringResource = "Turn On Clear-Sky Notifications"
    static let description = IntentDescription("Turns Nightwatch's clear-sky notifications on.")
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        IntentHost.store?.setNotifyEnabled(true)
        return .result(dialog: "Clear-sky notifications are on.")
    }
}

struct NotificationsOffIntent: AppIntent {
    static let title: LocalizedStringResource = "Turn Off Clear-Sky Notifications"
    static let description = IntentDescription("Turns Nightwatch's clear-sky notifications off.")
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        IntentHost.store?.setNotifyEnabled(false)
        return .result(dialog: "Clear-sky notifications are off.")
    }
}

// `.system.searchInApp` is in the iOS 27 SDK (Xcode 27, Swift 6.4); CI's Xcode 26 builds without it.
#if compiler(>=6.4)
/// "Find the Crescent Nebula in Nightwatch" (#72), as on the Mac. Siri on iOS 27 sends "... in <app>" to an app's in-app search; this takes its words to
/// the Targets group that holds the match (a target that is not up tonight too, with the hint saying so). Words that ask for tonight, such as
/// "What's worth imaging tonight", open the plan instead, since no target is named by them.
@available(iOS 27, *)
@AppIntent(schema: .system.searchInApp)
struct SearchTargetsIntent {
    static let searchScopes: [StringSearchScope] = [.general]
    static let supportedModes: IntentModes = .foreground   // the results are shown in the app
    var criteria: StringSearchCriteria
    @MainActor func perform() async throws -> some IntentResult {
        let term = SpokenSearch.normalise(criteria.term)
        IntentHost.store?.pendingLink = SpokenSearch.asksForTonight(term) ? .plan : .search(term)
        return .result()
    }
}
#endif

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

/// An answer as a card: the sentence, and the forecast's source at its foot, Apple's mark when Apple Weather supplied it, as the Mac's
/// cards have it (Spotlight runs an action without showing its sentence).
struct AnswerCard: View {
    let text: String
    let snapshot: WidgetSnapshot?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text.plainDashes).font(.body).fixedSize(horizontal: false, vertical: true)
            if let snapshot { WeatherMarkView(snapshot: snapshot, height: 11).font(.caption).foregroundStyle(.secondary) }
        }
        .padding().frame(maxWidth: .infinity, alignment: .leading)
    }
}

// Spotlight and Siri's semantic index. Tonight's answer is indexed as one entry in the words the app already uses, and indexed again with every new
// snapshot, so the system can answer "is it clear for stargazing tonight?" from here. Only this device's Spotlight index holds it.

/// Tonight's sky as one entry: the sky score, verdict, clear window and best targets.
struct TonightEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Tonight's sky"
    static let defaultQuery = TonightQuery()
    let id: String   // always "tonight", so each re-index replaces the last
    let summary: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "Tonight's sky", subtitle: "\(summary)") }
}

struct TonightQuery: EntityQuery {
    @MainActor func entities(for identifiers: [String]) async throws -> [TonightEntity] {
        guard identifiers.contains("tonight"), let snap = IntentHost.store?.tonight?.snapshot else { return [] }
        return [TonightEntity(id: "tonight", summary: Copy.siriTonight(snap))]
    }
}

/// Spotlight's result for tonight opens the app.
struct OpenTonightIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Tonight's Sky"
    static let isDiscoverable = false
    static let openAppWhenRun = true
    @Parameter(title: "Tonight") var target: TonightEntity
    @MainActor func perform() async throws -> some IntentResult { .result() }
}

import CoreSpotlight

@available(iOS 18, *)
extension TonightEntity: IndexedEntity {
    var attributeSet: CSSearchableItemAttributeSet {
        let a = defaultAttributeSet
        a.title = "Tonight's sky for stargazing and astrophotography"
        a.contentDescription = summary
        a.textContent = summary
        a.keywords = ["tonight", "clear sky", "clear night", "stargazing", "astronomy", "astrophotography", "telescope", "sky score", "cloud", "Moon", "Nightwatch"]
        return a
    }
}

enum TonightIndex {
    /// Called with each new snapshot the app writes for the widget.
    static func update(_ snapshot: WidgetSnapshot) {
        guard #available(iOS 18, *) else { return }
        let entity = TonightEntity(id: "tonight", summary: Copy.siriTonight(snapshot))
        Task { try? await CSSearchableIndex.default().indexAppEntities([entity]) }
    }
}
