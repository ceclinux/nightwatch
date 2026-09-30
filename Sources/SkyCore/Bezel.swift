import Foundation

public enum BezelSlot: String, Codable, Sendable, Equatable { case clear, partCloud, cloudy, daylight }

extension NightPlan {
    /// The darkness the plan is measured in: nautical on a bright plan, astronomical otherwise.
    public var darkSpan: ClearWindow? {
        let (s, e) = mode == .bright ? (night.nauticalStart, night.nauticalEnd) : (night.darkStart, night.darkEnd)
        guard let s, let e else { return nil }
        return ClearWindow(start: s, end: e)
    }
}

/// The popover's 12-hour clock face (handover tick rule): tick i sits at 6i° and stands for the 12 minutes from clock time 12i (mod 12 h).
public enum Bezel {
    /// The face shows all of darkness when it fits in 12 hours, else the 12 hours centred on the primary window
    /// (or on the middle of darkness when there is none). Every slot is classified at its middle.
    /// ponytail: a clock change inside the face shifts that night's ticks by an hour; the two nights a year it happens are left as they are.
    public static func slots(darkness: ClearWindow?, windows: [ClearWindow], primary: ClearWindow?, hours: [HourlyConditions], site: Site) -> [BezelSlot] {
        guard let dark = darkness else { return Array(repeating: .daylight, count: 60) }
        let centre = dark.hours <= 12 ? dark.midpoint : (primary?.midpoint ?? dark.midpoint)
        let start = centre.addingTimeInterval(-6 * 3600)
        let c = site.calendar.dateComponents([.hour, .minute, .second], from: start)
        let startMinute = Double((c.hour ?? 0) % 12 * 60 + (c.minute ?? 0)) + Double(c.second ?? 0) / 60
        return (0..<60).map { i in
            var offset = (Double(12 * i) - startMinute).truncatingRemainder(dividingBy: 720)
            if offset < 0 { offset += 720 }
            let mid = start.addingTimeInterval(offset * 60 + 360)
            if windows.contains(where: { $0.start <= mid && mid < $0.end }) { return .clear }
            guard dark.start <= mid, mid < dark.end else { return .daylight }
            let cloud = hours.first { $0.time <= mid && mid < $0.time.addingTimeInterval(3600) }?.effectiveCloud ?? 100
            return cloud < 50 ? .partCloud : .cloudy
        }
    }
}
