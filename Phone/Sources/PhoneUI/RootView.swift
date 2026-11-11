import SwiftUI
import SkyCore
import PhoneCore

/// The whole app: first run until a site exists, then Tonight with a sites sheet and settings. Red night mode is per device.
public struct RootView: View {
    @ObservedObject var store: PhoneStore
    @ObservedObject var connectivity: ConnectivityMonitor
    @StateObject private var permission = NotificationPermission()
    @AppStorage("redNightMode") private var red = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSites = false
    @State private var showSettings = false
    @State private var showHorizon: HorizonTarget?
    /// Sites whose time zone has been checked this launch, so the geocoder is asked once for each.
    @State private var zonesChecked: Set<String> = []

    public init(store: PhoneStore, connectivity: ConnectivityMonitor) {
        self.store = store; self.connectivity = connectivity
        // `-demoTab plan` (or targets, week, and sites on iPad) opens that section first, for screenshots in the Simulator.
        let first = UserDefaults.standard.string(forKey: "demoTab").flatMap { ["tonight": SidebarItem.tonight, "plan": .plan, "targets": .targets, "week": .week, "sites": .sites][$0] } ?? .tonight
        _tab = State(initialValue: first); _selection = State(initialValue: first)
    }

    private func refresh(force: Bool = false) { Task { await store.refresh(force: force, connectivity: connectivity.current) } }

    /// A refresh the person asked for (the Refresh button, pull down, Try again): it ends with a tap that says how it went.
    private func refreshByHand() {
        Task {
            await store.refresh(force: true, connectivity: connectivity.current)
            if store.offline || store.phase != .ready { Haptic.warning() } else { Haptic.success() }
        }
    }

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: SidebarItem?
    /// The sidebar starts closed in portrait, so the page has the full width; landscape has room for both.
    @State private var columns: NavigationSplitViewVisibility = .automatic
    enum SidebarItem: Hashable { case tonight, plan, targets, week, settings, sites }
    @State private var tab: SidebarItem
    @State private var planTomorrow = false

    @ViewBuilder private var phaseContent: some View {
        phaseSwitch.animation(reduceMotion ? nil : .easeOut(duration: 0.4), value: store.phase)
    }

    @ViewBuilder private var phaseSwitch: some View {
        switch store.phase {
        case .needsSite: FirstRunScreen(store: store)
        case .loading: LoadingScreen(siteName: store.site?.name ?? "your site", stage: store.stage).transition(.opacity)
        case .failed(let why):
            EmptyState(title: "No forecast yet", message: why, action: ("Try again", { refreshByHand() }))
        case .ready:
            if let m = store.tonight {
                TonightScreen(model: m, markData: store.appleMarkData, offline: store.offline, refreshing: store.refreshing,
                              onRefresh: { refreshByHand() },
                              alertsPrompt: AlertsPrompt(permission: permission, onGranted: { refresh(force: true) }), now: store.now)
                    .transition(.opacity)
            }
        }
    }

    /// The page for a section. Until the forecast is ready every section shows the same waiting, failed or first-run page.
    @ViewBuilder private func page(_ item: SidebarItem) -> some View {
        if store.phase != .ready || store.planning == nil || item == .tonight {
            phaseContent
        } else {
            switch item {
            case .plan: PlanScreen(store: store, onBrowse: { tab = .targets; selection = .targets })
            case .targets: TargetsScreen(store: store)
            case .week: WeekScreen(store: store, onOpenPlan: { _ in tab = .plan; selection = .plan })
            default: phaseContent
            }
        }
    }

    private func title(_ item: SidebarItem) -> String {
        switch item {
        case .tonight: store.site?.name ?? "Nightwatch"
        case .plan: "Plan"
        case .targets: "Targets"
        case .week: "The week ahead"
        case .settings: "Settings"
        case .sites: "Sites"
        }
    }

    private var nightModeButton: some View {
        Button { red.toggle() } label: { Image(systemName: red ? "moon.fill" : "moon") }
            .accessibilityLabel("Red night mode")
            .sensoryFeedback(.selection, trigger: red)
    }

