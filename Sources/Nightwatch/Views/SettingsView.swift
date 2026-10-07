import SwiftUI
import MapKit
import NightwatchUI
import ServiceManagement
import SkyCore

final class SettingsViewState: ObservableObject {
    @Published var presets: [TelescopePreset] = (try? TelescopePresets.bundled()) ?? []
    @Published var newSite = Site(name: "", latitude: 0, longitude: 0, elevationM: 0, timeZoneID: TimeZone.current.identifier, bortle: 5)
    @Published var loginStatus = ""
    @Published var confirmReset = false
    @Published var addingSite = false
    @Published var latText = ""
    @Published var lonText = ""
    /// The saved site whose horizon sheet is open.
    @Published var horizonFor: String?
}

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @Environment(\.openWindow) private var openWindow
    @StateObject private var ui = SettingsViewState()

    var body: some View {
        Form {
            // Plain wording: "Beats" lost people (owner, 25 September 2026). One list: click a site to observe from it, the star
            // marks home, a visited dark site sits apart until kept, and adding a site opens its own sheet.
            Section(L10n.text("Where you observe")) {
                ForEach(store.config.sites, id: \.name) { s in savedSiteRow(s) }
                HStack(spacing: 12) {
                    siteRow(title: L10n.text("This Mac's location"), detail: automaticStatus,
                            selected: store.config.visiting == nil && store.config.activeSiteName == nil && store.autoSite != nil,
                            enabled: store.autoSite != nil, home: thisMacIsHome) { store.config.choose(savedName: nil); store.saveConfig() }
                    homeStar(isHome: thisMacIsHome, name: L10n.text("This Mac's location")) { store.config.homeIsThisMac = true; store.saveConfig() }
                }
                if let v = store.config.visiting {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.text("Visiting")).font(Font.scaled(.caption).weight(.semibold)).foregroundStyle(Theme.dim)
                        HStack(spacing: 8) {
                            radio(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(v.name)
                                Text(L10n.format("From Dark sites · Bortle \(v.bortle) · \(Bortle.name(v.bortle).lowercased())")).font(Font.scaled(.caption)).foregroundStyle(Theme.dim)
                            }
                            Spacer()
                            Button(L10n.text("Keep")) { store.keepVisiting() }.help(L10n.format("Save \(v.name) to your sites")).disabled(!store.config.canAddSite)
                            Button(L10n.format("Back to \(store.homeLabel)")) { store.goHome() }
                        }
                    }
                }
                HStack {
                    Button(L10n.text("Add a site…")) {
                        ui.newSite = Site(name: "", latitude: 0, longitude: 0, elevationM: 0, timeZoneID: TimeZone.current.identifier, bortle: 5)
                        ui.latText = ""; ui.lonText = ""; ui.addingSite = true
                    }
                        .buttonStyle(ScaledButtonStyle(prominent: true))
                        .disabled(!store.config.canAddSite)
                    Spacer()
                }
                if !store.config.canAddSite {
                    Text(L10n.format("You have \(store.config.sites.count) saved sites, the most Nightwatch keeps. Remove one to add another."))
                        .font(Font.scaled(.caption)).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
                }
                Text(L10n.text("Click a site to observe from it. Home (★) is where “Back to …” returns and what dark sites are compared with."))
                    .font(Font.scaled(.caption)).foregroundStyle(Theme.dim)
            }
            Section(L10n.text("Telescope")) {
                Picker(L10n.text("Preset"), selection: Binding(get: { store.config.fovPresetID ?? "custom" }, set: { id in
                    store.config.fovPresetID = id == "custom" ? nil : id
                    if let p = ui.presets.first(where: { $0.id == id }) { store.config.fov = p.fov }
                    store.saveConfig()
                })) {
                    ForEach(ui.presets) { Text($0.name).scaledItem.tag($0.id) }
                    Text(L10n.text("Custom")).scaledItem.tag("custom")
                }
                .id("Preset \(store.config.textSize)")   // a pop-up keeps the items it was built with: rebuilt when the size changes
                HStack {
                    TextField(L10n.text("Width °"), value: Binding(get: { store.config.fov.widthDeg }, set: { setFOV(width: $0) }), format: .number)
                    TextField(L10n.text("Height °"), value: Binding(get: { store.config.fov.heightDeg }, set: { setFOV(height: $0) }), format: .number)
                }
            }
            // Tonight's plan's own section: under Telescope, "Stop by" read as a camera setting rather than bedtime (owner's
            // UAT, 29 September 2026).
            Section(L10n.text("Tonight's plan")) {
                Toggle(L10n.text("Show Tonight's plan in Targets and the heads-up"), isOn: bind(\.showPlan))
                Toggle(L10n.text("Finish by a set time"), isOn: bind(\.stopBy.enabled))
                if store.config.stopBy.enabled {
                    DatePicker(L10n.text("Finish by"), selection: Binding(get: {
                        let m = store.config.stopBy.minutes
                        return Calendar.current.date(bySettingHour: m / 60 % 24, minute: m % 60, second: 0, of: .now) ?? .now
                    }, set: { d in
                        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                        store.config.stopBy.minutes = (c.hour ?? 0) * 60 + (c.minute ?? 0); store.saveConfig()
                    }), displayedComponents: .hourAndMinute)
                    .controlSize(store.config.textSize == .standard ? .regular : .large)   // the time follows the control's size, not a font
                }
                Text(L10n.text("For bed or an early start: the plan ends at this time, and favourites only up after it are left out."))
                    .font(Font.scaled(.caption)).foregroundStyle(Theme.dim)
            }
            Section(L10n.text("Go rule")) {
                Text(L10n.text("A night qualifies when there is one unbroken run of clear hours inside astronomical darkness that meets all three."))
                    .font(Font.scaled(.caption)).foregroundStyle(Theme.dim)
                choiceRow(L10n.text("Clear for at least"), Binding(get: { store.config.goRule.minHours }, set: { store.config.goRule.minHours = $0; store.saveConfig() }),
                          [1, 2, 3, 4, 5, 6, 7, 8]) { String(format: "%.0f h", $0) }
                choiceRow(L10n.text("Cloud cover at most"), Binding(get: { store.config.goRule.maxCloudPct }, set: { store.config.goRule.maxCloudPct = $0; store.saveConfig() }),
                          Array(stride(from: 5, through: 60, by: 5))) { "\($0) %" }
                choiceRow(L10n.text("Targets must reach"), Binding(get: { store.config.goRule.minAltitudeDeg }, set: { store.config.goRule.minAltitudeDeg = $0; store.saveConfig() }),
                          Array(stride(from: 10.0, through: 60, by: 5))) { L10n.format("\(Int($0))° altitude") }
            }
            Section(L10n.text("Alerts")) {
                // The master switch, moved here from the popover's footer (owner, 27 September 2026): "Notify at 20:30" tonight.
                Toggle(store.site.map { Copy.notifyLabel(store.plan, site: $0, settings: store.config.alerts) } ?? L10n.text("Notify when clear"),
                       isOn: bind(\.notifyEnabled))
                Toggle(L10n.text("Evening heads-up (one hour before sunset)"), isOn: bind(\.alerts.headsUp))
                Toggle(L10n.text("Tomorrow preview when tonight is out"), isOn: bind(\.alerts.tomorrowPreview))
                choiceRow(L10n.text("Nudge before the window opens"), bind(\.alerts.preWindowMinutes), Array(stride(from: 0, through: 120, by: 15))) {
                    $0 == 0 ? L10n.text("When it opens") : L10n.format("\($0) min")
                }
                Toggle(L10n.text("Cancel notice if the forecast turns"), isOn: bind(\.alerts.cancelOnDowngrade))
                // Keyed on the build's source, not on one fetch: a single failed Open-Meteo call must not grey it out, and a
                // switch that is on can always be turned off.
                let signed = store.forecast?.cloudSource == "Apple Weather"
                Toggle(L10n.text("Alert only when Open-Meteo agrees"), isOn: bind(\.alerts.requireAgreement))
                    .disabled(!signed && !store.config.alerts.requireAgreement)
                if !signed {
                    Text(L10n.text("Needs Apple Weather (signed build)")).font(Font.scaled(.caption)).foregroundStyle(Theme.dim)
                }
                choiceRow(L10n.text("Quiet hours start"), bind(\.alerts.quietStartHour), Array(0...23)) { String(format: "%02d:00", $0) }
                choiceRow(L10n.text("Quiet hours end"), bind(\.alerts.quietEndHour), Array(0...23)) { String(format: "%02d:00", $0) }
                Text(L10n.text("No banners between those hours; the popover still shows what was missed.")).font(Font.scaled(.caption)).foregroundStyle(Theme.dim)
            }
            Section(L10n.text("Dark sites")) {
                Toggle(L10n.text("Look for darker skies nearby"), isOn: bind(\.darkSites.enabled))
                Picker(L10n.text("Distance unit"), selection: bind(\.darkSites.unit)) { Text(L10n.text("Kilometres")).scaledItem.tag(DistanceUnit.km); Text(L10n.text("Miles")).scaledItem.tag(DistanceUnit.mi) }
                    .id("Distance unit \(store.config.textSize)")
                choiceRow(L10n.text("Search radius"), bind(\.darkSites.radiusKm), [5, 10, 15, 20, 25, 30, 40, 50, 75, 100, 150, 200, 250, 300]) {
                    Geo.format(km: $0, unit: store.config.darkSites.unit)
                }
                Text(L10n.text("Certified places plus the darkest spots on the bundled light-pollution grid. Tonight's forecast is fetched for the nearest eight.")).font(Font.scaled(.caption)).foregroundStyle(Theme.dim)
            }
            Section(L10n.text("Bright nights")) {
                Toggle(L10n.text("Moon and planets when there is no proper darkness"), isOn: bind(\.brightNights.enabled))
                choiceRow(L10n.text("Minimum clear run"), bind(\.brightNights.minHours), Array(stride(from: 1.0, through: 6, by: 0.5))) { String(format: "%.1f h", $0) }
                Text(L10n.text("Applies only on nights when the dark rule above cannot be met, from about early May to early August at British latitudes. The Moon or a planet must stand 15° up in a clear stretch of nautical darkness. Deep-sky targets are never suggested on a bright night.")).font(Font.scaled(.caption)).foregroundStyle(Theme.dim)
            }
            if Distribution.checksForUpdates {   // the App Store build has no update check
                Section(L10n.text("Updates")) {
                    Toggle(L10n.text("Check for a new version once a day"), isOn: Binding(get: { store.config.checkForUpdates }, set: {
                        store.config.checkForUpdates = $0
                        if !$0 { store.availableUpdate = nil }   // off means the line goes now, not at the next patrol
                        store.saveConfig()
                    }))
                    Text(L10n.text("Asks GitHub for the latest release and shows a line in the popover when there is a newer one. Nothing else is sent."))
                        .font(Font.scaled(.caption)).foregroundStyle(Theme.dim)
                }
            }
            Section(L10n.text("Aurora")) {
                Toggle(L10n.text("Alert me to aurora when the sky is clear"), isOn: bind(\.aurora.enabled))
                Picker(L10n.text("Alert from"), selection: bind(\.aurora.threshold)) {
                    ForEach([AuroraLevel.yellow, .amber, .red], id: \.self) { Text($0.displayName).scaledItem.tag($0) }
                }
                .id("Alert from \(store.config.textSize)")
                Text(L10n.format("In the UK and Ireland, status from AuroraWatch UK (Lancaster University), checked every 5 minutes after dark. Elsewhere, NOAA's 30-minute aurora forecast for your site, checked every 15 minutes: yellow from \(Ovation.yellowFrom)%, amber from \(Ovation.amberFrom)%, red from \(Ovation.redFrom)%. An alert needs the Sun 12° down and this hour's forecast cloud under your limit. Quiet hours apply.")).font(Font.scaled(.caption)).foregroundStyle(Theme.dim)
            }
            Section(L10n.text("App")) {
                LanguagePicker()
                Text(L10n.text("Changes immediately. Language is saved only on this Mac."))
                    .font(Font.scaled(.caption)).foregroundStyle(Theme.dim)
                // Reads the live login-item status (the user can remove it in System Settings); config.loginItem only records the choice.
                Toggle(L10n.text("Start at login"), isOn: Binding(get: { SMAppService.mainApp.status == .enabled }, set: { on in
                    do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; store.config.loginItem = on; store.saveConfig() }
                    catch { ui.loginStatus = error.localizedDescription }
                    if SMAppService.mainApp.status == .requiresApproval { ui.loginStatus = L10n.text("Approve Nightwatch under System Settings › General › Login Items.") }
                }))
                if !ui.loginStatus.isEmpty { Text(ui.loginStatus).font(Font.scaled(.caption)).foregroundStyle(Theme.warn) }
                Picker(L10n.text("Text size"), selection: bind(\.textSize)) {
                    ForEach(TextSize.allCases, id: \.self) { Text($0.displayName).scaledItem.tag($0) }
                }
                .id("Text size \(store.config.textSize)")
                Text(L10n.text("For Nightwatch's popover and windows on this Mac. Desktop widgets keep their own size."))
                    .font(Font.scaled(.caption)).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
                // #49: iCloud key-value storage replaces the file path and the symlink advice, which the sandbox cannot follow.
                Text(store.syncsSettings
                     ? L10n.text("Settings sync through iCloud to your other Macs, home included: with This Mac's location as home, each Mac uses its own. Start at login, text size and where this Mac is observing from stay on this Mac.")
                     : L10n.text("Not signed in to iCloud: settings stay on this Mac."))
                    .font(Font.scaled(.caption)).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
                if store.configLoadFailed {
                    Text(L10n.text("The config file could not be read, so changes are not being saved. A copy is at config.json.bad. Fix the file, or reset to defaults.")).font(Font.scaled(.caption)).foregroundStyle(Theme.warn)
                }
                Button(L10n.text("Reset config"), role: .destructive) { ui.confirmReset = true }
                    .confirmationDialog(L10n.text("Replace your settings with defaults? Sites and settings will be lost."), isPresented: $ui.confirmReset) {
                        Button(L10n.text("Reset config"), role: .destructive) { store.resetConfig() }
                    } message: {
                        Text(store.syncsSettings ? L10n.text("Resetting affects all your Macs.") : "")
                    }
            }
            Section {
                Button(L10n.text("What the numbers mean")) { openWindow(id: "numbers") }   // #59, at the foot
                // The only way in: a menu-bar app never shows its own menus, so Window › About Nightwatch cannot be
                // reached, and nothing else opened this window (owner, 6 October 2026).
                Button(L10n.text("About Nightwatch")) { openWindow(id: "about") }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $ui.addingSite) { AddSiteSheet(ui: ui).environmentObject(store).scaledText() }
        .sheet(isPresented: Binding(get: { ui.horizonFor != nil }, set: { if !$0 { ui.horizonFor = nil } })) {
            if let name = ui.horizonFor { HorizonSheet(siteName: name).environmentObject(store).scaledText() }
        }
        .preferredColorScheme(.dark)
        .tint(Tokens.controlOn)
    }

    /// A setting chosen from a menu of values, which says what it is and what it will change to (owner, 25 September 2026:
    /// the old up/down arrows left the value adrift from its control). A value outside the list, from an older or hand-edited
    /// config, is kept as a choice.
    /// A typed field of view becomes Custom only when the number really changes. The width box has keyboard focus when
    /// Settings opens, and it writes back on losing focus even unchanged, which silently turned a preset into Custom (0.7.0).
    private func setFOV(width: Double? = nil, height: Double? = nil) {
        var f = store.config.fov
        if let width { f.widthDeg = max(0.05, width) }
        if let height { f.heightDeg = max(0.05, height) }
        guard f != store.config.fov else { return }
        store.config.fov = f; store.config.fovPresetID = nil; store.saveConfig()
    }

    private func choiceRow<V: Hashable & Comparable>(_ label: String, _ binding: Binding<V>, _ options: [V], _ text: @escaping (V) -> String) -> some View {
        Picker(label, selection: binding) {
            ForEach(Array(Set(options + [binding.wrappedValue])).sorted(), id: \.self) { Text(text($0)).scaledItem.tag($0) }
        }
        .id("\(label) \(store.config.textSize)")   // unique among the rows: one id shared by several drew the first row for each
    }

    private func radio(_ on: Bool) -> some View {
        Image(systemName: on ? "largecircle.fill.circle" : "circle").foregroundStyle(on ? Tokens.controlOn : Theme.dim).accessibilityHidden(true)
    }

    private func siteRow(title: String, detail: String, selected: Bool, enabled: Bool = true, home: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                radio(selected)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title).foregroundStyle(enabled ? Theme.text : Theme.dim)
                        if home {
                            Text(L10n.text("Home")).font(.system(size: TextScale.pt(10), weight: .semibold)).foregroundStyle(Tokens.statusWarning)
                                .padding(.horizontal, 5).padding(.vertical, 1).overlay(Capsule().stroke(Tokens.statusWarning.opacity(0.6)))
                        }
                    }
                    Text(detail).font(Font.scaled(.caption)).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!enabled)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var thisMacIsHome: Bool { store.config.homeIsThisMac || store.config.sites.isEmpty }

    private func homeStar(isHome: Bool, name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: isHome ? "star.fill" : "star").foregroundStyle(isHome ? Tokens.statusWarning : Theme.dim)
        }
        .buttonStyle(.plain).help(isHome ? L10n.format("\(name) is home") : L10n.format("Make \(name) home")).accessibilityLabel(isHome ? L10n.format("\(name) is home") : L10n.format("Make \(name) home"))
    }

    private func savedSiteRow(_ s: Site) -> some View {
        let isHome = !store.config.homeIsThisMac && store.homeSite?.name == s.name
        let selected = store.config.visiting == nil && store.site?.name == s.name
        return HStack(spacing: 12) {
            siteRow(title: s.name, detail: String(format: L10n.text("%.3f, %.3f · Bortle %d · %@"), s.latitude, s.longitude, s.bortle, Bortle.name(s.bortle).lowercased())
                        + "\n" + Copy.horizonSummary(s, openDeg: store.config.goRule.minAltitudeDeg),
                    selected: selected, home: isHome) { store.config.choose(savedName: s.name); store.saveConfig() }
            Button(L10n.text("Horizon…")) { ui.horizonFor = s.name }.accessibilityLabel(L10n.format("Horizon at \(s.name)"))
            homeStar(isHome: isHome, name: s.name) { store.config.homeSiteName = s.name; store.config.homeIsThisMac = false; store.saveConfig() }
            Button(role: .destructive) { store.config.remove(savedName: s.name); store.saveConfig() } label: { Image(systemName: "trash") }
                .buttonStyle(.plain).foregroundStyle(Theme.dim).help(L10n.format("Remove \(s.name)")).accessibilityLabel(L10n.format("Remove \(s.name)"))
        }
    }

    private var automaticStatus: String {
        if let a = store.autoSite { return String(format: L10n.text("%.3f, %.3f · from Location Services"), a.latitude, a.longitude) }
        return L10n.text("Not available: allow Nightwatch in System Settings › Privacy & Security › Location Services")
    }

    private func bind<T>(_ path: WritableKeyPath<Config, T>) -> Binding<T> {
        Binding(get: { store.config[keyPath: path] }, set: { store.config[keyPath: path] = $0; store.saveConfig() })
    }
}

