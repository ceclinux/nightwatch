import Testing
import Foundation
import SkyCore
@testable import PhoneCore

@Test func plainDashesTurnsEnAndEmDashesIntoHyphens() {
    #expect("20:11\u{2013}05:38".plainDashes == "20:11-05:38")
    #expect("a \u{2014} b".plainDashes == "a - b")
}

@Test func tonightsWordingHasNoEnOrEmDash() throws {
    let p = try plans(cloud: 5)
    let m = TonightModel.make(plan: p.tonight, tomorrow: p.tomorrow, forecast: forecast(fetchedAt: utc(2026, 9, 23, 12)), site: sheffield, config: .default)
    let all = [m.snapshot.headline, m.snapshot.window ?? "", m.snapshot.reason ?? "", m.snapshot.barsLabel, m.snapshot.bezelLabel, m.snapshot.tomorrow ?? "",
               m.tiles.dark, m.tiles.moon, m.tiles.seeing ?? "", m.tiles.wind ?? "", m.tiles.transparency ?? "", m.picksNote ?? ""]
        + m.picks.flatMap { [$0.title, $0.line, $0.best] }
    for s in all { #expect(!s.contains("\u{2013}") && !s.contains("\u{2014}"), "\(s)") }
}

@Test func ourSourceFilesHaveNoEnOrEmDash() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    for dir in ["Sources", "App"] {
        let files = FileManager.default.enumerator(at: root.appendingPathComponent(dir), includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? []
        for f in files where f.pathExtension == "swift" || f.pathExtension == "md" {
            let text = try String(contentsOf: f, encoding: .utf8)
            #expect(!text.contains("\u{2013}") && !text.contains("\u{2014}"), "\(f.lastPathComponent)")
        }
    }
}

@Test func theNumbersGuideReadsWithPlainHyphensOnly() {
    #expect(NumbersGuide.entries.count >= 10)
    for e in NumbersGuide.entries {
        #expect(e.title.isEmpty == false && e.body.isEmpty == false)
        #expect(e.title.plainDashes.contains("\u{2013}") == false && e.body.plainDashes.contains("\u{2013}") == false && e.body.plainDashes.contains("\u{2014}") == false)
    }
}
