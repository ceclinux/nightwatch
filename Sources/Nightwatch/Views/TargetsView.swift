import SwiftUI
import NightwatchUI
import SkyCore

enum BrowserSection: Hashable { case group(TargetGroup), darkSites }

/// Asks the Targets window to show a section and, optionally, scroll to one dark-site card (the popover's Clearer sky line)
/// or open one target's detail (the widget). A nil section just brings the window forward as the user left it.
struct TargetsRequest: Equatable { let section: BrowserSection?; let siteID: String?; var targetID: String? = nil }

final class TargetsViewState: ObservableObject {
    @Published var section: BrowserSection = .group(.nebulae)
    @Published var fitsOnly = false
    @Published var includeMoonWashed = false
    @Published var search = ""
    @Published var selected: RankedTarget? = nil
    @Published var pendingScrollID: String? = nil
    @Published var sort: TargetSort = .bestNow
}

struct TargetsView: View {
    @EnvironmentObject var store: Store
    @StateObject private var ui = TargetsViewState()

    /// On a bright night only the Moon and planets are suggested, so they stand in for the ranked list.
    private var targets: [RankedTarget] { store.plan.map { $0.mode == .bright ? $0.brightTargets : $0.targets } ?? [] }

    private func count(_ g: TargetGroup) -> Int {
        g == .events ? store.events.count : targets.filter { $0.group == g }.count
    }

    private var selectedGroup: TargetGroup {
        if case .group(let g) = ui.section { return g }
        return .nebulae
    }

    private var sections: [BrowserSection] { TargetGroup.allCases.map { BrowserSection.group($0) } + [.darkSites] }


    /// The filtered, sorted cards at `now`. "Best now" sorts by altitude at that instant, so the grid passes a clock tick.
    private func visible(at now: Date) -> [RankedTarget] {
        guard case .group(let g) = ui.section, let site = store.site else { return [] }
        let shown = targets.filter { $0.group == g }
            .filter { !$0.hiddenByFit(fitsOnly: ui.fitsOnly) && !$0.hiddenByMoon(includeMoonWashed: ui.includeMoonWashed) }
            .filter { $0.matches(ui.search) }
        return Planner.sorted(shown, by: ui.sort, now: now, span: store.plan.flatMap { $0.primary ?? $0.darkSpan }, site: site)
    }

    var body: some View {
        NavigationSplitView {
            // The native sidebar list: v0.4's hand-built column of buttons drew its rows about two rows below where it took
            // clicks (owner, 25 September 2026: a click on Planets and Moon selected Constellations). The list also brings
            // the standard arrow keys, type-to-select and VoiceOver selection back.
            // The selection is applied just after the current view update. Publishing ui.section and ui.selected from inside
            // it ("Publishing changes from within view updates is not allowed") left the detail pane showing a stale page
            // while clicks landed on the real one (owner, 25 September 2026).
            List(sections, id: \.self, selection: Binding(get: { ui.section }, set: { s in
                guard let s else { return }
                DispatchQueue.main.async { ui.section = s; ui.selected = nil }
            })) { section in
                sidebarRow(section).tag(section)
            }
            .listStyle(.sidebar)
            .safeAreaInset(edge: .bottom) { filters }
            .navigationSplitViewColumnWidth(232)
        } detail: {
            if let selected = ui.selected {
                // A fresh page per target: a late image from the previous target's cancelled load can never land on this one.
                DetailView(target: selected) { ui.selected = nil }.id(selected.id)
            } else {
                switch ui.section {
                case .group(.events): eventsList
                case .darkSites: darkSitesList
                case .group: grid
                }
            }
        }
        .searchable(text: $ui.search, prompt: "M42, Orion, comet…")
        .preferredColorScheme(.dark)
        .background(Theme.bg)
        .onAppear { consumeRequest() }
        .onChange(of: store.targetsRequest) { _, _ in consumeRequest() }
    }

    private func sidebarRow(_ section: BrowserSection) -> some View {
        HStack {
            switch section {
            case .group(let g):
                Label(g.displayName, systemImage: Theme.glyph(for: g)); Spacer(); Text("\(count(g))").foregroundStyle(Tokens.textSecondary)
            case .darkSites:
                Label("Dark sites", systemImage: "moon.stars"); Spacer(); Text("\(store.darkSites.count)").foregroundStyle(Tokens.textSecondary)
            }
        }
        .font(.system(size: 12))
    }