    /// iPhone and Slide Over: four tabs, each in its own stack, with sites and settings as sheets.
    private func stack(_ theme: PhoneTheme) -> some View {
        TabView(selection: $tab) {
            ForEach([SidebarItem.tonight, .plan, .targets, .week], id: \.self) { item in
                NavigationStack {
                    page(item)
                        .navigationBarTitleDisplayModeInline()
                        .toolbar {
                            // A drawn title, not .navigationTitle: the system title ignores the red palette.
                            if store.phase != .ready || item != .tonight {
                                ToolbarItem(placement: .principal) { Text(title(item)).font(.headline).foregroundStyle(theme.textPrimary) }
                            }
                            ToolbarItemGroup(placement: .primaryAction) {
                                nightModeButton
                                if store.phase != .needsSite {
                                    Button { showSites = true } label: { Image(systemName: "mappin.and.ellipse") }.accessibilityLabel("Sites")
                                }
                                Button { showSettings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Settings")
                            }
                            .plainBackground()
                        }
                        .clearNavigationBar()
                }
                .tabItem { Label(tabName(item), systemImage: tabSymbol(item)) }
                .tag(item)
            }
        }
    }

    private func tabName(_ i: SidebarItem) -> String { i == .tonight ? "Tonight" : i == .plan ? "Plan" : i == .targets ? "Targets" : "Week" }
    private func tabSymbol(_ i: SidebarItem) -> String { i == .tonight ? "moon.stars" : i == .plan ? "list.bullet.rectangle" : i == .targets ? "sparkles" : "calendar" }

    /// The selected row is a pill drawn here, in the accent (pale in the normal theme, red in the red one), with a dark label: left to the system,
    /// iPadOS 26 drew it mid-grey under that dark label (owner's screenshot, 29 October 2026: not WCAG AA). 15:1 normal, 5.6:1 red.
    private func labelColour(_ item: SidebarItem, _ theme: PhoneTheme) -> Color { selection == item ? theme.background : theme.textPrimary }
    private func row(_ title: String, _ symbol: String, _ item: SidebarItem, _ theme: PhoneTheme) -> some View {
        Label(title, systemImage: symbol).tag(item).foregroundStyle(labelColour(item, theme)).listRowBackground(pill(item, theme))
    }
    private func pill(_ item: SidebarItem, _ theme: PhoneTheme) -> some View {
        RoundedRectangle(cornerRadius: 12).fill(selection == item ? theme.accent : Color.clear).padding(.horizontal, 2)
    }

    /// iPad: a sidebar with Tonight, the sites and Settings, and the page beside it.
    private func split(_ theme: PhoneTheme) -> some View {
        NavigationSplitView(columnVisibility: $columns) {
            List(selection: $selection) {
                Section {
                    row("Tonight", "moon.stars", .tonight, theme)
                    row("Plan", "list.bullet.rectangle", .plan, theme)
                    row("Targets", "sparkles", .targets, theme)
                    row("The week ahead", "calendar", .week, theme)
                    row("Settings", "gearshape", .settings, theme)
                }
                Section {
                    HStack {
                        Label("Sites", systemImage: "mappin.and.ellipse")
                        Spacer()
                        Text(store.site?.name ?? "").font(.callout).secondary().lineLimit(1)
                    }.tag(SidebarItem.sites).foregroundStyle(labelColour(.sites, theme)).listRowBackground(pill(.sites, theme))
                    Toggle(isOn: $red) { Label("Red night mode", systemImage: "moon.fill") }
                        .toggleStyle(PhoneToggleStyle())
                }
            }
            // Plain dark, not the picture: the page beside it has its own backdrop, and a second crop of the image would never line up with it.
            .scrollContentBackground(.hidden).background(theme.background.ignoresSafeArea())
            .navigationTitle("Nightwatch")
        } detail: {
            NavigationStack {
                Group {
                    if selection == .settings { SettingsScreen(store: store, red: $red, permission: permission, embedded: true) }
                    else if selection == .sites { SitesScreen(store: store, embedded: true, onChosen: { selection = .tonight }) }
                    else { page(selection ?? .tonight) }
                }
                .navigationBarTitleDisplayModeInline()
                .clearNavigationBar()
            }
        }
    }

    public var body: some View {
        let theme = PhoneTheme.named(red: red)
        Group {
            if sizeClass == .regular && store.phase != .needsSite {
                GeometryReader { geo in
                    split(theme).onAppear { columns = geo.size.width < 1000 ? .detailOnly : .all }
                }
            } else { stack(theme) }
        }
        .sheet(isPresented: $showSites) { SitesScreen(store: store).phoneTheme(theme) }
        .sheet(item: $showHorizon) { HorizonSheet(store: store, siteName: $0.name).phoneTheme(theme) }
        // While the app is open and aurora alerts are on: look every 5 minutes (the sources' own gaps still apply).
        .task(id: store.config.aurora.enabled) {
            while store.config.aurora.enabled, !Task.isCancelled {
                await store.pollAurora(connectivity: connectivity.current)
                try? await Task.sleep(for: .seconds(300))
            }
        }
        .onOpenURL { url in if let link = WidgetLink(url: url) { store.pendingLink = link } }
        // A link from the widget or from a Shortcut: show the page that handles it.
        .onChange(of: store.pendingLink) { _, link in
            guard let link else { return }
            let item: SidebarItem = link.phoneRoute == .plan ? .plan : .targets
            tab = item; selection = item
        }
        .sheet(isPresented: $showSettings) { SettingsScreen(store: store, red: $red, permission: permission).phoneTheme(theme) }
        .phoneTheme(theme)
        .environment(\.allowsOptionalDownloads, connectivity.current.allowsOptionalDownloads)
        // A site saved with this device's time zone may be somewhere else (the zone was missing when it was found): ask once, and correct it.
        .task(id: store.site?.name) {
            guard let s = store.site, s.timeZoneID == TimeZone.current.identifier, zonesChecked.insert(s.name).inserted else { return }
            if let tz = await PlaceCompleter.timeZone(latitude: s.latitude, longitude: s.longitude), tz.identifier != s.timeZoneID {
                store.correctTimeZone(of: s.name, to: tz.identifier)
            }
        }
        .task {
            refresh()
            // `-demoOpen horizon` opens the active site's horizon sheet at launch, for screenshots in the Simulator.
            if UserDefaults.standard.string(forKey: "demoOpen") == "horizon", let n = store.site?.name { try? await Task.sleep(for: .seconds(2)); showHorizon = HorizonTarget(name: n) }
            if UserDefaults.standard.string(forKey: "demoOpen") == "settings" { try? await Task.sleep(for: .seconds(2)); showSettings = true }
        }
        .onChange(of: scenePhase) { _, p in if p == .active { refresh(); Task { await permission.refresh() } } }
        .onChange(of: connectivity.current.isOnline) { _, on in if on { refresh() } }
    }
}

extension ToolbarContent {
    /// The toolbar's buttons without iOS 26's glass capsule behind them.
    func plainBackground() -> some ToolbarContent {
        #if os(iOS)
        if #available(iOS 26.0, *) { return AnyToolbarContent(self.sharedBackgroundVisibility(.hidden)) }
        #endif
        return AnyToolbarContent(self)
    }
}

/// Type erasure for the two branches above.
struct AnyToolbarContent<Content: ToolbarContent>: ToolbarContent {
    let content: Content
    init(_ content: Content) { self.content = content }
    var body: some ToolbarContent { content }
}

extension View {
    /// No translucent bar behind the title and buttons: the sky shows through to the top.
    func clearNavigationBar() -> some View {
        #if os(iOS)
        toolbarBackground(.hidden, for: .navigationBar)
        #else
        self
        #endif
    }

