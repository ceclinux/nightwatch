import SwiftUI
import UniformTypeIdentifiers
import NightwatchUI
import SkyCore

final class WelcomeState: ObservableObject {
    @Published var presets: [TelescopePreset] = (try? TelescopePresets.bundled()) ?? []
    @Published var locating = false
    @Published var locationFailed = false
    @Published var importFailed = false
}

/// First launch only (v0.6.7, owner-approved mockup): what the user images with, and where they observe from, then
/// Nightwatch watches the sky. Everything here can be changed later in Settings.
struct WelcomeView: View {
    @EnvironmentObject var store: Store
    @StateObject private var state = WelcomeState()
    @StateObject private var sites = SettingsViewState()   // the Add a site sheet's own state, as in Settings
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 52, height: 52).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to Nightwatch").font(Font.scaled(.title2).weight(.semibold))
                    Text("Two questions, then it watches the sky for you.").font(Font.scaled(.callout)).foregroundStyle(Theme.dim)
                }
            }
            // 0.6.x settings synced by a link the sandbox cannot follow (0.7.0): choosing the file is allowed.
            if let link = store.linkedSettings {
                step("Your earlier settings") {
                    Text("Nightwatch 0.6 kept your settings in a synced file, \(link.lastPathComponent) in \(link.deletingLastPathComponent().path). Choose it to keep your sites and choices.")
                        .font(Font.scaled(.caption)).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
                    Button("Import settings…") { importLinked(link) }.buttonStyle(ScaledButtonStyle(prominent: true))
                    if state.importFailed {
                        Text("That file isn't Nightwatch settings. Choose config.json, or set up below.").font(Font.scaled(.caption)).foregroundStyle(Tokens.statusWarning)
                    }
                }
            }
            if let e = store.importError {
                Text(e).font(Font.scaled(.caption)).foregroundStyle(Tokens.statusWarning).fixedSize(horizontal: false, vertical: true)
            }
            step("1  What do you image with?") {
                ForEach(state.presets) { p in
                    choice(p.name, detail: String(format: "%g × %g°", p.fov.widthDeg, p.fov.heightDeg), on: store.config.fovPresetID == p.id) {
                        store.config.fovPresetID = p.id; store.config.fov = p.fov; store.saveConfig()
                    }
                }
                choice("Something else", detail: "Enter its field of view in Settings", on: store.config.fovPresetID == nil) {
                    store.config.fovPresetID = nil; store.saveConfig()
                }
            }
            step("2  Where do you observe from?") {
                Text("Nightwatch needs a place to forecast for. Your location stays on this Mac; only its coordinates go to the weather services.")
                    .font(Font.scaled(.caption)).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button(store.autoSite == nil ? "Use this Mac's location" : "Using this Mac's location ✓") { useThisMac() }
                        .buttonStyle(ScaledButtonStyle(prominent: true)).disabled(state.locating || store.autoSite != nil)
                    Button("Add a site…") {
                        sites.newSite = Site(name: "", latitude: 0, longitude: 0, elevationM: 0, timeZoneID: TimeZone.current.identifier, bortle: 5)
                        sites.latText = ""; sites.lonText = ""; sites.addingSite = true
                    }
                    if state.locating { ProgressView().controlSize(.small) }
                }
                if state.locating {
                    Text("If macOS asks, choose Allow.").font(Font.scaled(.caption)).foregroundStyle(Theme.dim)
                }
                if let s = store.site, store.config.activeSiteName != nil { Text("Observing from \(s.name) ✓").font(Font.scaled(.caption)) }
                if state.locationFailed, store.autoSite == nil {   // a fix can still arrive after requestOnce gives up
                    Text("Location is not available. Allow Nightwatch in System Settings › Privacy & Security › Location Services, or add a site.")
                        .font(Font.scaled(.caption)).foregroundStyle(Tokens.statusWarning).fixedSize(horizontal: false, vertical: true)
                }
            }
            Text(store.site == nil
                 ? "No place yet: Nightwatch starts forecasting as soon as it has one. You can add it later in Settings."
                 : "You'll get a heads-up an hour before sunset on nights worth imaging. Change any of this later in Settings.")
                .font(Font.scaled(.caption)).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Start watching") {
                    store.config.welcomed = true; store.saveConfig()
                    dismissWindow(id: "welcome")
                }
                .buttonStyle(ScaledButtonStyle(prominent: true)).keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: TextScale.pt(460))
        .background(Theme.bg)
        .foregroundStyle(Theme.text)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $sites.addingSite) { AddSiteSheet(ui: sites).environmentObject(store).scaledText() }
        // Notifications are asked for as the welcome closes, after it has said what they are for: from Start watching
        // or the close button alike, so nobody is left never asked. Once answered, the alerts are worked out straight away
        // (recompute, not refresh: a refresh already in flight would make a refresh return early).
        .onDisappear { Task { @MainActor in await Notifier.requestAuthorisation(); await store.recompute(now: Date()) } }
    }

    private func importLinked(_ link: URL) {
        let panel = NSOpenPanel()
        panel.directoryURL = link.deletingLastPathComponent()
        panel.allowedContentTypes = [.json]
        panel.message = "Choose your Nightwatch settings file (\(link.lastPathComponent))"
        panel.prompt = "Import"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard store.importSettings(from: url) else { state.importFailed = true; return }
        // Boot skipped the location fix while the welcome was pending: settings that observe from this Mac need one now.
        if store.config.activeSiteName == nil || store.config.homeIsThisMac {
            store.awaitingFix = true
            Task { @MainActor in
                store.autoSite = await store.requestLocationFix?(); store.awaitingFix = false
                await store.refresh(force: false)
            }
        }
        dismissWindow(id: "welcome")
    }

    private func useThisMac() {
        state.locating = true; state.locationFailed = false
        Task { @MainActor in
            let fix = await store.requestLocationFix?()
            state.locating = false
            if let fix { store.autoSite = fix; store.config.choose(savedName: nil); store.saveConfig() } else { state.locationFailed = true }
        }
    }

    private func step<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(Font.scaled(.headline))
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))
    }

    private func choice(_ title: String, detail: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: on ? "largecircle.fill.circle" : "circle").foregroundStyle(on ? Tokens.controlOn : Theme.dim).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                    Text(detail).font(Font.scaled(.caption)).foregroundStyle(Theme.dim)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
