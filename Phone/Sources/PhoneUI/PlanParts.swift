import SwiftUI
import SkyCore
import PhoneCore

/// A heart that adds a target to the favourites (which also puts it in tonight's plan when it is up).
struct HeartButton: View {
    @ObservedObject var store: PhoneStore
    let id: String
    @Environment(\.phoneTheme) private var theme

    var body: some View {
        let on = store.isFavourite(id)
        Button { store.toggleFavourite(id) } label: {
            Image(systemName: on ? "heart.fill" : "heart").font(.title3).foregroundStyle(on ? theme.ember : theme.textSecondary)
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .sensoryFeedback(.selection, trigger: on)
        .accessibilityLabel(on ? "Remove from favourites" : "Add to favourites")
    }
}

/// One target as a card, as on the Mac's Targets window: its picture, the catalogue ID, what it is, and when it is highest.
struct TargetCardView: View {
    @ObservedObject var store: PhoneStore
    let target: RankedTarget
    var dimmed = false
    var note: String? = nil
    /// In Eyes and binoculars: how to look, and what it looks like, in place of when it is highest.
    var eye: EyeView? = nil
    @Environment(\.phoneTheme) private var theme

    var body: some View {
        let pick = store.site.map { TargetPick.make(target, site: $0, fov: store.config.fov) }
        HStack(spacing: 12) {
            if let pick {
                TargetPicture(pick: pick).frame(width: 84, height: 84).clipShape(RoundedRectangle(cornerRadius: 9))
                    .opacity(dimmed ? 0.45 : 1)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(target.catalogueID).font(.headline.weight(.heavy)).lineLimit(1)
                    if let c = target.cardNote { Text(c).font(.footnote).secondary() }
                }
                Text((target.commonName ?? target.typeName).uppercased()).font(.caption2).tracking(1.2).secondary().lineLimit(1)
                if let note { Text(note.plainDashes).font(.caption).foregroundStyle(theme.warning).lineLimit(2) }
                else if let eye {
                    Chip(text: eye.rawValue, symbol: eye == .nakedEye ? "eye" : "binoculars")
                    Text(Copy.eyeLook(target, eye).plainDashes).font(.caption).secondary().lineLimit(2)
                }
                else if let pick { Text(pick.best).font(.caption.weight(.medium)).monospacedDigit().foregroundStyle(theme.bestLine).lineLimit(1) }
            }
            Spacer(minLength: 4)
            if !MilkyWay.isMilkyWay(target.id) { HeartButton(store: store, id: target.id) }   // not a catalogue target: no place in Favourites or the plan
        }
        .padding(10)
        .cardSurface()
        .accessibilityElement(children: .contain)
    }
}

/// The line styles for the altitude chart: a colour and a dash each, so no line relies on colour alone (and red mode has one hue).
enum ChartLine {
    static func colour(_ i: Int, theme: PhoneTheme) -> Color {
        if theme.isRed { return theme.accent.opacity(i % 2 == 0 ? 1 : 0.7) }
        return [Color(hex: 0x6EE7B7), Color(hex: 0xF9A8D4), Color.white, Color(hex: 0xFCD34D), Color(hex: 0x93C5FD), Color(hex: 0xC4B5FD)][i % 6]
    }
    static func dash(_ i: Int) -> [CGFloat] { [[], [7, 4], [2, 3], [10, 3, 2, 3], [4, 4], [1, 5]][i % 6] }
}

