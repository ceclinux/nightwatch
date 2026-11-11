import Foundation

/// The pieces of the Tonight hero, cut from wording that already exists: the snapshot's window ("20:11-05:38 · 9.4 h") and the
/// tiles. Nothing here is new wording beyond joining and lower-casing, so it stays the Mac's wording.
public struct TonightHero: Equatable, Sendable {
    /// "20:11-05:38".
    public var times: String?
    /// "9.4 hours".
    public var hours: String?
    /// "medium dew risk", "high dew risk, dew heater advised", or "frost likely" when the night drops to 0 degrees. Nil when there is no dew figure.
    public var dewLine: String?
    /// The Mac's "Held back by ..." line, left out when the dew line already says the same thing.
    public var reason: String?
    /// High dew risk or frost: drawn with a "!" and bold, so the warning never rests on colour alone.
    public var dewWarns: Bool
    /// "Moon down tonight", or "Moon 35% · Sets 20:36": the Moon note under the clear-hours line.
    public var moonNote: String
    /// What the tiles said, as label and value pairs drawn small-over-bold: Dark (only when it differs from the window), Seeing, Wind, Transparency.
    public var facts: [Fact]

    public struct Fact: Equatable, Sendable {
        public var label: String
        public var value: String
    }

    /// The facts as one sentence, for VoiceOver and tests: "Seeing 0.5-0.75" · Wind 10 km/h · Transparency Good".
    public var conditions: String { facts.map { "\($0.label) \($0.value)" }.joined(separator: " · ") }

    public static func make(window: String?, tiles: TonightTiles, reason: String? = nil) -> TonightHero {
        var times: String?, hours: String?
        if let window {
            let parts = window.components(separatedBy: " · ")
            times = parts.first
            hours = parts.dropFirst().first.map { $0.hasSuffix(" h") ? String($0.dropLast(2)) + " hours" : $0 }
        }
        let frost = tiles.dewLabel == "Frost likely"
        let dewLine = frost ? "frost likely" : tiles.dew.map { "\($0.lowercased()) dew risk" + (tiles.dewHint.map { ", " + $0.lowercased() } ?? "") }
        // "Dark" is left out when it is the same span as the clear window already shown above.
        let facts: [Fact] = [tiles.dark == "None" || tiles.dark == times ? nil : Fact(label: "Dark", value: tiles.dark),
                             tiles.seeing.map { Fact(label: "Seeing", value: $0) },
                             tiles.wind.map { Fact(label: "Wind", value: $0) },
                             tiles.transparency.map { Fact(label: "Transparency", value: $0) }].compactMap { $0 }
        let moonNote = tiles.moon == "Down" ? "Moon down tonight" : "Moon \(tiles.moon)" + (tiles.moonLine.map { " · \($0)" } ?? "")
        let shownReason = reason.flatMap { dewLine != nil && $0.lowercased().contains("dew risk") ? nil : $0 }
        return TonightHero(times: times, hours: hours, dewLine: dewLine, reason: shownReason, dewWarns: frost || tiles.dew == "High", moonNote: moonNote, facts: facts)
    }
}

extension TonightModel {
    public var hero: TonightHero { TonightHero.make(window: snapshot.window, tiles: tiles, reason: snapshot.reason) }
}
