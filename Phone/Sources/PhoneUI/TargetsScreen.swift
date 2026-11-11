import SwiftUI
import SkyCore
import PhoneCore

/// The Targets browser: Favourites and the groups, each with how many are up tonight, as the Mac's sidebar lists them.
struct TargetsScreen: View {
    @ObservedObject var store: PhoneStore
    @Environment(\.phoneTheme) private var theme
    // `-demoOpen eyes` / `events` opens that page at launch, for screenshots in the Simulator.
    @State private var linkedTarget: RankedTarget?
    @State private var showLinked = false
    @State private var showSearched = false
    @State private var searchedGroup = TargetGroup.nebulae
    @State private var searchedText = ""
    @State private var demoEyes = UserDefaults.standard.string(forKey: "demoOpen") == "eyes"
    @State private var demoDark = UserDefaults.standard.string(forKey: "demoOpen") == "dark"
    @State private var demoEvents = ["events", "event"].contains(UserDefaults.standard.string(forKey: "demoOpen"))

    private var plan: NightPlan? { store.planning?.tonight }
    private func targets(in g: TargetGroup) -> [RankedTarget] { (plan?.mode == .bright ? plan?.brightTargets : plan?.targets)?.filter { $0.group == g } ?? [] }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                row(title: "Favourites", symbol: "heart.fill", count: store.config.favourites.count) { FavouritesScreen(store: store) }.risesIn(0)
                row(title: "Eyes and binoculars", symbol: "binoculars", count: store.eyeTargets.count + store.eyeEvents.count) { EyesScreen(store: store) }.risesIn(1)
                ForEach(Array(TargetGroup.allCases.enumerated()), id: \.element) { i, g in
                    if g == .events {
                        row(title: g.displayName, symbol: g.phoneSymbol, count: store.events.count) { EventsScreen(store: store) }.risesIn(i + 2)
                    } else {
                        row(title: g.displayName, symbol: g.phoneSymbol, count: targets(in: g).count) { TargetGroupScreen(store: store, group: g) }.risesIn(i + 2)
                    }
                }
                row(title: "Dark sites", symbol: "mappin.and.ellipse", count: store.darkSites.count) { DarkSitesScreen(store: store) }.risesIn(TargetGroup.allCases.count + 2)
            }
            .padding(16).frame(maxWidth: 700).frame(maxWidth: .infinity)
        }
        .background { StarField(seed: "targets", calm: true).ignoresSafeArea() }
        .navigationDestination(isPresented: $demoEyes) { EyesScreen(store: store) }
        .navigationDestination(isPresented: $showLinked) { if let t = linkedTarget { TargetDetailScreen(store: store, target: t) } }
        .navigationDestination(isPresented: $showSearched) { TargetGroupScreen(store: store, group: searchedGroup, initialQuery: searchedText) }
        .onAppear(perform: consumeLink)
        .onChange(of: store.pendingLink) { _, _ in consumeLink() }
        .navigationDestination(isPresented: $demoDark) { DarkSitesScreen(store: store) }
        .navigationDestination(isPresented: $demoEvents) { EventsScreen(store: store) }
    }

    /// A widget or Shortcut link: a target's page opens on top of this list; any other link has done its work by landing here.
    private func consumeLink() {
        guard let link = store.pendingLink else { return }
        store.pendingLink = nil
        if case .target(let id) = link, let t = store.target(withID: id) { linkedTarget = t; showLinked = true }
        // Siri's "find X in Nightwatch" (#72): the group holding the best match, with the words in its search box and the hint that says what was found.
        if case .search(let text) = link, let g = store.groupForSearch(text) { searchedGroup = g; searchedText = text; showSearched = true }
    }

    private func row<D: View>(title: String, symbol: String, count: Int, @ViewBuilder dest: @escaping () -> D) -> some View {
        NavigationLink(destination: dest) {
            HStack(spacing: 12) {
                Image(systemName: symbol).frame(width: 28).foregroundStyle(theme.lit)
                Text(title).font(.title3.weight(.heavy))
                Spacer()
                Text("\(count)").font(.callout.weight(.semibold)).monospacedDigit().secondary()
                Image(systemName: "chevron.right").font(.footnote).secondary()
            }
            .padding(.horizontal, 14).frame(minHeight: 56)
            .cardSurface()
        }
        .buttonStyle(PressStyle())
    }
}

/// One group's targets for tonight: search, sort, and the two switches the Mac has (only those that fit the telescope, include those
/// washed out by the Moon). While searching, matches the switches would hide still show, last.
struct TargetGroupScreen: View {
    @ObservedObject var store: PhoneStore
    let group: TargetGroup
    @State private var query: String
    init(store: PhoneStore, group: TargetGroup, initialQuery: String = "") {
        self.store = store; self.group = group; _query = State(initialValue: initialQuery)
    }
    @State private var sort = TargetSort.bestNow
    @AppStorage("fitsOnly") private var fitsOnly = false
    @AppStorage("includeMoonWashed") private var includeMoonWashed = false
    @Environment(\.phoneTheme) private var theme

