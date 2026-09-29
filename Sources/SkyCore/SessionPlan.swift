import Foundation

/// When the night's session must end (#57): sleep, or work the next day. Off by default; `minutes` after local midnight.
public struct StopBy: Codable, Equatable, Sendable {
    public var enabled = false
    public var minutes = 30   // 00:30
    public init(enabled: Bool = false, minutes: Int = 30) { self.enabled = enabled; self.minutes = minutes }

    /// This clock time on `night`: the first one after that day's noon, so 23:00 is the same evening and 00:30 the next
    /// morning, whenever the window opens. Set by clock hour and minute, so the night the clocks change keeps it right.
    public func date(night: Night, site: Site) -> Date {
        let cal = site.calendar
        let noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: night.localDate)!
        let h = minutes / 60 % 24, m = minutes % 60
        let same = cal.date(bySettingHour: h, minute: m, second: 0, of: noon)!
        return same > noon ? same : cal.date(bySettingHour: h, minute: m, second: 0, of: cal.date(byAdding: .day, value: 1, to: noon)!)!
    }
}

/// One target's turn in Tonight's plan, and why it has this place.
public struct PlanSlot: Equatable, Sendable, Identifiable {
    public enum Reason: Equatable, Sendable { case bestPlaced, favourite, added }
    public let target: RankedTarget
    public let start: Date
    public let end: Date
    public let reason: Reason
    public var id: String { target.id }
}

/// Tonight's plan (#57, owner-approved mock-up, 29 September 2026): the clear window as a running order of the night's best
/// deep-sky targets, each when it is best placed and for a stack's length, ending with the window or the Stop by time.
public struct SessionPlan: Equatable, Sendable {
    public let slots: [PlanSlot]
    /// The window's end, or Stop by when that comes first.
    public let end: Date
    /// Time left after the last slot; nil when under 15 minutes.
    public let leftover: ClearWindow?
    /// The stack each slot holds, in minutes; nil without a frame count (a slot is then the time a target is well placed).
    public let stackMinutes: Double?
    /// The leftover is shorter than a stack (an hour without a frame count), rather than empty for want of a target.
    public var leftoverTooShort: Bool { leftover.map { $0.hours * 60 < (stackMinutes ?? SessionPlanner.minimumSlot / 60) } ?? false }
    /// The maker's battery life when the plan runs longer than it (a power bank or spare battery may be needed); else nil.
    public let outlastsBatteryHours: Double?
    public var hours: Double { slots.last.map { $0.end.timeIntervalSince(slots[0].start) / 3600 } ?? 0 }
}

public enum SessionPlanner {
    static let deepSky: Set<TargetGroup> = [.nebulae, .galaxies, .clusters]
    /// Only deep sky is stacked for hours, so only deep sky can be added; its frame and the Moon are the user's call.
    public static func canTake(_ t: RankedTarget) -> Bool { deepSky.contains(t.group) }
    /// How many of the night's best targets the plan chooses among, before favourites and added ones.
    static let poolSize = 12
    /// No slot is shorter than this, and a target must be well placed for at least this long to take one.
    static let minimumSlot: TimeInterval = 3600
    static let step: TimeInterval = 600

