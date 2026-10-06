import SwiftUI
import AppKit
import NightwatchUI
import SkyCore

/// An event's page (v1.0.1), laid out as a target's page is: the picture fills the space above a black caption box with the
/// title, the facts and "How to shoot this". The picture is the event's artwork, the radiant's constellation for a meteor
/// shower, and a drawing of the pass across the sky for the ISS (owner's choices, 27 September 2026).
struct EventDetailView: View {
    @EnvironmentObject var store: Store
    let event: SkyEvent
    let onBack: () -> Void
    @StateObject private var tipsUI = TipsState()
    private static let presets = (try? TelescopePresets.bundled()) ?? []

    var body: some View {
        DetailPage(back: "Events", onBack: onBack) {
            EmptyView()
        } hero: { _ in
            hero
        } tips: {
            tips
        } title: {
            titleBlock
        } stats: {
            facts
        }
    }

    @ViewBuilder private var hero: some View {
        if event.kind == .occultation, let o = event.occultation, let s = store.site {
            OccultationView(occultation: o, site: s).frame(maxWidth: 520, maxHeight: 420)
        } else if event.kind == .issPass, !event.path.isEmpty, let s = store.site {
            SkyPathView(path: event.path, site: s).frame(maxWidth: 420, maxHeight: 420)
        } else if event.kind == .meteorShower, let id = event.radiantConstellation, let art = ConstellationArt(id: id) {
            art
        } else {
            EventArt(kind: event.kind).clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder private var tips: some View {
        if tipsUI.shown, let s = store.site {
            let preset = Self.presets.first { $0.id == store.config.fovPresetID }
            ShootingTipCard(tip: ShootingTips.tip(for: event, fov: store.config.fov, presetName: preset?.name, site: s))
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(event.title).font(.system(size: TextScale.pt(24), weight: .semibold)).lineLimit(2)
            Text(event.detail).font(.system(size: TextScale.pt(13))).foregroundStyle(Theme.text.opacity(0.85)).frame(maxWidth: 420, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            EventChips(event: event, onPage: true).padding(.top, 2)
            if let s = store.site {
                HStack(spacing: 8) {
                    HowToShootButton(shown: $tipsUI.shown).help("How to photograph this event")
                    Button { addToCalendar(site: s) } label: {
                        HStack(spacing: 5) { Image(systemName: "calendar.badge.plus").accessibilityHidden(true); Text("Add to Calendar") }
                    }
                    .captionButton().padding(.top, 4)
                }
            }
        }
    }

    private func addToCalendar(site: Site) { CalendarExport.open(event, site: site) }

    private var facts: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
            ForEach(event.facts, id: \.label) { f in
                GridRow {
                    Text(f.label).font(.system(size: TextScale.pt(11))).foregroundStyle(Theme.dim)
                    Text(f.value).font(.system(size: TextScale.pt(12))).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// "Add to Calendar" (v1.1): the event as an iCalendar file, handed to the Mac's calendar app, which asks which calendar.
/// Shared by an event's page and the Events page's "Coming up".
enum CalendarExport {
    @MainActor static func open(_ e: SkyEvent, site: Site) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(e.title.replacingOccurrences(of: "/", with: "-")).ics")
        guard (try? CalendarFile.ics(for: e, site: site).write(to: url, atomically: true, encoding: .utf8)) != nil else { return }
        NSWorkspace.shared.open(url)
    }
}
