import SwiftUI
import NightwatchUI

/// Liquid Glass on macOS 26 and later with Reduce Transparency and Increase Contrast off; the solid `fill` otherwise (spec §3,
/// #60): text on glass sits on whatever is behind it, so both settings get a ground of known colour.
/// Apply it after every other appearance modifier, as Apple's guidance asks.
struct NightwatchGlass<S: Shape>: ViewModifier {
    let shape: S
    let fill: Color
    let tint: Color
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        if #available(macOS 26, *), !reduceTransparency, contrast != .increased {
            content.glassEffect(.regular.tint(tint), in: shape)
        } else {
            content.background(fill, in: shape)
        }
    }
}

extension View {
    func nightwatchGlass(in shape: some Shape, fill: Color = Tokens.targetsBackground, tint: Color = Tokens.glassTint) -> some View {
        modifier(NightwatchGlass(shape: shape, fill: fill, tint: tint))
    }
}

/// One `GlassEffectContainer` around a group of glass views, as Apple advises for performance; a plain group otherwise.
struct GlassGroup<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        if #available(macOS 26, *), !reduceTransparency, contrast != .increased {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
    }
}
