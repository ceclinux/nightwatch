import SwiftUI
import SkyCore

/// Two sizes of home-screen widget, drawn from a snapshot. Static: no animation, nothing fetched.
public struct NightwatchWidgetView: View {
    public enum Size { case small, medium, large }
    let snapshot: WidgetSnapshot?
    let size: Size
    let red: Bool
    let now: Date

    public init(snapshot: WidgetSnapshot?, size: Size, red: Bool, now: Date = .now) {
        self.snapshot = snapshot; self.size = size; self.red = red; self.now = now
    }

    private var text: Color { red ? Color(red: 1, green: 0.16, blue: 0.1) : .white }
    private var dim: Color { red ? Color(red: 0.7, green: 0.1, blue: 0.06) : Color(white: 0.62) }
    /// What is lit: warm white, as in the app (red in red mode).
    private var accent: Color { red ? Color(red: 1, green: 0.16, blue: 0.1) : Color(red: 0.957, green: 0.945, blue: 0.918) }
    /// The widget's plain card: the Mac widget's colour (0x1C1F27), so a widget looks the same on every device. Black in red mode.
    public static func background(red: Bool) -> Color { red ? .black : Color(red: 28 / 255, green: 31 / 255, blue: 39 / 255) }

    /// Plain hyphens only, never an en or em dash, whatever wording SkyCore supplies.
    private func plain(_ t: String) -> String { t.replacingOccurrences(of: "\u{2013}", with: "-").replacingOccurrences(of: "\u{2014}", with: "-") }

    public var body: some View {
        if let s = snapshot {
            switch size {
            case .small: small(s)
            case .medium: medium(s)
            case .large: large(s)
            }
        } else {
            VStack(spacing: 4) {
                Image(systemName: "moon.stars").font(.title2).foregroundStyle(accent)
                Text("Open Nightwatch to read tonight's forecast").font(.caption).multilineTextAlignment(.center).foregroundStyle(dim)
            }
        }
    }

    private func tickColour(_ slot: BezelSlot) -> Color {
        switch slot {
        case .clear: accent
        case .partCloud: red ? Color(red: 0.55, green: 0.08, blue: 0.05) : Color(red: 0.55, green: 0.6, blue: 0.7)
        case .cloudy: red ? Color(red: 0.3, green: 0.04, blue: 0.03) : Color(white: 0.3)
        case .daylight: red ? Color(red: 0.16, green: 0.02, blue: 0.02) : Color(white: 0.17)
        }
    }

