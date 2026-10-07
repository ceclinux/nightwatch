import SwiftUI
import NightwatchUI
import SkyCore

enum BrowserSection: Hashable { case plan, week, favourites, eyes, group(TargetGroup), darkSites }

/// Asks the Targets window to show a section and, optionally, scroll to one dark-site card (the popover's Clearer sky line)
/// or open one target's detail (the widget). A nil section just brings the window forward as the user left it.
struct TargetsRequest: Equatable { let section: BrowserSection?; let siteID: String?; var targetID: String? = nil; var search: String? = nil }

final class TargetsViewState: ObservableObject {
    /// The window opens on Tonight's plan, the first page in the sidebar (owner, 6 October 2026); it used to open on
    /// Nebulae. With the plan switched off in Settings, TargetsView moves it to the first page that is shown.
    @Published var section: BrowserSection = .plan
    @Published var fitsOnly = false
    @Published var includeMoonWashed = false
    @Published var search = ""
    @Published var selected: RankedTarget? = nil
    @Published var selectedEvent: SkyEvent? = nil
    /// A narrow grid (a small screen, or Larger Text scaling) shows two columns, not three (#60). A flag, not the width, so
    /// resizing redraws the window only when it crosses the line.
    @Published var narrow = false
    @Published var pendingScrollID: String? = nil
    @Published var sort: TargetSort = .bestNow
    @Published var eventSort: EventSort = .time
    @Published var siteSort: SiteSort = .score
    /// Tonight | Tomorrow night: planning for tomorrow night (owner, 28 September 2026).
    @Published var tomorrow = false
}

struct TargetsView: View {
    @EnvironmentObject var store: Store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var ui = TargetsViewState()

    /// Tomorrow night can be planned whenever it has a forecast, clear or not: tied to tonight being cloudy and tomorrow
    /// clear, the switch came and went with each refresh (owner's UAT, 30 September 2026).
    private var canPlanTomorrow: Bool { store.plan != nil && store.tomorrow != nil }
    /// Events are tonight's only, so their page always reads tonight.
    private var showingTomorrow: Bool { ui.tomorrow && canPlanTomorrow && !isEvents }
    /// The night the whole window shows: groups, counts, search, favourites and pages all switch together.
    private var plan: NightPlan? { showingTomorrow ? store.tomorrow : store.plan }

    /// On a bright night only the Moon and planets are suggested, so they stand in for the ranked list.
    private var targets: [RankedTarget] { plan.map { $0.mode == .bright ? $0.brightTargets : $0.targets } ?? [] }

    private func count(_ g: TargetGroup) -> Int {
        g == .events ? store.events.count : targets.filter { $0.group == g }.count
    }

    private var selectedGroup: TargetGroup {
        if case .group(let g) = ui.section { return g }
        return .nebulae
    }

    /// Tonight's plan first, as a page of its own (owner's UAT, 29 September 2026), unless it is switched off in Settings.
    private var sections: [BrowserSection] {
        (store.config.showPlan ? [.plan] : []) + [.week, .favourites, .eyes] + TargetGroup.allCases.map { BrowserSection.group($0) } + [.darkSites]
    }

    /// Eyes and binoculars (#63): how each target can be seen from this site's sky, and the events that need no telescope.
    private func eyeView(_ t: RankedTarget) -> EyeView? { store.site.flatMap { EyeViews.view(t, bortle: $0.bortle) } }
    private var eyeTargets: [RankedTarget] { (targets + milkyWay.shown).filter { eyeView($0) != nil } }
    /// The Milky Way (#114, owner-approved mock-up): the core and the Cygnus band when they clear 10° in tonight's window,
    /// and the core dimmed with the reason in its season where it never can.
    private var milkyWay: (shown: [RankedTarget], dimmed: FavouriteTarget?) {
        guard let p = plan, let s = store.site else { return ([], nil) }
        let washed = (Planner.moonTonight(p).map { $0 != .down } ?? false) && p.moonIllumination >= 0.25
        let window = p.primary ?? p.darkSpan
        let all = MilkyWay.targets(window: window ?? ClearWindow(start: p.night.sunset, end: p.night.sunrise), site: s, moonWashed: washed)
        return (window == nil ? [] : all.filter { $0.viewable != nil },
                MilkyWay.coreNeverClears(site: s, on: p.night.sunset).map { FavouriteTarget(target: all[0], notTonight: $0) })
    }
    /// Tonight's only: the events are worked out for tonight, so none show while Tomorrow night is chosen. Searched as the
    /// Events group searches, by title, detail and kind.
    private var eyeEvents: [SkyEvent] {
        guard !showingTomorrow else { return [] }
        let q = ui.search.trimmingCharacters(in: .whitespaces)
        return store.events.filter { e in
            EyeViews.includes(e) && (q.isEmpty || [e.title, e.detail, Self.eventKinds[e.kind] ?? ""].contains { $0.localizedCaseInsensitiveContains(q) })
        }
    }

