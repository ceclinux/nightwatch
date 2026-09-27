import SwiftUI
import NightwatchUI
import SkyCore

enum BrowserSection: Hashable { case favourites, group(TargetGroup), darkSites }

/// Asks the Targets window to show a section and, optionally, scroll to one dark-site card (the popover's Clearer sky line)
/// or open one target's detail (the widget). A nil section just brings the window forward as the user left it.
struct TargetsRequest: Equatable { let section: BrowserSection?; let siteID: String?; var targetID: String? = nil }

final class TargetsViewState: ObservableObject {
    @Published var section: BrowserSection = .group(.nebulae)
    @Published var fitsOnly = false
    @Published var includeMoonWashed = false
    @Published var search = ""
    @Published var selected: RankedTarget? = nil
    @Published var selectedEvent: SkyEvent? = nil
    @Published var pendingScrollID: String? = nil
    @Published var sort: TargetSort = .bestNow
    @Published var eventSort: EventSort = .time
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

    private var sections: [BrowserSection] { [.favourites] + TargetGroup.allCases.map { BrowserSection.group($0) } + [.darkSites] }

    private var favourites: [FavouriteTarget] { store.plan?.favourites ?? [] }


    /// The filtered, sorted cards at `now`. "Best now" sorts by altitude at that instant, so the grid passes a clock tick.
    /// Favourites ignore the two filters, since every favourite is always shown: usable ones sorted, then the greyed rest.
    private func visible(at now: Date) -> [FavouriteTarget] {
        guard let site = store.site else { return [] }
        let span = store.plan.flatMap { $0.primary ?? $0.darkSpan }
        switch ui.section {
        case .favourites:
            let found = favourites.filter { $0.target.matches(ui.search) }
            let usable = Planner.sorted(found.filter { $0.notTonight == nil }.map(\.target), by: ui.sort, now: now, span: span, site: site)
            return usable.map { FavouriteTarget(target: $0, notTonight: nil) } + found.filter { $0.notTonight != nil }
        case .group(let g):
            let shown = targets.filter { $0.group == g }
                .filter { !$0.hiddenByFit(fitsOnly: ui.fitsOnly) && !$0.hiddenByMoon(includeMoonWashed: ui.includeMoonWashed) }
                .filter { $0.matches(ui.search) }
            return Planner.sorted(shown, by: ui.sort, now: now, span: span, site: site).map { FavouriteTarget(target: $0, notTonight: nil) }
        case .darkSites:
            return []
        }
    }

    private func isFavourite(_ t: RankedTarget) -> Bool { store.config.favourites.contains(t.id) }

