import Testing
import Foundation
@testable import SkyCore

// iss.tle epoch (line 1, columns 19-32): day 266.43236339 of 2026

private let site = Site(name: "Sheffield", latitude: 53.38, longitude: -1.47, elevationM: 100, timeZoneID: "Europe/London", bortle: 5)

private func issTLE() throws -> TLE {
    try Satellites.parseTLE(String(decoding: try fixture("iss.tle"), as: UTF8.self))
}

private func epochDate(_ tle: TLE) -> Date {
    // columns 19-32 of line 1: YYDDD.DDDDDDDD
    let s = tle.line1
    let yy = Int(s[s.index(s.startIndex, offsetBy: 18)..<s.index(s.startIndex, offsetBy: 20)])!
    let doy = Double(s[s.index(s.startIndex, offsetBy: 20)..<s.index(s.startIndex, offsetBy: 32)].trimmingCharacters(in: .whitespaces))!
    var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
    let jan1 = cal.date(from: DateComponents(year: 2000 + yy, month: 1, day: 1))!
    return jan1.addingTimeInterval((doy - 1) * 86_400)
}

@Test func parsesThreeLineTLE() throws {
    let t = try issTLE()
    #expect(t.line0.hasPrefix("ISS"))
    #expect(t.line1.hasPrefix("1 25544"))
    #expect(t.line2.hasPrefix("2 25544"))
}

@Test func rejectsMalformedTLE() {
    #expect(throws: (any Error).self) { try Satellites.parseTLE("nonsense") }
}

@Test func passesAreWellFormedAndOrdered() throws {
    let tle = try issTLE()
    let from = epochDate(tle)
    let to = from.addingTimeInterval(3 * 86_400)
    let passes = try Satellites.passes(tle: tle, site: site, from: from, to: to, minPeakElevation: 0, stepSeconds: 30)
    #expect(passes.count >= 3)                       // ISS crosses a 53° site several times in three days
    for p in passes {
        #expect(p.rise < p.peak && p.peak < p.set)
        #expect(p.set.timeIntervalSince(p.rise) < 15 * 60)
        #expect(p.maxElevationDeg >= 0 && p.maxElevationDeg <= 90)
        #expect(p.peakAzimuthDeg >= 0 && p.peakAzimuthDeg < 360)
        #expect((p.riseAzimuthDeg ?? -1) >= 0 && (p.riseAzimuthDeg ?? 360) < 360)   // where to look (v1.0.1)
        #expect((p.setAzimuthDeg ?? -1) >= 0 && (p.setAzimuthDeg ?? 360) < 360)
    }
    #expect(passes == passes.sorted { $0.rise < $1.rise })
}

@Test func higherThresholdReturnsSubset() throws {
    let tle = try issTLE()
    let from = epochDate(tle), to = from.addingTimeInterval(3 * 86_400)
    let all = try Satellites.passes(tle: tle, site: site, from: from, to: to, minPeakElevation: 0, stepSeconds: 30)
    let high = try Satellites.passes(tle: tle, site: site, from: from, to: to, minPeakElevation: 30, stepSeconds: 30)
    #expect(high.count <= all.count)
    #expect(high.allSatisfy { $0.maxElevationDeg >= 30 })
}

@Test func visiblePassesRequireDarkObserverAndSunlitSatellite() throws {
    let tle = try issTLE()
    let from = epochDate(tle), to = from.addingTimeInterval(3 * 86_400)
    let visible = try Satellites.visiblePasses(tle: tle, site: site, from: from, to: to, minPeakElevation: 0)
    let all = try Satellites.passes(tle: tle, site: site, from: from, to: to, minPeakElevation: 0, stepSeconds: 30)
    #expect(visible.count <= all.count)
    for p in visible {
        #expect(Ephemeris.sunAltitude(at: p.peak, site: site) < -6)
        // The sunlit stretch (v1.0.1) lies within the pass and includes the peak, which visiblePasses requires sunlit.
        let a = try #require(p.appears), v = try #require(p.vanishes)
        #expect(p.rise <= a && a <= p.peak.addingTimeInterval(10) && p.peak.addingTimeInterval(-10) <= v && v <= p.set)
        #expect(p.appearsAzimuthDeg != nil && p.vanishesAzimuthDeg != nil)
        #expect((p.appearsElevationDeg ?? -1) > 0 && (p.vanishesElevationDeg ?? -1) > 0)   // for the compass drawing
    }
}
