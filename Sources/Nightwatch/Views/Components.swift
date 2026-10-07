import SwiftUI
import NightwatchUI
import SkyCore

/// A popover stat tile: label over value and an optional hint ("Dew heater advised"). No tile is singled out with a colour or
/// outline: the words are enough (owner's UAT, 29 September 2026). A missing value reads "No data" in the secondary colour.
/// Values wrap rather than truncate.
struct StatTile: View {
    let label: String
    let value: String?
    var hint: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: TextScale.pt(10))).foregroundStyle(Tokens.textSecondary)
            Text(value ?? L10n.text("No data")).font(.system(size: TextScale.pt(12.5), weight: .medium))
                .foregroundStyle(value == nil ? Tokens.textSecondary : Tokens.textPrimary).fixedSize(horizontal: false, vertical: true)
            if let hint { Text(hint).font(.system(size: TextScale.pt(9))).foregroundStyle(Tokens.textPrimary).fixedSize(horizontal: false, vertical: true) }
        }
        .padding(9).frame(maxWidth: .infinity, minHeight: 49.5, maxHeight: .infinity, alignment: .topLeading)   // fills its TileRow
        .accessibilityElement(children: .combine)
        // A plain translucent fill on the glass panel, not a second glass layer: measured live (25 Sep 2026), system glass
        // tinted surface.tile rendered #5A5D63 and left text.secondary at 2.9:1. The fill keeps it near #373A40 (spec §7).
        .background(Tokens.surfaceTile, in: RoundedRectangle(cornerRadius: 8))
    }
}

extension View {
    /// The window's own text at the chosen size (Settings › App › Text size): text with no font of its own follows it,
    /// and a change of size rebuilds the window so every view inside makes its fonts again.
    func textSized(_ size: TextSize) -> some View { font(Font.scaled(.body)).id(size) }

    /// Text and macOS's own buttons at the chosen size, for the windows and sheets made of them: Settings, the Welcome
    /// and the site and horizon sheets. Not for a window with links in it: a link is a button to the system, and drew as
    /// a bordered one under this style (1.5.2 and 1.5.3: the popover's Apple Weather mark and Download, About's links).
    /// A lone native button elsewhere takes `ScaledButtonStyle()` itself.
    func scaledText() -> some View { font(Font.scaled(.body)).buttonStyle(ScaledButtonStyle()) }

    /// A card that opens something: a click, Return or Space with keyboard focus on it, or VoiceOver's own action, which
    /// each card adds beside its label. Not a Button, because a card holds buttons of its own (the heart) that a Button's
    /// label would swallow.
    func opens(_ action: @escaping () -> Void) -> some View {
        contentShape(Rectangle())
            .onTapGesture(perform: action)
            .focusable(interactions: .activate)   // as a button is: in the Tab order when macOS's keyboard navigation is on
            .onKeyPress(.return) { action(); return .handled }
            .onKeyPress(.space) { action(); return .handled }
    }
}

/// Black caption backing for text laid over an image (the detail page, v0.6.4), so white text stays legible on any photo.
extension View {
    func captionBacking(cornerRadius: CGFloat = 6) -> some View { modifier(CaptionBacking(cornerRadius: cornerRadius)) }
    /// An 11 pt label in a caption backing: the detail page's back button and field-of-view note.
    func captionPill() -> some View {
        font(.system(size: TextScale.pt(11))).foregroundStyle(Tokens.textPrimary).padding(.horizontal, 9).padding(.vertical, 5).captionBacking()
    }
}

/// A warning-colour dot and "{n} h ago" beside any timestamp older than the six-hour stale rule.
struct StaleBadge: View {
    let fetchedAt: Date
    var body: some View {
        HStack(spacing: 4) { WarningDot(size: 5); Text(Copy.hoursAgo(fetchedAt, now: Date())) }
            .font(.system(size: TextScale.pt(10))).foregroundStyle(Tokens.statusWarning)
            .accessibilityElement(children: .combine)
    }
}

