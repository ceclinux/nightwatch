import SwiftUI
import SkyCore

/// One column per hour of darkness, filled to the clear-sky share (100 − cloud). Hours inside a clear window are red with a
/// glow, the others bar.cloudy. Draws `ClearSkyBar` data, so the popover, the Targets header and the widget share it.
public struct ClearSkyBars: View {
    let bars: [ClearSkyBar]
    let label: String
    var trackHeight: CGFloat
    var labels: Bool
    var caption: Bool
    let language: AppLanguage?

    /// `caption`: the "Clear sky by hour" line under the hour labels. The source is named once, in the footer (owner, 28 September 2026).
    public init(bars: [ClearSkyBar], label: String, trackHeight: CGFloat = 37, labels: Bool = true, caption: Bool = true, language: AppLanguage? = nil) {
        self.bars = bars; self.label = label; self.trackHeight = trackHeight; self.labels = labels; self.caption = caption
        self.language = language
    }

    @ViewBuilder public var body: some View {
        if !bars.isEmpty { chart }
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .bottom, spacing: 3.4) {
                ForEach(Array(bars.enumerated()), id: \.offset) { _, b in
                    let clear = CGFloat(b.clearPct) / 100
                    VStack(spacing: 2) {
                        if labels, b.peak {
                            // "80%" alone read as visibility, or a clear night (owner's UAT, 30 September 2026).
                            Text(L10n.format("\(b.clearPct)% clear", language: language)).font(.system(size: TextScale.pt(8), weight: .medium)).foregroundStyle(Tokens.textPrimary).fixedSize()
                        }
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 2.5).fill(Tokens.surfaceTrack)
                            RoundedRectangle(cornerRadius: 2.5).fill(b.lit ? Tokens.accentClear : Tokens.barCloudy)
                                .frame(height: trackHeight * clear)
                                .shadow(color: b.lit ? Tokens.accentClear.opacity(0.7) : .clear, radius: 3)
                        }
                        .frame(height: trackHeight)
                        if labels {
                            Text(b.hour).font(.system(size: TextScale.pt(8.5))).foregroundStyle(Tokens.textSecondary).fixedSize()
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            if labels, caption {
                Text(L10n.text("Clear sky by hour", language: language)).font(.system(size: TextScale.pt(9))).foregroundStyle(Tokens.textSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}