    /// Toggles with the Moon line above them, so "Include Moon-washed" has context (follow-on 5).
    private var filters: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let p = store.plan, let s = store.site, let m = Planner.moonTonight(p), m != .down {
                HStack(spacing: 5) { WarningDot(size: 5); Text("Moon \(Int((p.moonIllumination * 100).rounded()))% · \(Copy.moonText(m, site: s).lowercased())") }
                    .font(.system(size: 10)).foregroundStyle(Tokens.statusWarning)
            }
            Toggle("Fits my field of view", isOn: $ui.fitsOnly)
            Toggle("Include Moon-washed", isOn: $ui.includeMoonWashed)
        }
        .toggleStyle(.switch).controlSize(.mini).tint(Tokens.controlOn).font(.system(size: 11)).padding(10)
    }

    /// Applies a pending request from the popover once, then clears it.
    private func consumeRequest() {
        guard let r = store.targetsRequest else { return }
        if let section = r.section {
            ui.section = section
            ui.pendingScrollID = r.siteID
            ui.selected = r.targetID.flatMap { id in targets.first { $0.id == id } }
        }
        store.targetsRequest = nil
    }

    private var darkSitesList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Text("Dark sites").font(.title2.weight(.semibold))
                HStack(spacing: 6) {
                    Text("Within \(Geo.format(km: store.config.darkSites.radiusKm, unit: store.distanceUnit)) of \(store.site?.name ?? "home") · sorted by tonight's score").foregroundStyle(Theme.dim)
                    if store.isAway { Button("Back to \(store.homeLabel)") { store.goHome() }.buttonStyle(.link) }
                }
                .font(.caption)
            }.frame(maxWidth: .infinity, alignment: .leading).padding([.horizontal, .top], 20)
            if !store.config.darkSites.enabled {
                Text("Dark sites are off. Turn them on in Settings › Dark sites.").foregroundStyle(Theme.dim).padding(20)
            } else if store.darkSites.isEmpty {
                Text("No dark sites within \(Geo.format(km: store.config.darkSites.radiusKm, unit: store.distanceUnit)). Widen the radius in Settings.")
                    .foregroundStyle(Theme.dim).padding(20)
            }
            ScrollViewReader { proxy in
                GlassGroup(spacing: 12) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                        ForEach(store.sitePlans) { DarkSiteCard(plan: $0).id($0.id) }
                        ForEach(store.darkSites.dropFirst(8)) { DarkSiteCard(plan: SitePlan.missing($0)).id($0.id) }
                    }.padding(20)
                }
                .onAppear { scroll(proxy) }
                .onChange(of: ui.pendingScrollID) { _, _ in scroll(proxy) }
            }
        }
    }

    private func scroll(_ proxy: ScrollViewProxy) {
        guard let id = ui.pendingScrollID else { return }
        withAnimation { proxy.scrollTo(id, anchor: .top) }
        ui.pendingScrollID = nil
    }

    private var grid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(selectedGroup.displayName).font(.title2.weight(.semibold))
                    Spacer()
                    Picker("Sort", selection: $ui.sort) {
                        ForEach(TargetSort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented).fixedSize()
                }
                if let p = store.plan, let s = store.site {
                    ClearSkyBars(bars: Planner.clearSkyBars(plan: p, site: s), label: Copy.barsLabel(plan: p, site: s), trackHeight: 14, labels: false).frame(maxWidth: 360)
                    if p.darkSpan == nil {
                        Text("No astronomical darkness tonight.").font(.caption).foregroundStyle(Tokens.textSecondary)
                    } else if p.primary == nil {
                        Text(store.copy.noWindow).font(.caption).foregroundStyle(Tokens.textSecondary)
                    }
                } else {
                    Text(store.lastError ?? "Waiting for the first forecast…").font(.caption).foregroundStyle(Tokens.textSecondary)
                }
                if store.isStale, let f = store.forecast { StaleBadge(fetchedAt: f.fetchedAt) }
                if store.plan?.mode == .bright, selectedGroup != .planets {
                    Text("Bright night: no deep-sky targets suggested.").font(.caption).foregroundStyle(Tokens.textSecondary)
                }
                if let hint = Copy.searchHint(query: ui.search, targets: targets, group: selectedGroup, fitsOnly: ui.fitsOnly,
                                              includeMoonWashed: ui.includeMoonWashed) {
                    Text(hint).font(.caption).foregroundStyle(Tokens.textSecondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding([.horizontal, .top], 20)
            GlassGroup(spacing: 12) {
                TimelineView(.periodic(from: .now, by: 300)) { clock in   // "Best now" re-sorts every five minutes
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                        ForEach(visible(at: clock.date)) { t in
                            Button { ui.selected = t } label: { card(t) }.buttonStyle(.plain)
                                .accessibilityLabel(store.site.map { Copy.cardLabel(t, lit: store.plan?.primary != nil, nearMoon: nearMoon(t), site: $0) } ?? t.name)
                        }
                    }.padding(20)
                }
            }
        }
    }

    private func nearMoon(_ t: RankedTarget) -> Bool {
        guard let p = store.plan else { return false }
        return t.isNearMoon(moonIllumination: p.moonIllumination, moonUpTonight: Planner.moonTonight(p).map { $0 != .down } ?? false)
    }

    private func chips(_ t: RankedTarget) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            if !ui.fitsOnly { Chip(text: Copy.frameChip(t), icon: "viewfinder") }
            if t.moonWashed { Chip(text: "Moon-washed", icon: "moon.fill", warning: true) }
            else if nearMoon(t) { Chip(text: "Near Moon", icon: "moon.fill", warning: true) }
        }
    }

    private func card(_ t: RankedTarget) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ThumbnailView(target: t).frame(height: 110).overlay(alignment: .topTrailing) { chips(t).padding(8) }
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(t.catalogueID).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Tokens.textPrimary).fixedSize()
                Text(t.cardLine).font(.system(size: 11.5)).foregroundStyle(Tokens.textSecondary).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 4)
                Text(t.magnitude.map { String(format: "mag %.1f", $0) } ?? "mag –").font(.system(size: 9)).foregroundStyle(Tokens.textSecondary).fixedSize()
            }
            if let s = store.site, let p = store.plan, let track = p.primary ?? p.darkSpan {
                ViewabilityTimeline(target: t, track: track, lit: p.primary != nil, site: s)
            }
        }
        .padding(10)
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Tokens.targetsTrack, lineWidth: 1))
        .nightwatchGlass(in: RoundedRectangle(cornerRadius: 9), fill: Tokens.targetsCard)
    }

    private var eventsList: some View {
        List(store.events) { e in
            HStack {
                Image(systemName: e.kind == .issPass ? "airplane" : (e.kind == .meteorShower ? "sparkle" : (e.kind == .comet ? "comet" : "moon.stars"))).foregroundStyle(Theme.accent)
                VStack(alignment: .leading) {
                    Text(e.title).font(.callout.weight(.semibold))
                    Text(e.detail).font(.caption).foregroundStyle(Theme.dim)
                }
                Spacer()
                if let s = store.site { Text(e.kind == .lunarEclipse || e.kind == .solarEclipse ? e.time.formatted(date: .abbreviated, time: .shortened) : Copy.hhmm(e.time, site: s)).font(.caption).foregroundStyle(Theme.dim) }
            }.padding(.vertical, 4)
        }
        .overlay { if store.events.isEmpty { Text("No events tonight").foregroundStyle(Theme.dim) } }
    }
}

