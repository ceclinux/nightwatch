import Foundation
import SkyCore

/// Where a `nightwatch://` link (from the widget, or a Shortcut) takes the app. SkyCore's `WidgetLink` reads the URL; this says which page.
public enum LinkRoute: Equatable, Sendable { case plan, targets }

public extension WidgetLink {
    /// Plan has its own page; everything else lands in Targets (a target opens its page there, a search opens the list).
    var phoneRoute: LinkRoute { if case .plan = self { return .plan }; return .targets }
}

public extension PhoneStore {
    /// A target by its id, from tonight's lists, the favourites and the Milky Way entries; nil when it is not one of tonight's.
    func target(withID id: String) -> RankedTarget? {
        guard let p = planning?.tonight else { return nil }
        let pool = p.targets + p.brightTargets + p.best + p.favourites.map(\.target) + milkyWayTonight
        return pool.first { $0.id == id }
    }
}

public extension PhoneStore {
    /// What a spoken search matches in the whole catalogue, up tonight or not, and the group it opens (the Mac's Siri search, #72).
    func catalogueMatches(_ query: String) -> [DeepSkyObject] { Self.bundledCatalogue.objects(matching: query) }
    func groupForSearch(_ text: String) -> TargetGroup? {
        let plan = planning?.tonight
        return SpokenSearch.group(for: text, planned: (plan?.mode == .bright ? plan?.brightTargets : plan?.targets).map { $0 + (plan?.favourites.map(\.target) ?? []) } ?? [],
                                  catalogue: Self.bundledCatalogue)
    }
    /// Read once: the catalogue is a large CSV, and a search can come several times in a session.
    private static let bundledCatalogue = (try? Catalog.bundled()) ?? Catalog(objects: [])
}

public extension PhoneStore {
    /// Tonight's snapshot for a Siri or Shortcuts answer. An action can run as the app is launched in the background, before the first page is
    /// built, so it works the page out from what is saved (a forecast that is still fresh is not fetched again). Nil with no site or no forecast.
    func snapshotForAnswer() async -> WidgetSnapshot? {
        if tonight == nil, site != nil { await refresh() }
        return tonight?.snapshot
    }

    /// A target's name by id from the whole catalogue, so a saved Show Target shortcut still finds it on a night it is not in the list.
    func targetName(id: String) -> String? {
        if let t = target(withID: id) { return t.name }
        if id == "moon" { return "Moon" }
        if id.hasPrefix("planet-"), let p = Planet(rawValue: String(id.dropFirst(7))) { return p.displayName }
        if let s = ((try? BrightStars.bundled()) ?? []).first(where: { $0.id == id }) { return s.name }
        if let c = ((try? Constellations.bundled()) ?? []).first(where: { $0.id == id }) { return c.name }
        return ((try? Catalog.bundled()) ?? Catalog(objects: [])).objects.first { $0.id == id }?.displayName
    }
}
