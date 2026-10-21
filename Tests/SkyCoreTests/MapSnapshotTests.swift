import Testing
@testable import SkyCore

@Test func aPaleGridIsABlankMapAndADarkMapIsNot() {
    #expect(MapSnapshot.isBlank(brightness: Array(repeating: 0.91, count: 384)))            // the cream placeholder, measured at 0.91 mean
    #expect(!MapSnapshot.isBlank(brightness: Array(repeating: 0.32, count: 384)))           // dark teal land, measured at 0.31 to 0.35
    #expect(!MapSnapshot.isBlank(brightness: Array(repeating: 0.2, count: 300) + Array(repeating: 0.95, count: 84)))   // a dark map with pale labels
    #expect(!MapSnapshot.isBlank(brightness: []))                                          // nothing to judge is not blank
}