    var body: some View {
        let plan = store.planning?.tonight
        let all = (plan?.mode == .bright ? plan?.brightTargets : plan?.targets) ?? []
        let shown = store.site.map { site in
            RankedTarget.cards(all, group: group, query: query, fitsOnly: fitsOnly, includeMoonWashed: includeMoonWashed, sort: sort,
                               now: store.now, span: plan?.primary, site: site)
        } ?? []
        ScrollView {
            LazyVStack(spacing: 10) {
                HStack {
                    Menu { Picker("Sort", selection: $sort) { ForEach(TargetSort.allCases, id: \.self) { Text($0.rawValue).tag($0) } } } label: {
                        Label("Sort: \(sort.rawValue)", systemImage: "arrow.up.arrow.down").font(.callout)
                    }
                    Spacer()
                }
                // As the Mac's Targets window: both are things to show, so a switch that is on always means more cards.
                VStack(alignment: .leading, spacing: 6) {
                    Text(SettingsCopy.showHeading).capsLabel()
                    Toggle(SettingsCopy.showMisfits, isOn: Binding(get: { !fitsOnly }, set: { fitsOnly = !$0 })).font(.callout)
                    Toggle(SettingsCopy.showMoonWashed, isOn: $includeMoonWashed).font(.callout)
                }
                if let hint = searchHint(all) {   // what the search found, as the Mac's Targets window says it
                    Text(hint).font(.callout).foregroundStyle(theme.warning).fixedSize(horizontal: false, vertical: true)
                } else if shown.isEmpty {
                    Text("Nothing in this group is up tonight.").font(.callout).secondary().padding(.top, 20)
                }
                ForEach(Array(shown.enumerated()), id: \.element.id) { i, t in
                    NavigationLink { TargetDetailScreen(store: store, target: t) } label: {
                        TargetCardView(store: store, target: t, dimmed: t.hiddenByFit(fitsOnly: fitsOnly) || t.hiddenByMoon(includeMoonWashed: includeMoonWashed))
                    }.buttonStyle(PressStyle()).risesIn(i)
                }
            }
            .padding(16).frame(maxWidth: 700).frame(maxWidth: .infinity)
        }
        .toggleStyle(PhoneToggleStyle())
        .scrollDismissesKeyboard(.interactively)
        .background { StarField(seed: group.rawValue, calm: true).ignoresSafeArea() }
        .searchable(text: $query, prompt: "M42, Orion, comet")
        .navigationTitle(group.displayName)
        .navigationBarTitleDisplayModeInline()
    }

    /// The Mac's search hint: matches here, the two switches' hidden ones, matches in other groups, and a target the catalogue has but tonight's
    /// list leaves out. Nil with no search.
    private func searchHint(_ all: [RankedTarget]) -> String? {
        let notPlanned = all.contains { $0.matches(query) } ? [] : store.catalogueMatches(query)
        return Copy.searchHint(query: query, targets: all, group: group, fitsOnly: fitsOnly, includeMoonWashed: includeMoonWashed, notPlanned: notPlanned)
    }
}

/// The user's favourites for tonight: those that are up first, then the rest greyed with the reason, as on the Mac.
struct FavouritesScreen: View {
    @ObservedObject var store: PhoneStore

    var body: some View {
        let favs = store.planning?.tonight.favourites ?? []
        let usable = favs.filter { $0.notTonight == nil }.sorted { $0.target.peakTime < $1.target.peakTime }
        let rest = favs.filter { $0.notTonight != nil }
        ScrollView {
            LazyVStack(spacing: 10) {
                if favs.isEmpty {
                    EmptyState(title: "No favourites yet", message: "Tap the heart on any target to keep it here, and in every night's plan when it is up.")
                }
                ForEach(Array(usable.enumerated()), id: \.element.id) { i, f in
                    NavigationLink { TargetDetailScreen(store: store, target: f.target) } label: { TargetCardView(store: store, target: f.target) }.buttonStyle(PressStyle()).risesIn(i)
                }
                ForEach(rest) { f in
                    NavigationLink { TargetDetailScreen(store: store, target: f.target) } label: {
                        TargetCardView(store: store, target: f.target, dimmed: true, note: f.notTonight)
                    }.buttonStyle(PressStyle())
                }
            }
            .padding(16).frame(maxWidth: 700).frame(maxWidth: .infinity)
        }
        .background { StarField(seed: "favourites", calm: true).ignoresSafeArea() }
        .navigationTitle("Favourites")
        .navigationBarTitleDisplayModeInline()
    }
}
