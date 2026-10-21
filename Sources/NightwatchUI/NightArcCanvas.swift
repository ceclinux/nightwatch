import SwiftUI
import SkyCore

/// The night as a low arc over the horizon, for the popover and the desktop widgets. Each hour is a stretch of the curve: lit with a
/// glow where the sky is clear (brighter the clearer it is), a faint line where it is not, with the hour beneath. An optional dot marks
/// the current hour. Colours come from the caller. It takes the same `ClearSkyBar`s as `ClearSkyBars`, which stays on the Week page.
public struct NightArcCanvas: View {
    public let bars: [ClearSkyBar]
    public var lit: Color
    /// The colour the faint stretches and unlit hour labels are drawn in (at low opacity).
    public var faint: Color
    public var ember: Color? = nil
    /// How far along the night the current hour is, 0 to 1; nil draws no dot.
    public var nowFraction: Double? = nil
    public var labels = true
    public var glow = true
    public var height: CGFloat = 88
    public var lineWidth: CGFloat = 4
    /// The screen-reader sentence, as `ClearSkyBars` carries it (`Copy.barsLabel`).
    public var label: String

    public init(bars: [ClearSkyBar], label: String, lit: Color = Tokens.lit, faint: Color = Tokens.textSecondary, ember: Color? = nil,
                nowFraction: Double? = nil, labels: Bool = true, glow: Bool = true, height: CGFloat = 88, lineWidth: CGFloat = 4) {
        self.bars = bars; self.label = label; self.lit = lit; self.faint = faint; self.ember = ember; self.nowFraction = nowFraction
        self.labels = labels; self.glow = glow; self.height = height; self.lineWidth = lineWidth
    }

    private func arc(_ size: CGSize) -> Path {
        let inset: CGFloat = labels ? 30 : 10
        var p = Path()
        p.move(to: CGPoint(x: 3, y: size.height - inset))
        p.addQuadCurve(to: CGPoint(x: size.width - 3, y: size.height - inset), control: CGPoint(x: size.width / 2, y: -size.height * 0.45))
        return p
    }

    public var body: some View {
        Canvas { ctx, size in
            let path = arc(size), n = Double(max(1, bars.count)), gap = 0.004
            ctx.stroke(path, with: .color(faint.opacity(0.18)), style: StrokeStyle(lineWidth: 1, lineCap: .round))
            func seg(_ i: Int) -> Path { path.trimmedPath(from: Double(i) / n + gap, to: Double(i + 1) / n - gap) }
            if glow {
                ctx.drawLayer { layer in
                    layer.addFilter(.blur(radius: 5))
                    for (i, b) in bars.enumerated() where b.lit {
                        layer.stroke(seg(i), with: .color(lit.opacity(0.8 * Double(b.clearPct) / 100)), style: StrokeStyle(lineWidth: lineWidth * 2, lineCap: .butt))
                    }
                }
            }
            for (i, b) in bars.enumerated() {
                if b.lit { ctx.stroke(seg(i), with: .color(lit.opacity(0.55 + 0.45 * Double(b.clearPct) / 100)), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt)) }
                else if b.clearPct > 0 { ctx.stroke(seg(i), with: .color(faint.opacity(0.28)), style: StrokeStyle(lineWidth: max(1, lineWidth - 1), lineCap: .butt)) }
                if labels {
                    // The hour under its stretch: bright and heavy when clear, faint when not.
                    let mid = path.trimmedPath(from: 0, to: (Double(i) + 0.5) / n).currentPoint ?? .zero
                    let text = Text(b.hour).font(.system(size: TextScale.pt(11), weight: b.lit ? .heavy : .regular)).monospacedDigit()
                        .foregroundStyle(b.lit ? lit : faint.opacity(0.45))
                    ctx.draw(ctx.resolve(text), at: CGPoint(x: mid.x, y: mid.y + 17), anchor: .center)
                }
            }
            if let ember, let f = nowFraction, let pt = path.trimmedPath(from: 0, to: min(max(f, 0.001), 1)).currentPoint {
                let dot = CGRect(x: pt.x - 6, y: pt.y - 6, width: 12, height: 12)
                ctx.fill(Path(ellipseIn: dot), with: .color(ember))
                ctx.stroke(Path(ellipseIn: dot), with: .color(faint), lineWidth: 1.5)
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel(label)
    }
}
