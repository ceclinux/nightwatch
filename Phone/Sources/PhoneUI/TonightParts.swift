import SwiftUI
import SkyCore
import PhoneCore

/// The sky score inside a 60-tick, 12-hour bezel: the Mac app's dial, drawn the same way (outer radius 45.5, hour ticks 8 by
/// 1.7, minute ticks 4.5 by 1.1; ticks inside a clear window lit with one glow; the numeral and its caption lifted 6 pt as a pair).
struct ScoreBezelView: View {
    let score: Int
    let slots: [BezelSlot]
    let label: String
    var size: CGFloat = 104
    /// The colour of the lit (clear) ticks; the system accent when nil, as on the Mac.
    var lit: Color? = nil
    /// The score's weight: light on the Mac's dial, bold on Tonight.
    var numeralWeight: Font.Weight = .light
    @Environment(\.phoneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrived = false

    private func colour(_ s: BezelSlot) -> Color {
        switch s { case .clear: lit ?? theme.accent; case .partCloud: theme.tickPartCloud; case .cloudy: theme.tickCloudy; case .daylight: theme.tickDaylight }
    }

    private func ticks(_ include: @escaping (BezelSlot) -> Bool) -> some View {
        ZStack {
            ForEach(0..<60, id: \.self) { i in
                if i < slots.count, include(slots[i]) {
                    let hour = i % 5 == 0
                    Capsule().fill(colour(slots[i]))
                        .frame(width: hour ? 1.7 : 1.1, height: hour ? 8 : 4.5)
                        .offset(y: -45.5 + (hour ? 4 : 2.25))
                        .frame(width: 91, height: 91)
                        .rotationEffect(.degrees(Double(i) * 6))
                        .opacity(arrived ? 1 : 0)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.25).delay(Double(i) * 0.012), value: arrived)
                }
            }
        }
    }

    var body: some View {
        ZStack {
            Circle().stroke(theme.ring, lineWidth: 0.75).frame(width: 66, height: 66)
            ticks { $0 != .clear }
            ticks { $0 == .clear }.compositingGroup().shadow(color: (lit ?? theme.accent).opacity(0.7), radius: 3)
            Text("\(arrived ? score : 0)").font(.system(size: 27, weight: numeralWeight)).monospacedDigit().foregroundStyle(theme.textPrimary)
                .contentTransition(.numericText(value: Double(arrived ? score : 0)))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.9), value: arrived)
                .overlay(alignment: .top) {
                    Text("SKY SCORE").font(.system(size: 9, weight: .medium)).secondary().fixedSize().offset(y: 28)
                }
                .offset(y: -6)
        }
        .frame(width: 91, height: 91)
        .scaleEffect(size / 91).frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .onAppear { arrived = true }
    }
}

/// One column per hour of darkness, filled to the clear-sky share; hours inside a clear window are lit with a glow, and the
/// clearest hour says how clear it is, as on the Mac.
struct ClearSkyBarsView: View {
    let bars: [ClearSkyBar]
    let caption: String
    var trackHeight: CGFloat = 37
    @Environment(\.phoneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrived = false

    var body: some View {
        if bars.isEmpty { EmptyView() } else {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .bottom, spacing: 3.4) {
                    ForEach(Array(bars.enumerated()), id: \.offset) { i, b in
                        VStack(spacing: 2) {
                            if b.peak {
                                Text("\(b.clearPct)% clear").font(.system(size: 9, weight: .medium)).foregroundStyle(theme.textPrimary).fixedSize()
                            }
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 2.5).fill(theme.barTrack)
                                RoundedRectangle(cornerRadius: 2.5).fill(b.lit ? theme.accent : theme.barCloudy)
                                    .frame(height: max(2, arrived ? trackHeight * CGFloat(b.clearPct) / 100 : 2))
                                    .shadow(color: b.lit ? theme.accent.opacity(0.7) : .clear, radius: 3)
                                    .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.8).delay(Double(i) * 0.04), value: arrived)
                            }
                            .frame(height: trackHeight)
                            Text(b.hour).font(.system(size: 9.5)).secondary().fixedSize()
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                Text("Clear sky by hour").font(.caption2).secondary().dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            }
            .onAppear { arrived = true }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.speech(caption: caption, bars: bars))
        }
    }

    /// What VoiceOver says for the hours, shared with the thin line Tonight draws instead.
    static func speech(caption: String, bars: [ClearSkyBar]) -> String {
        caption + " " + bars.map { "\($0.hour) hundred hours \($0.clearPct) percent clear" }.joined(separator: ", ")
    }
}

/// The source line at the foot: Apple's mark (the link to its legal page) when Apple Weather supplied the forecast, otherwise
/// the service's name; when it was updated; and Refresh. Apple's mark is drawn exactly as supplied, in either palette.
struct SourceFooter: View {
    let model: TonightModel
    let markData: Data?
    let refreshing: Bool
    let onRefresh: () -> Void
    @Environment(\.phoneTheme) private var theme
    @State private var refreshes = 0

    var body: some View {
        HStack(spacing: 12) {
            attribution
            Spacer(minLength: 8)
            Text(model.snapshot.updated ?? "").font(.caption).secondary()
            Button { refreshes += 1; onRefresh() } label: {
                Group {
                    if refreshing { ShimmerText(text: "Reading the forecast", font: .callout.weight(.medium)) }
                    else { Text("Refresh").font(.callout.weight(.medium)).foregroundStyle(theme.accent) }
                }
                .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(PressStyle())
            .sensoryFeedback(.impact(weight: .light), trigger: refreshes)
            .accessibilityLabel("Refresh the forecast")
        }
    }

    @ViewBuilder private var attribution: some View {
        let label = Group {
            if model.markURL != nil, let data = markData, let image = Image(platformData: data) {
                image.resizable().scaledToFit().frame(height: 14)   // exactly as supplied: never tinted
            } else {
                Text(model.source).font(.caption).secondary()
            }
        }
        if let legal = model.legalURL.flatMap(URL.init(string:)) {
            Link(destination: legal) { label.frame(minHeight: 44) }
                .accessibilityLabel("Apple Weather, legal attribution and data sources")
        } else {
            label
        }
    }
}
