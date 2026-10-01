import Testing
@testable import SkyCore

@Test func aTargetKeepsItsStyleWhateverElseIsInThePlan() {
    let full = ChartLayout.styles(for: ["ngc7023", "ngc7814", "planet-saturn", "capella"], count: 6)
    let without = ChartLayout.styles(for: ["ngc7023", "planet-saturn", "capella"], count: 6)
    #expect(Set(full.values).count == 4)                                  // no two alike in one plan
    let unclashed = ["ngc7023", "planet-saturn", "capella"].filter { ChartLayout.styles(for: [$0], count: 6)[$0] == full[$0] }
    for id in unclashed { #expect(without[id] == full[id]) }               // taking one off moves no one else
    #expect(ChartLayout.styles(for: ["capella", "ngc7023"], count: 6) == ChartLayout.styles(for: ["ngc7023", "capella"], count: 6))
    #expect(ChartLayout.fnv1a("capella") == ChartLayout.fnv1a("capella"))
    #expect(Set(ChartLayout.styles(for: (0..<8).map { "t\($0)" }, count: 6).values).count == 6)   // more than six: styles repeat
}

@Test func labelsKeepClearOfEachOtherAndOfOtherLines() {
    // Two peaks at the same spot, and a third label whose spot above its peak has another line through it.
    let crossing: [(x: Double, y: Double)] = stride(from: 0.0, through: 400, by: 10).map { ($0, 60) }
    let anchors: [(x: Double, y: Double)] = [(200, 100), (200, 100), (300, 71)]
    let sizes: [(width: Double, height: Double)] = [(60, 12), (60, 12), (60, 12)]
    let flat: [(x: Double, y: Double)] = [(0, 100), (400, 100)]
    let spots = ChartLayout.placeLabels(anchors: anchors, sizes: sizes, lines: [flat, flat, crossing.map { ($0.x, $0.y + 11) }], width: 400, height: 170)
    let l = spots.map { ChartLayout.Label(x: $0.x, y: $0.y, width: 60, height: 12) }
    #expect(!l[0].overlaps(l[1]) && !l[0].overlaps(l[2]) && !l[1].overlaps(l[2]))
    #expect(ChartLayout.crossings(l[2], flat) == 0 && ChartLayout.crossings(l[0], crossing.map { ($0.x, $0.y + 11) }) == 0)
    #expect(spots.allSatisfy { $0.x >= 30 && $0.x <= 370 && $0.y >= 6 && $0.y <= 164 })
}
