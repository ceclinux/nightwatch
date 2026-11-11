import SwiftUI
import SkyCore
import PhoneCore

/// "What the numbers mean": every term Tonight and the target cards show, explained plainly, in SkyCore's own words (the Mac's guide).
struct NumbersScreen: View {
    @Environment(\.phoneTheme) private var theme

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(NumbersGuide.entries) { e in
                    Card {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(e.title.plainDashes).font(.callout.weight(.semibold))
                            Text(e.body.plainDashes).font(.footnote).secondary().fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(16).frame(maxWidth: 700).frame(maxWidth: .infinity)
        }
        .background { StarField(seed: "numbers", calm: true).ignoresSafeArea() }
        .navigationTitle("What the numbers mean")
        .navigationBarTitleDisplayModeInline()
    }
}