    func navigationBarTitleDisplayModeInline() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}

/// Where do you observe from? Shown until the first site exists (sites arriving from the Mac's iCloud settings skip it).
struct FirstRunScreen: View {
    @ObservedObject var store: PhoneStore
    @StateObject private var location = LocationProvider()
    @State private var name = ""
    @State private var message: String?
    @State private var busy = false
    @StateObject private var places = PlaceCompleter()
    @FocusState private var typing: Bool
    @Environment(\.phoneTheme) private var theme

    var body: some View {
        // The place field is the whole point of this screen, so it takes focus on arrival; the buttons are a bottom inset, which rides up
        // with the keyboard, and dragging the page down puts the keyboard away.
        ScrollView {
            VStack(spacing: 16) {
                Text("Is tonight a night to observe?").font(.title2.weight(.medium)).multilineTextAlignment(.center)
            Text("Nightwatch reads the sky forecast and tells you, then alerts you. Where do you observe from?")
                .font(.callout).secondary().multilineTextAlignment(.center)
                TextField("A place name", text: $name).textFieldStyle(.roundedBorder).submitLabel(.search).onSubmit(add).focused($typing)
                    .onChange(of: name) { places.update(name, near: store.site) }
                if let message { Text(message).font(.footnote).foregroundStyle(theme.warning) }
                PlaceChoices(places: places) { site in store.addSite(site); name = "" }
            }
            .padding(20).padding(.top, 60).frame(maxWidth: 520).frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                SecondaryButton(title: "Use this device's location", systemImage: "location") { useLocation() }
                PrimaryButton(title: busy ? "Searching" : "Add this place", action: add)
            }
            .padding(20).frame(maxWidth: 520).frame(maxWidth: .infinity)
            .background(theme.background)   // solid: place results scrolled under the buttons no longer show through them (seen on the iPhone Duo simulator)
        }
        .task { try? await Task.sleep(for: .milliseconds(600)); typing = true }
    }

