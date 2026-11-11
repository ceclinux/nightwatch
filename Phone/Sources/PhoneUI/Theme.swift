import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

/// The app's colours, in two sets: the Mac app's dark palette, and a red-only one for use at the telescope. See docs/brand.md.
/// Every screen reads the set from the environment, so switching it changes the whole app at once.
public struct PhoneTheme: Equatable, Sendable {
    public var isRed: Bool
    public var background: Color
    public var card: Color
    public var track: Color
    public var textPrimary: Color
    public var textSecondary: Color
    /// Supporting text under Increase Contrast.
    public var textSecondaryHigh: Color
    public var accent: Color
    public var warning: Color
    public var hairline: Color
    public var barCloudy: Color
    public var barTrack: Color
    public var tickCloudy: Color
    public var tickPartCloud: Color
    public var tickDaylight: Color
    public var ring: Color
    /// The hero card's gradient (clear night / no window) and its top-edge highlight; the quieter tile fill.
    public var heroClear: [Color]
    public var heroDull: [Color]
    public var highlight: Color
    /// The top of the sky behind Tonight, fading into the background.
    public var skyTop: Color
    public var tile: Color
    public var outline: Color
    /// The "Best 03:43 · 87° overhead" (or "· 75° in the SE") line under a target.
    public var bestLine: Color
    /// The horizon dial: what blocks the sky, and the hills the elevation data finds.
    public var blocked: Color
    public var terrain: Color
    /// Warm white for what is lit on iPad and iPhone (the clear hours on the arc, the hours and dew line, a target's best time). One
    /// quiet tone, not a colour: the photograph supplies the colour. The Mac keeps the system accent.
    public var lit: Color
    /// The one warm accent, used sparingly: the call-to-action pill and the marker for the current hour. A flat colour, never a glow.
    public var ember: Color
    /// Frosted-glass cards over the photograph: a faint white fill and a hairline (a red-only pair in red mode).
    public var glassFill: Color
    public var glassHairline: Color

    public static let normal = PhoneTheme(
        isRed: false, background: Color(hex: 0x14171D), card: Color(hex: 0x1C1F27, opacity: 0.80), track: Color(hex: 0x272A34),
        textPrimary: Color(hex: 0xE8EAEF), textSecondary: Color(hex: 0xA8AEBE), textSecondaryHigh: Color(hex: 0xCDD2DC),
        accent: Color(hex: 0xF4F1EA), warning: Color(hex: 0xE8A04A), hairline: Color(hex: 0x272A34),
        barCloudy: Color.white.opacity(0.35), barTrack: Color.white.opacity(0.07),
        tickCloudy: Color.white.opacity(0.31), tickPartCloud: Color.white.opacity(0.47), tickDaylight: Color.white.opacity(0.12),
        ring: Color.white.opacity(0.09),
        heroClear: [Color(hex: 0x1A2750), Color(hex: 0x1C1F27)], heroDull: [Color(hex: 0x262932), Color(hex: 0x1C1F27)],
        highlight: Color.white.opacity(0.14), skyTop: Color(hex: 0x0B1030), tile: Color(hex: 0x1A1D26, opacity: 0.92), outline: Color(hex: 0x272A34), bestLine: Color(hex: 0xCDD2DC), blocked: Color.white.opacity(0.28), terrain: Color(hex: 0xB07A45, opacity: 0.30),
        lit: Color(hex: 0xF4F1EA), ember: Color(hex: 0xE8A04A), glassFill: Color.white.opacity(0.09), glassHairline: Color.white.opacity(0.16))

    /// Red on black and nothing else, so dark adaptation survives. No yellow: a warning is drawn with a dashed outline and a "!".
    public static let red = PhoneTheme(
        isRed: true, background: Color(hex: 0x000000), card: Color(hex: 0x120000), track: Color(hex: 0x2E0000),
        textPrimary: Color(hex: 0xE0281C), textSecondary: Color(hex: 0x8F1710), textSecondaryHigh: Color(hex: 0xB5281C),
        accent: Color(hex: 0xFF2A1A), warning: Color(hex: 0xFF2A1A), hairline: Color(hex: 0x2E0000),
        barCloudy: Color(hex: 0xA0140C, opacity: 0.55), barTrack: Color(hex: 0x260000),
        tickCloudy: Color(hex: 0xA0140C, opacity: 0.55), tickPartCloud: Color(hex: 0xA0140C, opacity: 0.8), tickDaylight: Color(hex: 0xA0140C, opacity: 0.2),
        ring: Color(hex: 0xA0140C, opacity: 0.25),
        heroClear: [Color(hex: 0x2A0000), Color(hex: 0x120000)], heroDull: [Color(hex: 0x180000), Color(hex: 0x120000)],
        highlight: Color(hex: 0xA0140C, opacity: 0.35), skyTop: Color(hex: 0x1A0000), tile: Color(hex: 0x1A0000, opacity: 0.92), outline: Color(hex: 0x2E0000), bestLine: Color(hex: 0xB5281C), blocked: Color(hex: 0xA0140C, opacity: 0.45), terrain: Color(hex: 0xFF2A1A, opacity: 0.25),
        lit: Color(hex: 0xFF2A1A), ember: Color(hex: 0xFF2A1A), glassFill: Color(hex: 0xA0140C, opacity: 0.10), glassHairline: Color(hex: 0xA0140C, opacity: 0.35))

    public static func named(red: Bool) -> PhoneTheme { red ? .red : .normal }
}

private struct PhoneThemeKey: EnvironmentKey { static let defaultValue = PhoneTheme.normal }

extension EnvironmentValues {
    public var phoneTheme: PhoneTheme {
        get { self[PhoneThemeKey.self] }
        set { self[PhoneThemeKey.self] = newValue }
    }
}

extension View {
    /// Draw this view and everything in it with `theme`, on its background, always dark.
    public func phoneTheme(_ theme: PhoneTheme) -> some View {
        environment(\.phoneTheme, theme)
            .background(theme.background.ignoresSafeArea())
            .foregroundStyle(theme.textPrimary)
            .tint(theme.accent)
            .preferredColorScheme(.dark)
    }
}

/// The supporting-text colour, brighter under Increase Contrast.
struct SecondaryText: ViewModifier {
    @Environment(\.phoneTheme) private var theme
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        content.foregroundStyle(contrast == .increased ? theme.textSecondaryHigh : theme.textSecondary)
    }
}

extension View {
    func secondary() -> some View { modifier(SecondaryText()) }
}

#if canImport(UIKit)
import UIKit
extension Image {
    /// An image from its file data, as supplied.
    init?(platformData data: Data) {
        guard let i = UIImage(data: data) else { return nil }
        self.init(uiImage: i)
    }
}
#elseif canImport(AppKit)
import AppKit
extension Image {
    init?(platformData data: Data) {
        guard let i = NSImage(data: data) else { return nil }
        self.init(nsImage: i)
    }
}
#endif
