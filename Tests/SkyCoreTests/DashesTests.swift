import Testing
@testable import SkyCore

@Test func plainDashesTurnsEnAndEmDashesIntoHyphens() {
    #expect("21:07\u{2013}06:43 \u{00B7} 9.6 h".plainDashes == "21:07-06:43 \u{00B7} 9.6 h")
    #expect("Moon \u{2014} up all night".plainDashes == "Moon - up all night")
    #expect("0.5-0.75\"".plainDashes == "0.5-0.75\"")   // a hyphen is left alone
}
