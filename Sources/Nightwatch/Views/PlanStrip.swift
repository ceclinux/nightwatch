import SwiftUI
import NightwatchUI
import SkyCore

/// Tonight's plan above the Targets grid (#57, owner-approved mock-up, 29 September 2026): the running order for the clear
/// window, a bar of its slots, the time left, and a note when it outlasts the telescope's battery. Browsing below is unchanged.
struct PlanStrip: View {
    @EnvironmentObject var store: Store
    let plan: NightPlan
    let session: SessionPlan
    let site: Site
    let constellations: [Constellation]
    /// Three, or two in a narrow window (#60).
    var columns = 3
    let onSelect: (RankedTarget) -> Void

    private var title: String { plan.night.key == store.plan?.night.key ? "Tonight's plan" : "Tomorrow night's plan" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Spacer()
                if let w = plan.primary {
                    Text(Copy.planHeader(session, window: w, site: site)).font(.caption).foregroundStyle(Tokens.textSecondary)
                }
            }
            bar
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: columns), alignment: .leading, spacing: 10) {
                ForEach(Array(session.slots.enumerated()), id: \.element.id) { i, slot in slotCard(slot, index: i) }
            }
            if let left = Copy.planLeftover(session, site: site) {
                Text(left).font(.caption).foregroundStyle(Tokens.textSecondary)
            }
            if let note = Copy.planBattery(session, telescope: store.telescope?.name ?? "telescope") {
                Text(note).font(.caption).foregroundStyle(Tokens.textPrimary)
            }
        }
        .padding(14)
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Tokens.cardOutline, lineWidth: 1))
        .nightwatchGlass(in: RoundedRectangle(cornerRadius: 11), fill: Tokens.targetsCard)
    }

    /// The slots, any waits between them, then any time left, in proportion.
    private var bar: some View {
        var parts: [(Double, Color)] = []
        for (i, s) in session.slots.enumerated() {
            if i > 0, s.start > session.slots[i - 1].end { parts.append((s.start.timeIntervalSince(session.slots[i - 1].end), Tokens.targetsTrack)) }
            parts.append((s.end.timeIntervalSince(s.start), Tokens.accentClear.opacity(1 - 0.2 * Double(min(i, 3)))))
        }
        if let l = session.leftover { parts.append((l.end.timeIntervalSince(l.start), Tokens.targetsTrack)) }
        let total = max(1, parts.map(\.0).reduce(0, +))
        return GeometryReader { g in
            HStack(spacing: 4) {
                ForEach(parts.indices, id: \.self) { k in
                    RoundedRectangle(cornerRadius: 3).fill(parts[k].1)
                        .frame(width: max(4, (g.size.width - 4 * CGFloat(parts.count - 1)) * parts[k].0 / total))
                }
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)   // the slots below say the same in words
    }

    private func slotCard(_ slot: PlanSlot, index: Int) -> some View {
        let t = slot.target
        return HStack(alignment: .top, spacing: 10) {
            Text("\(index + 1)").font(.system(size: 18, weight: .semibold)).foregroundStyle(Tokens.accentClear).frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text("\(Copy.span(slot.start, slot.end, site: site)) · \(t.catalogueID)").font(.system(size: 12, weight: .semibold))
                    if let n = t.cardNote { Text(n).font(.system(size: 12)).foregroundStyle(Tokens.textSecondary) }
                }
                HStack(spacing: 5) {
                    if store.config.favourites.contains(t.id) {
                        Image(systemName: "heart.fill").font(.system(size: 10)).foregroundStyle(Tokens.accentClear).accessibilityLabel("Favourite")
                    }
                    Text(Copy.slotName(t, constellations: constellations)).font(.system(size: 12)).lineLimit(1)
                }
                Text(Copy.slotDetail(slot, index: index, presetID: store.config.fovPresetID, site: site))
                    .font(.system(size: 10.5)).foregroundStyle(Tokens.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { onSelect(t) }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onSelect(t) }
            Button { store.setInPlan(t.id, false, night: plan.night.key) } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Tokens.textSecondary)
                    .frame(width: 28, height: 28).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(t.catalogueID) from the plan")
        }
        .padding(10)
        .background(Tokens.targetsBackground, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Tokens.cardOutline, lineWidth: 1))
    }
}
