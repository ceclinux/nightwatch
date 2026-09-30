import Testing
import Foundation
@testable import SkyCore

let sheffield = Site(name: "Sheffield", latitude: 53.38, longitude: -1.47, elevationM: 100, timeZoneID: "Europe/London", bortle: 5)
let sydney = Site(name: "Sydney", latitude: -33.87, longitude: 151.21, elevationM: 20, timeZoneID: "Australia/Sydney", bortle: 7)

func utc(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
    var c = DateComponents(); c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi
    var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
    return cal.date(from: c)!
}

func close(_ a: Date, _ b: Date, minutes: Double) -> Bool { abs(a.timeIntervalSince(b)) <= minutes * 60 }

// Oracles: USNO sunset 18:02 UTC (23rd); sunrise-sunset.org api.sunrise-sunset.org/json (date=2026-09-23)
// astronomical_twilight_end 20:01:49 (23rd evening); (date=2026-09-24) astronomical_twilight_begin 03:56:43,
// sunrise 05:53:39 (24th morning, verified live — the brief's original 03:54:39/05:51:54 were the
// date=2026-09-23 response's own morning fields, i.e. the 23rd's dawn, not the night-ending 24th morning).
@Test func sheffieldNightOracle() throws {
    let night = try Ephemeris.night(localDate: utc(2026, 9, 23, 12, 0), site: sheffield)
    #expect(night.key == "2026-09-23")
    #expect(close(night.sunset, utc(2026, 9, 23, 18, 3), minutes: 3))
    #expect(close(try #require(night.darkStart), utc(2026, 9, 23, 20, 2), minutes: 3))
    #expect(close(try #require(night.darkEnd), utc(2026, 9, 24, 3, 57), minutes: 3))
    #expect(close(night.sunrise, utc(2026, 9, 24, 5, 54), minutes: 3))
}

// Oracle: sunrise-sunset.org Sydney 2026-09-23: sunset 07:53:02 UTC, astronomical twilight end 09:15:09 UTC.
@Test func sydneyNightOracleSouthernHemisphere() throws {
    let night = try Ephemeris.night(localDate: utc(2026, 9, 23, 2, 0), site: sydney)
    #expect(night.key == "2026-09-23")
    #expect(close(night.sunset, utc(2026, 9, 23, 7, 53), minutes: 3))
    #expect(close(try #require(night.darkStart), utc(2026, 9, 23, 9, 15), minutes: 3))
}

@Test func polarSummerHasNoAstronomicalDarkness() throws {
    let tromso = Site(name: "Tromsø", latitude: 69.65, longitude: 18.96, elevationM: 10, timeZoneID: "Europe/Oslo", bortle: 4)
    let night = try Ephemeris.night(localDate: utc(2026, 7, 20, 10, 0), site: tromso)
    #expect(night.darkStart == nil)
    #expect(night.darkEnd == nil)
    #expect(night.sunrise > night.sunset)
    #expect(!night.hasDarkness)
}

@Test func polarNightHasDarkness() throws {
    let tromso = Site(name: "Tromsø", latitude: 69.65, longitude: 18.96, elevationM: 10, timeZoneID: "Europe/Oslo", bortle: 4)
    let night = try Ephemeris.night(localDate: utc(2026, 12, 21, 10, 0), site: tromso)
    #expect(night.hasDarkness)
    let ds = try #require(night.darkStart), de = try #require(night.darkEnd)
    #expect(ds >= night.sunset && de <= night.sunrise && de > ds)
    #expect(Ephemeris.sunAltitude(at: ds.addingTimeInterval(3600), site: tromso) < -18)
    #expect(de.timeIntervalSince(ds) > 12 * 3600)   // most of the polar night is astronomically dark
}

@Test func polarisIsHighFromSheffield() {
    let p = Ephemeris.altAz(raHours: 2.53, decDeg: 89.26, at: utc(2026, 9, 23, 22, 0), site: sheffield)
    #expect(abs(p.alt - 53.4) < 1.5)
}

@Test func moonIlluminationInRange() {
    let m = Ephemeris.moon(at: utc(2026, 9, 23, 22, 0), site: sheffield)
    #expect(m.illumination >= 0 && m.illumination <= 1)
    #expect(m.position.altDeg > -90 && m.position.altDeg < 90)
}

@Test func separationOfIdenticalPointsIsZeroAndPolesIs180() {
    #expect(Ephemeris.separationDeg(ra1Hours: 1, dec1Deg: 10, ra2Hours: 1, dec2Deg: 10) < 1e-9)
    #expect(abs(Ephemeris.separationDeg(ra1Hours: 0, dec1Deg: 90, ra2Hours: 0, dec2Deg: -90) - 180) < 1e-9)
}

@Test func constellationLookup() {
    let c = Ephemeris.constellation(raHours: 5.6, decDeg: -5.4)   // M42
    #expect(c.symbol == "Ori")
}

@Test func nextLunarEclipseExists() {
    let e = Ephemeris.nextLunarEclipse(after: utc(2026, 9, 23, 0, 0))
    #expect(e != nil)
    #expect(e!.peak > utc(2026, 9, 23, 0, 0))
}

