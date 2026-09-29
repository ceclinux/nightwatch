import SwiftUI

extension Color {
    public init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }

    /// `normal`, or `increased` under System Settings › Accessibility › Display › Increase contrast (#60): macOS then draws
    /// with its high-contrast appearances, which the colour reads each time it is drawn, in the app and the widgets alike.
    static func contrast(_ normal: NSColor, _ increased: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let high: [NSAppearance.Name] = [.accessibilityHighContrastDarkAqua, .accessibilityHighContrastAqua,
                                             .accessibilityHighContrastVibrantDark, .accessibilityHighContrastVibrantLight]
            return appearance.bestMatch(from: high + [.darkAqua, .aqua]).map(high.contains) == true ? increased : normal
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: Double = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

/// Design tokens, v0.4 spec §4. The spec's dotted names are in the comments.
public enum Tokens {
    public static let textPrimary = Color(hex: 0xE8EAEF)                 // text.primary
    public static let textSecondary = Color.contrast(NSColor(hex: 0xA8AEBE), NSColor(hex: 0xCDD2DC))   // text.secondary; brighter under Increase contrast
    // The accent follows the colour chosen in System Settings, and Nightwatch sets none of its own, so Multicolour gives
    // macOS blue (owner, 28 September 2026: the red and the orange clashed, and glare at the telescope mattered less than
    // expected). Warnings keep a colour of their own that sits with any accent.
    public static let accentClear = Color.accentColor                    // accent.clear: the System Settings accent
    public static let accentClearLow = Color.accentColor.opacity(0.35)   // accent.clear.low
    public static let statusWarning = Color(hex: 0xEDB40D)               // status.warning (owner, 28 September 2026)
    public static let controlOn = Color(hex: 0x0A84FF)                   // control.on: system blue, never green
    public static let glassTint = Color(hex: 0x0C0E16, opacity: 0.62)    // glass.tint
    public static let glassHairline = Color.contrast(NSColor(white: 1, alpha: 0.12), NSColor(white: 1, alpha: 0.45))   // glass.hairline
    public static let surfaceTile = Color.contrast(NSColor(white: 1, alpha: 0.06), NSColor(white: 1, alpha: 0.12))   // surface.tile
    public static let surfaceTrack = Color.white.opacity(0.07)           // surface.track
    public static let surfaceButton = Color.white.opacity(0.23)          // surface.button
    public static let tickCloudy = Color.white.opacity(0.31)             // tick.cloudy
    public static let tickPartCloud = Color.white.opacity(0.47)          // tick.partcloud
    public static let tickDaylight = Color.white.opacity(0.12)           // tick.daylight
    public static let barCloudy = Color.white.opacity(0.35)              // bar.cloudy
    public static let targetsBackground = Color(hex: 0x14171D)           // targets.background
    public static let targetsCard = Color(hex: 0x1C1F27)                 // targets.card
    public static let targetsTrack = Color(hex: 0x272A34)                // targets.track: timeline tracks, bar gaps
    /// Card and strip outlines: the track colour normally, a clear white edge under Increase contrast (#60). Kept apart from
    /// the track so the timeline's grey "up in darkness" bar still stands out against it.
    public static let cardOutline = Color.contrast(NSColor(hex: 0x272A34), NSColor(white: 1, alpha: 0.45))
    public static let bestLine = Color(hex: 0xCDD2DC)                    // handover type table: the target "Best" line

    /// accent.clear.low towards accent.clear by u (0…1): the accent's opacity, since the accent is only known at run time.
    public static func clearBlend(_ u: Double) -> Color {
        Color.accentColor.opacity(0.35 + 0.65 * min(1, max(0, u)))
    }
}
