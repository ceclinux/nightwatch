import SwiftUI
import SkyCore

struct LanguagePicker: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        Picker(L10n.text("Language"), selection: Binding(get: { store.language }, set: { store.setLanguage($0) })) {
            ForEach(AppLanguage.allCases, id: \.self) { language in
                Text(verbatim: language.nativeName).tag(language)
            }
        }
    }
}

extension View {
    /// Recreate presentation state, not the shared Store, so computed labels and native pickers update together.
    func interfaceLanguage(_ language: AppLanguage) -> some View {
        environment(\.locale, L10n.locale).id(language)
    }
}
