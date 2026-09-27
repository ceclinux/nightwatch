import SwiftUI
import NightwatchUI
import SkyCore

/// An event's page (v1.0.1): what it is, when and where to look, whether tonight is clear for it, and how to shoot it.
struct EventDetailView: View {
    @EnvironmentObject var store: Store
    let event: SkyEvent
    let onBack: () -> Void
    private static let presets = (try? TelescopePresets.bundled()) ?? []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Button(action: onBack) { Label("Events", systemImage: "chevron.left") }.buttonStyle(.plain).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title).font(.system(size: 24, weight: .semibold))
                    Text(event.detail).font(.system(size: 13)).foregroundStyle(Theme.text.opacity(0.85))
                    if let c = event.clear {
                        Chip(text: c ? "Clear then" : "Cloudy then", icon: c ? "checkmark" : "cloud.fill", warning: !c).padding(.top, 4)
                    }
                }
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    ForEach(event.facts, id: \.label) { f in
                        GridRow {
                            Text(f.label).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.dim)
                            Text(f.value).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if let s = store.site {
                    let preset = Self.presets.first { $0.id == store.config.fovPresetID }
                    let tip = ShootingTips.tip(for: event, fov: store.config.fov, presetName: preset?.name, site: s)
                    VStack(alignment: .leading, spacing: 8) {
                        Label(tip.title, systemImage: "camera.aperture").font(.system(size: 13, weight: .semibold))
                        ForEach(tip.rows, id: \.label) { r in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(r.label).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.dim).frame(width: 70, alignment: .leading)
                                Text(r.text).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(14)
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Tokens.targetsTrack, lineWidth: 1))
                }
            }
            .frame(maxWidth: 620, alignment: .leading)
            .padding(24)
        }
        .foregroundStyle(Theme.text)
    }
}
