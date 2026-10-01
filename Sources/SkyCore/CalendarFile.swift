import Foundation

/// "Add to Calendar" on an event's page (owner, 1 October 2026, from the competitor review): one iCalendar event that
/// Calendar opens and offers to add. A file, not EventKit, so the app needs no calendar entitlement (App Review asks
/// about every entitlement, guideline 2.4.5(i)).
public enum CalendarFile {
    /// The event from its start to its end (an hour when it has none), with a reminder 15 minutes before. The best time,
    /// when it differs from the start, goes in the notes: a shower runs all night but is best at one hour.
    /// A shower whose peak is still to come is added for its peak night (`calendarSpan`), not tonight.
    public static func ics(for e: SkyEvent, site: Site, now: Date = Date()) -> String {
        let title = e.calendarSpan?.title ?? e.title, start = e.calendarSpan?.start ?? e.time
        let end = e.calendarSpan?.end ?? max(e.endTime ?? e.time.addingTimeInterval(3600), e.time.addingTimeInterval(600))
        var notes = e.calendarSpan?.notes ?? e.detail
        if e.calendarSpan == nil, let b = e.best, b != e.time, !notes.contains(Copy.hhmm(b, site: site)) {
            notes += (notes.isEmpty ? "" : ". ") + "Best at \(Copy.hhmm(b, site: site))"
        }
        // ponytail: no line folding at 75 octets; Calendar reads long lines, add folding if another app needs it.
        return [
            "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Nightwatch//EN", "BEGIN:VEVENT",
            "UID:\(e.id)-\(Int(e.time.timeIntervalSince1970))@nightwatch",
            "DTSTAMP:\(stamp(now))", "DTSTART:\(stamp(start))", "DTEND:\(stamp(end))",
            "SUMMARY:\(escape(title))", "LOCATION:\(escape(site.name))", "DESCRIPTION:\(escape(notes))",
            "BEGIN:VALARM", "ACTION:DISPLAY", "DESCRIPTION:\(escape(title))", "TRIGGER:-PT15M", "END:VALARM",
            "END:VEVENT", "END:VCALENDAR", "",
        ].joined(separator: "\r\n")
    }

    static func stamp(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return f.string(from: d)
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,").replacingOccurrences(of: "\n", with: "\\n")
    }
}