    private func add() {
        guard !name.isEmpty, !busy else { return }
        busy = true; message = nil
        Task {
            if let first = places.suggestions.first, let s = await PlaceCompleter.site(for: first) { Haptic.success(); store.addSite(s); name = ""; places.clear() }
            else { message = "Could not find that place." }
            busy = false
        }
    }

    private func useLocation() {
        Task {
            do { store.addSite(try await location.currentSite()) } catch { message = "Location is not available. Type a place name instead." }
        }
    }
}

/// A site named for the horizon sheet to open.
struct HorizonTarget: Identifiable { let name: String; var id: String { name } }

/// The sites: a sheet on iPhone, a page in the sidebar on iPad (`embedded`), the same list either way.
struct SitesScreen: View {
    @ObservedObject var store: PhoneStore
    var embedded = false
    /// Called after a site is chosen in the embedded page, which has no sheet to close.
    var onChosen: () -> Void = {}
    @Environment(\.phoneTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var message: String?
    @State private var horizonSite: HorizonTarget?
    @StateObject private var places = PlaceCompleter()

    var body: some View {
        if embedded { list } else {
            NavigationStack {
                list
                    .navigationBarTitleDisplayModeInline()
                    .toolbar {
                        ToolbarItem(placement: .principal) { Text("Sites").font(.headline).foregroundStyle(theme.textPrimary) }
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                    }
            }
        }
    }

    private var list: some View {
            List {
                Section(header: Text("Your sites").capsLabel()) {
                    ForEach(store.config.sites, id: \.name) { s in
                        HStack {
                            Button { Haptic.selection(); store.selectSite(s); if embedded { onChosen() } else { dismiss() } } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(s.name).multilineTextAlignment(.leading)
                                        Text(Copy.horizonSummary(s, openDeg: store.openDeg).plainDashes).font(.caption).secondary().lineLimit(1)
                                    }
                                    Spacer(); if s.name == store.site?.name { Image(systemName: "checkmark") }
                                }
                            }
                            .buttonStyle(.borderless)
                            Button { horizonSite = HorizonTarget(name: s.name) } label: {
                                Image(systemName: "mountain.2").frame(width: 44, height: 44).contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Horizon for \(s.name)")
                        }
                    }
                    .onDelete { store.removeSites(at: $0) }
                }.listRowBackground(theme.card)
                Section(header: Text("Add a site").capsLabel()) {
                    TextField("A place name", text: $name).submitLabel(.search)
                        .onChange(of: name) { places.update(name, near: store.site) }
                    if let message { Text(message).font(.footnote) }
                    PlaceChoices(places: places) { site in store.addSite(site); name = "" }
                }.listRowBackground(theme.card)
            }
            .sheet(item: $horizonSite) { HorizonSheet(store: store, siteName: $0.name).phoneTheme(theme) }
            .scrollDismissesKeyboard(.interactively)
            .scrollContentBackground(.hidden).background { StarField(seed: "settings", calm: true).ignoresSafeArea() }
    }
}

