import SwiftUI
import SkyCore
import PhoneCore

/// A press scales the control down at once so the touch is seen to be heard, and springs back. A press that is dragged away
/// from the control, or cancelled by a scroll, ends without acting (the button's own behaviour), and the scale shows it.
public struct PressStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// The phone's taps, in one place. `selection` is a step or a choice, `impact` a press, `success` and `warning` how something turned out.
/// Declarative `.sensoryFeedback` stays where a value on screen changes; this is for actions. iOS drops them itself when the device has
/// haptics turned off.
enum Haptic {
    enum Weight { case light, medium }
    #if canImport(UIKit)
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
    static func impact(_ weight: Weight = .light) { UIImpactFeedbackGenerator(style: weight == .light ? .light : .medium).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    #else
    static func selection() {}
    static func impact(_ weight: Weight = .light) {}
    static func success() {}
    static func warning() {}
    #endif
}

/// The card surface of the Photographic look: a faint white fill and a hairline, 16 pt radius (a red-only pair in red mode). Under Reduce
/// Transparency, or at the accessibility text sizes, it becomes the solid card, so text never sits on the picture. Every card in the app
/// takes its surface from here; `glass: false` forces the solid one.
struct CardSurface: ViewModifier {
    var glass = true
    @Environment(\.phoneTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var typeSize

    func body(content: Content) -> some View {
        let solid = !glass || reduceTransparency || typeSize.isAccessibilitySize
        content
            .background(solid ? theme.card : theme.glassFill, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(solid ? theme.hairline : (contrast == .increased ? theme.textSecondaryHigh : theme.glassHairline), lineWidth: 1))
    }
}

extension View {
    func cardSurface(glass: Bool = true) -> some View { modifier(CardSurface(glass: glass)) }

    /// A section label: small wide-tracked capitals, semibold, in the supporting colour ("BEST TONIGHT", "TAKEN OFF TONIGHT").
    func capsLabel() -> some View { font(.caption.weight(.semibold)).tracking(1.4).secondary() }
}

/// A card: the surface the lists, charts and rows sit on.
struct Card<Content: View>: View {
    var padding: CGFloat = 12
    var glass = true
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(glass: glass)
    }
}

/// Waiting text that says what is happening, and breathes gently. Still under Reduce Motion.
struct WaitingText: View {
    let text: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false
    var body: some View {
        Text(text).font(.callout).secondary()
            .opacity(dim ? 0.45 : 1)
            .onAppear { if !reduceMotion { withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { dim = true } } }
    }
}

/// A screen's empty state: what is missing and what to do about it.
struct EmptyState: View {
    let title: String
    let message: String
    var action: (title: String, run: () -> Void)?
    @Environment(\.phoneTheme) private var theme
    var body: some View {
        VStack(spacing: 10) {
            Text(title).font(.title3.weight(.heavy))
            Text(message).font(.callout).secondary().multilineTextAlignment(.center)
            if let action {
                PillButton(title: action.title, action: action.run).padding(.top, 6)
            }
        }
        .padding(24)
    }
}

/// The big blue (or red) button at the foot of a screen: low on the screen, wide, easy to reach with a thumb.
struct PrimaryButton: View {
    let title: String
    let action: () -> Void
    var body: some View { PillButton(title: title, fullWidth: true, action: action) }
}

/// The one warm pill: the Photographic design's single call to action, ember with dark text, red on black in red mode.
struct PillButton: View {
    let title: String
    var fullWidth = false
    let action: () -> Void
    @Environment(\.phoneTheme) private var theme
    var body: some View {
        Button { Haptic.impact(); action() } label: {
            Text(title).font(.callout.weight(.heavy)).padding(.horizontal, 22).frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 48)
                .background(theme.ember, in: Capsule())
                .foregroundStyle(theme.isRed ? Color.black : Color(hex: 0x1A1206))
        }
        .buttonStyle(PressStyle())
    }
}

