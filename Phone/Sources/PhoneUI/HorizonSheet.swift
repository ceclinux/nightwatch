import SwiftUI
import SkyCore
import PhoneCore

/// The sky seen from above, as on the Mac's horizon editor: the zenith at the centre, the horizon at the rim, north at the top. Each of
/// the eight directions is shaded from the rim inwards as far as its height; the hills the elevation data finds sit behind; the dashed
/// ring is the go rule's height, below which a horizon changes nothing.
struct HorizonDial: View {
    let heights: [Double]
    let terrain: [Double]?
    let openDeg: Double
    @Environment(\.phoneTheme) private var theme

    /// The band of sector `i` from `from` degrees up to `height` degrees, seen from above (the rim is 0, the centre 90).
    private func sector(_ i: Int, from: Double = 0, height: Double, in r: CGFloat, centre c: CGPoint) -> Path {
        let outer = r * (1 - CGFloat(min(90, max(0, from)) / 90))
        let inner = r * (1 - CGFloat(min(90, max(0, height)) / 90))
        let start = Angle.degrees(Double(i) * 45 - 22.5 - 90), end = Angle.degrees(Double(i) * 45 + 22.5 - 90)
        var p = Path()
        p.addArc(center: c, radius: outer, startAngle: start, endAngle: end, clockwise: false)
        p.addArc(center: c, radius: inner, startAngle: end, endAngle: start, clockwise: true)
        p.closeSubpath()
        return p
    }

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2), r = min(size.width, size.height) / 2 - 28
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(theme.textSecondary.opacity(0.6)), lineWidth: 1)
            if let t = terrain, t.count == 8 {
                for i in 0..<8 where t[i] > 0 { ctx.fill(sector(i, height: t[i], in: r, centre: c), with: .color(theme.terrain)) }
            }
            // Below the go rule's height nothing changes whatever stands there: a faint band. Only what rises above it blocks the sky.
            ctx.fill(Path { p in p.addArc(center: c, radius: r, startAngle: .zero, endAngle: .degrees(360), clockwise: false)
                             p.addArc(center: c, radius: r * (1 - CGFloat(openDeg / 90)), startAngle: .degrees(360), endAngle: .zero, clockwise: true) },
                     with: .color(theme.textPrimary.opacity(0.04)), style: FillStyle(eoFill: true))
            for i in 0..<8 where heights[i] > openDeg { ctx.fill(sector(i, from: openDeg, height: heights[i], in: r, centre: c), with: .color(theme.blocked)) }
            let ring = r * (1 - CGFloat(openDeg / 90))
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - ring, y: c.y - ring, width: 2 * ring, height: 2 * ring)), with: .color(theme.textPrimary.opacity(0.7)),
                       style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            for (i, name) in Site.horizonDirections.enumerated() {
                let a = Angle.degrees(Double(i) * 45 - 90).radians
                let p = CGPoint(x: c.x + (r + 14) * CGFloat(cos(a)), y: c.y + (r + 14) * CGFloat(sin(a)))
                ctx.draw(Text(name).font(.caption2.weight(.semibold)).foregroundStyle(theme.textSecondary), at: p)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// Edit a site's horizon: eight heights in 5 degree steps, Open sky, and the hills the elevation data finds, with a button to raise the
/// horizon to clear them. Saves as you go, and the plan, targets and week follow at once.
struct HorizonSheet: View {
    @ObservedObject var store: PhoneStore
    let siteName: String
    @State private var heights: [Double] = Array(repeating: 0, count: 8)
    @State private var measuring = false
    @Environment(\.phoneTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    private var site: Site? { store.config.sites.first { $0.name == siteName } }
    private var open: Double { store.openDeg }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let site {
                        Text(Copy.horizonSummary(site, openDeg: open).plainDashes).font(.callout).secondary()
                    }
                    HorizonDial(heights: heights, terrain: site?.terrain, openDeg: open).frame(maxWidth: 320).frame(maxWidth: .infinity)
                    Card {
                        VStack(spacing: 0) {
                            ForEach(0..<8, id: \.self) { i in
                                HStack {
                                    Text(Site.horizonDirections[i]).font(.body.weight(.medium)).frame(minWidth: 36, alignment: .leading).fixedSize()
                                    if let t = site?.terrain, t.count == 8, t[i] > 0 { Text("hills \(Int(t[i].rounded()))°").font(.caption).secondary().lineLimit(1).minimumScaleFactor(0.7) }
                                    Spacer()
                                    stepButton("minus", i, -5)
                                    Text("\(Int(heights[i]))°").font(.body).monospacedDigit().frame(minWidth: 48).fixedSize()
                                        .accessibilityLabel("\(Site.horizonDirections[i]) horizon, \(Int(heights[i])) degrees")
                                    stepButton("plus", i, 5)
                                }
                                .frame(minHeight: 48)
                                .dynamicTypeSize(...DynamicTypeSize.accessibility1)   // eight rows with two buttons each cannot grow without bound
                                if i < 7 { Divider().overlay(theme.hairline) }
                            }
                        }
                    }
                    SecondaryButton(title: "Open sky", systemImage: "sun.max") { heights = Array(repeating: open, count: 8); save() }
                    SecondaryButton(title: "Measure from a photo", systemImage: "camera.viewfinder") { measuring = true }
                    terrainBox
                    Text("Heights below \(Int(open))° change nothing: the planner already keeps targets above that. The hills come from elevation data and see land only, never trees or buildings.")
                        .font(.footnote).secondary()
                }
                .padding(16).frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .background(theme.background)
            .navigationBarTitleDisplayModeInline()
            .toolbar {
                ToolbarItem(placement: .principal) { Text("Horizon: \(siteName)").font(.headline).foregroundStyle(theme.textPrimary) }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .sheet(isPresented: $measuring) {
            if let site {
                MeasurePhotoSheet(site: site, unit: store.distanceUnit, onUse: { d, v in heights[d] = v; save() },
                                  onMove: { store.moveSite(named: siteName, to: $0) }).phoneTheme(theme)
            }
        }
        .onAppear {
            heights = site?.horizon ?? Array(repeating: open, count: 8)
            store.checkTerrain()
        }
    }

    private func stepButton(_ symbol: String, _ i: Int, _ step: Double) -> some View {
        Button { Haptic.selection(); heights[i] = min(80, max(0, heights[i] + step)); save() } label: {
            Image(systemName: symbol).frame(width: 44, height: 44).background(theme.track, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("\(step > 0 ? "Raise" : "Lower") \(Site.horizonDirections[i]) horizon")
    }

    private func save() { store.setHorizon(siteNamed: siteName, heights: heights) }

    @ViewBuilder private var terrainBox: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("HILLS AROUND HERE").capsLabel()
                if store.terrainChecking.contains(siteName) {
                    ShimmerText(text: "Checking the hills around \(siteName)")
                } else if store.terrainFailed.contains(siteName) {
                    Text("The elevation service did not answer.").font(.callout)
                    SecondaryButton(title: "Try again", systemImage: "arrow.clockwise") { store.retryTerrain(siteNamed: siteName) }
                } else if let site, let t = site.terrain {
                    Text(Copy.terrainSummary(t).plainDashes).font(.callout)
                    let raises = Terrain.raises(terrain: t, site: site, openDeg: open)
                    if !raises.isEmpty {
                        SecondaryButton(title: "Raise the horizon to clear them", systemImage: "mountain.2") {
                            Haptic.success()
                            store.raiseToTerrain(siteNamed: siteName)
                            heights = store.config.sites.first { $0.name == siteName }?.horizon ?? Array(repeating: open, count: 8)
                        }
                    }
                } else {
                    Text("Not checked yet.").font(.callout).secondary()
                }
            }
        }
    }
}
