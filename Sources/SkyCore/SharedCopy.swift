import Foundation

/// Words the Mac's and the phone's screens both use, held once so the two cannot drift apart again (the 28 October 2026 parity audit
/// found the Alerts and Targets labels worded differently on each).
public enum SettingsCopy {
    public static let headsUp = "Evening heads-up (one hour before sunset)"
    public static let tomorrowPreview = "Tomorrow preview when tonight is out"
    public static let cancelOnDowngrade = "Cancel notice if the forecast turns"
    public static let quietHoursStart = "Quiet hours start"
    public static let quietHoursEnd = "Quiet hours end"
    /// The Targets filters: both read as things to show, so a switch that is on always means more cards (owner, 28 September 2026).
    public static let showHeading = "SHOW"
    public static let showMisfits = "Doesn't fit my frame"
    public static let showMoonWashed = "Washed out by the Moon"
    public static let comingUpCaption = "The Moon covering a planet, a bright star or the Pleiades, seen from here in darkness."
}

extension Copy {
    /// The line under Tonight's heading: the day, the Bortle class, and the tilt a polar-aligned equatorial mount needs, with "bright night"
    /// when the plan is the Moon-and-planets one. `dayText` is the day as each app words it ("13 Oct", "Tue 13 Oct").
    public static func nightLine(dayText: String, site: Site, bright: Bool) -> String {
        let tilt = String(format: "%.1f", abs(site.latitude))
        return "\(dayText) · Bortle \(site.bortle) · EQ tilt \(tilt)° \(site.latitude >= 0 ? "true north" : "true south")" + (bright ? " · bright night" : "")
    }
}
