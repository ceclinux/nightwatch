import Testing
@testable import SkyCore

/// Coordinates typed or pasted into Add a site (location entry check, 30 September 2026).
@Test func coordinatesAcceptWhatMapsCopy() throws {
    #expect(Coordinates.degrees("53.381", latitude: true) == 53.381)
    #expect(Coordinates.degrees("−1.470", latitude: false) == -1.47)
    #expect(Coordinates.degrees("53.381° N", latitude: true) == 53.381)
    #expect(Coordinates.degrees("1.470° W", latitude: false) == -1.47)
    #expect(Coordinates.degrees("33.9 s", latitude: true) == -33.9)
    #expect(Coordinates.degrees("1.47 E", latitude: true) == nil)      // a longitude letter on a latitude
    #expect(Coordinates.degrees("91", latitude: true) == nil)
    #expect(Coordinates.degrees("", latitude: true) == nil)
    let a = try #require(Coordinates.pair("53.381, -1.470"))
    #expect(a.latitude == 53.381 && a.longitude == -1.47)
    let b = try #require(Coordinates.pair("54.0610° N, 2.1520° W"))
    #expect(b.latitude == 54.061 && b.longitude == -2.152)
    #expect(Coordinates.pair("53.381") == nil)
    #expect(Coordinates.pair("53.381, -1.470, 12") == nil)
}