    private var favourites: [FavouriteTarget] { plan?.favourites ?? [] }


    /// The filtered, sorted cards at `now`. "Best now" sorts by altitude at that instant, so the grid passes a clock tick.
    /// Favourites ignore the two filters, since every favourite is always shown: usable ones sorted, then the greyed rest.
    private func visible(at now: Date) -> [FavouriteTarget] {
        guard let site = store.site else { return [] }
        let span = plan.flatMap { $0.primary ?? $0.darkSpan }
        switch ui.section {
        case .favourites:
            let found = favourites.filter { $0.target.matches(ui.search) }
            let usable = Planner.sorted(found.filter { $0.notTonight == nil }.map(\.target), by: ui.sort, now: now, span: span, site: site)
            return usable.map { FavouriteTarget(target: $0, notTonight: nil) } + found.filter { $0.notTonight != nil }
        case .group(let g):
            return RankedTarget.cards(targets, group: g, query: ui.search, fitsOnly: ui.fitsOnly, includeMoonWashed: ui.includeMoonWashed,
                                      sort: ui.sort, now: now, span: span, site: site).map { FavouriteTarget(target: $0, notTonight: nil) }
        case .eyes:
            let found = eyeTargets.filter { $0.matches(ui.search) }
            let dimmed = milkyWay.dimmed.flatMap { $0.target.matches(ui.search) ? [$0] : nil } ?? []
            return Planner.sorted(found, by: ui.sort, now: now, span: span, site: site).map { FavouriteTarget(target: $0, notTonight: nil) } + dimmed
        case .darkSites, .plan, .week:
            return []
        }
    }

