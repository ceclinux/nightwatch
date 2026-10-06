import WidgetKit
import SwiftUI
import SkyCore
import NightwatchUI

// Nightwatch's desktop widget (v0.6). It never fetches: it draws the snapshot the app writes after each patrol, so it can
// never disagree with the popover. Layouts follow the owner-approved canvas (small, medium, large).

struct NightEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

enum SnapshotFile {
    static var dir: URL? {
        (Bundle.main.object(forInfoDictionaryKey: "NightwatchAppGroup") as? String)
            .flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
    }
    static func load() -> WidgetSnapshot? {
        guard let dir, let data = try? Data(contentsOf: dir.appendingPathComponent("widget.json")) else { return nil }
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return try? d.decode(WidgetSnapshot.self, from: data)
    }
}

/// macOS goes on running the copy of the widget it first started, even after Nightwatch has been replaced by a newer
/// version in Applications, and then refuses everything that old copy draws ("Bundle version did not match"): the widget
/// keeps its last picture, or shows grey bars if it was added after the update (owner, 6 October 2026). Measured that
/// day: ending the old process is all it takes, macOS starts the new copy at once, and the app's sandbox is not allowed
/// to end it (kill returns EPERM). So the widget ends itself when the copy on disk is no longer the one running.
enum ReplacedCopy {
    static func leaveIfReplaced() {
        let onDisk = NSDictionary(contentsOf: Bundle.main.bundleURL.appendingPathComponent("Contents/Info.plist"))?["CFBundleVersion"] as? String
        let running = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String   // read once, at launch
        if let onDisk, let running, onDisk != running { exit(0) }
    }
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> NightEntry { NightEntry(date: .now, snapshot: .sample) }
    /// The gallery shows the sample until the app has written a snapshot.
    func getSnapshot(in context: Context, completion: @escaping (NightEntry) -> Void) {
        ReplacedCopy.leaveIfReplaced()
        completion(NightEntry(date: .now, snapshot: SnapshotFile.load() ?? (context.isPreview ? .sample : nil)))
    }
    /// The app reloads the widget after every patrol; the 30-minute refresh is only a fallback. A second entry just past the
    /// six-hour mark shows "Forecast N h old" on time rather than at the next refresh.
    func getTimeline(in context: Context, completion: @escaping (Timeline<NightEntry>) -> Void) {
        ReplacedCopy.leaveIfReplaced()
        let s = SnapshotFile.load()
        var entries = [NightEntry(date: .now, snapshot: s)]
        if let s, case let staleAt = s.fetchedAt.addingTimeInterval(6 * 3600 + 60), staleAt > .now {
            entries.append(NightEntry(date: staleAt, snapshot: s))
        }
        // And when the aurora line stops being current, so it goes on time (the app rewrites it while it is still news).
        if let end = s?.auroraExpires, end > .now { entries.append(NightEntry(date: end.addingTimeInterval(1), snapshot: s)) }
        entries.sort { $0.date < $1.date }
        completion(Timeline(entries: entries, policy: .after(.now.addingTimeInterval(1800))))
    }
}

/// A grey line with a tick, or a warning-colour one with a dot: the reason and agreement lines, as in the popover.
struct NoteLine: View {
    let text: String
    let warns: Bool
    var tick = false
    var lines = 2
    var body: some View {
        HStack(spacing: 5) {
            if warns { WarningDot(size: 4.5) }
            else if tick { Image(systemName: "checkmark").font(.system(size: 7, weight: .bold)).accessibilityHidden(true) }
            Text(text).lineLimit(lines)
        }
        .font(.system(size: 10)).foregroundStyle(Tokens.textSecondary)
    }
}

/// `compact` (the medium size): the headline on one line, shrinking to fit, and no Tomorrow line when a reason is shown,
/// so the reason and the Open-Meteo line are never cut off (owner's desktop, 25 September 2026). With a window line as
/// well, each note keeps to one line. `showStale` false: the large widget shows staleness in its footer instead.
struct Headline: View {
    let s: WidgetSnapshot
    let now: Date
    var compact = false
    var showStale = true
    private var noteLines: Int { compact && s.window != nil ? 1 : 2 }
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Aurora (v0.6.6) at the end of the header line, where it costs no height.
            HStack(spacing: 6) {
                Text("TONIGHT · \(s.siteName.uppercased())").font(.system(size: 10)).foregroundStyle(Tokens.textSecondary).lineLimit(1)
                if let a = s.auroraLine(now: now) {
                    Spacer(minLength: 0)
                    AuroraMark(text: a.text.uppercased(), hex: a.hex, size: 9.5)
                }
            }
            Text(s.headline).font(.system(size: 15, weight: .medium)).foregroundStyle(Tokens.textPrimary)
                .lineLimit(compact ? 1 : 2).minimumScaleFactor(compact ? 0.7 : 0.8)
            if let w = s.window { Text(w).font(.system(size: 13)).foregroundStyle(Tokens.textPrimary) }
            // No dot on the reason line, as in the popover (owner, 28 September 2026).
            if let r = s.reason { NoteLine(text: r, warns: false, lines: noteLines).fixedSize(horizontal: false, vertical: true) }
            // A disagreement is the popover's plain line; agreement keeps its tick (owner, 28 September 2026).
            if let a = s.agreement { NoteLine(text: a, warns: false, tick: !s.agreementWarns, lines: noteLines).fixedSize(horizontal: false, vertical: true) }
            if let t = s.tomorrow, !(compact && s.reason != nil) { NoteLine(text: t, warns: false) }
            if showStale, let stale = s.staleText(now: now) { NoteLine(text: stale, warns: true) }
        }
    }
}

