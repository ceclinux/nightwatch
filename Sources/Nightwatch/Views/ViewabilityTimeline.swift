import SwiftUI
import NightwatchUI
import SkyCore

/// A card's viewability timeline (handover timeline table). The track spans tonight's clear window, or darkness when there
/// is none, when the span the target is up is drawn grey. The card, not this view, carries the screen-reader sentence (Copy.cardLabel). The viewable span is lit from accent.clear.low to accent.clear following altitude, with a white best-moment marker.
struct ViewabilityTimeline: View {
    let target: RankedTarget
    let track: ClearWindow
    let lit: Bool
    let site: Site

    private func x(_ d: Date, _ w: CGFloat) -> CGFloat {
        let len = track.end.timeIntervalSince(track.start)
        return len <= 0 ? 0 : w * CGFloat(min(1, max(0, d.timeIntervalSince(track.start) / len)))
    }

    private var hourTicks: [Date] {
        var out: [Date] = []
        var t = site.calendar.nextDate(after: track.start, matching: DateComponents(minute: 0, second: 0), matchingPolicy: .nextTime) ?? track.end
        while t < track.end { out.append(t); t = t.addingTimeInterval(3600) }
        return out
    }

    var body: some View {
        VStack(spacing: 7) {
            GeometryReader { g in
                let w = g.size.width
                ZStack(alignment: .topLeading) {
                    Capsule().fill(Tokens.targetsTrack).frame(width: w, height: 3)
                    ForEach(hourTicks, id: \.self) { t in
                        Rectangle().fill(Color.white.opacity(0.27)).frame(width: 0.75, height: 3).offset(x: x(t, w), y: 5)
                    }
                    if !lit, let v = target.viewable {
                        // No clear window: when it is up in darkness anyway, in grey, with its highest point (owner, 28 September 2026).
                        Capsule().fill(Tokens.barCloudy).frame(width: max(3, x(v.end, w) - x(v.start, w)), height: 3)
                            .offset(x: min(x(v.start, w), w - 3))
                        Circle().fill(Tokens.textSecondary).frame(width: 5.5, height: 5.5)
                            .offset(x: x(target.peakTime, w) - 2.75, y: -1.25)
                    }
                    if lit, let v = target.viewable {
                        let stops = Planner.timelineStops(target.altitudeSamples)
                        Capsule()
                            .fill(LinearGradient(stops: stops.enumerated().map { i, u in
                                Gradient.Stop(color: Tokens.clearBlend(u), location: Double(i) / Double(max(1, stops.count - 1)))
                            }, startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(3, x(v.end, w) - x(v.start, w)), height: 3)
                            .shadow(color: Tokens.accentClear.opacity(0.7), radius: 3)
                            .offset(x: min(x(v.start, w), w - 3))   // a span that starts on the last sample stays on the track
                        Circle().fill(Color.white).frame(width: 6.5, height: 6.5)
                            .overlay(Circle().stroke(Tokens.targetsCard, lineWidth: 1.25))
                            .offset(x: x(target.peakTime, w) - 3.25, y: -1.75)
                    }
                }
            }
            .frame(height: 9)
            HStack {
                Text(caption).foregroundStyle(Tokens.textSecondary)
                Spacer()
                if target.viewable != nil {
                    Text("\(lit ? L10n.text("Best") : L10n.text("Highest")) \(Copy.hhmm(target.peakTime, site: site)) · \(Int(target.peakAltDeg.rounded()))°")
                        .fontWeight(.medium).foregroundStyle(lit ? Tokens.textPrimary : Tokens.textSecondary)
                }
            }
            .font(.system(size: TextScale.pt(9)))
        }
        .accessibilityHidden(true)   // the card carries the sentence label (spec §7)
    }

    private var caption: String {
        guard let v = target.viewable else { return lit ? L10n.text("Viewable outside the clear window") : L10n.text("Too low in darkness tonight") }
        return "\(lit ? L10n.text("Viewable") : L10n.text("Up in darkness")) \(Copy.hhmm(v.start, site: site))–\(Copy.hhmm(v.end, site: site))"
    }
}
