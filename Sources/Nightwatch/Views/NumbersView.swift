import SwiftUI
import NightwatchUI
import SkyCore

/// "What the numbers mean" (#59, owner-approved mock-up, 29 September 2026): a window of its own, opened from About
/// and Settings (the Targets toolbar button went at the owner's UAT, 29 September 2026). The same native sidebar as Targets (a hand-made split left the title bar looking odd,
/// owner, 29 September 2026): a list of terms that Tab and the arrow keys reach, beside plain sections a screen reader
/// reads in order. No hover tooltips.
struct NumbersView: View {
    @State private var selected: String? = NumbersGuide.entries[0].id
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationSplitView {
            List(NumbersGuide.entries, selection: $selected) { e in
                Text(e.title).font(.system(size: 13)).tag(e.id)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(210)
            .accessibilityLabel("Terms")
        } detail: {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(NumbersGuide.entries) { e in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(e.title).font(.system(size: 17, weight: .semibold)).accessibilityAddTraits(.isHeader)
                                Text(e.body).font(.system(size: 13.5)).foregroundStyle(Tokens.textSecondary)
                                    .lineSpacing(3).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                            }
                            .id(e.id)
                        }
                    }
                    .padding(28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                // Choosing a term scrolls its section to the top, after the selection has been published rather than inside
                // the list's own update, where the scroll was lost (owner's test, 29 September 2026). VoiceOver focus stays
                // in the list, so the arrow keys keep stepping through the terms; the sections carry headings.
                .onChange(of: selected) { _, id in
                    guard let id else { return }
                    DispatchQueue.main.async { proxy.scroll(to: id, reduceMotion: reduceMotion) }
                }
            }
            .background(Theme.bg)
        }
        .frame(minWidth: 640, minHeight: 480)
        .foregroundStyle(Tokens.textPrimary)
        .preferredColorScheme(.dark)
    }
}
