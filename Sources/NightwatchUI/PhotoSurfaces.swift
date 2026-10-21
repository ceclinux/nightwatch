import SwiftUI
import SkyCore

// The shared pieces of the Photographic design language (owner, 18 October 2026): one card surface, one section label, one warning chip,
// one call-to-action pill, one switch, one backdrop. Every screen takes these from here, so a change is one edit.

public extension View {
    /// The card surface: a faint white fill and a hairline, 16 pt radius. Under Reduce Transparency, Increase Contrast, or the largest
    /// text size it becomes the solid card, so text never sits on the picture. `glass: false` forces the solid one.
    func cardSurface(glass: Bool = true, radius: CGFloat = 16) -> some View { modifier(CardSurface(glass: glass, radius: radius)) }

    /// A section label: small wide-tracked semibold type in the supporting colour. Pass the capitals ("BEST TONIGHT") as written.
    func capsLabel() -> some View { font(.system(size: TextScale.pt(10), weight: .semibold)).tracking(1.4).foregroundStyle(Tokens.textSecondary) }
}

struct CardSurface: ViewModifier {
    let glass: Bool
    let radius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let solid = !glass || reduceTransparency || contrast == .increased || TextScale.factor >= 1.3
        content
            .background(solid ? Tokens.targetsCard : Tokens.glassFill, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(solid ? Tokens.cardOutline : Tokens.glassEdge, lineWidth: 1))
    }
}

/// A warning: a triangle and words in a capsule with a 1 pt amber outline and a faint amber fill, the text in the lit colour. Never a "!" in
/// the words and never coloured bold type, so the warning does not rest on colour alone.
public struct WarningChip: View {
    public let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: TextScale.pt(10), weight: .semibold)).accessibilityHidden(true)
            Text(text).font(.system(size: TextScale.pt(11), weight: .semibold))
        }
        .foregroundStyle(Tokens.lit)
        .padding(.horizontal, 9).padding(.vertical, 3)
        .background(Tokens.ember.opacity(0.14), in: Capsule())
        .overlay(Capsule().stroke(Tokens.ember, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// The one warm pill: ember with dark heavy text. One per screen at most.
public struct PillButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isEnabled ? 1 : 0.45)
            .font(.system(size: TextScale.pt(12), weight: .heavy))
            .padding(.horizontal, 16).padding(.vertical, 6)
            .background(Tokens.ember.opacity(configuration.isPressed ? 0.8 : 1), in: Capsule())
            .foregroundStyle(Tokens.onEmber)
    }
}

/// A switch with a warm-white track and a dark knob when on; a faint track and a pale knob when off.
public struct WarmSwitchStyle: ToggleStyle {
    public var compact = false
    public init(compact: Bool = false) { self.compact = compact }
    public func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack {
                configuration.label
                Spacer(minLength: 12)
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule().fill(configuration.isOn ? Tokens.lit : Color.white.opacity(0.18)).frame(width: compact ? 32 : 40, height: compact ? 19 : 24)
                    Circle().fill(configuration.isOn ? Tokens.targetsBackground : Color.white.opacity(0.85)).frame(width: compact ? 13 : 18, height: compact ? 13 : 18).padding(3)
                }
                .animation(.easeOut(duration: 0.12), value: configuration.isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(configuration.isOn ? L10n.text("On") : L10n.text("Off"))
    }
}

/// The night-sky picture behind a screen, held back by a scrim so text on it stays readable: Tonight shows the sky brighter than the list
/// and form screens (`calm`). The pictures are bundled in a `Backdrop` folder (`night-sky-wide.jpg` for wide windows, `night-sky-tall.jpg` for the
/// popover). With no picture bundled, or Reduce Transparency on, it is the plain dark background, so nothing depends on the picture.
public struct NightBackdrop: View {
    public var calm = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    public init(calm: Bool = false) { self.calm = calm }

    private static func load(_ name: String) -> NSImage? {
        Bundle.main.url(forResource: name, withExtension: "jpg", subdirectory: "Backdrop").flatMap { NSImage(contentsOf: $0) }
    }
    private static let wide = load("night-sky-wide")
    private static let tall = load("night-sky-tall")

    public var body: some View {
        if reduceTransparency || (Self.wide == nil && Self.tall == nil) {
            Tokens.targetsBackground
        } else {
            GeometryReader { geo in
                let picture = (geo.size.width > geo.size.height ? Self.wide : Self.tall) ?? Self.wide ?? Self.tall
                // At the largest text size the words sit on a near-solid scrim, so contrast never depends on the picture.
                let top = TextScale.factor >= 1.3 ? 0.88 : calm ? 0.55 : 0.16, foot = TextScale.factor >= 1.3 ? 0.92 : calm ? 0.88 : 0.78
                Image(nsImage: picture!).resizable().scaledToFill().frame(width: geo.size.width, height: geo.size.height).clipped()
                    .overlay(LinearGradient(colors: [Tokens.targetsBackground.opacity(top), Tokens.targetsBackground.opacity(foot)], startPoint: .top, endPoint: .bottom))
            }
            .allowsHitTesting(false).accessibilityHidden(true)
        }
    }
}
