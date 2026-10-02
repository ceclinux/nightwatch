import Testing
import Foundation
@testable import SkyCore

private let malham = Site(name: "Malham", latitude: 54.06, longitude: -2.154, elevationM: 200, timeZoneID: "Europe/London", bortle: 2)

@Test func thePleiadesGoBehindTheMoonFromMalhamOn28October() throws {
    let found = Occultations.find(from: utc(2026, 10, 2, 0, 0), days: 100, site: malham, stars: try BrightStars.bundled())
    let oct = try #require(found.first { $0.id == "pleiades" })
    #expect(oct.object == "the Pleiades")
    // Worked out on 2 October 2026 from Malham; published predictions name Taygeta and Maia for 27–28 October,
    // within the event's global window of 22:07–03:29 UT.
    let taygeta = try #require(oct.contacts.first { $0.name == "Taygeta" })
    let maia = try #require(oct.contacts.first { $0.name == "Maia" })
    #expect(abs(taygeta.disappears.timeIntervalSince(utc(2026, 10, 28, 0, 24))) < 90)
    #expect(abs(maia.disappears.timeIntervalSince(utc(2026, 10, 28, 0, 43))) < 90)
    #expect(taygeta.reappears > taygeta.disappears && taygeta.altDeg > 50)
    #expect(oct.moonIllumination > 0.9)
    #expect(oct.start >= utc(2026, 10, 27, 22, 7) && oct.end <= utc(2026, 10, 28, 3, 29))
    #expect(found.contains { $0.id == "pleiades" && Calendar(identifier: .gregorian).component(.month, from: $0.start) == 12 })   // 21 December
    #expect(!found.contains { $0.id == "planet-saturn" })   // none from here in this span
}

@Test func onlyStarsNearTheEclipticAreSearched() throws {
    let b = Occultations.bodies(stars: try BrightStars.bundled())
    #expect(b.contains { $0.name == "Regulus" } && b.contains { $0.name == "Spica" } && b.contains { $0.name == "Aldebaran" })
    #expect(!b.contains { $0.name == "Capella" } && !b.contains { $0.name == "Vega" })
    #expect(b.filter { $0.group == "pleiades" }.count == 6 && b.contains { $0.planet == .saturn })
}

@Test func anOccultationBecomesAnEventWithEachStarsTimesAndEdges() throws {
    let found = Occultations.find(from: utc(2026, 10, 27, 12, 0), days: 2, site: malham, stars: try BrightStars.bundled())
    let o = try #require(found.first { $0.id == "pleiades" })
    let e = Events.occultation(o, site: malham)
    #expect(e.kind == .occultation && e.title == "The Moon covers the Pleiades")
    #expect(e.detail.hasPrefix("Taygeta and Maia go behind the Moon") || e.detail.hasPrefix("Maia and Taygeta go behind the Moon"))
    #expect(e.time == o.start && e.endTime == o.end && e.occultation == o)
    #expect(e.facts.first?.value.contains("gone 00:2") == true && e.facts.contains { $0.label == "Moon" })
    #expect(EyeViews.includes(e))
    #expect(ShootingTips.tip(for: e, fov: FieldOfView(widthDeg: 2.1, heightDeg: 1.2), presetName: nil, site: malham).title == "How to see this")
    // Each star's drawn path crosses behind the disc.
    let tracks = Occultations.tracks(o, site: malham, stars: try BrightStars.bundled())
    #expect(tracks.count == o.contacts.count)
    #expect(tracks.allSatisfy { $0.points.contains { ($0.x * $0.x + $0.y * $0.y).squareRoot() < 1 } && ($0.points.first.map { ($0.x * $0.x + $0.y * $0.y).squareRoot() > 1 } ?? false) })
}

/// 28 October 2026 is two days after full, so the Moon is waning and its sunlit edge faces east, the edge it is moving
/// towards: the stars go behind at the lit edge, as the facts say, and the drawing shades the west side.
@Test func theSunlitEdgeFacesEastAfterFullMoon() throws {
    let found = Occultations.find(from: utc(2026, 10, 27, 12, 0), days: 1, site: malham, stars: [])
    let o = try #require(found.first { $0.id == "pleiades" })
    let limb = Occultations.brightLimbDeg(o, site: malham)
    #expect(limb > 45 && limb < 135)
    let allLit = o.contacts.allSatisfy { $0.disappearsAtLitEdge }
    #expect(allLit)
}