    /// The plan for `plan`'s clear window from `now` (or its start), or nil on a night with no window, a bright night, or
    /// nothing to shoot. The pool is the night's best deep-sky targets that fit the frame and escape the Moon (well-known
    /// names first, then the brightest), plus favourites and targets `added` from a page; `removed` never take part.
    /// `added`, then favourites, take their turn first when they are up; otherwise the one highest in the middle of the slot
    /// goes next, so each comes when it is best placed and one that sets early is not left until it has gone. When nothing
    /// is up the plan waits for the next target to rise.
    public static func make(plan: NightPlan, presetID: String?, batteryHours: Double?, stopBy: StopBy, favourites: [String],
                            added: [String] = [], removed: Set<String> = [], now: Date? = nil, site: Site) -> SessionPlan? {
        guard plan.mode == .dark, let w = plan.primary else { return nil }
        let end = stopBy.enabled ? min(w.end, stopBy.date(night: plan.night, site: site)) : w.end
        var t = w.start
        if let now, now > t { t = Date(timeIntervalSinceReferenceDate: (now.timeIntervalSinceReferenceDate / 300).rounded(.up) * 300) }
        guard end > t else { return nil }

        var byID: [String: RankedTarget] = [:]
        for x in plan.targets + plan.favourites.filter({ $0.notTonight == nil }).map(\.target) where byID[x.id] == nil { byID[x.id] = x }
        let best = byID.values
            .filter { deepSky.contains($0.group) && !$0.moonWashed && $0.fit == .fits }
            .sorted { ($0.commonName == nil ? 1 : 0, $0.magnitude ?? 12, $0.id) < ($1.commonName == nil ? 1 : 0, $1.magnitude ?? 12, $1.id) }
            .prefix(poolSize)
        let chosen = added + favourites.filter { !added.contains($0) }
        let pool = (Array(best) + chosen.compactMap { byID[$0] })
            .reduce(into: [RankedTarget]()) { acc, x in if !acc.contains(where: { $0.id == x.id }) { acc.append(x) } }
            .filter { !removed.contains($0.id) && $0.viewable != nil && canTake($0) }
        let stack = ShootingTips.stackMinutes(presetID: presetID).map { $0 * 60 }

        func alt(_ c: RankedTarget, _ at: Date) -> Double { Ephemeris.altAz(raHours: c.raHours, decDeg: c.decDeg, at: at, site: site).alt }
        /// The slot `c` would take from `t`: a stack while it stays up, or without a frame count the time it stays well
        /// placed (within 10° of its best tonight); nil when that is not possible now.
        func slot(_ c: RankedTarget) -> TimeInterval? {
            guard let v = c.viewable, v.start <= t else { return nil }
            let upTo = min(v.end, end)
            if let s = stack { return upTo.timeIntervalSince(t) >= s ? s : nil }
            let floor = c.peakAltDeg - 10
            var u = t
            while u < upTo, alt(c, u) >= floor { u = min(upTo, u.addingTimeInterval(step)) }
            return u.timeIntervalSince(t) >= minimumSlot ? u.timeIntervalSince(t) : nil
        }

        var slots: [PlanSlot] = []
        while end.timeIntervalSince(t) >= min(stack ?? minimumSlot, minimumSlot) {
            let used = Set(slots.map(\.id))
            let open = pool.compactMap { c in used.contains(c.id) ? nil : slot(c).map { (c, $0) } }
            let first = chosen.lazy.compactMap { id in open.first { $0.0.id == id } }.first
            guard let (pick, len) = first ?? open.max(by: { alt($0.0, t.addingTimeInterval($0.1 / 2)) < alt($1.0, t.addingTimeInterval($1.1 / 2)) }) else {
                t = t.addingTimeInterval(step)   // nothing up long enough yet: wait for the next to rise
                continue
            }
            let reason: PlanSlot.Reason = added.contains(pick.id) ? .added : (favourites.contains(pick.id) ? .favourite : .bestPlaced)
            slots.append(PlanSlot(target: pick, start: t, end: t.addingTimeInterval(len), reason: reason))
            t = t.addingTimeInterval(len)
        }
        guard let last = slots.last else { return nil }
        let left = end.timeIntervalSince(last.end) >= 15 * 60 ? ClearWindow(start: last.end, end: end) : nil
        let hours = last.end.timeIntervalSince(slots[0].start) / 3600
        return SessionPlan(slots: slots, end: end, leftover: left, stackMinutes: stack.map { $0 / 60 },
                           outlastsBatteryHours: batteryHours.flatMap { hours > $0 ? $0 : nil })
    }
}
