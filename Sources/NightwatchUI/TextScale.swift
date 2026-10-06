import SwiftUI

/// The app's text size (Settings › App › Text size, 1.5). Every font in the app's windows and popover is made through
/// `TextScale.pt` or `Font.scaled`, so one factor enlarges all of it. The desktop widgets never set the factor: WidgetKit
/// fixes their size, so their text stays as designed.
public enum TextScale {
    /// 1 is the size the app was designed at. Set by the app when its settings load or change, on the main thread.
    public static var factor: CGFloat = 1
    /// A point size, or a width that has to hold text, at the chosen text size.
    public static func pt(_ size: CGFloat) -> CGFloat { size * factor }
}

public extension Font {
    /// A system text style at the chosen text size. At the standard size it is the style itself, so nothing changes;
    /// larger, it is that style's own point size (and headline's bold) multiplied up, as macOS itself does not enlarge
    /// text styles for an app.
    static func scaled(_ style: Font.TextStyle) -> Font {
        guard TextScale.factor != 1 else { return .system(style) }
        return .system(size: TextScale.pt(TextScale.basePoints(style)), weight: style == .headline ? .bold : .regular)
    }
}

extension TextScale {
    /// macOS's point size for each text style (measured from NSFont.preferredFont on macOS 27, 6 October 2026).
    static func basePoints(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 26
        case .title: 22
        case .title2: 17
        case .title3: 15
        case .headline, .body: 13
        case .callout: 12
        case .subheadline: 11
        case .footnote, .caption, .caption2: 10
        @unknown default: 13
        }
    }
}