struct SecondaryButton: View {
    let title: String
    var systemImage: String? = nil
    let action: () -> Void
    @Environment(\.phoneTheme) private var theme
    var body: some View {
        Button { Haptic.impact(); action() } label: {
            HStack(spacing: 8) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.callout).frame(maxWidth: .infinity).padding(.vertical, 13)
            .background(theme.track, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(PressStyle())
    }
}

/// A switch drawn in the palette. The system switch has a white knob, which is a glare at the telescope in red mode.
struct PhoneToggleStyle: ToggleStyle {
    @Environment(\.phoneTheme) private var theme
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack {
                configuration.label
                Spacer()
                Capsule().fill(configuration.isOn ? (theme.isRed ? theme.accent : theme.lit) : theme.track).frame(width: 51, height: 31)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle().fill(configuration.isOn ? (theme.isRed ? Color.black : Color(hex: 0x0A1022)) : theme.textSecondary)
                            .frame(width: 25, height: 25).padding(3)
                    }
                    .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isOn)
            }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: configuration.isOn)
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}

/// A two-or-more way switch drawn in the palette (the system segmented control stays grey in red mode).
struct PhoneSegmented<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(label: String, value: Value)]
    @Environment(\.phoneTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // At the accessibility text sizes the choices stack, so none wraps inside a half-width segment.
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 4)) : AnyLayout(HStackLayout(spacing: 4))
        layout {
            ForEach(options.indices, id: \.self) { i in
                let on = options[i].value == selection
                Button { selection = options[i].value } label: {
                    Text(options[i].label).font(.callout.weight(on ? .heavy : .regular)).frame(maxWidth: .infinity, minHeight: 40)
                        .foregroundStyle(on ? (theme.isRed ? Color.black : Color(hex: 0x0A1022)) : theme.textPrimary)
                        .background(on ? (theme.isRed ? theme.accent : theme.lit) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(PressStyle())
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3).background(theme.track, in: RoundedRectangle(cornerRadius: 12))
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// The entry motion the clear-sky bars have, for rows and cards: each rises into place and fades in, one after another, the first time
/// it appears. A short stagger (capped, so a long list never makes anyone wait) and still under Reduce Motion.
struct RisesIn: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrived = false

    func body(content: Content) -> some View {
        content
            .opacity(arrived || reduceMotion ? 1 : 0)
            .offset(y: arrived || reduceMotion ? 0 : 14)
            .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.82).delay(Double(min(index, 8)) * 0.05), value: arrived)
            .onAppear { arrived = true }
    }
}

extension View {
    func risesIn(_ index: Int = 0) -> some View { modifier(RisesIn(index: index)) }
}

/// The corner of a chip: a rounded rectangle, not a capsule, so a chip whose words wrap keeps them inside its corners (owner, 29 October 2026). A
/// one-line chip is as tall as twice this at most, so it still reads as a pill.
private let chipCorner: CGFloat = 12

/// A warning, drawn once for the whole app: a triangle and words in a quiet rounded chip with an ember outline and a faint ember fill. Never a shouting
/// line of coloured type and never a "!" in the text; the icon and the outline mean it does not rely on colour alone (red mode has one hue).
struct WarningChip: View {
    let text: String
    @Environment(\.phoneTheme) private var theme
    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote.weight(.semibold)).foregroundStyle(theme.lit).fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(theme.warning.opacity(0.16), in: RoundedRectangle(cornerRadius: chipCorner))
            .overlay(RoundedRectangle(cornerRadius: chipCorner).strokeBorder(theme.warning, lineWidth: 1))
            .accessibilityElement(children: .combine)
    }
}

/// A small label with a symbol. A warning keeps its colour, a dashed outline and a "!", so it never relies on colour alone.
struct Chip: View {
    let text: String
    let symbol: String
    var warning = false
    @Environment(\.phoneTheme) private var theme
    var body: some View {
        Label(text, systemImage: symbol).font(.caption.weight(warning ? .semibold : .medium)).lineLimit(2)
            .foregroundStyle(warning ? theme.lit : theme.textSecondary)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(warning ? theme.warning.opacity(0.16) : theme.tile, in: RoundedRectangle(cornerRadius: chipCorner))
            .overlay { if warning { RoundedRectangle(cornerRadius: chipCorner).strokeBorder(theme.warning, lineWidth: 1) } }
    }
}

/// "How to shoot this" (or "How to see this"): the settings or advice, a row at a time, and where the numbers come from.
struct ShootingTipCard: View {
    let tip: ShootingTip
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Label(tip.title.plainDashes, systemImage: tip.symbol).font(.callout.weight(.medium))
                ForEach(Array(tip.rows.enumerated()), id: \.offset) { _, r in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(r.label.plainDashes).font(.caption).secondary()
                        Text(r.text.plainDashes).font(.footnote).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let s = tip.source { Text(s.plainDashes).font(.caption2).secondary() }
            }
        }
    }
}