struct SettingsScreen: View {
    @AppStorage("liveActivityOn") private var liveCard = true   // per device, not synced; read by the app's Live Activity scheduler
    @ObservedObject var store: PhoneStore
    @Environment(\.phoneTheme) private var theme
    @Binding var red: Bool
    @ObservedObject var permission: NotificationPermission
    var embedded = false
    @Environment(\.dismiss) private var dismiss

    private func binding<T>(_ kp: WritableKeyPath<AlertSettings, T>) -> Binding<T> {
        Binding(get: { store.config.alerts[keyPath: kp] }, set: { v in store.setAlerts { $0[keyPath: kp] = v } })
    }

    /// A setting chosen from a menu of values. A value outside the list, from the Mac or an older version, is kept as a choice.
    private func choiceRow<V: Hashable & Comparable>(_ label: String, _ value: V, _ options: [V], _ set: @escaping (V) -> Void, _ text: @escaping (V) -> String) -> some View {
        Picker(label, selection: Binding(get: { value }, set: set)) {
            ForEach(Array(Set(options + [value])).sorted(), id: \.self) { Text(text($0)).tag($0) }
        }
        .sensoryFeedback(.selection, trigger: value)
    }

    private func fieldOfView(width: Bool) -> some View {
        HStack(spacing: 4) {
            TextField("0", value: Binding(get: { width ? store.config.fov.widthDeg : store.config.fov.heightDeg },
                                          set: { width ? store.setFieldOfView(width: $0) : store.setFieldOfView(height: $0) }),
                      format: .number.precision(.fractionLength(0...2)))
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
                .multilineTextAlignment(.trailing).frame(maxWidth: 90)
            Text("°").secondary()
        }
    }

    private func step(_ delta: Int) {
        store.config.stopBy.minutes = ((store.config.stopBy.minutes + delta) % 1440 + 1440) % 1440
        store.saveConfig(); store.replan()
    }

