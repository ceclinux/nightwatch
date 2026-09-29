import Testing
@testable import SkyCore

@Test func siriCatalogueNumbersBecomeWhatTheSearchExpects() {
    #expect(SpokenSearch.normalise("M3 one") == "M31")            // the owner's test, 29 September 2026
    #expect(SpokenSearch.normalise("M thirty one") == "M31")
    #expect(SpokenSearch.normalise("Messier 31") == "M31")
    #expect(SpokenSearch.normalise("Caldwell twenty seven") == "C27")
    #expect(SpokenSearch.normalise("NGC 7000") == "NGC7000")
    #expect(SpokenSearch.normalise("the m42.") == "the M42")
    #expect(SpokenSearch.normalise("M3") == "M3")
}

@Test func namesAreLeftAlone() {
    #expect(SpokenSearch.normalise("Seven Sisters") == "Seven Sisters")
    #expect(SpokenSearch.normalise("Crescent nebula") == "Crescent nebula")
    #expect(SpokenSearch.normalise("M") == "M")
    #expect(SpokenSearch.normalise("") == "")
}
