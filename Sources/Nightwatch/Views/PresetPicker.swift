import SwiftUI
import SkyCore

/// The telescope menu: a heading per maker, the models under it, then Custom (owner-approved mock-up A, 7 October 2026).
/// Settings and the welcome share it, so a new preset shows in both.
struct PresetPicker: View {
    @EnvironmentObject var store: Store
    let presets: [TelescopePreset]

    var body: some View {
        Picker("Preset", selection: Binding(get: { store.config.fovPresetID ?? "custom" }, set: { id in
            store.config.fovPresetID = id == "custom" ? nil : id
            if let p = presets.first(where: { $0.id == id }) { store.config.fov = p.fov }
            store.saveConfig()
        })) {
            ForEach(TelescopePresets.byMaker(presets)) { group in
                Section(group.maker) { ForEach(group.presets) { Text($0.model).scaledItem.tag($0.id) } }
            }
            Divider()
            Text("Custom").scaledItem.tag("custom")
        }
        .id("Preset \(store.config.textSize)")   // a pop-up keeps the items it was built with: rebuilt when the size changes
    }
}
