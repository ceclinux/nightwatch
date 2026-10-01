import Testing
import Foundation
@testable import SkyCore

private let site = Site(name: "Malham, Yorkshire", latitude: 54.06, longitude: -2.15, elevationM: 300, timeZoneID: "Europe/London", bortle: 3)

@Test func calendarFileHoldsTheEventItsBestTimeAndAReminder() {
    let start = utc(2026, 10, 21, 19, 0), end = utc(2026, 10, 22, 4, 30)
    var e = SkyEvent(id: "shower-ori", kind: .meteorShower, title: "Orionids", detail: "Up to 20 an hour; radiant in Orion",
                     time: start, endTime: end, raHours: nil, decDeg: nil)
    e.best = utc(2026, 10, 22, 2, 0)
    let ics = CalendarFile.ics(for: e, site: site, now: start)
    #expect(ics.hasPrefix("BEGIN:VCALENDAR\r\n") && ics.hasSuffix("END:VCALENDAR\r\n"))
    #expect(ics.contains("DTSTART:20261021T190000Z\r\n") && ics.contains("DTEND:20261022T043000Z\r\n"))
    #expect(ics.contains("SUMMARY:Orionids\r\n") && ics.contains("LOCATION:Malham\\, Yorkshire\r\n"))
    #expect(ics.contains("DESCRIPTION:Up to 20 an hour\\; radiant in Orion. Best at 03:00\r\n"))   // 02:00 UTC is 03:00 BST
    #expect(ics.contains("TRIGGER:-PT15M"))
}

@Test func calendarFileGivesAnEventWithNoEndAnHour() {
    let t = utc(2026, 11, 3, 20, 0)
    let e = SkyEvent(id: "conj-moon-saturn", kind: .conjunction, title: "Moon near Saturn", detail: "", time: t, endTime: nil, raHours: nil, decDeg: nil)
    let ics = CalendarFile.ics(for: e, site: site, now: t)
    #expect(ics.contains("DTSTART:20261103T200000Z\r\n") && ics.contains("DTEND:20261103T210000Z\r\n"))
    #expect(ics.contains("DESCRIPTION:\r\n"))
}

@Test func calendarFileDoesNotRepeatABestTimeTheDetailAlreadyGives() {
    let t = utc(2026, 10, 1, 19, 38)
    var e = SkyEvent(id: "x", kind: .comet, title: "C/2026 A1", detail: "Best 22:00", time: t, endTime: t.addingTimeInterval(8 * 3600), raHours: nil, decDeg: nil)
    e.best = utc(2026, 10, 1, 21, 0)   // 22:00 BST
    #expect(CalendarFile.ics(for: e, site: site, now: t).contains("DESCRIPTION:Best 22:00\r\n"))
}