/// Where the forecast came from, as its terms ask (v1.0.1): Apple's Weather mark, which is itself the link to Apple's legal page
/// where the widget can hold a link (medium and large; a small widget is one click target, which opens Nightwatch,
/// whose popover carries the link). Owner-approved mockup, 27 September 2026. Open-Meteo builds name Open-Meteo.
struct WeatherAttribution: View {
    let s: WidgetSnapshot
    var link = true
    var body: some View {
        WeatherMark(s: s, link: link)
        .font(.system(size: 9.5)).foregroundStyle(Tokens.textSecondary).lineLimit(1)
    }
}

/// Apple's Weather mark, or the source's name when Apple Weather did not supply the forecast (Open-Meteo builds). With `link`
/// the mark itself is the link to Apple's legal page (owner's decision, 27 September 2026: a separate "Sources" label read as
/// a link to Open-Meteo and the rest, and crowded the footer).
struct WeatherMark: View {
    let s: WidgetSnapshot
    var link = false
    static func image(_ s: WidgetSnapshot) -> NSImage? {
        s.weatherMarkFile.flatMap { f in SnapshotFile.dir.flatMap { NSImage(contentsOf: $0.appendingPathComponent(f)) } }
    }
    static func legal(_ s: WidgetSnapshot) -> URL? { s.weatherLegalURL.flatMap(URL.init(string:)) }
    var body: some View {
        if let m = Self.image(s) {
            let mark = Image(nsImage: m).resizable().scaledToFit().frame(height: 9)
            if link, let l = Self.legal(s) {
                Link(destination: l) { mark }.accessibilityLabel("Apple Weather, legal attribution and data sources")
            } else {
                mark.accessibilityLabel("Apple Weather")
            }
        } else if let src = s.source { Text(src) }
    }
}


/// "● Aurora amber" in AuroraWatch UK's own colour for the level (owner ruling, v0.6.1).
struct AuroraMark: View {
    let text: String
    let hex: UInt32
    let size: CGFloat
    var body: some View {
        HStack(spacing: 3) { Circle().fill(Color(hex: hex)).frame(width: 5, height: 5); Text(text) }
            .font(.system(size: size, weight: .semibold)).foregroundStyle(Color(hex: hex)).fixedSize()
    }
}

struct SmallView: View {
    let s: WidgetSnapshot
    let now: Date
    var body: some View {
        VStack(spacing: 6) {
            ScoreBezel(score: s.score, slots: s.slots, label: s.bezelLabel)
            // The small size has room for one short line: the first sentence of the headline ("Nothing to see here").
            Text(s.windowShort ?? (s.headline.components(separatedBy: ". ").first ?? s.headline).trimmingCharacters(in: CharacterSet(charactersIn: ".")))
                .font(.system(size: 12.5, weight: .medium)).foregroundStyle(Tokens.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7).multilineTextAlignment(.center)
            if let a = s.auroraLine(now: now) {
                AuroraMark(text: a.text, hex: a.hex, size: 10)
            } else if let stale = s.staleText(now: now) {
                NoteLine(text: stale, warns: true)
            } else {
                Text(s.windowShort == nil ? (s.tomorrow ?? s.siteName)
                     : s.brightList ?? [s.siteName, s.notifyShort].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 10)).foregroundStyle(Tokens.textSecondary).lineLimit(1)
            }
            WeatherAttribution(s: s, link: false)
        }
    }
}

struct MediumView: View {
    let s: WidgetSnapshot
    let now: Date
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 14) {
                ScoreBezel(score: s.score, slots: s.slots, label: s.bezelLabel)
                Headline(s: s, now: now, compact: true)
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            ClearSkyBars(bars: s.bars, label: s.barsLabel, trackHeight: 14, labels: false)
            HStack { Spacer(minLength: 0); WeatherAttribution(s: s) }
        }
    }
}

