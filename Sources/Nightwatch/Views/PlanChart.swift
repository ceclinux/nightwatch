import SwiftUI
import NightwatchUI
import SkyCore

/// One line style per plan target (#92, owner-approved mock-up, 1 October 2026): colours that differ in lightness as well
/// as hue, each with its own dash, so the lines read apart without colour. Yellow stays free for warnings; a plan longer
/// than the list repeats it.
enum PlanLineStyle {
    static let all: [(colour: Color, dash: [CGFloat])] = [
        (Color(hex: 0x9ED0FF), []), (Color(hex: 0xFF9F43), [7, 4]), (Color(hex: 0xB794FF), [2, 3]),
        (Color(hex: 0x4FD1A5), [10, 3, 2, 3]), (Color(hex: 0xF78FB3), [5, 2]), (Color(hex: 0xE8EAEF), [1, 3]),
    ]
    static func at(_ i: Int) -> (colour: Color, dash: [CGFloat]) { all[i % all.count] }
}

/// A plan row's key: a short sample of its target's line.
struct PlanLineKey: View {
    let index: Int
    var body: some View {
        let s = PlanLineStyle.at(index)
        Path { p in p.move(to: CGPoint(x: 1, y: 5)); p.addLine(to: CGPoint(x: 25, y: 5)) }
            .stroke(s.colour, style: StrokeStyle(lineWidth: 2.6, dash: s.dash))
            .frame(width: 26, height: 10)
            .accessibilityHidden(true)
    }
}

/// "Altitude tonight": every target in the plan on one chart, from sunset to sunrise, with the clear window shaded. Each
/// line is faint all night and bold where its target is in the window and clear of the floor (the go rule's height, or
/// the site's horizon in that target's direction), with its best moment marked and named. Without a horizon the floor
/// is one dashed line; with one there is none to draw, since each target sits in its own direction.
struct PlanChart: View {
    let items: [PlanItem]
    let night: Night
    let window: ClearWindow
    let minAltitude: Double
    let site: Site
    var nightWords = "tonight"

    private var span: TimeInterval { night.sunrise.timeIntervalSince(night.sunset) }
    private func frac(_ t: Date) -> Double { t.timeIntervalSince(night.sunset) / span }

    var body: some View {
        let tracks = items.map { AltitudeTrack.samples(raHours: $0.target.raHours, decDeg: $0.target.decDeg, night: night, window: window,
                                                       site: site, minAlt: minAltitude) }
        VStack(alignment: .leading, spacing: 6) {
            Text("Altitude \(nightWords)").font(.system(size: 11)).foregroundStyle(Tokens.textSecondary)
                GeometryReader { g in
                    let x = { (f: Double) in g.size.width * max(0, min(1, f)) }
                    let y = { (alt: Double) in g.size.height * (1 - max(0, min(90, alt)) / 90) }
                    Rectangle().fill(Color.white.opacity(0.07))
                        .frame(width: max(0, x(frac(window.end)) - x(frac(window.start))), height: g.size.height)
                        .offset(x: x(frac(window.start)))
                    if site.horizon == nil {
                        Path { p in p.move(to: CGPoint(x: 0, y: y(minAltitude))); p.addLine(to: CGPoint(x: g.size.width, y: y(minAltitude))) }
                            .stroke(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        Text("\(Int(minAltitude))°").font(.system(size: 9)).foregroundStyle(Tokens.textSecondary)
                            .position(x: g.size.width - 12, y: y(minAltitude) - 7)
                    }
                    ForEach(Array(tracks.enumerated()), id: \.offset) { i, samples in
                        let style = PlanLineStyle.at(i)
                        Path { p in for (k, s) in samples.enumerated() { let pt = CGPoint(x: x(s.fraction), y: y(s.alt)); k == 0 ? p.move(to: pt) : p.addLine(to: pt) } }
                            .stroke(style.colour.opacity(0.35), style: StrokeStyle(lineWidth: 1.2, dash: style.dash))
                        Path { p in
                            for run in AltitudeTrack.clearRuns(samples, window: window) {
                                for (k, s) in run.enumerated() { let pt = CGPoint(x: x(s.fraction), y: y(s.alt)); k == 0 ? p.move(to: pt) : p.addLine(to: pt) }
                            }
                        }
                        .stroke(style.colour, style: StrokeStyle(lineWidth: 2.6, dash: style.dash))
                        let t = items[i].target
                        if t.peakTime >= night.sunset, t.peakTime <= night.sunrise {
                            let px = x(frac(t.peakTime)), py = y(t.peakAltDeg)
                            Circle().fill(style.colour).frame(width: 7, height: 7).position(x: px, y: py)
                            Text("\(shortName(t)) \(Copy.hhmm(t.peakTime, site: site))")
                                .font(.system(size: 10, weight: .medium)).foregroundStyle(style.colour).fixedSize()
                                .position(x: min(max(px, 60), g.size.width - 60), y: max(8, py - 11))
                        }
                    }
                }
                .frame(height: 170)
            HStack {
                Text("Sunset \(Copy.hhmm(night.sunset, site: site))"); Spacer()
                Text("Clear \(Copy.span(window.start, window.end, site: site))"); Spacer()
                Text("Sunrise \(Copy.hhmm(night.sunrise, site: site))")
            }
            .font(.system(size: 10)).foregroundStyle(Tokens.textSecondary)
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
        .background(Tokens.targetsCard, in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Tokens.cardOutline, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Altitude \(nightWords)")
        .accessibilityValue(items.map { "\($0.target.name), best \(Copy.hhmm($0.target.peakTime, site: site)) at \(Int($0.target.peakAltDeg.rounded())) degrees" }
            .joined(separator: "; "))
    }

    /// The name people know, as short as the line label allows: "Iris" for the Iris Nebula, else the catalogue name.
    private func shortName(_ t: RankedTarget) -> String {
        guard t.group != .stars, let n = t.commonName else { return t.name }   // a star's commonName is its designation
        for suffix in [" Nebula", " Galaxy", " Cluster"] where n.hasSuffix(suffix) && n.count > suffix.count + 2 { return String(n.dropLast(suffix.count)) }
        return n
    }
}
