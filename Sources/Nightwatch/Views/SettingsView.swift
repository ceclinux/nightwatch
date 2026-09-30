import SwiftUI
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
}

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @Environment(\.openWindow) private var openWindow
    @StateObject private var ui = SettingsViewState()

    var body: some View {
        Form {
            // Plain wording: "Beats" lost people (owner, 25 September 2026). One list: click a site to observe from it, the star
            // marks home, a visited dark site sits apart until kept, and adding a site opens its own sheet.
            Section("Where you observe") {
                ForEach(store.config.sites, id: \.name) { s in savedSiteRow(s) }
                HStack(spacing: 12) {
                    siteRow(title: "This Mac's location", detail: automaticStatus,
                            selected: store.config.visiting == nil && store.config.activeSiteName == nil && store.autoSite != nil,
                            enabled: store.autoSite != nil, home: thisMacIsHome) { store.config.choose(savedName: nil); store.saveConfig() }
                    homeStar(isHome: thisMacIsHome, name: "This Mac's location") { store.config.homeIsThisMac = true; store.saveConfig() }
                }
                if let v = store.config.visiting {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Visiting").font(.caption.weight(.semibold)).foregroundStyle(Theme.dim)
                        HStack(spacing: 8) {
                            radio(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(v.name)
                                Text("From Dark sites · Bortle \(v.bortle) · \(Bortle.name(v.bortle).lowercased())").font(.caption).foregroundStyle(Theme.dim)
                            }
                            Spacer()
                            Button("Keep") { store.keepVisiting() }.help("Save \(v.name) to your sites")
                            Button("Back to \(store.homeLabel)") { store.goHome() }
                        }
                    }
                }
                HStack {
                    Button("Add a site…") {
                        ui.newSite = Site(name: "", latitude: 0, longitude: 0, elevationM: 0, timeZoneID: TimeZone.current.identifier, bortle: 5)
                        ui.latText = ""; ui.lonText = ""; ui.addingSite = true
                    }
                        .buttonStyle(.borderedProminent)
                    Spacer()
                }
                Text("Click a site to observe from it. Home (★) is where “Back to …” returns and what dark sites are compared with.")
                    .font(.caption).foregroundStyle(Theme.dim)
            }
            Section("Telescope") {
                Picker("Preset", selection: Binding(get: { store.config.fovPresetID ?? "custom" }, set: { id in
                    store.config.fovPresetID = id == "custom" ? nil : id
                    if let p = ui.presets.first(where: { $0.id == id }) { store.config.fov = p.fov }
                    store.saveConfig()
                })) {
                    ForEach(ui.presets) { Text($0.name).tag($0.id) }
                    Text("Custom").tag("custom")
                }
                HStack {
                    TextField("Width °", value: Binding(get: { store.config.fov.widthDeg }, set: { setFOV(width: $0) }), format: .number)
                    TextField("Height °", value: Binding(get: { store.config.fov.heightDeg }, set: { setFOV(height: $0) }), format: .number)
                }
            }
            // Tonight's plan's own section: under Telescope, "Stop by" read as a camera setting rather than bedtime (owner's
            // UAT, 29 September 2026).
            Section("Tonight's plan") {
                Toggle("Show Tonight's plan in Targets and the heads-up", isOn: bind(\.showPlan))
                Toggle("Finish by a set time", isOn: bind(\.stopBy.enabled))
                if store.config.stopBy.enabled {
                    DatePicker("Finish by", selection: Binding(get: {
                        let m = store.config.stopBy.minutes
                        return Calendar.current.date(bySettingHour: m / 60 % 24, minute: m % 60, second: 0, of: .now) ?? .now
                    }, set: { d in
                        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                        store.config.stopBy.minutes = (c.hour ?? 0) * 60 + (c.minute ?? 0); store.saveConfig()
                    }), displayedComponents: .hourAndMinute)
                }
                Text("For bed or an early start: the plan ends at this time, and favourites only up after it are left out.")
                    .font(.caption).foregroundStyle(Theme.dim)
            }
            Section("Go rule") {
                Text("A night qualifies when there is one unbroken run of clear hours inside astronomical darkness that meets all three.")
                    .font(.caption).foregroundStyle(Theme.dim)
                choiceRow("Clear for at least", Binding(get: { store.config.goRule.minHours }, set: { store.config.goRule.minHours = $0; store.saveConfig() }),
                          [1, 2, 3, 4, 5, 6, 7, 8]) { String(format: "%.0f h", $0) }
                choiceRow("Cloud cover at most", Binding(get: { store.config.goRule.maxCloudPct }, set: { store.config.goRule.maxCloudPct = $0; store.saveConfig() }),
                          Array(stride(from: 5, through: 60, by: 5))) { "\($0) %" }
                choiceRow("Targets must reach", Binding(get: { store.config.goRule.minAltitudeDeg }, set: { store.config.goRule.minAltitudeDeg = $0; store.saveConfig() }),
                          Array(stride(from: 10.0, through: 60, by: 5))) { "\(Int($0))° altitude" }
            }
            Section("Alerts") {
                // The master switch, moved here from the popover's footer (owner, 27 September 2026): "Notify at 20:30" tonight.
                Toggle(store.site.map { Copy.notifyLabel(store.plan, site: $0, settings: store.config.alerts) } ?? "Notify when clear",
                       isOn: bind(\.notifyEnabled))
                Toggle("Evening heads-up (one hour before sunset)", isOn: bind(\.alerts.headsUp))
                Toggle("Tomorrow preview when tonight is out", isOn: bind(\.alerts.tomorrowPreview))
                choiceRow("Nudge before the window opens", bind(\.alerts.preWindowMinutes), Array(stride(from: 0, through: 120, by: 15))) {
                    $0 == 0 ? "When it opens" : "\($0) min"
                }
                Toggle("Cancel notice if the forecast turns", isOn: bind(\.alerts.cancelOnDowngrade))
                // Keyed on the build's source, not on one fetch: a single failed Open-Meteo call must not grey it out, and a
                // switch that is on can always be turned off.
                let signed = store.forecast?.cloudSource == "Apple Weather"
                Toggle("Alert only when Open-Meteo agrees", isOn: bind(\.alerts.requireAgreement))
                    .disabled(!signed && !store.config.alerts.requireAgreement)
                if !signed {
                    Text("Needs Apple Weather (signed build)").font(.caption).foregroundStyle(Theme.dim)
                }
                choiceRow("Quiet hours start", bind(\.alerts.quietStartHour), Array(0...23)) { String(format: "%02d:00", $0) }
                choiceRow("Quiet hours end", bind(\.alerts.quietEndHour), Array(0...23)) { String(format: "%02d:00", $0) }
                Text("No banners between those hours; the popover still shows what was missed.").font(.caption).foregroundStyle(Theme.dim)
            }
            Section("Dark sites") {
                Toggle("Look for darker skies nearby", isOn: bind(\.darkSites.enabled))
                Picker("Distance unit", selection: bind(\.darkSites.unit)) { Text("Kilometres").tag(DistanceUnit.km); Text("Miles").tag(DistanceUnit.mi) }
                choiceRow("Search radius", bind(\.darkSites.radiusKm), [5, 10, 15, 20, 25, 30, 40, 50, 75, 100, 150, 200, 250, 300]) {
                    Geo.format(km: $0, unit: store.config.darkSites.unit)
                }
                Text("Certified places plus the darkest spots on the bundled light-pollution grid. Tonight's forecast is fetched for the nearest eight.").font(.caption).foregroundStyle(Theme.dim)
            }
            Section("Bright nights") {
                Toggle("Moon and planets when there is no proper darkness", isOn: bind(\.brightNights.enabled))
                choiceRow("Minimum clear run", bind(\.brightNights.minHours), Array(stride(from: 1.0, through: 6, by: 0.5))) { String(format: "%.1f h", $0) }
                Text("Applies only on nights when the dark rule above cannot be met, from about early May to early August at British latitudes. The Moon or a planet must stand 15° up in a clear stretch of nautical darkness. Deep-sky targets are never suggested on a bright night.").font(.caption).foregroundStyle(Theme.dim)
            }
            if Distribution.checksForUpdates {   // the App Store build has no update check
                Section("Updates") {
                    Toggle("Check for a new version once a day", isOn: Binding(get: { store.config.checkForUpdates }, set: {
                        store.config.checkForUpdates = $0
                        if !$0 { store.availableUpdate = nil }   // off means the line goes now, not at the next patrol
                        store.saveConfig()
                    }))
                    Text("Asks GitHub for the latest release and shows a line in the popover when there is a newer one. Nothing else is sent.")
                        .font(.caption).foregroundStyle(Theme.dim)
                }
            }
            Section("Aurora") {
                Toggle("Alert me to aurora when the sky is clear", isOn: bind(\.aurora.enabled))
                Picker("Alert from", selection: bind(\.aurora.threshold)) {
                    ForEach([AuroraLevel.yellow, .amber, .red], id: \.self) { Text($0.displayName).tag($0) }
                }
                Text("Status from AuroraWatch UK (Lancaster University), checked every 5 minutes after dark. An alert needs the Sun 12° down and this hour's forecast cloud under your limit. Quiet hours apply.").font(.caption).foregroundStyle(Theme.dim)
            }
            Section("App") {
                // Reads the live login-item status (the user can remove it in System Settings); config.loginItem only records the choice.
                Toggle("Start at login", isOn: Binding(get: { SMAppService.mainApp.status == .enabled }, set: { on in
                    do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; store.config.loginItem = on; store.saveConfig() }
                    catch { ui.loginStatus = error.localizedDescription }
                    if SMAppService.mainApp.status == .requiresApproval { ui.loginStatus = "Approve Nightwatch under System Settings › General › Login Items." }
                }))
                if !ui.loginStatus.isEmpty { Text(ui.loginStatus).font(.caption).foregroundStyle(Theme.warn) }
                // #49: iCloud key-value storage replaces the file path and the symlink advice, which the sandbox cannot follow.
                Text(store.syncsSettings
                     ? "Settings sync through iCloud to your other Macs. Start at login, where this Mac is observing from and its own location stay on this Mac."
                     : "Not signed in to iCloud: settings stay on this Mac.")
                    .font(.caption).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
                if store.configLoadFailed {
                    Text("The config file could not be read, so changes are not being saved. A copy is at config.json.bad. Fix the file, or reset to defaults.").font(.caption).foregroundStyle(Theme.warn)
                }
                Button("Reset config", role: .destructive) { ui.confirmReset = true }
                    .confirmationDialog("Replace your settings with defaults? Sites and settings will be lost.", isPresented: $ui.confirmReset) {
                        Button("Reset config", role: .destructive) { store.resetConfig() }
                    } message: {
                        Text(store.syncsSettings ? "Resetting affects all your Macs." : "")
                    }
            }
            Section { Button("What the numbers mean") { openWindow(id: "numbers") } }   // #59, at the foot
        }
        .formStyle(.grouped)
        .sheet(isPresented: $ui.addingSite) { AddSiteSheet(ui: ui).environmentObject(store) }
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
            ForEach(Array(Set(options + [binding.wrappedValue])).sorted(), id: \.self) { Text(text($0)).tag($0) }
        }
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
                            Text("Home").font(.system(size: 10, weight: .semibold)).foregroundStyle(Tokens.statusWarning)
                                .padding(.horizontal, 5).padding(.vertical, 1).overlay(Capsule().stroke(Tokens.statusWarning.opacity(0.6)))
                        }
                    }
                    Text(detail).font(.caption).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
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
        .buttonStyle(.plain).help(isHome ? "\(name) is home" : "Make \(name) home").accessibilityLabel(isHome ? "\(name) is home" : "Make \(name) home")
    }

    private func savedSiteRow(_ s: Site) -> some View {
        let isHome = !store.config.homeIsThisMac && store.homeSite?.name == s.name
        let selected = store.config.visiting == nil && store.site?.name == s.name
        return HStack(spacing: 12) {
            siteRow(title: s.name, detail: String(format: "%.3f, %.3f · Bortle %d · %@", s.latitude, s.longitude, s.bortle, Bortle.name(s.bortle).lowercased()),
                    selected: selected, home: isHome) { store.config.choose(savedName: s.name); store.saveConfig() }
            homeStar(isHome: isHome, name: s.name) { store.config.homeSiteName = s.name; store.config.homeIsThisMac = false; store.saveConfig() }
            Button(role: .destructive) { store.config.remove(savedName: s.name); store.saveConfig() } label: { Image(systemName: "trash") }
                .buttonStyle(.plain).foregroundStyle(Theme.dim).help("Remove \(s.name)").accessibilityLabel("Remove \(s.name)")
        }
    }

    private var automaticStatus: String {
        if let a = store.autoSite { return String(format: "%.3f, %.3f · from Location Services", a.latitude, a.longitude) }
        return "Not available: allow Nightwatch in System Settings › Privacy & Security › Location Services"
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

    private var trimmed: String { ui.newSite.name.trimmingCharacters(in: .whitespaces) }
    private var nameTaken: Bool { store.config.sites.contains { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame } }
    /// Typed as text and parsed on Add, so a value is never lost to a field that has not committed; "−" is accepted.
    private func degrees(_ s: String) -> Double? { Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "−", with: "-")) }
    private var lat: Double? { degrees(ui.latText).flatMap { abs($0) <= 90 ? $0 : nil } }
    private var lon: Double? { degrees(ui.lonText).flatMap { abs($0) <= 180 ? $0 : nil } }
    /// 0, 0 is in the Gulf of Guinea: almost certainly fields left empty rather than a real site.
    private var valid: Bool { !trimmed.isEmpty && !nameTaken && lat != nil && lon != nil && !(lat == 0 && lon == 0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add a site").font(.title3.weight(.semibold))
            field("Name") {
                TextField("", text: $ui.newSite.name, prompt: Text("Back garden"))
                if nameTaken { Text("You already have a site called \(trimmed).").font(.caption).foregroundStyle(Tokens.statusWarning) }
            }
            HStack(alignment: .top, spacing: 12) {
                field("Latitude") { TextField("", text: $ui.latText, prompt: Text("53.381")) }
                field("Longitude") { TextField("", text: $ui.lonText, prompt: Text("−1.470")) }
            }
            HStack(alignment: .top, spacing: 10) {
                Button("Use this Mac's location") {
                    if let a = store.autoSite {
                        ui.latText = String(format: "%.4f", a.latitude); ui.lonText = String(format: "%.4f", a.longitude); ui.newSite.elevationM = a.elevationM
                    }
                }
                .disabled(store.autoSite == nil)
                .help(store.autoSite == nil ? "Location Services has not given Nightwatch a fix yet" : "Copy this Mac's coordinates into the fields")
                Text("or type decimal degrees, north and east positive: Sheffield is 53.381, −1.470")
                    .font(.caption).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
            }
            field("How dark is the sky there?") {
                Picker("", selection: $ui.newSite.bortle) {
                    ForEach(1...9, id: \.self) { Text("\($0) · \(Bortle.name($0))").tag($0) }
                }
                .labelsHidden()
                Text("The Bortle scale, 1 darkest to 9 brightest. It is shown in the popover header; it does not change the forecast.")
                    .font(.caption).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add site") {
                    guard let lat, let lon else { return }
                    var s = ui.newSite; s.name = trimmed; s.latitude = lat; s.longitude = lon
                    store.config.sites.append(s)
                    store.config.choose(savedName: s.name)
                    store.saveConfig()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction).disabled(!valid)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(Theme.dim)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