@Test func nauticalTwilightExistsAtTheTestSiteInJuneWhenAstronomicalDoesNot() throws {
    let testSite = Site(name: "Test site", latitude: 54.0, longitude: -1.5, elevationM: 100, timeZoneID: "Europe/London", bortle: 5)
    let n = try Ephemeris.night(localDate: utc(2026, 6, 20, 12, 0), site: testSite)
    #expect(!n.hasDarkness)
    #expect(n.hasNauticalDarkness)
    let ns = try #require(n.nauticalStart), ne = try #require(n.nauticalEnd)
    #expect(ns > n.sunset && ne < n.sunrise && ne > ns)
    #expect(ne.timeIntervalSince(ns) > 3600 && ne.timeIntervalSince(ns) < 2 * 3600)   // Sun bottoms out near -12.7 deg at the solstice: about 1.6 h
}

@Test func nauticalTwilightBracketsAstronomicalInSeptember() throws {
    let testSite = Site(name: "Test site", latitude: 54.0, longitude: -1.5, elevationM: 100, timeZoneID: "Europe/London", bortle: 5)
    let n = try Ephemeris.night(localDate: utc(2026, 9, 24, 12, 0), site: testSite)
    let ns = try #require(n.nauticalStart), ne = try #require(n.nauticalEnd)
    let ds = try #require(n.darkStart), de = try #require(n.darkEnd)
    #expect(ns < ds && ne > de)
}

@Test func noNauticalTwilightInPolarDay() throws {
    let tromso = Site(name: "Tromsø", latitude: 69.65, longitude: 18.96, elevationM: 10, timeZoneID: "Europe/Oslo", bortle: 4)
    let n = try Ephemeris.night(localDate: utc(2026, 6, 20, 12, 0), site: tromso)
    #expect(!n.hasNauticalDarkness)
}

/// Tonight switches to the coming night when darkness ends (owner's UAT, 30 September 2026), not at sunrise or 09:00.
@Test func theCurrentNightSwitchesWhenDarknessEnds() throws {
    let lastNight = try Ephemeris.night(localDate: utc(2026, 9, 26, 12, 0), site: sheffield)
    #expect(lastNight.key == "2026-09-26")
    func key(_ d: Date) throws -> String { try Ephemeris.currentNight(now: d, site: sheffield).key }
    #expect(try key(utc(2026, 9, 26, 21, 0)) == "2026-09-26")                              // evening: the night ahead
    #expect(try key(utc(2026, 9, 27, 1, 0)) == "2026-09-26")                               // small hours: still that night
    let darkEnd = try #require(lastNight.darkEnd)
    #expect(darkEnd < lastNight.sunrise)
    #expect(Ephemeris.nightEnds(lastNight) == darkEnd)
    #expect(try key(darkEnd.addingTimeInterval(-60)) == "2026-09-26")                     // a minute before darkness ends
    #expect(try key(darkEnd.addingTimeInterval(60)) == "2026-09-27")                      // a minute after: the coming night
    #expect(try key(lastNight.sunrise.addingTimeInterval(-60)) == "2026-09-27")           // before sunrise, already the next
    #expect(try key(utc(2026, 9, 27, 6, 37)) == "2026-09-27")                              // 07:37 BST, the recording's time
    #expect(try key(utc(2026, 9, 27, 12, 0)) == "2026-09-27")
    #expect(try key(utc(2026, 9, 27, 22, 30)) == "2026-09-27")                             // 23:30 BST, before midnight
}

// The next moonless run (#62). The full Moon of 26 September 2026 puts the new Moon on or about 11 October.
@Test func theNextMoonlessRunSurroundsTheNewMoon() throws {
    let tonight = try Ephemeris.night(localDate: utc(2026, 9, 29, 12, 0), site: sheffield)
    #expect(!MoonCalendar.isMoonless(tonight, site: sheffield))                 // 88% lit and up all night
    let r = try #require(MoonCalendar.nextRun(from: tonight, site: sheffield))
    #expect(!r.includesTonight)
    let newMoon = try #require(r.newMoon)
    #expect(Copy.dayMonth(newMoon, site: sheffield).hasSuffix(" Oct"))
    #expect(r.first.localDate <= newMoon && newMoon <= r.last.localDate.addingTimeInterval(86_400))
    #expect(r.last.localDate.timeIntervalSince(r.first.localDate) >= 3 * 86_400)
    let text = Copy.moonlessRun(r, site: sheffield)
    #expect(text.hasPrefix("Next moonless run: ") && text.contains(" – ") && text.contains(" · new Moon "))
    // From a night inside the run it reads from tonight.
    let inside = try #require(MoonCalendar.nextRun(from: r.first, site: sheffield))
    #expect(inside.includesTonight && Copy.moonlessRun(inside, site: sheffield) == "Moonless tonight, and until \(Copy.dayMonth(r.last.localDate, site: sheffield)).")
    // A British midsummer has no astronomical darkness, so no night then is moonless.
    let june = try Ephemeris.night(localDate: utc(2026, 6, 21, 12, 0), site: sheffield)
    #expect(!MoonCalendar.isMoonless(june, site: sheffield))
}
