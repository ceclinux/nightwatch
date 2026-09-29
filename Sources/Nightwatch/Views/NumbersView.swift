import SwiftUI
import NightwatchUI
import SkyCore

/// "What the numbers mean" (#59, owner-approved mock-up, 29 September 2026): a window of its own, opened from About,
/// Settings and the Targets window. A list of terms that Tab and the arrow keys reach, beside plain sections a screen
/// reader reads in order. No hover tooltips.
struct NumbersView: View {
    @State private var selected = NumbersGuide.entries[0].id

    var body: some View {
        ScrollViewReader { proxy in
            HStack(spacing: 0) {
                List(NumbersGuide.entries, selection: Binding(get: { selected }, set: { id in
                    guard let id else { return }
                    selected = id
                    // Scrolls only. Moving VoiceOver's focus here too would pull it out of the list on every arrow key, so
                    // the list could not be stepped through; the sections carry headings and read in order instead.
                    withAnimation { proxy.scrollTo(id, anchor: .top) }
                })) { e in
                    Text(e.title).font(.system(size: 13)).tag(e.id)
                }
                .listStyle(.sidebar)
                .frame(width: 210)
                .accessibilityLabel("Terms")
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
            }
        }
        .frame(minWidth: 640, minHeight: 480)
        .background(Theme.bg)
        .foregroundStyle(Tokens.textPrimary)
        .preferredColorScheme(.dark)
    }
}