/// A small glass chip on a card: neutral text, or the warning colour with an icon for a warning.
struct Chip: View {
    let text: String
    var icon: String? = nil
    var warning = false
    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).accessibilityHidden(true) }
            Text(text)
        }
        .font(.system(size: TextScale.pt(9.5), weight: .medium))
        .foregroundStyle(warning ? Tokens.statusWarning : Tokens.textPrimary)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .nightwatchGlass(in: Capsule(), fill: Color.black.opacity(0.55))
    }
}

/// One row of tiles, every tile as tall as the tallest: the row takes its ideal height, and each tile's flexible frame fills it.
struct TileRow<Content: View>: View {
    var spacing: CGFloat = 8.5
    @ViewBuilder let content: () -> Content
    var body: some View {
        HStack(alignment: .top, spacing: spacing) { content() }.fixedSize(horizontal: false, vertical: true)
    }
}

/// macOS's own bordered button at the chosen Text size. The button ignores a font set on it or around it and reads only
/// one set on its label, so this draws the same button with the font put there. At Standard it is identical to the plain
/// button (compared on screen, 6 October 2026). The font is a property so a change of size makes a new style.
struct ScaledButtonStyle: PrimitiveButtonStyle {
    var prominent = false
    var font = Font.scaled(.body)

    func makeBody(configuration: Configuration) -> some View {
        let button = Button(role: configuration.role, action: configuration.trigger) { configuration.label.font(font) }
        if prominent { button.buttonStyle(.borderedProminent) } else { button.buttonStyle(.bordered) }
    }
}

extension Text {
    /// An item of a pop-up picker: the pop-up shows its choice in the item's own font, not one set around the picker.
    var scaledItem: Text { font(Font.scaled(.body)) }
}

/// The popover's secondary button (Refresh, All targets): a filled surface.button pill with primary text, so it reads as a
/// button rather than a caption. One style, so the two can never drift apart.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: TextScale.pt(11), weight: .medium)).foregroundStyle(Tokens.textPrimary)
            .padding(.horizontal, 10).frame(minWidth: 44, minHeight: 22)
            .background(Tokens.surfaceButton.opacity(configuration.isPressed ? 0.6 : 1), in: RoundedRectangle(cornerRadius: 6))
            .contentShape(RoundedRectangle(cornerRadius: 6))
    }
}


/// The black box behind text on a photograph: see-through normally, all but solid under Reduce Transparency or Increase
/// Contrast (#60), so the text never sits on a bright part of the image.
struct CaptionBacking: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        content.background(Color.black.opacity(reduceTransparency || contrast == .increased ? 0.92 : 0.62),
                           in: RoundedRectangle(cornerRadius: cornerRadius))
    }
}

extension ScrollViewProxy {
    /// Scrolls to `id`, gliding unless Reduce Motion is on, when it jumps (#60).
    func scroll(to id: some Hashable, reduceMotion: Bool) {
        if reduceMotion { scrollTo(id, anchor: .top) } else { withAnimation { scrollTo(id, anchor: .top) } }
    }
}

/// Reports the usable height of the screen its window is on, when it appears and whenever the window changes screen
/// (#60): the popover opens on the screen of the menu bar clicked, which need not be the one with focus.
struct WindowScreenReader: NSViewRepresentable {
    let onHeight: (CGFloat) -> Void
    func makeNSView(context: Context) -> ReaderView { ReaderView(onHeight: onHeight) }
    func updateNSView(_ view: ReaderView, context: Context) { view.onHeight = onHeight }

    final class ReaderView: NSView {
        var onHeight: (CGFloat) -> Void
        private var observer: NSObjectProtocol?
        init(onHeight: @escaping (CGFloat) -> Void) { self.onHeight = onHeight; super.init(frame: .zero) }
        required init?(coder: NSCoder) { nil }
        deinit { observer.map(NotificationCenter.default.removeObserver) }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observer.map(NotificationCenter.default.removeObserver)
            guard let window else { return }
            report(window)
            observer = NotificationCenter.default.addObserver(forName: NSWindow.didChangeScreenNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { if let w = self?.window { self?.report(w) } }
            }
        }

        private func report(_ window: NSWindow) {
            guard let screen = window.screen ?? NSScreen.main else { return }
            let h = screen.visibleFrame.height
            DispatchQueue.main.async { self.onHeight(h) }   // after this update, not inside it
        }
    }
}
