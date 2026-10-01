import SwiftUI
import NightwatchUI
import SkyCore

/// "Horizon…" on a saved site (owner-approved mock-up, 1 October 2026): how high houses, trees or hills block the sky in
/// eight directions, drawn as a sky seen from above. A target counts as up only once it clears this (`Site.floorDeg`).
struct HorizonSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let siteName: String
    @State private var heights: [Double] = []

    private static let names = ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
    private var openDeg: Double { store.config.goRule.minAltitudeDeg }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Horizon at \(siteName)").font(.title3.weight(.semibold))
            Text("How high the sky is blocked in each direction, by houses, trees or hills. Nightwatch counts a target as up only once it clears this. Open sky is the Go rule’s “Targets must reach” height, \(Int(openDeg))°.")
                .font(.caption).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 24) {
                VStack(spacing: 6) {
                    HorizonDial(heights: heights, openDeg: openDeg).frame(width: 220, height: 220)
                    Text("Seen from above, north at the top. Grey is blocked; the dashed ring is \(Int(openDeg))°.")
                        .font(.caption2).foregroundStyle(Theme.dim).multilineTextAlignment(.center).frame(width: 220)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Copy.horizonSummary(edited, openDeg: openDeg))
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(heights.indices, id: \.self) { i in row(i) }
                    Button("Open sky: \(Int(openDeg))° all round") { heights = Array(repeating: openDeg, count: 8) }.padding(.top, 4)
                }
            }
            Text("To measure: stand where the telescope goes, face each way, and read the angle to the top of the roof or trees with a clinometer app on your phone. Steps of 5° are plenty.")
                .font(.caption).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Done") { save(); dismiss() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 560)
        .onAppear {
            heights = store.config.sites.first { $0.name == siteName }?.horizon ?? Array(repeating: openDeg, count: 8)
        }
    }

    /// The site with the heights as edited, for the summary VoiceOver reads.
    private var edited: Site {
        var s = store.config.sites.first { $0.name == siteName } ?? Site(name: siteName, latitude: 0, longitude: 0, elevationM: 0, timeZoneID: "UTC", bortle: 5)
        s.horizon = heights.count == 8 ? heights : nil
        return s
    }

    private func row(_ i: Int) -> some View {
        HStack(spacing: 10) {
            Text(Site.horizonDirections[i]).font(.system(size: 13, weight: .semibold)).frame(width: 30, alignment: .leading)
            Text(heights[i] == openDeg ? "open sky" : heights[i] < openDeg ? "lower than usual" : "blocked")
                .font(.caption).foregroundStyle(Theme.dim).frame(width: 110, alignment: .leading)
            Button { heights[i] = max(0, heights[i] - 5) } label: { Image(systemName: "minus") }
                .accessibilityLabel("Lower \(Self.names[i])").disabled(heights[i] <= 0)
            Text("\(Int(heights[i]))°").monospacedDigit().frame(width: 34)
            Button { heights[i] = min(80, heights[i] + 5) } label: { Image(systemName: "plus") }
                .accessibilityLabel("Raise \(Self.names[i])").disabled(heights[i] >= 80)
        }
        .accessibilityElement(children: .contain)
    }

    /// All at open sky saves no horizon, so the site follows the go rule if its height changes later.
    private func save() {
        guard let i = store.config.sites.firstIndex(where: { $0.name == siteName }) else { return }
        store.config.sites[i].horizon = heights.allSatisfy { $0 == openDeg } ? nil : heights
        store.saveConfig()
    }
}

/// The sky from above: zenith at the centre, the horizon on the rim, each direction's blocked part shaded.
struct HorizonDial: View {
    let heights: [Double]
    let openDeg: Double

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2), R = min(size.width, size.height) / 2 - 14
            func r(_ alt: Double) -> CGFloat { R * CGFloat(90 - alt) / 90 }
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - R, y: c.y - R, width: 2 * R, height: 2 * R)), with: .color(Color(red: 0.09, green: 0.14, blue: 0.23)))
            for (i, h) in heights.enumerated() {
                // Azimuth clockwise from north; on screen north is up, so the angle is measured from −90°.
                let a0 = Angle.degrees(Double(i) * 45 - 22.5 - 90), a1 = Angle.degrees(Double(i) * 45 + 22.5 - 90)
                var p = Path()
                p.addArc(center: c, radius: r(h), startAngle: a0, endAngle: a1, clockwise: false)
                p.addArc(center: c, radius: R, startAngle: a1, endAngle: a0, clockwise: true)
                p.closeSubpath()
                ctx.fill(p, with: .color(.gray.opacity(h > openDeg ? 0.6 : 0.45)))
            }
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r(openDeg), y: c.y - r(openDeg), width: 2 * r(openDeg), height: 2 * r(openDeg))),
                       with: .color(.white.opacity(0.45)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - R, y: c.y - R, width: 2 * R, height: 2 * R)), with: .color(.white.opacity(0.45)), lineWidth: 1)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 2.5, y: c.y - 2.5, width: 5, height: 5)), with: .color(Theme.text))
            for (label, x, y) in [("N", c.x, c.y - R - 8), ("E", c.x + R + 8, c.y), ("S", c.x, c.y + R + 8), ("W", c.x - R - 8, c.y)] {
                ctx.draw(Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.text), at: CGPoint(x: x, y: y))
            }
        }
    }
}