    private var form: some View {
        Form {
            Section {
                Picker("Telescope", selection: Binding(get: { store.config.fovPresetID ?? "custom" },
                                                       set: { store.setTelescope(presetID: $0 == "custom" ? nil : $0) })) {
                    ForEach(TelescopePresets.byMaker(TelescopePresets.shared)) { group in
                        Section(group.maker) { ForEach(group.presets) { Text($0.model).tag($0.id) } }
                    }
                    Text("Custom").tag("custom")
                }
                .sensoryFeedback(.selection, trigger: store.config.fovPresetID)
                LabeledContent("Width") { fieldOfView(width: true) }
                LabeledContent("Height") { fieldOfView(width: false) }
            } header: { Text("Telescope").capsLabel() } footer: {
                Text("The size of the sky your telescope or camera frames, in degrees. It decides which targets fit, and the shooting tips.")
            }.listRowBackground(theme.card)
            Section {
                choiceRow("Clear for at least", store.config.goRule.minHours, [1, 2, 3, 4, 5, 6, 7, 8], { v in store.setGoRule { $0.minHours = v } }) { String(format: "%.0f h", $0) }
                choiceRow("Cloud cover at most", store.config.goRule.maxCloudPct, Array(stride(from: 5, through: 60, by: 5)), { v in store.setGoRule { $0.maxCloudPct = v } }) { "\($0) %" }
                choiceRow("Targets must reach", store.config.goRule.minAltitudeDeg, Array(stride(from: 10.0, through: 60, by: 5)), { v in store.setGoRule { $0.minAltitudeDeg = v } }) { "\(Int($0))° altitude" }
            } header: { Text("Go rule").capsLabel() } footer: {
                Text("A night qualifies when there is one unbroken run of clear hours inside astronomical darkness that meets all three.")
            }.listRowBackground(theme.card)
            Section {
                if permission.status == .denied {
                    Text("Alerts are off for Nightwatch in iOS Settings, Notifications.").font(.footnote)
                }
                Toggle(store.site.map { Copy.notifyLabel(store.planning?.tonight, site: $0, settings: store.config.alerts) } ?? "Notify when clear",
                       isOn: Binding(get: { store.config.notifyEnabled }, set: { store.setNotifyEnabled($0) }))
                Toggle(SettingsCopy.headsUp, isOn: binding(\.headsUp))
                Toggle(SettingsCopy.tomorrowPreview, isOn: binding(\.tomorrowPreview))
                choiceRow("Nudge before the window opens", store.config.alerts.preWindowMinutes, Array(stride(from: 0, through: 120, by: 15)),
                          { v in store.setAlerts { $0.preWindowMinutes = v } }) { $0 == 0 ? "When it opens" : "\($0) min" }
                Toggle("Clear-window card on the Lock Screen", isOn: $liveCard).onChange(of: liveCard) { _ in store.replan() }
                Text("A countdown to the end of the clear window. iOS asks to allow Live Activities the first time one appears. It cannot update itself, so it shows the time of the forecast it came from.")
                    .font(.footnote).secondary()
                Toggle(SettingsCopy.cancelOnDowngrade, isOn: binding(\.cancelOnDowngrade))
                // A switch that is on can always be turned off; one that is off needs Apple Weather, which supplies the forecast being checked.
                Toggle("Alert only when Open-Meteo agrees", isOn: binding(\.requireAgreement))
                    .disabled(store.forecast?.cloudSource != "Apple Weather" && !store.config.alerts.requireAgreement)
                if store.forecast?.cloudSource != "Apple Weather" && !store.config.alerts.requireAgreement {
                    Text("Needs Apple Weather, which is not answering at the moment.").font(.footnote).secondary()
                }
                choiceRow(SettingsCopy.quietHoursStart, store.config.alerts.quietStartHour, Array(0...23), { v in store.setAlerts { $0.quietStartHour = v } }) { String(format: "%02d:00", $0) }
                choiceRow(SettingsCopy.quietHoursEnd, store.config.alerts.quietEndHour, Array(0...23), { v in store.setAlerts { $0.quietEndHour = v } }) { String(format: "%02d:00", $0) }
            } header: { Text("Alerts").capsLabel() } footer: {
                Text("An alert is only sent from a forecast under six hours old. If you have not opened the app for a while, an alert may wait until the next refresh. iOS decides when the app may refresh in the background.")
            }.listRowBackground(theme.card)
            Section {
                Toggle("Finish by", isOn: Binding(get: { store.config.stopBy.enabled }, set: { store.config.stopBy.enabled = $0; store.saveConfig(); store.replan() }))
                if store.config.stopBy.enabled {
                    Stepper(String(format: "Stop at %02d:%02d", store.config.stopBy.minutes / 60, store.config.stopBy.minutes % 60),
                            onIncrement: { step(30) }, onDecrement: { step(-30) })
                        .sensoryFeedback(.selection, trigger: store.config.stopBy.minutes)
                }
            } header: { Text("Plan").capsLabel() } footer: {
                Text("A finish time (for sleep, or work the next day) shortens the clear window the plan uses, and keeps targets that are best after it out.")
            }.listRowBackground(theme.card)
            Section {
                Toggle("Moon and planets when there is no proper darkness", isOn: Binding(get: { store.config.brightNights.enabled },
                                                                                          set: { v in store.setBrightNights { $0.enabled = v } }))
                if store.config.brightNights.enabled {
                    choiceRow("Minimum clear run", store.config.brightNights.minHours, Array(stride(from: 1.0, through: 6, by: 0.5)),
                              { v in store.setBrightNights { $0.minHours = v } }) { String(format: "%.1f h", $0) }
                }
            } header: { Text("Bright nights").capsLabel() } footer: {
                Text("Applies only on nights when the dark rule above cannot be met, from about early May to early August at British latitudes: the Moon or a planet must be up in a clear run at least this long.")
            }.listRowBackground(theme.card)
            Section {
                Toggle("Dark sites", isOn: Binding(get: { store.config.darkSites.enabled }, set: { v in store.setDarkSites { $0.enabled = v } }))
                if store.config.darkSites.enabled {
                    Stepper("Within \(Geo.format(km: store.config.darkSites.radiusKm, unit: store.distanceUnit))",
                            value: Binding(get: { store.config.darkSites.radiusKm }, set: { v in store.setDarkSites { $0.radiusKm = v } }), in: 5...300, step: 5)
                        .sensoryFeedback(.selection, trigger: store.config.darkSites.radiusKm)
                    PhoneSegmented(selection: Binding(get: { store.config.darkSites.unit }, set: { v in store.setDarkSites { $0.unit = v } }),
                                   options: [("Kilometres", DistanceUnit.km), ("Miles", DistanceUnit.mi)])
                }
            } header: { Text("Dark sites").capsLabel() } footer: {
                Text("Darker places within this distance of where you observe. Tonight's forecast is read for the nearest three when you open the page.")
            }.listRowBackground(theme.card)
            Section {
                Toggle("Alert me to aurora when the sky is clear", isOn: Binding(get: { store.config.aurora.enabled },
                                                                                  set: { store.config.aurora.enabled = $0; store.saveConfig(); Task { await store.pollAurora() } }))
                if store.config.aurora.enabled {
                    Picker("Alert from", selection: Binding(get: { store.config.aurora.threshold }, set: { store.config.aurora.threshold = $0; store.saveConfig() })) {
                        ForEach([AuroraLevel.yellow, .amber, .red], id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .sensoryFeedback(.selection, trigger: store.config.aurora.threshold)
                }
            } header: { Text("Aurora").capsLabel() } footer: {
                Text("In the UK and Ireland, status from AuroraWatch UK (Lancaster University). Elsewhere, NOAA's 30-minute aurora forecast for your site: yellow from \(Ovation.yellowFrom)%, amber from \(Ovation.amberFrom)%, red from \(Ovation.redFrom)%. An alert needs the Sun 12° down and this hour's forecast cloud under your limit, and quiet hours apply. With no server behind it, the phone checks while Nightwatch is open, and when iOS lets it refresh in the background, so an alert can come late, or not at all, when the app is closed. The Mac app, left running, is the dependable one.")
            }.listRowBackground(theme.card)
            Section {
                NavigationLink { NumbersScreen() } label: { Label("What the numbers mean", systemImage: "questionmark.circle") }
            }.listRowBackground(theme.card)
            Section {
                Toggle("Red night mode", isOn: $red)
            } header: { Text("Display").capsLabel() } footer: {
                Text("Keeps your eyes dark-adapted. iOS cannot recolour the status bar, keyboard or permission alerts, and screen brightness is yours to lower. For a fully red screen, use iOS Settings, Accessibility, Display, Colour Filters, Colour Tint.")
            }.listRowBackground(theme.card)
        }
        .scrollContentBackground(.hidden).background { StarField(seed: "settings", calm: true).ignoresSafeArea() }
        .scrollDismissesKeyboard(.interactively)
        .toggleStyle(PhoneToggleStyle())
        .navigationBarTitleDisplayModeInline()
    }

    var body: some View {
        if embedded {
            form.toolbar { ToolbarItem(placement: .principal) { Text("Settings").font(.headline).foregroundStyle(theme.textPrimary) } }
        } else {
            NavigationStack {
                form.toolbar {
                    ToolbarItem(placement: .principal) { Text("Settings").font(.headline).foregroundStyle(theme.textPrimary) }
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
            }
        }
    }
}

/// The suggestions for what has been typed, each with where it is; tapping one looks it up and adds it.
struct PlaceChoices: View {
    @ObservedObject var places: PlaceCompleter
    let pick: (Site) -> Void
    var body: some View {
        ForEach(places.suggestions, id: \.self) { m in
            Button {
                Task { if let s = await PlaceCompleter.site(for: m) { places.clear(); Haptic.success(); pick(s) } }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.title)
                    if !m.subtitle.isEmpty { Text(m.subtitle).font(.caption).secondary() }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.borderless)
        }
    }
}
