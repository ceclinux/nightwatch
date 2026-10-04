import SwiftUI
import NightwatchUI
import SkyCore

/// The week ahead (owner-approved mock-up A, 30 September 2026): one row per night in date order, so the nights worth
/// going out on stand out and the best single night of the week is easy to pick. Tonight and tomorrow open their plans;
/// later nights are for choosing, not planning.
struct WeekView: View {
    @EnvironmentObject var store: Store
    let onOpenPlan: (_ tomorrow: Bool) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("The week ahead").font(.title2.weight(.semibold))
                if let s = store.site, !store.week.isEmpty {
                    let clear = store.week.filter { $0.plan.primary != nil }.count
                    Text("\(s.name) · the next \(store.week.count) nights · \(clear == 0 ? "none" : "\(clear)") with a clear window")
                        .font(.callout).foregroundStyle(Tokens.textSecondary)
                    if let run = store.moonlessRun {
                        Label(Copy.moonlessRun(run, site: s), systemImage: "circle").font(.callout).foregroundStyle(Tokens.textPrimary)
                    }
                    Text("Moon and darkness are worked out exactly for every night. Cloud comes from the forecast, which is less certain the further ahead it looks. Seeing and transparency are forecast for the next three nights only.")
                        .font(.caption).foregroundStyle(Tokens.textSecondary).fixedSize(horizontal: false, vertical: true)
                    VStack(spacing: 6) { ForEach(store.week, id: \.plan.night.key) { row($0, site: s) } }
                } else {
                    Text(store.lastError ?? "Waiting for the first forecast…").font(.callout).foregroundStyle(Tokens.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
    }

    private func row(_ n: WeekNight, site: Site) -> some View {
        let p = n.plan
        return HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Copy.weekDay(n, site: site)).font(.system(size: 14, weight: .semibold))
                Text(Copy.dayMonth(p.night.localDate, site: site)).font(.system(size: 11)).foregroundStyle(Tokens.textSecondary)
            }
            .frame(width: 96, alignment: .leading)
            ClearSkyBars(bars: Planner.clearSkyBars(plan: p, site: site), label: Copy.barsLabel(plan: p, site: site),
                         trackHeight: 28, labels: false, caption: false)
                .frame(width: 190)
            VStack(alignment: .leading, spacing: 3) {
                Text(Copy.weekVerdict(p, rule: store.config.goRule, bright: store.config.brightNights, site: site))
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(p.primary == nil ? Tokens.textSecondary : Tokens.textPrimary)
                Text(Copy.weekDetail(p, site: site)).font(.system(size: 11)).foregroundStyle(Tokens.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(Copy.weekLead(daysAhead: n.daysAhead) ?? "").font(.system(size: 11)).foregroundStyle(Tokens.textSecondary)
                .frame(width: 150, alignment: .trailing)
            Group {
                if n.daysAhead <= 1, p.primary != nil, store.config.showPlan {
                    Button("Open plan") { onOpenPlan(n.daysAhead == 1) }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityLabel("Open \(n.daysAhead == 1 ? "tomorrow night's" : "tonight's") plan")
                } else {
                    Color.clear
                }
            }
            .frame(width: 104, alignment: .trailing)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(Tokens.targetsCard, in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Tokens.cardOutline, lineWidth: 1))
    }
}
