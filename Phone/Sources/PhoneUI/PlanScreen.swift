import SwiftUI
import SkyCore
import PhoneCore

/// Tonight's plan, as the Mac builds it: the favourites that are up in the clear window plus anything added for the night, in order of
/// their best time. Take off the ones you will skip; two with the same best time are flagged so you can choose.
struct PlanScreen: View {
    @ObservedObject var store: PhoneStore
    @State private var tomorrow = false
    var onBrowse: () -> Void = {}
    @Environment(\.phoneTheme) private var theme

    private var night: NightPlan? { store.planning.map { tomorrow ? $0.tomorrow : $0.tonight } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PhoneSegmented(selection: $tomorrow, options: [("Tonight", false), ("Tomorrow night", true)])
                if let night, let site = store.site {
                    content(night: night, site: site)
                }
            }
            .padding(16).frame(maxWidth: 900).frame(maxWidth: .infinity)
        }
        .background { StarField(seed: "plan", calm: true).ignoresSafeArea() }
    }

    @ViewBuilder private func content(night: NightPlan, site: Site) -> some View {
        if let session = store.session(tomorrow: tomorrow) {
            Text("Clear \(Copy.hhmm(session.window.start, site: site))-\(Copy.hhmm(session.window.end, site: site)) · \(String(format: "%.0f", session.window.hours)) h · Moon \(Int((night.moonIllumination * 100).rounded()))%")
                .font(.callout).secondary()
            if session.items.isEmpty {
                EmptyState(title: "Nothing planned yet", message: "Heart targets you want to shoot. The ones that are up in tonight's clear window appear here, in order of their best time.",
                           action: ("Browse targets", onBrowse))
            } else {
                Card {
                    AltitudeChart(lines: AltitudeChart.lines(for: session.items.map(\.target), night: night.night, window: session.window, site: site,
                                                             floor: store.config.goRule.minAltitudeDeg),
                                  night: night.night, window: session.window, floor: store.config.goRule.minAltitudeDeg, site: site)
                }
                ForEach(Array(session.items.enumerated()), id: \.element.id) { i, item in
                    planRow(item, index: i, count: session.items.count, site: site).risesIn(i + 1)
                }
            }
            if !session.takenOff.isEmpty {
                Text(tomorrow ? "TAKEN OFF TOMORROW" : "TAKEN OFF TONIGHT").capsLabel()
                ForEach(session.takenOff) { t in
                    HStack {
                        Text("\(t.catalogueID) · \(t.commonName ?? t.typeName)").font(.callout).lineLimit(1)
                        Spacer()
                        Button("Put back") { Haptic.success(); store.setInPlan(t.id, on: true, tomorrow: tomorrow) }.buttonStyle(PressStyle()).foregroundStyle(theme.accent).frame(minHeight: 44)
                    }
                    .padding(.horizontal, 12).cardSurface()
                }
            }
            if !session.omitted.isEmpty {
                Text("LEFT OUT").capsLabel()
                ForEach(session.omitted) { o in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(o.target.catalogueID) · \(o.target.commonName ?? o.target.typeName)").font(.callout).lineLimit(1)
                        Text(o.reason.plainDashes).font(.caption).secondary()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12).cardSurface().opacity(0.8)
                }
            }
            Text("Heart a target to keep it in every plan, or add it to one night only from its page.").font(.footnote).secondary()
        } else {
            EmptyState(title: tomorrow ? "No plan for tomorrow night" : "No plan tonight",
                       message: "A plan needs a clear window. \(night.mode == .bright ? "Tonight is a bright night." : "Tonight has none.")")
        }
    }

    private func planRow(_ item: PlanItem, index: Int, count: Int, site: Site) -> some View {
        let t = item.target, style = ChartLayout.styles(for: store.session(tomorrow: tomorrow)?.items.map(\.id) ?? [], count: count)[t.id] ?? index
        return HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 6) {
                Text(Copy.hhmm(t.peakTime, site: site)).font(.title3.weight(.heavy)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                Path { p in p.move(to: .zero); p.addLine(to: CGPoint(x: 34, y: 0)) }
                    .stroke(ChartLine.colour(style, theme: theme), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, dash: ChartLine.dash(style)))
                    .frame(width: 34, height: 2)
            }.frame(width: 66)
            NavigationLink { TargetDetailScreen(store: store, target: t) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) { Text(t.catalogueID).font(.headline.weight(.heavy)); if item.added { Text("added").font(.caption).secondary() } }
                    Text((t.commonName ?? t.typeName).uppercased()).font(.caption2).tracking(1.2).secondary()
                    Text("Best \(Copy.hhmm(t.peakTime, site: site)) at \(Copy.peakHeight(t, site: site))").font(.caption).monospacedDigit().foregroundStyle(theme.bestLine)
                    if !item.clashes.isEmpty {
                        // The note sits under the chip, on the card's full width: beside it, it was squeezed into a column of one or two words a line
                        // (owner's recording, 29 October 2026).
                        VStack(alignment: .leading, spacing: 4) {
                            WarningChip(text: "Clash").fixedSize()   // one short word: never wrap it (it broke to "Cla / sh" on the iPhone Duo simulator)
                            Text("Same best time as \(item.clashes.map(\.catalogueID).joined(separator: ", "))").font(.caption).secondary().fixedSize(horizontal: false, vertical: true)
                        }.padding(.top, 4)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(PressStyle())
            Button { Haptic.impact(.medium); store.setInPlan(t.id, on: false, tomorrow: tomorrow) } label: {
                Text(item.added ? "Remove" : "Not tonight").font(.caption.weight(.medium)).padding(.horizontal, 10).frame(minHeight: 44)
                    .background(theme.track, in: RoundedRectangle(cornerRadius: 8))
            }.buttonStyle(PressStyle())
        }
        .padding(12).cardSurface()
    }
}
