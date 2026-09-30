import AppIntents
import CoreSpotlight
import SkyCore

// Siri answering from Nightwatch (#72). On macOS 27 Siri answers "is it clear for stargazing tonight?" from Apple Weather,
// and reads app content only from Spotlight's semantic index (WWDC26 sessions 240, 343, 344). So tonight's answer and
// tonight's targets are indexed as entities, in the words the popover and the target cards already use, and re-indexed
// with every widget snapshot. Only this Mac's Spotlight index holds them.

/// Tonight's sky as one entry: the sky score, verdict, clear window, best targets and events.
struct TonightEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Tonight's sky"
    static let defaultQuery = TonightQuery()
    let id: String   // always "tonight", so each re-index replaces the last
    let summary: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "Tonight's sky", subtitle: "\(summary)") }
}

struct TonightQuery: EntityQuery {
    @MainActor func entities(for identifiers: [String]) async throws -> [TonightEntity] {
        identifiers.contains("tonight") ? [SiriIndex.tonight()] : []
    }
}

/// Spotlight's result for tonight opens the Targets window.
struct OpenTonightIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Tonight's Sky"
    static let isDiscoverable = false
    @Parameter(title: "Tonight") var target: TonightEntity
    @MainActor func perform() async throws -> some IntentResult {
        AppDelegate.handle(WidgetLink.targets.url)
        return .result()
    }
}

@available(macOS 15, *)
extension TonightEntity: IndexedEntity {
    var attributeSet: CSSearchableItemAttributeSet {
        let a = defaultAttributeSet
        a.title = "Tonight's sky for stargazing and astrophotography"
        a.contentDescription = summary
        a.textContent = summary
        a.keywords = ["tonight", "clear sky", "clear night", "stargazing", "astronomy", "astrophotography", "telescope",
                      "sky score", "cloud", "Moon", "Nightwatch"]
        return a
    }
}

@available(macOS 15, *)
extension TargetEntity: IndexedEntity {
    var attributeSet: CSSearchableItemAttributeSet {
        let a = defaultAttributeSet
        a.title = name
        a.contentDescription = summary
        a.textContent = summary
        a.keywords = keywords
        return a
    }
}

@MainActor enum SiriIndex {
    private static var running: Task<Void, Never>?

    static func tonight() -> TonightEntity {
        let store = IntentHost.store, snap = store.snapshot()
        let text = [Copy.siriTonight(snap), Copy.siriBest(snap, session: store.session(for: store.plan), site: store.site),
                    Copy.siriEvents(store.events)].joined(separator: " ")
        return TonightEntity(id: "tonight", summary: text)
    }

    /// Tonight's targets as their cards read to VoiceOver: "NGC 6888 Crescent Nebula, viewable from 20:46 to 02:16, …".
    static func targets() -> [TargetEntity] {
        let store = IntentHost.store
        guard let p = store.plan, let site = store.site else { return [] }
        let moonUp = Planner.moonTonight(p).map { $0 != .down } ?? false
        var seen = Set<String>()
        return (p.targets + p.brightTargets + p.favourites.map(\.target)).filter { seen.insert($0.id).inserted }.map { t in
            let near = t.isNearMoon(moonIllumination: p.moonIllumination, moonUpTonight: moonUp)
            let summary = "Tonight at \(site.name): " + Copy.cardLabel(t, lit: p.primary != nil, nearMoon: near, site: site)
            return TargetEntity(id: t.id, name: t.name, summary: summary,
                                keywords: [t.catalogueID, t.commonName, t.typeName, t.group.displayName].compactMap { $0 }.filter { !$0.isEmpty })
        }
    }

    /// Replaces what is indexed with tonight's answer and targets. One update at a time, in order; plain awaits, no task
    /// group (one crashed on macOS 27, 29 September 2026).
    static func update() {
        guard #available(macOS 15, *) else { return }
        let tonight = tonight(), targets = targets(), previous = running
        running = Task {
            await previous?.value
            let index = CSSearchableIndex.default()
            try? await index.deleteAppEntities(ofType: TargetEntity.self)
            try? await index.indexAppEntities([tonight])
            try? await index.indexAppEntities(targets)
        }
    }
}
