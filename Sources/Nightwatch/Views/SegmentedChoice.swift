import SwiftUI
import NightwatchUI

/// A segmented control that follows Settings › App › Text size (owner-approved mock-up A, 6 October 2026). macOS's own
/// ignores any font: a control size grows its bezel, but its text stays at 13 pt (measured the same day). At Standard
/// this is macOS's own control, so nothing changes there. At Large and Extra large it is drawn here in the same shape,
/// with the text at the chosen size, and VoiceOver still meets the system's picker.
struct SegmentedChoice<Value: Hashable>: View {
    let title: String
    /// False where the control needs no word beside it ("Tonight | Tomorrow night"); the title still names it for VoiceOver.
    var showsTitle = true
    @Binding var selection: Value
    let options: [(value: Value, label: String)]

    var body: some View {
        if TextScale.factor == 1 {
            native
        } else {
            HStack(spacing: 8) {
                if showsTitle { Text(title).font(Font.scaled(.body)) }
                HStack(spacing: 0) {
                    ForEach(options, id: \.value) { option in
                        let chosen = option.value == selection
                        Button { selection = option.value } label: {
                            Text(option.label).font(Font.scaled(.body)).lineLimit(1)
                                .foregroundStyle(chosen ? Color.white : Tokens.textPrimary)
                                .padding(.horizontal, TextScale.pt(13)).frame(minHeight: TextScale.pt(20))
                                .background(chosen ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(2)
                .background(Tokens.targetsTrack, in: RoundedRectangle(cornerRadius: 8))
            }
            .fixedSize()
            .accessibilityRepresentation { native }
        }
    }

    @ViewBuilder private var native: some View {
        let picker = Picker(title, selection: $selection) {
            ForEach(options, id: \.value) { Text($0.label).tag($0.value) }
        }
        .pickerStyle(.segmented)
        if showsTitle { picker } else { picker.labelsHidden() }
    }
}
