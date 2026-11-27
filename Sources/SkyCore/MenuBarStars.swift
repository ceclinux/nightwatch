import Foundation

/// The menu bar's picture of tonight (1.9, this branch). The owner's ask, 27 November 2026: when tonight is worth imaging,
/// show the menu-bar icon as solid stars rather than the usual single star.
///
/// "Visible tonight" here means what the app already calls a good night: the plan has a clear window inside darkness, and
/// the forecast behind it is under six hours old (the rule that marks a forecast stale in the popover and the icons).
/// The setting itself is `Config.menuBarFilledStars`; this only answers whether the stars are filled.
public enum MenuBarStars {
    /// Solid when there is a clear window and the forecast is not stale; the icon is the usual one otherwise.
    public static func filled(plan: NightPlan?, isStale: Bool) -> Bool {
        guard !isStale else { return false }
        return plan?.primary != nil
    }
}
