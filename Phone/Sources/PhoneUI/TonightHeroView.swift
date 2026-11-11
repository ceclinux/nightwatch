import SwiftUI
import SkyCore
import PhoneCore
import PhoneWidgetUI

/// A constellation's figure and star plot (the owner's art), drawn faint behind the hero on a night with no clear window.
struct FigureArt: View {
    let figure: (Data, Data)
    @Environment(\.phoneTheme) private var theme
    var body: some View {
        if let f = Image(platformData: figure.0), let p = Image(platformData: figure.1) {
            ZStack { f.resizable().scaledToFit(); p.resizable().scaledToFit() }
                .saturation(theme.isRed ? 0 : 1).colorMultiply(theme.isRed ? Color(hex: 0xC0180E) : .white)
                .opacity(0.13).padding(10).accessibilityHidden(true)
        }
    }
}

/// The Tonight verdict on the photograph, with no card: the Mac's dial with the score inside, and beside it
/// the headline, the clear window in large light type, then hours clear and the dew line in warm white.
struct TonightHeroView: View {
    enum Scale { case compact, medium, large }
    let snap: WidgetSnapshot
    let hero: TonightHero
    let scale: Scale
    var figure: (Data, Data)? = nil
    @Environment(\.phoneTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    private var dialSize: CGFloat { typeSize.isAccessibilitySize ? 140 : scale == .large ? 200 : scale == .medium ? 170 : 120 }
    @ScaledMetric(relativeTo: .title) private var headSize: CGFloat = 30

    /// The headline in two weights (see `TwoWeight`).
    private var headline: Text { TwoWeight.headline(snap.headline, size: headSize) }

    private var timesSize: CGFloat { scale == .large ? 38 : scale == .medium ? 34 : 28 }

    /// The Mac's 60-tick, 12-hour dial with the score inside: ticks inside a clear window are lit.
    private var dial: some View {
        ScoreBezelView(score: snap.score, slots: snap.slots, label: snap.bezelLabel, size: dialSize, lit: theme.lit, numeralWeight: .bold)
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: 6) {
            headline.dynamicTypeSize(...DynamicTypeSize.accessibility2).fixedSize(horizontal: false, vertical: true)
            if let t = hero.times {
                Text(snap.windowZone.map { t + " " + $0 } ?? t).font(.system(size: timesSize, weight: .thin)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
            }
            if let line = hoursLine {
                Text(line).font(.callout).foregroundStyle(theme.lit).fixedSize(horizontal: false, vertical: true)
            }
            if hero.dewWarns, let dew = hero.dewLine {
                WarningChip(text: dew.prefix(1).uppercased() + dew.dropFirst())
            }
            if let r = hero.reason { Text(r).font(.footnote).secondary().fixedSize(horizontal: false, vertical: true) }
            if let a = snap.agreement {
                if snap.agreementWarns { WarningChip(text: a) }
                else { Text("✓ " + a).font(.footnote).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true) }
            }
        }
    }

    /// "9.4 hours · medium dew risk", whichever of the two there is.
    private var hoursLine: String? {
        let parts = [hero.hours, hero.dewWarns ? nil : hero.dewLine].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        // At the accessibility text sizes the numeral sits above the words so neither is squeezed.
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(alignment: .top, spacing: scale == .compact ? 22 : 36))
        layout {
            dial
            words.frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .trailing) { if let figure { FigureArt(figure: figure).frame(maxHeight: 220) } }
    }
}

/// The night as a low arc over the horizon: each hour a stretch of the curve, lit white where the sky is clear (brighter the
/// clearer it is), a faint line where it is not, and the Moon note beneath. It replaces the ten bars on Tonight; the Week page keeps its bars.
struct NightArc: View {
    let bars: [ClearSkyBar]
    let caption: String
    let moonNote: String
    /// How far through the night it is now (0 to 1), or nil when it is outside the night: the ember dot sits there.
    var nowFraction: Double? = nil
    @Environment(\.phoneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrived = false

    var body: some View {
        if bars.isEmpty { EmptyView() } else {
            VStack(spacing: 6) {
                NightArcCanvas(bars: bars, lit: theme.lit, faint: theme.textPrimary, ember: theme.ember, nowFraction: nowFraction)
                .mask { GeometryReader { g in Rectangle().frame(width: arrived || reduceMotion ? g.size.width : 0)
                    .animation(reduceMotion ? nil : .easeOut(duration: 1.1), value: arrived) } }
                Text(moonNote).font(.caption).monospacedDigit().secondary().dynamicTypeSize(...DynamicTypeSize.xxxLarge).multilineTextAlignment(.center)
            }
            .onAppear { arrived = true }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(ClearSkyBarsView.speech(caption: caption, bars: bars) + ". " + moonNote)
        }
    }
}

/// Seeing, wind, transparency (and the dark hours when they differ from the window): a small capital label over a bold value, left-aligned
/// with room between, where the grey footer line was.
struct FactsRow: View {
    let facts: [TonightHero.Fact]
    /// Two by two on iPhone, one row on iPad; one column at the accessibility text sizes. Every value is the same size and none is cut short.
    var columns = 2
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        if facts.isEmpty { EmptyView() } else {
            let count = typeSize.isAccessibilitySize ? 1 : max(1, min(columns, facts.count))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .topLeading), count: count), alignment: .leading, spacing: 16) {
                ForEach(facts, id: \.label) { f in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(f.label.uppercased()).font(.caption2.weight(.semibold)).tracking(0.8).secondary().lineLimit(1)
                        Text(f.value).font(.title3.weight(.heavy)).monospacedDigit().fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(facts.map { "\($0.label) \($0.value)" }.joined(separator: ", "))
        }
    }
}