/// Altitude through the night for a few targets, from sunset to sunrise: the clear window shaded, the minimum height dashed,
/// each line bold while the target is up inside the window, a dot at its best moment. Drawn from SkyCore's `AltitudeTrack`.
struct AltitudeChart: View {
    struct Line: Identifiable { let id: String; let style: Int; let samples: [AltitudeSample]; let best: Date }
    let lines: [Line]
    let night: Night
    let window: ClearWindow?
    let floor: Double
    let site: Site
    var height: CGFloat = 170
    @Environment(\.phoneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    private func x(_ d: Date, _ w: CGFloat) -> CGFloat {
        let span = night.sunrise.timeIntervalSince(night.sunset)
        return w * CGFloat(max(0, min(1, d.timeIntervalSince(night.sunset) / span)))
    }
    private func y(_ alt: Double, _ h: CGFloat) -> CGFloat { h * (1 - CGFloat(max(0, min(90, alt)) / 90)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Canvas { ctx, size in
                if let win = window {
                    let r = CGRect(x: x(win.start, size.width), y: 0, width: x(win.end, size.width) - x(win.start, size.width), height: size.height)
                    ctx.fill(Path(r), with: .color(theme.textPrimary.opacity(0.07)))
                }
                var f = Path(); f.move(to: CGPoint(x: 0, y: y(floor, size.height))); f.addLine(to: CGPoint(x: size.width, y: y(floor, size.height)))
                ctx.stroke(f, with: .color(theme.textSecondary.opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                for line in lines {
                    let col = ChartLine.colour(line.style, theme: theme), dash = ChartLine.dash(line.style)
                    var faint = Path()
                    for (i, s) in line.samples.enumerated() {
                        let p = CGPoint(x: x(s.time, size.width), y: y(s.alt, size.height))
                        if i == 0 { faint.move(to: p) } else { faint.addLine(to: p) }
                    }
                    ctx.stroke(faint, with: .color(col.opacity(0.35)), style: StrokeStyle(lineWidth: 1.2, dash: dash))
                    if let win = window {
                        for run in AltitudeTrack.clearRuns(line.samples, window: win) {
                            var bold = Path()
                            for (i, s) in run.enumerated() {
                                let p = CGPoint(x: x(s.time, size.width), y: y(s.alt, size.height))
                                if i == 0 { bold.move(to: p) } else { bold.addLine(to: p) }
                            }
                            ctx.stroke(bold, with: .color(col), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, dash: dash))
                        }
                    }
                    if let s = line.samples.min(by: { abs($0.time.timeIntervalSince(line.best)) < abs($1.time.timeIntervalSince(line.best)) }) {
                        let p = CGPoint(x: x(s.time, size.width), y: y(s.alt, size.height))
                        ctx.fill(Path(ellipseIn: CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7)), with: .color(col))
                    }
                }
            }
            .frame(height: height)
            // The lines are drawn in from sunset to sunrise, as the bars rise on Tonight.
            .mask(alignment: .leading) { GeometryReader { g in Rectangle().frame(width: revealed || reduceMotion ? g.size.width : 0) } }
            .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.85), value: revealed)   // the same spring the rows rise with
            .onAppear { revealed = true }
            HStack {
                Text("Sunset \(Copy.hhmm(night.sunset, site: site))"); Spacer()
                if let w = window { Text("Clear \(Copy.hhmm(w.start, site: site))-\(Copy.hhmm(w.end, site: site))") }
                Spacer(); Text("Sunrise \(Copy.hhmm(night.sunrise, site: site))")
            }
            .font(.caption2).secondary()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Altitude tonight, from sunset to sunrise. " + lines.map { l in
            let peak = Int((l.samples.map(\.alt).max() ?? 0).rounded())
            return "\(l.id) reaches \(peak) degrees, best at \(Copy.hhmm(l.best, site: site))"
        }.joined(separator: ". "))
    }
}

extension AltitudeChart {
    /// Lines for `targets` over `night`, each from SkyCore's altitude samples, styled with `ChartLayout.styles`.
    static func lines(for targets: [RankedTarget], night: Night, window: ClearWindow, site: Site, floor: Double) -> [Line] {
        let styles = ChartLayout.styles(for: targets.map(\.id), count: targets.count)
        return targets.map { t in
            Line(id: t.catalogueID, style: styles[t.id] ?? 0,
                 samples: AltitudeTrack.samples(raHours: t.raHours, decDeg: t.decDeg, night: night,
                                                window: ClearWindow(start: night.sunset, end: night.sunrise), site: site, minAlt: floor),
                 best: t.peakTime)
        }
    }
}
