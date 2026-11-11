import Foundation
import SkyCore

/// What the Eyes and binoculars page lists: tonight's targets that can be seen without a telescope from this site's sky, the
/// Milky Way for a camera, and the events anyone can watch. The same rules as the Mac's page, from SkyCore's `EyeViews`.
extension PhoneStore {
    public func eyeView(_ t: RankedTarget) -> EyeView? { site.flatMap { EyeViews.view(t, bortle: $0.bortle) } }

    /// The Milky Way's core and the Cygnus band when they clear 10 degrees in tonight's window (the core's own card is dimmed
    /// elsewhere, so only those that show are listed here).
    public var milkyWayTonight: [RankedTarget] {
        guard let p = planning?.tonight, let s = site else { return [] }
        let washed = (Planner.moonTonight(p).map { $0 != .down } ?? false) && p.moonIllumination >= 0.25
        guard let window = p.primary ?? p.darkSpan else { return [] }
        return MilkyWay.targets(window: window, site: s, moonWashed: washed).filter { $0.viewable != nil }
    }

    public var eyeTargets: [RankedTarget] {
        guard let p = planning?.tonight else { return [] }
        return ((p.mode == .bright ? p.brightTargets : p.targets) + milkyWayTonight).filter { eyeView($0) != nil }
    }

    public var eyeEvents: [SkyEvent] { events.filter(EyeViews.includes) }
}