struct DarkSiteCard: View {
    @EnvironmentObject var store: Store
    let plan: SitePlan
    var body: some View {
        let s = plan.site
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(s.name).font(.callout.weight(.semibold)).lineLimit(2)
                Spacer()
                if !plan.forecastMissing { Text("\(plan.score)").font(.title3.weight(.semibold)).foregroundStyle(plan.qualifies ? Theme.accent : Theme.dim) }
            }
            Text("\(Geo.format(km: s.distanceKm, unit: store.distanceUnit)) \(s.compass) · \(s.kind.capitalized)" + (s.bortle.map { " · Bortle \($0)" } ?? s.band.map { " · \($0.displayName)" } ?? ""))
                .font(.caption).foregroundStyle(Theme.dim)
            // Compared with home, not with whichever site is active: while away, "at home" would be the wrong place (v0.6.5).
            if let home = store.homeSite {
                let siteSky = s.bortle.map { "Bortle \($0)" } ?? s.band?.displayName ?? "darkness unknown"
                let atHome = store.isAway ? "at \(store.homeLabel) (home)" : "at home"
                if !plan.forecastMissing, let hp = store.homePlan {
                    Text("Score \(plan.score) vs \(hp.score) \(atHome) · \(siteSky), home Bortle \(home.bortle)")
                        .font(.caption).foregroundStyle(plan.score >= hp.score + 20 ? Theme.accent : Theme.dim)
                } else {
                    Text("\(siteSky), home Bortle \(home.bortle)").font(.caption).foregroundStyle(Theme.dim)
                }
            }
            if let w = plan.primary, let home = store.site {
                Text("Clear \(Copy.hhmm(w.start, site: home))–\(Copy.hhmm(w.end, site: home)) · \(String(format: "%.1f h", w.hours))").font(.caption)
            } else if plan.forecastMissing {
                Text("No forecast fetched (beyond the nearest eight, or offline)").font(.caption).foregroundStyle(Theme.dim)
            } else {
                Text(store.copy.noWindow).font(.caption).foregroundStyle(Theme.dim)
            }
            HStack {
                if let src = s.source, let url = URL(string: src) { Link("Source", destination: url).font(.caption) }
                Spacer()
                // Plain in both wording modes: "Use as beat" lost people (owner, 25 September 2026).
                Button("Observe from here") { store.visit(s) }.font(.caption)
            }
        }
        .padding(12)
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Tokens.targetsTrack, lineWidth: 1))
        .nightwatchGlass(in: RoundedRectangle(cornerRadius: 9), fill: Tokens.targetsCard)
    }
}