    /// The 12-hour bezel the app and the Mac draw: 60 ticks, hours longer, the clear ones lit.
    private func bezel(_ s: WidgetSnapshot, _ d: CGFloat, glow: Bool = true) -> some View {
        ZStack {
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2), r = min(size.width, size.height) / 2
                for i in 0..<min(60, s.slots.count) {
                    let hour = i % 5 == 0, len: CGFloat = hour ? r * 0.17 : r * 0.1
                    let a = Double(i) * .pi / 30 - .pi / 2
                    var p = Path()
                    p.move(to: CGPoint(x: c.x + (r - len) * cos(a), y: c.y + (r - len) * sin(a)))
                    p.addLine(to: CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a)))
                    if glow, s.slots[i] == .clear {
                        ctx.drawLayer { layer in layer.addFilter(.blur(radius: 2.5)); layer.stroke(p, with: .color(accent.opacity(0.7)), style: StrokeStyle(lineWidth: hour ? 3.2 : 2.4, lineCap: .round)) }
                    }
                    ctx.stroke(p, with: .color(tickColour(s.slots[i])), style: StrokeStyle(lineWidth: hour ? 2 : 1.3, lineCap: .round))
                }
            }
            Text("\(s.score)").font(.system(size: d * 0.3, weight: .bold)).monospacedDigit().foregroundStyle(text)
        }
        .frame(width: d, height: d)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(s.bezelLabel)
    }

    private func stale(_ s: WidgetSnapshot) -> String? { s.staleText(now: now) }

    /// Where the forecast came from, as on the Mac's widget: Apple's mark (the link to its legal page, except on the small widget, which is one
    /// tap target), drawn as supplied in either palette; the service's name when Apple Weather did not supply the forecast.
    private func attribution(_ s: WidgetSnapshot, link: Bool) -> some View {
        WeatherMarkView(snapshot: s, link: link).font(.caption2).foregroundStyle(dim).lineLimit(1)
    }

    /// "Aurora amber" in the level's own colour (one hue in red mode), while the status is under an hour old.
    @ViewBuilder private func auroraLine(_ s: WidgetSnapshot) -> some View {
        if let l = s.auroraLine(now: now) {
            HStack(spacing: 5) {
                Circle().fill(red ? accent : Color(hex: l.hex)).frame(width: 7, height: 7)
                Text(l.text).font(.caption.weight(.medium)).foregroundStyle(text).lineLimit(1)
            }
        }
    }

    private func small(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center) {
                bezel(s, 62)
                Spacer(minLength: 0)
            }
            TwoWeight.headline(plain(s.headline), size: 15).foregroundStyle(text).lineLimit(2).minimumScaleFactor(0.7)
            if let w = s.windowShort ?? s.window { Text(plain(s.zoned(w))).font(.caption.weight(.light)).monospacedDigit().foregroundStyle(accent).lineLimit(1).minimumScaleFactor(0.7) }
            if s.auroraLine(now: now) != nil { auroraLine(s) }
            else { Text(plain(stale(s) ?? s.notifyShort ?? s.siteName)).font(.caption2).foregroundStyle(dim).lineLimit(1) }
            attribution(s, link: false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func medium(_ s: WidgetSnapshot) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                bezel(s, 82)
                Text(plain(s.siteName)).font(.caption2).foregroundStyle(dim).lineLimit(1)
            }
            VStack(alignment: .leading, spacing: 4) {
                TwoWeight.headline(plain(s.headline), size: 17).foregroundStyle(text).lineLimit(2).minimumScaleFactor(0.7)
                if let w = s.window { Text(plain(s.zoned(w))).font(.system(size: 15, weight: .thin)).monospacedDigit().foregroundStyle(accent).lineLimit(1).minimumScaleFactor(0.6) }
                if !s.bars.isEmpty { NightArcCanvas(bars: s.bars, lit: accent, faint: text, labels: false, height: 34, lineWidth: 3) }
                auroraLine(s)
                if !s.targets.isEmpty {
                    Text(plain(s.targets.prefix(2).map { "\($0.catalogueID) \($0.best)" }.joined(separator: " · "))).font(.caption).foregroundStyle(text).lineLimit(1).minimumScaleFactor(0.7)
                }
                HStack(spacing: 0) {
                    Text(plain(stale(s) ?? s.updated ?? "")).font(.caption2).foregroundStyle(dim).lineLimit(1)
                    Spacer(minLength: 8)
                    attribution(s, link: true)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    /// The large widget, as tall as the widget allows so nothing is ever clipped: the full layout; then one that keeps the reason but shrinks the
    /// dial, arc and gaps (an iPhone's, now that each target has two lines); then one without the reason, aurora line and tomorrow.
    private func large(_ s: WidgetSnapshot) -> some View {
        ViewThatFits(in: .vertical) {
            largeLayout(s, tier: 0)
            largeLayout(s, tier: 1)
            largeLayout(s, tier: 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func largeLayout(_ s: WidgetSnapshot, tier: Int) -> some View {
        let full = tier == 0, showsReason = tier <= 1
        return VStack(alignment: .leading, spacing: [12, 8, 6][tier]) {
            HStack(alignment: .top, spacing: 14) {
                bezel(s, [82, 72, 60][tier])
                VStack(alignment: .leading, spacing: full ? 4 : 2) {
                    Text("TONIGHT · " + s.siteName.uppercased()).font(.caption2.weight(.semibold)).tracking(1.4).foregroundStyle(dim).lineLimit(1)
                    TwoWeight.headline(plain(s.headline), size: full ? 20 : 17).foregroundStyle(text).lineLimit(1).minimumScaleFactor(0.7)
                    if let w = s.window { Text(plain(s.zoned(w))).font(.system(size: full ? 17 : 15, weight: .thin)).monospacedDigit().foregroundStyle(accent).lineLimit(1).minimumScaleFactor(0.6) }
                    if showsReason, let r = s.reason { Text(plain(r)).font(.caption).foregroundStyle(dim).lineLimit(full ? 3 : 2) }
                    if showsReason, let a = s.agreement {
                        HStack(spacing: 5) {
                            if s.agreementWarns { Circle().fill(dim).frame(width: 5, height: 5) } else { Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)) }
                            Text(plain(a)).lineLimit(2)
                        }.font(.caption).foregroundStyle(dim)
                    }
                }
            }
            if !s.bars.isEmpty { NightArcCanvas(bars: s.bars, lit: accent, faint: text, height: [70, 54, 52][tier], lineWidth: 3.5) }
            // The rule between the night and the targets, as on the Mac's large widget: it balances the card (owner, 27 October 2026).
            Rectangle().fill(Color.white.opacity(0.14)).frame(height: 1)
            if s.targets.isEmpty {
                // As the Mac's: a heading and why there is nothing, so the card is not left with a blank space.
                VStack(alignment: .leading, spacing: 4) {
                    Text("UP TONIGHT").font(.caption2.weight(.semibold)).tracking(1.4).foregroundStyle(dim)
                    Text(plain(s.emptyPicksNote)).font(.caption).foregroundStyle(dim)
                }
            } else {
                VStack(alignment: .leading, spacing: full ? 4 : 2) {
                    Text(s.mode == .bright ? "MOON AND PLANETS" : "BEST TONIGHT").font(.caption2.weight(.semibold)).tracking(1.4).foregroundStyle(dim)
                    ForEach(s.targets, id: \.id) { t in
                        Link(destination: WidgetLink.target(t.id).url) {
                            // As the Mac's rows: the group's icon on a faint tile, the id and type, the time beneath (owner, 27 October 2026).
                            HStack(spacing: 10) {
                                Image(systemName: t.group.symbolName).font(.system(size: full ? 14 : 12)).foregroundStyle(dim)
                                    .frame(width: full ? 28 : 24, height: full ? 28 : 24)
                                    .background(Color.white.opacity(red ? 0.06 : 0.1), in: RoundedRectangle(cornerRadius: 7))
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 1) {
                                    (Text(plain(t.catalogueID)).fontWeight(.heavy).foregroundColor(text) + Text("  " + plain(t.name)).foregroundColor(dim))
                                        .font(.footnote).lineLimit(1).minimumScaleFactor(0.75)
                                    Text(plain(s.rowTime(t))).font(.caption2.weight(.medium)).monospacedDigit().foregroundStyle(accent).lineLimit(1).minimumScaleFactor(0.7)
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(minHeight: [30, 28, 24][tier])
                        }
                    }
                }
            }
            if full {
                Spacer(minLength: 0)
                auroraLine(s)
                if let t = s.tomorrow { Text(plain(t)).font(.caption).foregroundStyle(dim).lineLimit(1) }
            }
            // Updated on the left, Apple's mark on the right, on one centre line, as the Mac's large widget has it.
            HStack(alignment: .center, spacing: 0) {
                Text(plain(stale(s) ?? s.updated ?? "")).font(.caption2).foregroundStyle(dim).lineLimit(1)
                Spacer(minLength: 8)
                attribution(s, link: true)
            }
        }
    }
}

/// Apple's Weather mark where Apple Weather supplied the forecast, else the source's name. The image is the file the app kept in the
/// App Group (a widget cannot fetch it). Never tinted: the mark is drawn as Apple supplies it, in red night mode too.
public struct WeatherMarkView: View {
    let snapshot: WidgetSnapshot
    let link: Bool
    let height: CGFloat

    public init(snapshot: WidgetSnapshot, link: Bool = true, height: CGFloat = 9) {
        self.snapshot = snapshot; self.link = link; self.height = height
    }

    private static func image(_ data: Data) -> Image? {
        #if canImport(UIKit)
        UIImage(data: data).map(Image.init(uiImage:))
        #else
        NSImage(data: data).map(Image.init(nsImage:))
        #endif
    }

    public var body: some View {
        if snapshot.weatherMarkFile != nil, let data = WidgetShare.loadMark(), let image = Self.image(data) {
            let mark = image.resizable().scaledToFit().frame(height: height)
            if link, let legal = snapshot.weatherLegalURL.flatMap(URL.init(string:)) {
                Link(destination: legal) { mark }.accessibilityLabel("Apple Weather, legal attribution and data sources")
            } else {
                mark.accessibilityLabel("Apple Weather")
            }
        } else if let source = snapshot.source {
            Text(source)
        }
    }
}

private extension Color {
    init(hex: UInt32) { self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255) }
}
