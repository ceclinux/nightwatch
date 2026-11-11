import SwiftUI
import SkyCore
import PhoneCore

/// A target's page: its picture, the figures, tonight's altitude, how to shoot it, and the heart and plan buttons.
struct TargetDetailScreen: View {
    @ObservedObject var store: PhoneStore
    let target: RankedTarget
    /// Opened from Eyes and binoculars: how to see it, in place of the telescope settings.
    var eye: EyeView? = nil
    @Environment(\.phoneTheme) private var theme
    private static let constellations = (try? Constellations.bundled()) ?? []
    private var isCatalogue: Bool { !MilkyWay.isMilkyWay(target.id) }

    var body: some View {
        let plan = store.planning?.tonight
        let site = store.site
        let pick = site.map { TargetPick.make(target, site: $0, fov: store.config.fov) }
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let pick {
                    TargetPicture(pick: pick, sharp: site.flatMap { TargetPick.sharp(target, site: $0, fov: store.config.fov) }).frame(height: 220).clipShape(RoundedRectangle(cornerRadius: 16))
                }
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(target.catalogueID).font(.title2.weight(.semibold))
                        Text(target.commonName ?? target.typeName).font(.callout).secondary()
                        Text(target.subtitle.plainDashes).font(.footnote).secondary()
                    }
                    Spacer()
                    if isCatalogue { HeartButton(store: store, id: target.id) }
                }
                HStack(spacing: 10) {
                    if let site {
                        stat("Best", "\(Copy.hhmm(target.peakTime, site: site))")
                        stat("Up to", Copy.peakHeight(target, site: site))
                    }
                    if let m = target.magnitude { stat("Magnitude", String(format: "%.1f", m)) }
                    stat("Moon", "\(Int(target.moonSepDeg.rounded()))° away")
                }
                if let plan, let site, let win = plan.primary {
                    Card { AltitudeChart(lines: AltitudeChart.lines(for: [target], night: plan.night, window: win, site: site,
                                                                    floor: store.config.goRule.minAltitudeDeg),
                                         night: plan.night, window: win, floor: store.config.goRule.minAltitudeDeg, site: site, height: 140) }
                }
                if isCatalogue, let plan, plan.primary != nil { planButton }
                if let site {
                    if let eye {
                        let abbr = target.subtitle.components(separatedBy: " in ").last ?? ""
                        let moonUp = plan.flatMap(Planner.moonTonight).map { $0 != .down } ?? false
                        ShootingTipCard(tip: ShootingTips.eyeTip(for: target, eye: eye, constellation: Self.constellations.first { $0.id == abbr }?.name,
                                                                moonIllumination: plan?.moonIllumination ?? 0, moonUp: moonUp, site: site))
                    } else {
                        ShootingTipCard(tip: ShootingTips.tip(for: target, presetID: store.config.fovPresetID, presetName: nil, stackMinutes: nil, site: site))
                    }
                }
            }
            .padding(16).frame(maxWidth: 700).frame(maxWidth: .infinity)
        }
        .background { StarField(seed: target.id, calm: true).ignoresSafeArea() }
        .navigationTitle(target.catalogueID)
        .navigationBarTitleDisplayModeInline()
    }

    private var planButton: some View {
        let inPlan = store.isInPlan(target.id)
        return PrimaryButton(title: inPlan ? "Take off tonight's plan" : "Add to tonight's plan") {
            store.setInPlan(target.id, on: !inPlan)
            if inPlan { Haptic.impact(.medium) } else { Haptic.success() }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).secondary()
            Text(value).font(.callout.weight(.medium)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading).background(theme.tile, in: RoundedRectangle(cornerRadius: 10))
    }
}