    private func toggleFavourite(_ t: RankedTarget) { store.config.toggleFavourite(t.id); store.saveConfig() }

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
                DispatchQueue.main.async { ui.section = s; ui.selected = nil; ui.selectedEvent = nil }
            })) { section in
                sidebarRow(section).tag(section)
            }
            .listStyle(.sidebar)
            .safeAreaInset(edge: .bottom) { filters }
            .navigationSplitViewColumnWidth(232)
        } detail: {
            if let ev = ui.selectedEvent {
                // The live copy, so a refresh updates the open page; the one clicked if the event has since gone.
                EventDetailView(event: store.events.first { $0.id == ev.id } ?? ev) { ui.selectedEvent = nil }.id(ev.id)
            } else if let selected = ui.selected {
                // A fresh page per target: a late image from the previous target's cancelled load can never land on this one.
                DetailView(target: selected) { ui.selected = nil }.id(selected.id)
            } else {
                switch ui.section {
                case .darkSites: darkSitesList
                case .group, .favourites: grid
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
            case .favourites:
                Label("Favourites", systemImage: "heart.fill"); Spacer(); Text("\(favourites.count)").foregroundStyle(Tokens.textSecondary)
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
            // Only where they filter something: not on Events, Dark sites or Favourites (which shows every favourite).
            if case .group(let g) = ui.section, g != .events {
                Toggle("Fits my field of view", isOn: $ui.fitsOnly)
                Toggle("Include Moon-washed", isOn: $ui.includeMoonWashed)
            }
        }
        .toggleStyle(.switch).controlSize(.mini).tint(Tokens.controlOn).font(.system(size: 11)).padding(10)
    }

    /// Applies a pending request from the popover once, then clears it.
    private func consumeRequest() {
        guard let r = store.targetsRequest else { return }
        if let section = r.section {
            ui.section = section
            ui.pendingScrollID = r.siteID
            ui.selected = r.targetID.flatMap { id in (targets + favourites.map(\.target)).first { $0.id == id } }
            ui.selectedEvent = nil   // an open event page would hide the requested target
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
                    Text(ui.section == .favourites ? "Favourites" : selectedGroup.displayName).font(.title2.weight(.semibold))
                    Spacer()
                    if isEvents {
                        Picker("Sort", selection: $ui.eventSort) {
                            ForEach(EventSort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented).fixedSize()
                    } else {
                        Picker("Sort", selection: $ui.sort) {
                            ForEach(TargetSort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented).fixedSize()
                    }
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
                if store.plan?.mode == .bright, ui.section != .favourites, !isEvents, selectedGroup != .planets {
                    Text("Bright night: no deep-sky targets suggested.").font(.caption).foregroundStyle(Tokens.textSecondary)
                }
                if ui.section == .favourites {
                    if favourites.isEmpty {
                        Text("No favourites yet. Click the heart on any target to add it here.").font(.caption).foregroundStyle(Tokens.textSecondary)
                    } else if !favourites.contains(where: { $0.target.matches(ui.search) }) {
                        Text("No favourite matches “\(ui.search.trimmingCharacters(in: .whitespaces))”.").font(.caption).foregroundStyle(Tokens.textSecondary)
                    }
                } else if isEvents {
                    EmptyView()
                } else if let hint = Copy.searchHint(query: ui.search, targets: targets, group: selectedGroup, fitsOnly: ui.fitsOnly,
                                                     includeMoonWashed: ui.includeMoonWashed) {
                    Text(hint).font(.caption).foregroundStyle(Tokens.textSecondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding([.horizontal, .top], 20)
            GlassGroup(spacing: 12) {
                TimelineView(.periodic(from: .now, by: 300)) { clock in   // "Best now" re-sorts every five minutes
                    if isEvents {
                        if shownEvents.isEmpty {
                            VStack(spacing: 10) {
                                EventArt(name: "clear-sky").frame(width: 180, height: 180)
                                Text(store.events.isEmpty ? "No events tonight" : "No event matches “\(ui.search.trimmingCharacters(in: .whitespaces))”")
                                    .font(.callout).foregroundStyle(Tokens.textSecondary)
                            }
                            .frame(maxWidth: .infinity).padding(.top, 40)
                        } else {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                                ForEach(shownEvents) { e in
                                    eventCard(e)
                                        .contentShape(Rectangle())
                                        .onTapGesture { ui.selectedEvent = e }
                                        .accessibilityElement(children: .combine)
                                        .accessibilityLabel(eventLabel(e))
                                        .accessibilityAddTraits(.isButton)
                                        .accessibilityAction { ui.selectedEvent = e }
                                }
                            }.padding(20)
                        }
                    } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                        ForEach(visible(at: clock.date)) { f in
                            let t = f.target
                            // Not a Button: the heart inside the card needs its own clicks, and a button inside a button's label
                            // does not reliably get them. A heart overlaid outside the card was hidden under the Liquid Glass
                            // (owner, 27 September 2026), so it lives inside, beside the chips.
                            card(t, notTonight: f.notTonight)
                                .contentShape(Rectangle())
                                .onTapGesture { ui.selected = t }
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel(f.notTonight.map { "\(t.name), \($0)" }
                                                    ?? store.site.map { Copy.cardLabel(t, lit: store.plan?.primary != nil, nearMoon: nearMoon(t), site: $0) } ?? t.name)
                                .accessibilityAddTraits(.isButton)
                                .accessibilityAction { ui.selected = t }
                                .accessibilityAction(named: isFavourite(t) ? "Remove from favourites" : "Add to favourites") { toggleFavourite(t) }
                        }
                    }.padding(20)
                    }
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

    private func heart(_ t: RankedTarget) -> some View {
        let on = isFavourite(t)
        return Button { toggleFavourite(t) } label: {
            Image(systemName: on ? "heart.fill" : "heart").font(.system(size: 12, weight: .semibold))
                .foregroundStyle(on ? Theme.accent : Tokens.textPrimary).padding(5)
                .background(Circle().fill(.black.opacity(0.45)))
        }
        .buttonStyle(.plain).help(on ? "Remove from favourites" : "Add to favourites")
        .accessibilityLabel(on ? "Remove \(t.name) from favourites" : "Add \(t.name) to favourites")
    }

    /// `notTonight`: a favourite that is not usable tonight, drawn dimmed with the reason in place of its timeline.
    private func card(_ t: RankedTarget, notTonight: String? = nil) -> some View {
        TargetCardFrame(dimmed: notTonight != nil, title: t.catalogueID, subtitle: t.cardLine,
                        trailing: t.magnitude.map { String(format: "mag %.1f", $0) } ?? "mag –") {
            ThumbnailView(target: t)
        } corner: {
            chips(t)
        } badge: {
            heart(t)
        } footer: {
            if let reason = notTonight {
                Text(reason).font(.system(size: 10.5)).foregroundStyle(Tokens.textSecondary)
            } else if let s = store.site, let p = store.plan, let track = p.primary ?? p.darkSpan {
                ViewabilityTimeline(target: t, track: track, lit: p.primary != nil, site: s)
            }
        }
    }

    private var isEvents: Bool { ui.section == .group(.events) }

    /// An event card's whole sentence for VoiceOver, as `Copy.cardLabel` is for a target: kind, name, what, when, chips.
    private func eventLabel(_ e: SkyEvent) -> String {
        [Self.eventKinds[e.kind], e.title, e.detail, e.atPeak ? "at peak" : nil, e.fits.map { $0 ? "fits your frame" : "wider than your frame" },
         e.clear.map { $0 ? "clear then" : "cloudy then" }].compactMap { $0 }.joined(separator: ", ")
    }

    /// Tonight's events, searched and sorted.
    private var shownEvents: [SkyEvent] {
        let q = ui.search.trimmingCharacters(in: .whitespaces)
        // The kind too, so the search prompt's "comet" finds a comet listed by its designation.
        let found = q.isEmpty ? store.events : store.events.filter {
            [$0.title, $0.detail, Self.eventKinds[$0.kind] ?? ""].contains { $0.localizedCaseInsensitiveContains(q) }
        }
        return Events.sorted(found, by: ui.eventSort)
    }

    private static let eventKinds: [SkyEventKind: String] = [.meteorShower: "Meteor shower", .comet: "Comet", .conjunction: "Conjunction",
                                                              .issPass: "Space station", .lunarEclipse: "Lunar eclipse", .solarEclipse: "Solar eclipse"]

    /// An event on the same card as a target: artwork, chips, title row, and the altitude timeline where it has a place in the sky.
    private func eventCard(_ e: SkyEvent) -> some View {
        let eclipse = e.kind == .lunarEclipse || e.kind == .solarEclipse
        // "best" only when there is a best time: a shower whose radiant never rises has none.
        let when = store.site.map { s in eclipse ? e.when.formatted(date: .abbreviated, time: .shortened) : e.best.map { "best \(Copy.hhmm($0, site: s))" } ?? "" } ?? ""
        return TargetCardFrame(title: e.title, subtitle: Self.eventKinds[e.kind] ?? "", trailing: when) {
            EventPicture(kind: e.kind)
        } corner: {
            EventChips(event: e)
        } badge: {
            EmptyView()
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text(e.detail).font(.system(size: 10.5)).foregroundStyle(Tokens.textSecondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                if let s = store.site, let p = store.plan, let track = p.primary ?? p.darkSpan, let ra = e.raHours, let dec = e.decDeg,
                   e.kind == .meteorShower || e.kind == .comet || e.kind == .conjunction {
                    ViewabilityTimeline(target: Planner.skyTrack(id: e.id, name: e.title, raHours: ra, decDeg: dec, window: track, site: s,
                                                                 minAlt: e.kind == .meteorShower ? 0 : store.config.goRule.minAltitudeDeg),
                                        track: track, lit: p.primary != nil, site: s)
                }
            }
        }
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
