import SwiftUI
import NightwatchUI
import SkyCore

/// The week ahead (owner-approved mock-up A, 30 September 2026): one row per night in date order, so the nights worth
/// going out on stand out and the best single night of the week is easy to pick. Tonight and tomorrow open their plans;
/// later nights are for choosing, not planning.
struct WeekView: View {
    @EnvironmentObject var store: Store
    let onOpenPlan: (_ tomorrow: Bool) -> Void
    @State private var width: CGFloat = 0

    /// How a night's row is laid out, from the width it has. The mock-up's row (a column each for the lead and the
    /// button) needs about 960 pt, and the window opens at 980 with 708 for this page, so it is not the usual form.
    private enum RowForm { case wide, compact, stacked }
    private var form: RowForm { width >= TextScale.pt(960) ? .wide : width >= TextScale.pt(640) ? .compact : .stacked }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("The week ahead").font(Font.scaled(.title2).weight(.semibold))
                if let s = store.site, !store.week.isEmpty {
                    let clear = store.week.filter { $0.plan.primary != nil }.count
                    Text("\(s.name) · the next \(store.week.count) nights · \(clear == 0 ? "none" : "\(clear)") with a clear window")
                        .font(Font.scaled(.callout)).foregroundStyle(Tokens.textSecondary)
                    if let run = store.moonlessRun {
                        Label(Copy.moonlessRun(run, site: s), systemImage: "circle").font(Font.scaled(.callout)).foregroundStyle(Tokens.textPrimary)
                    }
                    Text("Moon and darkness are worked out exactly for every night. Cloud comes from the forecast, which is less certain the further ahead it looks. Seeing and transparency are forecast for the next three nights only.")
                        .font(Font.scaled(.caption)).foregroundStyle(Tokens.textSecondary).fixedSize(horizontal: false, vertical: true)
                    VStack(spacing: 6) { ForEach(store.week, id: \.plan.night.key) { row($0, site: s) } }
                } else {
                    Text(store.lastError ?? "Waiting for the first forecast…").font(Font.scaled(.callout)).foregroundStyle(Tokens.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .padding(20)
        }
    }

    private func row(_ n: WeekNight, site: Site) -> some View {
        let p = n.plan
        let form = form
        let lead = Copy.weekLead(daysAhead: n.daysAhead)
        let day = VStack(alignment: .leading, spacing: 2) {
            Text(Copy.weekDay(n, site: site)).font(.system(size: TextScale.pt(14), weight: .semibold))
            Text(Copy.dayMonth(p.night.localDate, site: site)).font(.system(size: TextScale.pt(11))).foregroundStyle(Tokens.textSecondary)
        }
        .frame(width: TextScale.pt(96), alignment: .leading)
        let bars = ClearSkyBars(bars: Planner.clearSkyBars(plan: p, site: site), label: Copy.barsLabel(plan: p, site: site),
                                trackHeight: 28, labels: false, caption: false)
            .frame(width: TextScale.pt(190))
        // The wide form keeps the lead in a column of its own; the others put it under the detail.
        let words = VStack(alignment: .leading, spacing: 3) {
            Text(Copy.weekVerdict(p, rule: store.config.goRule, bright: store.config.brightNights, site: site))
                .font(.system(size: TextScale.pt(13), weight: .semibold)).foregroundStyle(p.primary == nil ? Tokens.textSecondary : Tokens.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(Copy.weekDetail(p, site: site)).font(.system(size: TextScale.pt(11))).foregroundStyle(Tokens.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if form != .wide, let lead {
                Text(lead).font(.system(size: TextScale.pt(11))).foregroundStyle(Tokens.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        let button = Group {
            if n.daysAhead <= 1, p.primary != nil, store.config.showPlan {
                Button("Open plan") { onOpenPlan(n.daysAhead == 1) }
                    .buttonStyle(SecondaryButtonStyle()).fixedSize()
                    .accessibilityLabel("Open \(n.daysAhead == 1 ? "tomorrow night's" : "tonight's") plan")
            }
        }
        return Group {
            switch form {
            case .wide:
                HStack(spacing: 18) {
                    day; bars; words
                    Text(lead ?? "").font(.system(size: TextScale.pt(11))).foregroundStyle(Tokens.textSecondary)
                        .frame(width: TextScale.pt(150), alignment: .trailing)
                    ZStack { button }.frame(width: TextScale.pt(104), alignment: .trailing)   // held open on rows without one
                }
            case .compact:
                HStack(spacing: 18) { day; bars; words; button }
            case .stacked:
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 18) { day; bars; Spacer(minLength: 0); button }
                    words
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(Tokens.targetsCard, in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Tokens.cardOutline, lineWidth: 1))
    }
}
