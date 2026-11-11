import Testing
import Foundation
@testable import SkyCore

/// Which way to look at a target's best moment (owner, 24 October 2026).
@Test func fromEightyDegreesUpTheWayIsOverhead() {
    #expect(Copy.way(altDeg: 88, azDeg: 10) == "overhead")
    #expect(Copy.way(altDeg: 80, azDeg: 200) == "overhead")
    #expect(Copy.way(altDeg: 79.4, azDeg: 200) == "in the S")
}

@Test func eachDirectionIsOneOfTheHorizonDialsEightPoints() {
    #expect(Copy.way(altDeg: 40, azDeg: 0) == "in the N")
    #expect(Copy.way(altDeg: 40, azDeg: 44) == "in the NE")
    #expect(Copy.way(altDeg: 40, azDeg: 91) == "in the E")
    #expect(Copy.way(altDeg: 40, azDeg: 135) == "in the SE")
    #expect(Copy.way(altDeg: 40, azDeg: 225) == "in the SW")
    #expect(Copy.way(altDeg: 40, azDeg: 270) == "in the W")
    #expect(Copy.way(altDeg: 40, azDeg: 315) == "in the NW")
}

@Test func justWestOfNorthStillReadsNorth() {
    #expect(Copy.way(altDeg: 40, azDeg: 350) == "in the N")      // 350 / 45 rounds to 8, which wraps to the first point
    #expect(Copy.way(altDeg: 40, azDeg: -10) == "in the N")      // a negative bearing is the same sky
}

@Test func aTargetOnTheMeridianSouthOfTheZenithIsInTheSouth() {
    let site = Site(name: "x", latitude: 54, longitude: 0, elevationM: 0, timeZoneID: "UTC", bortle: 4)
    let when = utc(2026, 11, 20, 0, 0)
    // Look for a right ascension that is due south at that moment, then check the helper agrees with the geometry.
    var found = false
    for step in 0..<96 {
        let ra = Double(step) * 0.25
        let p = Ephemeris.altAz(raHours: ra, decDeg: 20, at: when, site: site)
        if abs(p.az - 180) < 8, p.alt < 79 {
            let t = RankedTarget(id: "x", name: "x", subtitle: "", group: .nebulae, raHours: ra, decDeg: 20, sizeArcmin: 10, magnitude: 8, fit: .fits,
                                 peakAltDeg: p.alt, peakTime: when, moonSepDeg: 90, moonWashed: false, visibleFraction: 1)
            #expect(Copy.peakWay(t, site: site) == "in the S")
            #expect(Copy.peakHeight(t, site: site) == "\(Int(p.alt.rounded()))° in the S")
            found = true
        }
    }
    #expect(found)
}

@Test func aWidgetRowKeepsTheHeightAndAPointOfTheCompassShort() {
    #expect(Copy.compassPoint(azDeg: 100) == "E")
    #expect(Copy.compassPoint(azDeg: 350) == "N")
    let site = Site(name: "x", latitude: 54, longitude: 0, elevationM: 0, timeZoneID: "UTC", bortle: 4)
    let when = utc(2026, 11, 20, 0, 0)
    for step in 0..<96 {
        let ra = Double(step) * 0.25
        let p = Ephemeris.altAz(raHours: ra, decDeg: 20, at: when, site: site)
        guard abs(p.az - 180) < 8, p.alt < 79 else { continue }
        let t = RankedTarget(id: "x", name: "x", subtitle: "", group: .nebulae, raHours: ra, decDeg: 20, sizeArcmin: 10, magnitude: 8, fit: .fits,
                             peakAltDeg: p.alt, peakTime: when, moonSepDeg: 90, moonWashed: false, visibleFraction: 1)
        #expect(Copy.peakHeightShort(t, site: site) == "\(Int(p.alt.rounded()))° S")
        var overhead = t; overhead.peakAltDeg = 88
        #expect(Copy.peakHeightShort(overhead, site: site) == "88° up")
        return
    }
    Issue.record("found no target due south to test with")
}
