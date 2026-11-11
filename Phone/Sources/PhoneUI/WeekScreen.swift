import SwiftUI
import SkyCore
import PhoneCore

/// The week ahead: one row per night with its hour-by-hour clear sky, a verdict and a detail line, as on the Mac. Nights further out are
/// marked less certain; the nights past the forecast's end are left out.
struct WeekScreen: View {
    @ObservedObject var store: PhoneStore
    var onOpenPlan: (Bool) -> Void = { _ in }
    @State private var moonless: String?
    @Environment(\.phoneTheme) private var theme

    var body: some View {
        let week = store.planning?.week ?? []
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let run = moonless { Text(run).font(.callout).secondary() }
                ForEach(week, id: \.daysAhead) { n in row(n).risesIn(n.daysAhead) }
                if week.isEmpty { EmptyState(title: "No week yet", message: "The forecast has not reached beyond tonight.") }
            }
            .padding(16).frame(maxWidth: 800).frame(maxWidth: .infinity)
        }
        .background { StarField(seed: "week", calm: true).ignoresSafeArea() }
        // Sixty nights of Moon maths: worked out once, off the main thread, and again only when the night or the site changes.
        .task(id: "\(store.planning?.tonight.night.key ?? "")|\(store.site?.name ?? "")") {
            guard let site = store.site, let night = store.planning?.tonight.night else { return }
            moonless = await Task.detached { MoonCalendar.nextRun(from: night, site: site).map { Copy.moonlessRun($0, site: site).plainDashes } }.value
        }
    }

    @ViewBuilder private func row(_ n: WeekNight) -> some View {
        if let site = store.site {
            let bars = Planner.clearSkyBars(plan: n.plan, site: site)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(Copy.weekDay(n, site: site).plainDashes).font(.title3.weight(.heavy))
                    Spacer()
                    if let lead = Copy.weekLead(daysAhead: n.daysAhead) { Text(lead.plainDashes).font(.caption).secondary() }
                }
                ClearSkyBarsView(bars: bars, caption: Copy.barsLabel(plan: n.plan, site: site), trackHeight: 26)
                Text(Copy.weekVerdict(n.plan, rule: store.config.goRule, bright: store.config.brightNights, site: site).plainDashes).font(.callout.weight(.bold))
                Text(Copy.weekDetail(n.plan, site: site).plainDashes).font(.footnote).secondary()
                if n.daysAhead <= 1, n.plan.primary != nil {
                    Button { onOpenPlan(n.daysAhead == 1) } label: {
                        Text(n.daysAhead == 0 ? "Open tonight's plan" : "Open tomorrow's plan").font(.footnote.weight(.medium))
                            .padding(.horizontal, 12).frame(minHeight: 44).background(theme.track, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.glassHairline, lineWidth: 1))
                    }.buttonStyle(PressStyle())
                }
            }
            .padding(14).cardSurface()
            .accessibilityElement(children: .contain)
        }
    }
}
