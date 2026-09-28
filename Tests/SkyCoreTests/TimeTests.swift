import Testing
import Foundation
import CAstronomyEngine
@testable import SkyCore

@Test func j2000RoundTrip() {
    let d = Date(timeIntervalSince1970: 946_728_000)
    let t = astro_time_t(d)
    #expect(abs(t.ut) < 1e-9)
    #expect(abs(t.date.timeIntervalSince(d)) < 0.001)
}

@Test func arbitraryDateRoundTrip() {
    let d = Date(timeIntervalSince1970: 1_790_000_000)
    #expect(abs(astro_time_t(d).date.timeIntervalSince(d)) < 0.001)
}

/// Dates read "Sun 27 Sep" in the site's own time zone: 23:30 UTC on the 27th is already Monday in Sydney.
@Test func datesReadDayDateMonth() {
    let london = Site(name: "L", latitude: 51.5, longitude: 0, elevationM: 0, timeZoneID: "Europe/London", bortle: 5)
    let sydney = Site(name: "S", latitude: -33.9, longitude: 151.2, elevationM: 0, timeZoneID: "Australia/Sydney", bortle: 5)
    #expect(Copy.dayMonth(utc(2026, 9, 27, 11, 0), site: london) == "Sun 27 Sep")
    #expect(Copy.dayMonth(utc(2026, 9, 27, 23, 30), site: sydney) == "Mon 28 Sep")
}

@Test func hoursAgoRoundsDown() {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    #expect(Copy.hoursAgo(now.addingTimeInterval(-7 * 3600 - 1200), now: now) == "7 h ago")
    #expect(Copy.hoursAgo(now.addingTimeInterval(-6 * 3600), now: now) == "6 h ago")
}