struct LargeView: View {
    let s: WidgetSnapshot
    let now: Date
    /// In macOS's see-through style (another app in front, or Monochrome) only lightness survives: the dark tile drew as a
    /// solid white square hiding its symbol, so it becomes a faint tint there (0.7.0).
    @Environment(\.widgetRenderingMode) private var renderingMode
    var body: some View {
        // Measured at the real 344 × 344 pt size, content about 312 pt: 9 pt gaps, 28 pt bars and 34 pt icons ran to 348 pt on
        // a clear night with three targets and cut off the footer (25 September 2026).
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 14) {
                ScoreBezel(score: s.score, slots: s.slots, label: s.bezelLabel)
                Headline(s: s, now: now, showStale: false)
                Spacer(minLength: 0)
            }
            ClearSkyBars(bars: s.bars, label: s.barsLabel, trackHeight: 20, labels: true, caption: false)
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            Text(s.targets.isEmpty ? "UP TONIGHT" : "BEST TONIGHT").font(.system(size: 10)).foregroundStyle(Tokens.textSecondary)
            if s.targets.isEmpty {
                Text(s.windowShort == nil ? "No clear window, so nothing is recommended."
                     : s.mode == .bright ? "No Moon or planet well placed in the window." : "Nothing well placed in the window.")
                    .font(.system(size: 10)).foregroundStyle(Tokens.textSecondary)
            }
            VStack(alignment: .leading, spacing: 5) { ForEach(s.targets, id: \.id) { t in
                Link(destination: WidgetLink.target(t.id).url) {
                    HStack(spacing: 10) {
                        Image(systemName: t.group.symbolName).font(.system(size: 14)).foregroundStyle(Tokens.textSecondary)
                            .frame(width: 26, height: 26)
                            .background(renderingMode == .fullColor ? Color(hex: 0x0E1018) : Color.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                        VStack(alignment: .leading, spacing: 1) {
                            (Text(t.catalogueID).fontWeight(.bold) + Text("  " + t.name).foregroundColor(Tokens.textSecondary))
                                .font(.system(size: 11)).foregroundStyle(Tokens.textPrimary).lineLimit(1)
                            Text(t.best).font(.system(size: 9.5, weight: .medium)).foregroundStyle(Tokens.bestLine)
                        }
                    }
                }
            } }
            Spacer(minLength: 0)
            // Updated on the left, Apple's mark on the right, on one centre line. No "Notify when clear": it did not earn its
            // place against a quieter footer (owner, 27 September 2026).
            HStack(alignment: .center, spacing: 0) {
                if let stale = s.staleText(now: now) { NoteLine(text: stale, warns: true, lines: 1) } else {
                    Text(s.updated ?? "Updated \(s.fetchedAt.formatted(date: .omitted, time: .shortened))")
                }
                Spacer(minLength: 8)
                WeatherMark(s: s, link: true)
            }
            .font(.system(size: 9.5)).foregroundStyle(Tokens.textSecondary).lineLimit(1)
        }
    }
}

struct NightwatchWidgetView: View {
    let entry: NightEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetContentMargins) private var margins
    /// The system's content margins, made symmetric left to right for the centred layouts (Apple's documented pattern with
    /// contentMarginsDisabled). On the owner's desktop the small widget sat a few points left of centre (25 September 2026)
    /// although the view measures centred offscreen; this did not cure it, so the cause is still open.
    private var padding: EdgeInsets {
        guard entry.snapshot == nil || family == .systemSmall else { return margins }
        let side = max(margins.leading, margins.trailing)
        return EdgeInsets(top: margins.top, leading: side, bottom: margins.bottom, trailing: side)
    }
    var body: some View {
        Group {
            if let s = entry.snapshot {
                switch family {
                case .systemSmall: SmallView(s: s, now: entry.date)
                case .systemLarge: LargeView(s: s, now: entry.date)
                default: MediumView(s: s, now: entry.date)
                }
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "star").font(.title2).foregroundStyle(Tokens.textSecondary)
                    Text("Open Nightwatch to load tonight's sky").font(.system(size: 11)).foregroundStyle(Tokens.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        // The small widget and the empty state are centred, as on the canvas; medium and large read from the top left.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: entry.snapshot == nil || family == .systemSmall ? .center : .topLeading)
        .padding(padding)
        .containerBackground(for: .widget) { Tokens.targetsCard }
        .widgetURL(WidgetLink.targets.url)
    }
}

@main
struct NightwatchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Nightwatch", provider: Provider()) { NightwatchWidgetView(entry: $0) }
            .configurationDisplayName("Nightwatch")
            .description("Tonight's sky at a glance")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
            .contentMarginsDisabled()   // the view applies the system's margins itself, symmetric where it is centred
    }
}
