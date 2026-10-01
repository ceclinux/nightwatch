import SwiftUI
import NightwatchUI
import SkyCore

/// Tonight's plan as a page of its own in the Targets window (#57, redesigned from the owner's UAT and approved mock-up,
/// 29 September 2026): the user's favourites that are up in the clear window, plus anything added for the night, in order
/// of their best time. "Not tonight" takes one off for that night; the choice is saved with the settings, so it syncs and
/// is still there when the night planned as tomorrow becomes tonight.
struct PlanView: View {
    @EnvironmentObject var store: Store
    /// The night shown: tonight, or tomorrow night while it is chosen.
    let plan: NightPlan?
    let canPlanTomorrow: Bool
    @Binding var tomorrow: Bool
    let onSelect: (RankedTarget) -> Void

    private var isTomorrow: Bool { plan != nil && plan?.night.key != store.plan?.night.key }
    private var session: SessionPlan? { store.session(for: plan) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(isTomorrow ? "Tomorrow night's plan" : "Tonight's plan").font(.title2.weight(.semibold))
                if canPlanTomorrow {
                    Picker("Night", selection: $tomorrow) { Text("Tonight").tag(false); Text("Tomorrow night").tag(true) }
                        .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
    }

    @ViewBuilder private var content: some View {
        if let p = plan, let s = store.site {
            if let session {
                Text(Copy.planSummary(session, plan: p, site: s)).font(.callout).foregroundStyle(Tokens.textSecondary)
                if session.items.isEmpty && session.takenOff.isEmpty && session.omitted.isEmpty {
                    empty
                } else {
                    Text("Your favourites that are up in the clear window, in order of their best time. Take off any you'll skip \(isTomorrow ? "tomorrow night" : "tonight"): your choices are kept for this night, even if you make them the day before.")
                        .font(.callout).foregroundStyle(Tokens.textSecondary).fixedSize(horizontal: false, vertical: true)
                    // Each target keeps its line style from night to night (owner, 1 October 2026).
                    let styles = ChartLayout.styles(for: session.items.map(\.target.id), count: PlanLineStyle.all.count)
                    if !session.items.isEmpty {
                        PlanChart(items: session.items, night: p.night, window: p.primary ?? session.window, minAltitude: store.config.goRule.minAltitudeDeg,
                                  site: s, nightWords: isTomorrow ? "tomorrow night" : "tonight", styles: styles)
                    }
                    VStack(spacing: 8) { ForEach(Array(session.items.enumerated()), id: \.element.id) { i, item in row(item, index: styles[item.target.id] ?? i, night: p.night.key, site: s) } }
                    if session.items.isEmpty {
                        Text("Nothing left in the plan for this night.").font(.callout).foregroundStyle(Tokens.textSecondary)
                    }
                    others(session, night: p.night.key, site: s)
                    Text("Heart a target to keep it in every plan, or use Add to plan on its page for one night only.")
                        .font(.caption).foregroundStyle(Tokens.textSecondary)
                }
            } else if p.mode == .bright {
                note("A bright night: the plan is for dark, clear nights. The Moon and planets are in Targets.")
            } else if p.primary == nil, canPlanTomorrow, let w = store.tomorrow?.primary {
                note("\(store.copy.noWindow) Tomorrow night looks clear \(Copy.span(w.start, w.end, site: s)): choose Tomorrow night above to plan it.")
            } else if p.primary == nil {
                note(isTomorrow ? "No clear window forecast for tomorrow night." : store.copy.noWindow)
            } else {
                note("Your finish time comes before \(isTomorrow ? "tomorrow night's" : "tonight's") clear window opens.")
            }
        } else {
            note(store.lastError ?? "Waiting for the first forecast…")
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.callout).foregroundStyle(Tokens.textSecondary).fixedSize(horizontal: false, vertical: true)
    }

    /// No favourites and nothing added: what the plan is made from.
    private var empty: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart").font(.system(size: 34)).foregroundStyle(Tokens.textSecondary).accessibilityHidden(true)
            Text("Your plan is made from your favourites").font(.headline)
            Text("Heart the targets you want to image. Each night, the ones up in the clear window appear here in order of their best time, and you choose which to keep.")
                .font(.callout).foregroundStyle(Tokens.textSecondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            Button("Browse tonight's targets") { store.targetsRequest = TargetsRequest(section: .group(.nebulae), siteID: nil) }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: 460).frame(maxWidth: .infinity).padding(.top, 40)
    }

    private func row(_ item: PlanItem, index: Int, night: String, site: Site) -> some View {
        let t = item.target
        return HStack(spacing: 16) {
            HStack(spacing: 16) {
                PlanLineKey(index: index)
                Text(Copy.hhmm(t.peakTime, site: site)).font(.system(size: 18, weight: .semibold)).monospacedDigit().frame(width: 58, alignment: .leading)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(t.catalogueID.isEmpty ? t.name : t.catalogueID).font(.system(size: 14, weight: .semibold))
                        if !t.catalogueID.isEmpty, t.cardName != t.catalogueID { Text(t.cardName).font(.system(size: 14)).foregroundStyle(Tokens.textSecondary) }
                    }
                    Text(Copy.planDetail(item, presetID: store.config.fovPresetID, site: site))
                        .font(.system(size: 12)).foregroundStyle(Tokens.textSecondary).fixedSize(horizontal: false, vertical: true)
                    if let clash = Copy.planClash(item) {
                        HStack(spacing: 6) {
                            Circle().fill(Tokens.statusWarning).frame(width: 6, height: 6).accessibilityHidden(true)
                            Text(clash).font(.system(size: 12)).foregroundStyle(Tokens.statusWarning)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
            .onTapGesture { onSelect(t) }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onSelect(t) }
            Button("Not \(isTomorrow ? "tomorrow" : "tonight")") { store.setInPlan(t.id, false, night: night) }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityLabel("Take \(t.name) off the plan")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Tokens.targetsCard, in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Tokens.cardOutline, lineWidth: 1))
    }

    /// Taken off for this night, and favourites that cannot be in it, side by side.
    @ViewBuilder private func others(_ session: SessionPlan, night: String, site: Site) -> some View {
        if !session.takenOff.isEmpty || !session.omitted.isEmpty {
            HStack(alignment: .top, spacing: 16) {
                if !session.takenOff.isEmpty {
                    group(isTomorrow ? "TAKEN OFF TOMORROW NIGHT" : "TAKEN OFF TONIGHT") {
                        ForEach(session.takenOff) { t in
                            HStack {
                                Text("\(t.name) · best \(Copy.hhmm(t.peakTime, site: site))").font(.system(size: 13)).foregroundStyle(Tokens.textSecondary)
                                Spacer()
                                Button("Put back") { store.setInPlan(t.id, true, night: night) }
                                    .buttonStyle(.plain).foregroundStyle(Tokens.controlOn).font(.system(size: 13))
                                    .accessibilityLabel("Put \(t.name) back in the plan")
                            }
                        }
                    }
                }
                if !session.omitted.isEmpty {
                    group("FAVOURITES NOT IN THE PLAN") {
                        ForEach(session.omitted) { o in
                            Text("\(o.target.name) · \(o.reason.prefix(1).lowercased() + o.reason.dropFirst())")
                                .font(.system(size: 13)).foregroundStyle(Tokens.textSecondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private func group<C: View>(_ title: String, @ViewBuilder _ rows: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 11, weight: .semibold)).tracking(0.6).foregroundStyle(Tokens.textSecondary)
            VStack(alignment: .leading, spacing: 6) { rows() }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Tokens.targetsCard, in: RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(Tokens.cardOutline, lineWidth: 1))
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
