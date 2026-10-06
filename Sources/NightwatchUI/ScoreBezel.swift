import SwiftUI
import SkyCore

/// Sky score inside a 60-tick 12-hour bezel (handover shape table: outer radius 45.5 pt, hour ticks 8 × 1.7, minute ticks 4.5 × 1.1).
public struct ScoreBezel: View {
    let score: Int
    let slots: [BezelSlot]
    let label: String

    public init(score: Int, slots: [BezelSlot], label: String) { self.score = score; self.slots = slots; self.label = label }

    private func colour(_ s: BezelSlot) -> Color {
        switch s { case .clear: Tokens.accentClear; case .partCloud: Tokens.tickPartCloud; case .cloudy: Tokens.tickCloudy; case .daylight: Tokens.tickDaylight }
    }

    /// The ticks whose slot passes `include`, each on the 45.5 pt radius at 6i° clockwise from 12 o'clock.
    private func ticks(_ include: @escaping (BezelSlot) -> Bool) -> some View {
        ZStack {
            ForEach(0..<60, id: \.self) { i in
                if include(slots[i]) {
                    let hour = i % 5 == 0
                    Capsule().fill(colour(slots[i]))
                        .frame(width: hour ? 1.7 : 1.1, height: hour ? 8 : 4.5)
                        .offset(y: -45.5 + (hour ? 4 : 2.25))
                        .frame(width: 91, height: 91)
                        .rotationEffect(.degrees(Double(i) * 6))
                }
            }
        }
    }

    public var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.09), lineWidth: 0.75).frame(width: 66, height: 66)
            ticks { $0 != .clear }
            ticks { $0 == .clear }.compositingGroup().shadow(color: Tokens.accentClear.opacity(0.7), radius: 3)   // one glow for all lit ticks
            Text("\(score)").font(.system(size: 27, weight: .light)).foregroundStyle(Tokens.textPrimary)
                .overlay(alignment: .top) {   // numeral centred in the bezel, caption hung beneath it (handover: caption 11 pt below centre)
                    Text("SKY SCORE").font(.system(size: 9, weight: .medium)).foregroundStyle(Tokens.textSecondary).fixedSize().offset(y: 28)
                }
        }
        .frame(width: 91, height: 91)
        // The whole dial grows with the app's text size, numeral and ticks together, so nothing inside it has to be refitted.
        .scaleEffect(TextScale.factor).frame(width: TextScale.pt(91), height: TextScale.pt(91))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}