/// "Add a site…" (v0.6.5): labelled fields, one per line, and the sky's darkness chosen by name.
struct AddSiteSheet: View {
    @EnvironmentObject var store: Store
    @ObservedObject var ui: SettingsViewState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var search = PlaceSearch()
    /// The name last filled in from a search, so a later search may replace it but a typed name is kept.
    @State private var searchedName: String?
    /// The darkness suggested from the light-pollution grid for the current coordinates; nil outside its coverage.
    @State private var suggested: Int?

    private var trimmed: String { ui.newSite.name.trimmingCharacters(in: .whitespaces) }
    private var nameTaken: Bool { store.config.sites.contains { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame } }
    /// Typed as text and parsed on Add, so a value is never lost to a field that has not committed. Degree signs and
    /// N, S, E or W are accepted, as maps write them.
    private var lat: Double? { Coordinates.degrees(ui.latText, latitude: true) }
    private var lon: Double? { Coordinates.degrees(ui.lonText, latitude: false) }
    /// 0, 0 is in the Gulf of Guinea: almost certainly fields left empty rather than a real site.
    private var valid: Bool { !trimmed.isEmpty && !nameTaken && lat != nil && lon != nil && !(lat == 0 && lon == 0) }

    private var coordinate: Coordinate? {
        guard let lat, let lon, !(lat == 0 && lon == 0) else { return nil }
        return Coordinate(latitude: lat, longitude: lon)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.text("Add a site")).font(Font.scaled(.title3).weight(.semibold))
            field(L10n.text("Search for a place")) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.dim).accessibilityHidden(true)
                    TextField("", text: $search.query, prompt: Text("Malham Tarn"))
                        .textFieldStyle(.plain)
                        .accessibilityLabel(L10n.text("Search for a place"))
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 6).stroke(Tokens.cardOutline))
                if !search.results.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(search.results, id: \.self) { r in
                            Button { choose(r) } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(r.title).font(.system(size: TextScale.pt(13), weight: .semibold))
                                    if !r.subtitle.isEmpty { Text(r.subtitle).font(.system(size: TextScale.pt(11))).foregroundStyle(Theme.dim) }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 6).fill(Tokens.surfaceTile))
                }
                Text(L10n.text("Places from Apple Maps. Only what you type is sent, never where you are."))
                    .font(Font.scaled(.caption)).foregroundStyle(Theme.dim)
            }
            if let c = coordinate { SiteMapView(coordinate: c) }
            field(L10n.text("Name")) {
                TextField("", text: $ui.newSite.name, prompt: Text(L10n.text("Back garden")))
                if nameTaken { Text(L10n.format("You already have a site called \(trimmed).")).font(Font.scaled(.caption)).foregroundStyle(Tokens.statusWarning) }
            }
            HStack(alignment: .top, spacing: 12) {
                // A pair pasted into Latitude, as maps copy them ("53.381, -1.470"), fills both fields.
                field(L10n.text("Latitude")) {
                    TextField("", text: $ui.latText, prompt: Text("53.381"))
                        .onChange(of: ui.latText) { _, t in
                            if let p = Coordinates.pair(t) { ui.latText = String(format: "%.4f", p.latitude); ui.lonText = String(format: "%.4f", p.longitude) }
                        }
                }
                field(L10n.text("Longitude")) { TextField("", text: $ui.lonText, prompt: Text("−1.470")) }
            }
            HStack(alignment: .top, spacing: 10) {
                Button(L10n.text("Use this Mac's location")) {
                    if let a = store.autoSite {
                        ui.latText = String(format: "%.4f", a.latitude); ui.lonText = String(format: "%.4f", a.longitude); ui.newSite.elevationM = a.elevationM
                    }
                }
                .disabled(store.autoSite == nil)
                // Said on screen, not in a hover tooltip (location entry check, 30 September 2026).
                Text(store.autoSite == nil
                     ? L10n.text("This Mac's location is not available yet. Search above, type the coordinates, or paste them as a pair from a map.")
                     : L10n.text("or search above, type the coordinates, or paste them as a pair from a map: Sheffield is 53.381, −1.470"))
                    .font(Font.scaled(.caption)).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
            }
            field(L10n.text("How dark is the sky there?")) {
                Picker("", selection: $ui.newSite.bortle) {
                    ForEach(1...9, id: \.self) { Text("\($0) · \(Bortle.name($0))").scaledItem.tag($0) }
                }
                .labelsHidden()
                Text(suggested != nil && suggested == ui.newSite.bortle
                     ? L10n.text("Suggested from light-pollution data for this spot. Change it if you know better. The Bortle scale, 1 darkest to 9 brightest.")
                     : L10n.text("The Bortle scale, 1 darkest to 9 brightest. It is shown in the popover header; it does not change the forecast."))
                    .font(Font.scaled(.caption)).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button(L10n.text("Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L10n.text("Add site")) {
                    guard let lat, let lon else { return }
                    var s = ui.newSite; s.name = trimmed; s.latitude = lat; s.longitude = lon
                    store.config.sites.append(s)
                    store.config.choose(savedName: s.name)
                    store.saveConfig()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction).buttonStyle(ScaledButtonStyle(prominent: true)).disabled(!valid || !store.config.canAddSite)
            }
        }
        .padding(20)
        .frame(width: TextScale.pt(480))
        // New coordinates, however they arrived, get the grid's darkness where it covers them.
        .onChange(of: coordinate) { _, c in
            suggested = c.flatMap { store.suggestedBortle(at: $0) }
            if let b = suggested { ui.newSite.bortle = b }
        }
    }

    /// A chosen place fills the coordinates, its time zone, and the name unless one was typed.
    private func choose(_ r: MKLocalSearchCompletion) {
        Task {
            guard let p = await search.resolve(r) else { return }
            if trimmed.isEmpty || trimmed == searchedName { ui.newSite.name = p.name; searchedName = p.name }
            ui.latText = String(format: "%.4f", p.coordinate.latitude); ui.lonText = String(format: "%.4f", p.coordinate.longitude)
            if let tz = p.timeZoneID { ui.newSite.timeZoneID = tz }
            search.clear()
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(Font.scaled(.caption).weight(.semibold)).foregroundStyle(Theme.dim)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