    /// "Best now" ranks by height at this moment inside the window. With no window tonight it reads "Highest" (owner,
    /// 28 September 2026), and for tomorrow night, whose hours have not begun, "Best".
    private func sortLabel(_ sort: TargetSort) -> String {
        guard sort == .bestNow else { return sort.rawValue }
        if showingTomorrow { return L10n.text("Best") }
        return plan?.primary == nil ? L10n.text("Highest") : sort.rawValue
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
            // As wide as its longest name needs at the chosen Text size: at Extra large a fixed 232 cut "Eyes and binoculars"
            // to "Eyes and binocul…" (owner's screenshot, 6 October 2026).
            .navigationSplitViewColumnWidth(TextScale.pt(232))
        } detail: {
            if let ev = ui.selectedEvent {
                // The live copy, so a refresh updates the open page; the one clicked if the event has since gone.
                EventDetailView(event: store.events.first { $0.id == ev.id } ?? ev) { ui.selectedEvent = nil }.id(ev.id)
            } else if let selected = ui.selected {
                // A fresh page per target: a late image from the previous target's cancelled load can never land on this one.
                DetailView(target: selected, plan: plan, back: sectionTitle, eye: ui.section == .eyes ? eyeView(selected) : nil) { ui.selected = nil }
                    .id(selected.id)
            } else {
                switch ui.section {
                case .darkSites: darkSitesList
                case .plan: PlanView(plan: plan, canPlanTomorrow: canPlanTomorrow, tomorrow: $ui.tomorrow) { ui.selected = $0 }
                case .week: WeekView { tomorrow in ui.tomorrow = tomorrow; ui.section = .plan }
                case .group, .favourites, .eyes: grid
                }
            }
        }
        // No "What the numbers mean" button here: it made the title bar busy (owner's UAT, 29 September 2026). Settings
        // and About open the guide.
        .searchable(text: $ui.search, prompt: L10n.text("M42, Orion, comet…"))
        .preferredColorScheme(.dark)
        .background(Theme.bg)
        .onAppear {
            if !sections.contains(ui.section) { ui.section = sections[0] }   // Tonight's plan is off: The week ahead
            consumeRequest()
        }
        .onChange(of: store.targetsRequest) { _, _ in consumeRequest() }
        // Here, not on the window: a change of Text size rebuilds what is above, and `ui` has to outlive that, or the
        // sidebar went back to Nebulae and the search and open page were lost (owner, 6 October 2026).
        .textSized(store.config.textSize)
    }

    private func sidebarRow(_ section: BrowserSection) -> some View {
        HStack {
            switch section {
            case .plan:
                Label(L10n.text("Tonight's plan"), systemImage: "list.bullet"); Spacer()
                Text("\(store.session(for: plan)?.items.count ?? 0)").foregroundStyle(Tokens.textSecondary)
            case .week:
                Label(L10n.text("The week ahead"), systemImage: "calendar"); Spacer()
                Text("\(store.week.filter { $0.plan.primary != nil }.count)").foregroundStyle(Tokens.textSecondary)
            case .favourites:
                Label(L10n.text("Favourites"), systemImage: "heart.fill"); Spacer(); Text("\(favourites.count)").foregroundStyle(Tokens.textSecondary)
            case .eyes:
                Label(L10n.text("Eyes and binoculars"), systemImage: "binoculars"); Spacer()
                Text("\(eyeTargets.count + store.events.filter(EyeViews.includes).count)").foregroundStyle(Tokens.textSecondary)
            case .group(let g):
                Label(g.displayName, systemImage: Theme.glyph(for: g)); Spacer(); Text("\(count(g))").foregroundStyle(Tokens.textSecondary)
            case .darkSites:
                Label(L10n.text("Dark sites"), systemImage: "moon.stars"); Spacer(); Text("\(store.darkSites.count)").foregroundStyle(Tokens.textSecondary)
            }
        }
        .font(.system(size: TextScale.pt(12)))
    }

    /// Switches with the Moon line above them, so the Moon one has context (follow-on 5). Both read "Show …", so on always
    /// means more cards (owner, 28 September 2026); "Doesn't fit my frame" on is the old "Fits my field of view" off.
    private var filters: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let p = plan, let s = store.site, let m = Planner.moonTonight(p), m != .down {
                HStack(spacing: 5) { WarningDot(size: 5); Text(L10n.format("Moon \(Int((p.moonIllumination * 100).rounded()))% · \(Copy.moonText(m, site: s).lowercased())")) }
                    .font(.system(size: TextScale.pt(10))).foregroundStyle(Tokens.statusWarning)
            }
            // Only where they filter something: not on Events, Dark sites or Favourites (which shows every favourite).
            if case .group(let g) = ui.section, g != .events {
                Text(L10n.text("SHOW")).font(.system(size: TextScale.pt(9.5))).foregroundStyle(Tokens.textSecondary).padding(.top, 2)
                Toggle(L10n.text("Doesn't fit my frame"), isOn: Binding(get: { !ui.fitsOnly }, set: { ui.fitsOnly = !$0 }))
                Toggle(L10n.text("Washed out by the Moon"), isOn: $ui.includeMoonWashed)
            }
        }
        .toggleStyle(.switch).controlSize(.mini).tint(Tokens.controlOn).font(.system(size: TextScale.pt(11))).padding(10)
    }

    /// Applies a pending request from the popover once, then clears it.
    private func consumeRequest() {
        guard let r = store.targetsRequest else { return }
        if let section = r.section {
            ui.tomorrow = false   // a request from the popover or widget is about tonight
            ui.section = section
            ui.pendingScrollID = r.siteID
            ui.selected = r.targetID.flatMap { id in (targets + favourites.map(\.target)).first { $0.id == id } }
            ui.selectedEvent = nil   // an open event page would hide the requested target
        }
        if let text = r.search {   // Siri's in-app search: the whole list, filtered, rather than one page
            ui.tomorrow = false
            ui.selected = nil
            ui.selectedEvent = nil
            ui.search = text
            // The search covers the section on screen: open the one holding a match unless this one has one.
            let found = (targets + favourites.map(\.target)).filter { $0.matches(text) }
            if case .group(let g) = ui.section, found.contains(where: { $0.group == g }) {} else if let first = found.first {
                ui.section = .group(first.group)
            }
        }
        store.targetsRequest = nil
    }

    private var darkSitesList: some View {
        // The shortest drive to a clear window (owner, 6 October 2026): named in a line, first in its own sort order, and
        // marked on its card, because by score a farther site can sit above a nearer one that is nearly as good.
        let nearest = SiteComparison.nearestClear(store.sitePlans)
        let radius = Geo.format(km: store.config.darkSites.radiusKm, unit: store.distanceUnit)
        // With nothing clear tonight, "Nearest clear" has nothing to put first: the choice is not offered, and the page
        // keeps its usual order (owner's UAT, 6 October 2026). The choice itself is remembered for a night that has one.
        let sort = nearest == nil ? SiteSort.score : ui.siteSort
        return ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(L10n.text("Dark sites")).font(Font.scaled(.title2).weight(.semibold))
                    Spacer(minLength: 12)
                    if nearest != nil {
                        SegmentedChoice(title: L10n.text("Sort"), selection: $ui.siteSort, options: SiteSort.allCases.map { ($0, $0.rawValue) }).fixedSize()
                    }
                }
                HStack(spacing: 6) {
                    Text(L10n.format("Within \(radius) of \(store.site?.name ?? L10n.text("home")) · \(sort == .score ? L10n.text("sorted by tonight's score") : L10n.text("nearest clear sky first"))")).foregroundStyle(Theme.dim)
                    if store.isAway { Button(L10n.format("Back to \(store.homeLabel)")) { store.goHome() }.buttonStyle(.link) }
                }
                .font(Font.scaled(.caption))
                if let n = nearest, let w = n.primary, let here = store.site {
                    Button { ui.pendingScrollID = n.id } label: {
                        Text(L10n.format("Nearest clear sky: \(n.site.name), \(Geo.format(km: n.site.distanceKm, unit: store.distanceUnit)) \(n.site.compass), clear \(Copy.hhmm(w.start, site: here))–\(Copy.hhmm(w.end, site: here)) →"))
                            .font(Font.scaled(.callout)).foregroundStyle(Tokens.textPrimary).multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.plain).padding(.top, 6)   // a link, so text.primary, as the popover's Clearer sky line is
                } else if store.sitePlans.contains(where: { !$0.forecastMissing }) {
                    Text(L10n.format("No site within \(radius) has a clear window tonight."))
                        .font(Font.scaled(.callout)).foregroundStyle(Theme.dim).padding(.top, 6)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding([.horizontal, .top], 20)
            if !store.config.darkSites.enabled {
                Text(L10n.text("Dark sites are off. Turn them on in Settings › Dark sites.")).foregroundStyle(Theme.dim).padding(20)
            } else if store.darkSites.isEmpty {
                Text(L10n.format("No dark sites within \(Geo.format(km: store.config.darkSites.radiusKm, unit: store.distanceUnit)). Widen the radius in Settings."))
                    .foregroundStyle(Theme.dim).padding(20)
            }
            ScrollViewReader { proxy in
                GlassGroup(spacing: 12) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 2), spacing: 12) {
                        ForEach(SiteComparison.sorted(store.sitePlans, by: sort)) { DarkSiteCard(plan: $0, nearestClear: $0.id == nearest?.id).id($0.id) }
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
        proxy.scroll(to: id, reduceMotion: reduceMotion)
        ui.pendingScrollID = nil
    }

    private var grid: some View {
        // Each card in the plan says its place in it; the plan itself is a page of its own.
        let session = isEvents || ui.section == .eyes ? nil : store.session(for: plan)
        let order = Dictionary(uniqueKeysWithValues: (session?.items ?? []).enumerated().map { ($1.id, $0) })
        return ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                // The title on its own line and the controls under it, on every page: a short title ("Stars") sat beside
                // the controls while the others sat above them (owner's UAT, 29 September 2026).
                VStack(alignment: .leading, spacing: 8) {
                    headerTitle
                    // Side by side when they fit; at a larger Text size the two controls are wider than the page, and
                    // Sort goes under the night (owner-approved mock-up A, 6 October 2026).
                    ViewThatFits(in: .horizontal) {
                        HStack { nightControl.padding(.leading, 8); Spacer(minLength: 12); sortControl }
                        VStack(alignment: .leading, spacing: 8) { nightControl; sortControl }   // both flush with the title
                    }
                }
                // A refresh that takes the switch away (no forecast for tomorrow) also puts it back to Tonight, so it
                // never jumps to tomorrow by itself on a later refresh.
                Color.clear.frame(width: 0, height: 0).onChange(of: canPlanTomorrow) { _, can in if !can { ui.tomorrow = false } }
                if let p = plan, let s = store.site {
                    // No hour bars here: the popover and the medium and large widgets already show them (owner's UAT, 29 September 2026).
                    if showingTomorrow {
                        let day = L10n.format("Tomorrow night, \(Copy.dayMonth(p.night.localDate, site: s))")
                        Text(p.primary.map { w in L10n.format("\(day): clear \(Copy.hhmm(w.start, site: s))–\(Copy.hhmm(w.end, site: s)) · \(String(format: "%.1f h", w.hours))") }
                             ?? (p.darkSpan == nil ? L10n.format("\(day): no astronomical darkness.") : L10n.format("\(day): no clear window forecast.")))
                            .font(Font.scaled(.caption)).foregroundStyle(Tokens.textSecondary)
                    } else if p.darkSpan == nil {
                        Text(L10n.text("No astronomical darkness tonight.")).font(Font.scaled(.caption)).foregroundStyle(Tokens.textSecondary)
                    } else if p.primary == nil, canPlanTomorrow, let w = store.tomorrow?.primary {
                        // Said once here instead of on every card (owner, 28 September 2026).
                        Text(L10n.format("\(store.copy.noWindow) Tomorrow night looks clear \(Copy.hhmm(w.start, site: s))–\(Copy.hhmm(w.end, site: s))."))
                            .font(Font.scaled(.callout)).foregroundStyle(Tokens.statusWarning)
                    } else if p.primary == nil {
                        Text(store.copy.noWindow).font(Font.scaled(.caption)).foregroundStyle(Tokens.textSecondary)
                    }
                } else {
                    Text(store.lastError ?? L10n.text("Waiting for the first forecast…")).font(Font.scaled(.caption)).foregroundStyle(Tokens.textSecondary)
                }
                // The next moonless run (#62): said once here, where planning happens; the popover stays as it is.
                if !isEvents, let run = store.moonlessRun, let s = store.site {
                    Label(Copy.moonlessRun(run, site: s), systemImage: "circle").font(Font.scaled(.callout)).foregroundStyle(Tokens.textPrimary)
                }
                if store.isStale, let f = store.forecast { StaleBadge(fetchedAt: f.fetchedAt) }
                if plan?.mode == .bright, ui.section != .favourites, ui.section != .eyes, !isEvents, selectedGroup != .planets {
                    Text(L10n.text("Bright night: no deep-sky targets suggested.")).font(Font.scaled(.caption)).foregroundStyle(Tokens.textSecondary)
                }
                // What the search found, under the night's state as before but in the callout size and the warning colour used for the Moon
                // line and chips: in grey caption text it went unseen while typing (owner, 27 September 2026).
                if ui.section != .favourites, ui.section != .eyes, !isEvents,
                   let hint = Copy.searchHint(query: ui.search, targets: targets, group: selectedGroup, fitsOnly: ui.fitsOnly,
                                              includeMoonWashed: ui.includeMoonWashed) {
                    Text(hint).font(Font.scaled(.callout)).foregroundStyle(Tokens.statusWarning).padding(.top, 2)
                }
                if ui.section == .eyes {
                    let q = ui.search.trimmingCharacters(in: .whitespaces)
                    let matches = eyeTargets.contains { $0.matches(ui.search) } || !eyeEvents.isEmpty
                    Text(!q.isEmpty && !matches ? L10n.format("Nothing here matches “\(q)”.")
                         : eyeTargets.isEmpty && eyeEvents.isEmpty ? L10n.format("Nothing bright enough to see without a telescope \(showingTomorrow ? L10n.text("tomorrow night") : L10n.text("tonight")).")
                         : L10n.text("No telescope needed. Look first with your eyes; binoculars show the rest."))
                        .font(Font.scaled(.caption)).foregroundStyle(Tokens.textSecondary)
                }
                if ui.section == .favourites {
                    if favourites.isEmpty {
                        Text(L10n.text("No favourites yet. Click the heart on any target to add it here.")).font(Font.scaled(.caption)).foregroundStyle(Tokens.textSecondary)
                    } else if !favourites.contains(where: { $0.target.matches(ui.search) }) {
                        Text(L10n.format("No favourite matches “\(ui.search.trimmingCharacters(in: .whitespaces))”.")).font(Font.scaled(.caption)).foregroundStyle(Tokens.textSecondary)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding([.horizontal, .top], 20)
            GlassGroup(spacing: 12) {
                TimelineView(.periodic(from: .now, by: 300)) { clock in   // "Best now" re-sorts every five minutes
                    if isEvents {
                        if shownEvents.isEmpty {
                            VStack(spacing: 10) {
                                EventArt(name: "no-events").frame(width: 360, height: 79)   // a wide strip: a quiet horizon
                                Text(store.events.isEmpty ? L10n.text("No events tonight") : L10n.format("No event matches “\(ui.search.trimmingCharacters(in: .whitespaces))”"))
                                    .font(Font.scaled(.callout)).foregroundStyle(Tokens.textSecondary)
                            }
                            .frame(maxWidth: .infinity).padding(.top, 40)
                        } else {
                            LazyVGrid(columns: gridColumns, spacing: 12) {
                                ForEach(shownEvents) { e in
                                    eventCard(e)
                                        .opens { ui.selectedEvent = e }
                                        .accessibilityElement(children: .combine)
                                        .accessibilityLabel(eventLabel(e))
                                        .accessibilityAddTraits(.isButton)
                                        .accessibilityAction { ui.selectedEvent = e }
                                }
                            }.padding(20)
                        }
                        comingUp
                    } else {
                    LazyVGrid(columns: gridColumns, spacing: 12) {
                        ForEach(visible(at: clock.date)) { f in
                            let t = f.target
                            // Not a Button: the heart inside the card needs its own clicks, and a button inside a button's label
                            // does not reliably get them. A heart overlaid outside the card was hidden under the Liquid Glass
                            // (owner, 27 September 2026), so it lives inside, beside the chips.
                            card(t, notTonight: f.notTonight, planIndex: order[t.id], eye: ui.section == .eyes ? eyeView(t) : nil)
                                .opens { ui.selected = t }
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel(cardLabel(t, notTonight: f.notTonight, planIndex: order[t.id], eye: ui.section == .eyes ? eyeView(t) : nil))
                                .accessibilityAddTraits(.isButton)
                                .accessibilityAction { ui.selected = t }
                                .accessibilityAction(named: isFavourite(t) ? L10n.text("Remove from favourites") : L10n.text("Add to favourites")) { toggleFavourite(t) }
                        }
                        if ui.section == .eyes {
                            ForEach(eyeEvents) { e in
                                eventCard(e)
                                    .opens { ui.selectedEvent = e }
                                    .accessibilityElement(children: .combine)
                                    .accessibilityLabel(eventLabel(e))
                                    .accessibilityAddTraits(.isButton)
                                    .accessibilityAction { ui.selectedEvent = e }
                            }
                        }
                    }.padding(20)
                    }
                }
            }
        }
        .onGeometryChange(for: Bool.self) { $0.size.width < 640 } action: { if ui.narrow != $0 { ui.narrow = $0 } }
    }

    /// The next occultations seen from here after tonight (#115), so one weeks away can go in the calendar.
    @ViewBuilder private var comingUp: some View {
        let tonight = Set(store.events.map(\.id))
        let next = store.occultationsAhead.filter { !tonight.contains($0.id) && $0.time > Date() }.prefix(4)
        if let s = store.site, !next.isEmpty, ui.search.trimmingCharacters(in: .whitespaces).isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.format("Coming up from \(s.name)")).font(Font.scaled(.headline))
                Text(L10n.text("The Moon covering a planet, a bright star or the Pleiades, seen from here in darkness."))
                    .font(Font.scaled(.caption)).foregroundStyle(Tokens.textSecondary)
                ForEach(Array(next)) { e in
                    HStack(spacing: 12) {
                        Text(e.time.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) + ", " + Copy.hhmm(e.time, site: s))
                            .font(.system(size: TextScale.pt(13), weight: .semibold)).frame(width: TextScale.pt(150), alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.title).font(.system(size: TextScale.pt(13)))
                            Text(e.detail).font(Font.scaled(.caption)).foregroundStyle(Tokens.textSecondary)
                        }
                        Spacer()
                        Button(L10n.text("Add to Calendar")) { CalendarExport.open(e, site: s) }.buttonStyle(SecondaryButtonStyle())
                            .accessibilityLabel(L10n.format("Add \(e.title) on \(e.time.formatted(date: .abbreviated, time: .omitted)) to Calendar"))
                    }
                    .opens { ui.selectedEvent = e }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Tokens.targetsCard, in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Tokens.cardOutline, lineWidth: 1))
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 20)
        }
    }

    /// A card's whole sentence for VoiceOver, with its place in Tonight's plan.
    private func cardLabel(_ t: RankedTarget, notTonight: String?, planIndex: Int?, eye: EyeView? = nil) -> String {
        let base: String
        // In Eyes and binoculars, how to look and what it looks like, in place of the frame chip (#63).
        if let eye { base = "\(t.name), \(L10n.text(eye.rawValue).lowercased()): \(Copy.eyeLook(t, eye))" }
        else if let reason = notTonight { base = "\(t.name), \(reason)" }
        else if let s = store.site { base = Copy.cardLabel(t, lit: plan?.primary != nil, nearMoon: nearMoon(t), site: s) }
        else { base = t.name }
        guard let i = planIndex else { return base }
        return base + ", " + Copy.inPlan(i).lowercased()
    }

    /// Three columns, or two once a column would be narrower than a card can be read at (#60).
    private var gridColumns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 12), count: ui.narrow ? 2 : 3) }

    /// The page's name, for a target page's back link.
    private var sectionTitle: String {
        switch ui.section {
        case .plan: return L10n.text("Tonight's plan")
        case .week: return L10n.text("The week ahead")
        case .favourites: return L10n.text("Favourites")
        case .eyes: return L10n.text("Eyes and binoculars")
        case .group(let g): return g.displayName
        case .darkSites: return L10n.text("Dark sites")
        }
    }

    private var headerTitle: some View {
        Text(ui.section == .favourites ? L10n.text("Favourites") : ui.section == .eyes ? L10n.text("Eyes and binoculars") : selectedGroup.displayName)
            .font(Font.scaled(.title2).weight(.semibold)).lineLimit(1).fixedSize()
    }

    @ViewBuilder private var nightControl: some View {
        if canPlanTomorrow && !isEvents {
            SegmentedChoice(title: L10n.text("Night"), showsTitle: false, selection: $ui.tomorrow, options: [(false, L10n.text("Tonight")), (true, L10n.text("Tomorrow night"))])
                .fixedSize()
        }
    }

    @ViewBuilder private var sortControl: some View {
        if isEvents {
            SegmentedChoice(title: L10n.text("Sort"), selection: $ui.eventSort, options: EventSort.allCases.map { ($0, $0.rawValue) }).fixedSize()
        } else {
            SegmentedChoice(title: L10n.text("Sort"), selection: $ui.sort, options: TargetSort.allCases.map { ($0, sortLabel($0)) }).fixedSize()
        }
    }

    private func nearMoon(_ t: RankedTarget) -> Bool {
        guard let p = plan else { return false }
        return t.isNearMoon(moonIllumination: p.moonIllumination, moonUpTonight: Planner.moonTonight(p).map { $0 != .down } ?? false)
    }

    private func chips(_ t: RankedTarget, eye: EyeView? = nil) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            // In Eyes and binoculars the chip says how to look, in place of the frame (#63).
            if let eye { Chip(text: L10n.text(eye.rawValue), icon: eye == .nakedEye ? "eye" : "binoculars") }
            else {
            // With Doesn't fit my frame off, a fitting card needs no chip; one a search shows anyway says why it is last.
            if !ui.fitsOnly || t.hiddenByFit(fitsOnly: true) { Chip(text: Copy.frameChip(t), icon: "viewfinder") }
            }
            if t.moonWashed { Chip(text: L10n.text("Moon-washed"), icon: "moon.fill", warning: true) }
            else if nearMoon(t) { Chip(text: L10n.text("Near Moon"), icon: "moon.fill", warning: true) }
        }
    }

    private func heart(_ t: RankedTarget) -> some View {
        let on = isFavourite(t)
        return Button { toggleFavourite(t) } label: {
            Image(systemName: on ? "heart.fill" : "heart").font(.system(size: TextScale.pt(12), weight: .semibold))
                .foregroundStyle(on ? Theme.accent : Tokens.textPrimary).padding(5)
                .background(Circle().fill(.black.opacity(0.45)))
        }
        .buttonStyle(.plain).help(on ? L10n.text("Remove from favourites") : L10n.text("Add to favourites"))
        .accessibilityLabel(on ? L10n.format("Remove \(t.name) from favourites") : L10n.format("Add \(t.name) to favourites"))
    }

    /// `notTonight`: a favourite that is not usable tonight, drawn dimmed with the reason in place of its timeline.
    /// `planIndex`: its place in Tonight's plan (#57), outlined and labelled "In the plan, 1st".
    /// `eye`: in Eyes and binoculars, how it can be seen, with a line saying what it looks like (#63).
    private func card(_ t: RankedTarget, notTonight: String? = nil, planIndex: Int? = nil, eye: EyeView? = nil) -> some View {
        TargetCardFrame(dimmed: notTonight != nil, highlighted: planIndex != nil, title: t.catalogueID, note: t.cardNote, subtitle: t.cardName,
                        trailing: t.magnitude.map { String(format: L10n.text("mag %.1f"), $0) }) {
            ThumbnailView(target: t)
        } corner: {
            chips(t, eye: eye)
        } badge: {
            if !MilkyWay.isMilkyWay(t.id) { heart(t) }   // not a catalogue target, so it has no place in Favourites or the plan
        } footer: {
            if let reason = notTonight {
                Text(reason).font(.system(size: TextScale.pt(10.5))).foregroundStyle(Tokens.textSecondary)
            } else if let s = store.site, let p = plan, let track = p.primary ?? p.darkSpan {
                VStack(alignment: .leading, spacing: 4) {
                    if let i = planIndex { Text(Copy.inPlan(i)).font(.system(size: TextScale.pt(10.5), weight: .medium)).foregroundStyle(Tokens.accentClear) }
                    if let eye { Text(Copy.eyeLook(t, eye)).font(.system(size: TextScale.pt(10.5))).foregroundStyle(Tokens.textSecondary) }
                    ViewabilityTimeline(target: t, track: track, lit: p.primary != nil, site: s)
                }
            }
        }
    }

    private var isEvents: Bool { ui.section == .group(.events) }

    /// An event card's whole sentence for VoiceOver, as `Copy.cardLabel` is for a target: kind, name, what, when, chips.
    private func eventLabel(_ e: SkyEvent) -> String {
        [Self.eventKinds[e.kind], e.title, e.detail, e.atPeak ? L10n.text("at peak") : nil, e.fits.map { $0 ? L10n.text("fits your frame") : L10n.text("wider than your frame") },
         e.clear.map { $0 ? L10n.text("clear then") : L10n.text("cloudy then") }].compactMap { $0 }.joined(separator: ", ")
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

    private static var eventKinds: [SkyEventKind: String] { [.meteorShower: L10n.text("Meteor shower"), .comet: L10n.text("Comet"), .conjunction: L10n.text("Conjunction"),
                                                              .issPass: L10n.text("Space station"), .lunarEclipse: L10n.text("Lunar eclipse"), .solarEclipse: L10n.text("Solar eclipse"),
                                                              .occultation: L10n.text("Occultation")] }

    /// An event on the same card as a target: artwork, chips, title row, and the altitude timeline where it has a place in the sky.
    private func eventCard(_ e: SkyEvent) -> some View {
        let eclipse = e.kind == .lunarEclipse || e.kind == .solarEclipse
        // "best" only when there is a best time: a shower whose radiant never rises has none.
        let when = store.site.map { s in
            eclipse ? e.when.formatted(date: .abbreviated, time: .shortened)
                : e.kind == .occultation ? Copy.hhmm(e.time, site: s)
                : e.best.map { L10n.format("best \(Copy.hhmm($0, site: s))") } ?? ""
        } ?? ""
        // No kind label: the artwork already says what it is, and the room goes to the title (owner, 27 September 2026).
        return TargetCardFrame(title: e.title, subtitle: "", trailing: when.isEmpty ? nil : when) {
            EventPicture(kind: e.kind)
        } corner: {
            EventChips(event: e)
        } badge: {
            EmptyView()
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text(e.brief ?? e.detail).font(.system(size: TextScale.pt(10.5))).foregroundStyle(Tokens.textSecondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
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
    /// The shortest drive to a clear window tonight: marked on its map.
    var nearestClear = false
    var body: some View {
        let s = plan.site
        VStack(alignment: .leading, spacing: 8) {
            SiteMapView(site: s)
                .overlay(alignment: .topTrailing) {
                    if nearestClear { Chip(text: L10n.text("Nearest clear sky"), icon: "mappin.and.ellipse").padding(6) }
                }
            HStack(alignment: .firstTextBaseline) {
                Text(s.name).font(Font.scaled(.callout).weight(.semibold)).lineLimit(2)
                Spacer()
                if !plan.forecastMissing { Text("\(plan.score)").font(Font.scaled(.title3).weight(.semibold)).foregroundStyle(plan.qualifies ? Theme.accent : Theme.dim) }
            }
            Text("\(Geo.format(km: s.distanceKm, unit: store.distanceUnit)) \(s.compass) · \(s.kind.capitalized)" + (s.bortle.map { L10n.format(" · Bortle \($0)") } ?? s.band.map { " · \($0.displayName)" } ?? ""))
                .font(Font.scaled(.caption)).foregroundStyle(Theme.dim)
            // Compared with home, not with whichever site is active: while away, "at home" would be the wrong place (v0.6.5).
            if let home = store.homeSite {
                let siteSky = s.bortle.map { L10n.format("Bortle \($0)") } ?? s.band?.displayName ?? L10n.text("darkness unknown")
                let atHome = store.isAway ? L10n.format("at \(store.homeLabel) (home)") : L10n.text("at home")
                if !plan.forecastMissing, let hp = store.homePlan {
                    Text(L10n.format("Score \(plan.score) vs \(hp.score) \(atHome) · \(siteSky), home Bortle \(home.bortle)"))
                        .font(Font.scaled(.caption)).foregroundStyle(plan.score >= hp.score + 20 ? Theme.accent : Theme.dim)
                } else {
                    Text(L10n.format("\(siteSky), home Bortle \(home.bortle)")).font(Font.scaled(.caption)).foregroundStyle(Theme.dim)
                }
            }
            if s.isComputed {
                Text(L10n.text("Found from light-pollution data: check access and park considerately.")).font(Font.scaled(.caption)).foregroundStyle(Theme.dim)
            }
            if let w = plan.primary, let home = store.site {
                Text(L10n.format("Clear \(Copy.hhmm(w.start, site: home))–\(Copy.hhmm(w.end, site: home)) · \(String(format: "%.1f h", w.hours))")).font(Font.scaled(.caption))
            } else if plan.forecastMissing {
                Text(L10n.text("No forecast fetched (beyond the nearest eight, or offline)")).font(Font.scaled(.caption)).foregroundStyle(Theme.dim)
            } else {
                Text(store.copy.noWindow).font(Font.scaled(.caption)).foregroundStyle(Theme.dim)
            }
            // Cards in a row share the tallest one's height, with the buttons along the bottom (owner UAT, 29 September 2026).
            Spacer(minLength: 0)
            HStack {
                if let src = s.source, let url = URL(string: src) { Link(L10n.text("Source"), destination: url).font(Font.scaled(.caption)) }
                Spacer()
                Button(L10n.text("Open in Maps")) { SiteMaps.open(s) }.buttonStyle(ScaledButtonStyle())
                // Plain in both wording modes: "Use as beat" lost people (owner, 25 September 2026).
                Button(L10n.text("Observe from here")) { store.visit(s) }.buttonStyle(ScaledButtonStyle())
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Tokens.cardOutline, lineWidth: 1))
        .nightwatchGlass(in: RoundedRectangle(cornerRadius: 9), fill: Tokens.targetsCard)
    }
}
