import SwiftUI
import NightwatchUI
import SkyCore

/// A page in the Targets window (v0.6.4, owner-approved mockup; shared by targets and events since v1.0.1): the picture fills
/// the space between the top bar and a black caption box, "How to shoot this" opens over the bottom of the picture, and the
/// caption holds the title on the left and the figures on the right, stacking when the window is narrow.
/// `hero` gets the page's size and draws inside the coordinate space "pane", for a survey photo centred on the clear space.
struct DetailPage<TopTrailing: View, Hero: View, Tips: View, Title: View, Stats: View>: View {
    let back: String
    let onBack: () -> Void
    @ViewBuilder let topTrailing: () -> TopTrailing
    @ViewBuilder let hero: (CGSize) -> Hero
    @ViewBuilder let tips: () -> Tips
    @ViewBuilder let title: () -> Title
    @ViewBuilder let stats: () -> Stats

    var body: some View {
        GeometryReader { g in
            ZStack {
                Theme.card
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Button(action: onBack) { Label(back, systemImage: "chevron.left").captionPill() }.buttonStyle(.plain)
                        Spacer()
                        topTrailing()
                    }
                    .zIndex(1)
                    // An overlay takes no layout space, so opening the tips never resizes the picture (owner, 25 Sep 2026).
                    // Six rows for a smart telescope stand taller than the picture in a window at its opening size: the
                    // tips then scroll, where they used to run up under the top bar with their title cut off (1.6.2).
                    hero(g.size).frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay(alignment: .bottomTrailing) {
                            ViewThatFits(in: .vertical) {
                                tips()
                                ScrollView { tips() }.fixedSize(horizontal: true, vertical: false)
                            }
                            .zIndex(2)
                        }
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .bottom, spacing: 18) { title().fixedSize(horizontal: true, vertical: false); Spacer(minLength: 12); stats().frame(maxWidth: 470) }
                        VStack(alignment: .leading, spacing: 12) { title(); stats() }
                    }
                    .padding(14)
                    .captionBacking(cornerRadius: 10)
                    .zIndex(1)
                }
                .padding(16)
            }
            .coordinateSpace(name: "pane")
            .clipped()
        }
        .foregroundStyle(Theme.text)
    }
}
