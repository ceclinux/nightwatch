import SwiftUI
import SkyCore
import PhoneCore

/// Tonight's answer for the active site. Three layouts from one set of sections: one column (iPhone, Slide Over), a wide
/// portrait page (iPad upright) and three columns (iPad landscape).
public struct TonightScreen: View {
    let model: TonightModel
    let markData: Data?
    let offline: Bool
    /// When iOS said there was a connection but the forecast services did not answer: the reason, so "No connection" is not claimed untruly.
    var failure: String? = nil
    let refreshing: Bool
    let onRefresh: () -> Void
    var alertsPrompt: AlertsPrompt? = nil
    var now: Date = .now
    var visit: AnyView? = nil
    @Environment(\.phoneTheme) private var theme

    public init(model: TonightModel, markData: Data?, offline: Bool, refreshing: Bool, onRefresh: @escaping () -> Void,
                alertsPrompt: AlertsPrompt? = nil, now: Date = .now, visit: AnyView? = nil, failure: String? = nil) {
        self.failure = failure
        self.alertsPrompt = alertsPrompt; self.now = now; self.visit = visit
        self.model = model; self.markData = markData; self.offline = offline; self.refreshing = refreshing; self.onRefresh = onRefresh
    }

    private var snap: WidgetSnapshot { model.snapshot }
    private var clearNight: Bool { snap.window != nil }
    private var figureArt: (Data, Data)? {
        guard let id = model.figureID, let f = bundledArt("\(id)-figure", folder: "Constellations"), let p = bundledArt("\(id)-plot", folder: "Constellations") else { return nil }
        return (f, p)
    }

    // MARK: Sections

    /// "TONIGHT · MALHAM TARN" over the date and Bortle class, as the Mac's popover has it.
    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(model.overline).capsLabel().lineLimit(2)
            Text(model.dateLine).font(.caption).secondary()
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)   // a caption never needs to be as big as the verdict
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func verdict(_ scale: TonightHeroView.Scale) -> some View {
        TonightHeroView(snap: snap, hero: model.hero, scale: scale, figure: clearNight ? nil : figureArt)
    }

    /// Aurora, when alerts are on and it is at or above your level and under an hour old, naming its source and linking to it (AuroraWatch UK's
    /// terms ask for that). The level keeps the source's own colour, except in red mode, which has one hue.
    @ViewBuilder private var auroraRow: some View {
        if let line = snap.auroraLine(now: now), let a = snap.aurora {
            Link(destination: a.source.link) {
                HStack(spacing: 8) {
                    Circle().fill(theme.isRed ? theme.accent : Color(hex: line.hex)).frame(width: 10, height: 10).accessibilityHidden(true)
                    Text("\(line.text) · \(a.source.name)").font(.callout.weight(.medium)).foregroundStyle(theme.textPrimary)
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right").font(.footnote).secondary()
                }
                .padding(.horizontal, 12).frame(minHeight: 44)
                .cardSurface()
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("\(line.text), from \(a.source.name). Opens their page.")
        }
    }

    /// How far through the night it is now, from the hour bars and the site's clock; nil by day.
    private var nowFraction: Double? {
        guard let tz = TimeZone(identifier: model.timeZoneID) else { return nil }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
        let c = cal.dateComponents([.hour, .minute], from: now)
        guard let h = c.hour, let m = c.minute, let i = snap.bars.firstIndex(where: { $0.hour == String(format: "%02d", h) }) else { return nil }
        return (Double(i) + Double(m) / 60) / Double(snap.bars.count)
    }

    private var hours: some View {
        NightArc(bars: snap.bars, caption: snap.barsLabel, moonNote: model.hero.moonNote, nowFraction: nowFraction)
    }

    private func targets(height: CGFloat = 78, style: PicksSection.Style = .row, fills: Bool = false) -> some View {
        PicksSection(model: model, pictureHeight: height, style: style, fills: fills)
    }

    private var offlineNote: some View {
        Card {
            let age = ForecastAge(fetchedAt: model.fetchedAt, now: now).text
            Text(failure.map { "Couldn't read a new forecast: \($0). Showing the one from \(age). Trying again shortly." } ?? "No connection. Showing the forecast from \(age).")
                .font(.callout)
        }
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(theme.warning, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }

    @ViewBuilder private var tomorrowCard: some View {
        if let t = snap.tomorrow {
            Card {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TOMORROW NIGHT").capsLabel()
                    Text(t.hasPrefix("Tomorrow ") ? String(t.dropFirst(9)) : t).font(.callout).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// The ember alerts pill (until alerts are decided), then the source, update time and Refresh.
    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let alertsPrompt { alertsPrompt }
            SourceFooter(model: model, markData: markData, refreshing: refreshing, onRefresh: onRefresh)
        }
    }

    // MARK: Layouts

    public var body: some View {
        GeometryReader { geo in
            ScrollView {
                Group {
                    if geo.size.width >= 1100 { spacious(.large, width: geo.size.width) } else if geo.size.width >= 640 { spacious(.medium, width: geo.size.width) } else { compact }
                }
                .padding(geo.size.width >= 640 ? 28 : 16)
                .frame(maxWidth: 1400)
                .frame(maxWidth: .infinity)
                .frame(minHeight: geo.size.height, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background { StarField(seed: model.overline + model.dateLine).ignoresSafeArea() }
        .refreshable { onRefresh() }
    }

    private var compact: some View {
        VStack(alignment: .leading, spacing: 18) {
            if offline { offlineNote }
            header
            visit
            verdict(.compact)
            hours
            FactsRow(facts: model.hero.facts, columns: 2)
            auroraRow
            targets(style: .list)
            tomorrowCard
            footer
        }
    }

    /// An iPad page, upright or landscape: the hero over the hours, then the three cards taking whatever height is left, then the foot.
    private func spacious(_ scale: TonightHeroView.Scale, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            if offline { offlineNote }
            header
            visit
            verdict(scale)
            hours
            FactsRow(facts: model.hero.facts, columns: 4)
            auroraRow
            targets(height: scale == .large ? 150 : 200, fills: true)
            tomorrowCard
            footer
        }
    }
}
