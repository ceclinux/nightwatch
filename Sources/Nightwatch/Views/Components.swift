import SwiftUI
import NightwatchUI
import SkyCore

/// A popover stat tile: label over value, an optional warning-colour hint, and a warning state (warning-colour outline and dot).
/// A missing value reads "No data" in the secondary colour. Values wrap rather than truncate.
struct StatTile: View {
    let label: String
    let value: String?
    var hint: String? = nil
    var warning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 10)).foregroundStyle(Tokens.textSecondary)
            Text(value ?? "No data").font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(value == nil ? Tokens.textSecondary : Tokens.textPrimary).fixedSize(horizontal: false, vertical: true)
            if let hint { Text(hint).font(.system(size: 9)).foregroundStyle(Tokens.statusWarning).fixedSize(horizontal: false, vertical: true) }
        }
        .padding(9).frame(maxWidth: .infinity, minHeight: 49.5, maxHeight: .infinity, alignment: .topLeading)   // fills its TileRow
        .overlay(alignment: .topTrailing) { if warning { WarningDot(size: 5).padding(7) } }
        .overlay { if warning { RoundedRectangle(cornerRadius: 8).stroke(Tokens.statusWarning.opacity(0.59), lineWidth: 0.75) } }
        .accessibilityElement(children: .combine)
        // A plain translucent fill on the glass panel, not a second glass layer: measured live (25 Sep 2026), system glass
        // tinted surface.tile rendered #5A5D63 and left text.secondary at 2.9:1. The fill keeps it near #373A40 (spec §7).
        .background(Tokens.surfaceTile, in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Black caption backing for text laid over an image (the detail page, v0.6.4), so white text stays legible on any photo.
extension View {
    func captionBacking(cornerRadius: CGFloat = 6) -> some View {
        background(Color.black.opacity(0.62), in: RoundedRectangle(cornerRadius: cornerRadius))
    }
    /// An 11 pt label in a caption backing: the detail page's back button and field-of-view note.
    func captionPill() -> some View {
        font(.system(size: 11)).foregroundStyle(Tokens.textPrimary).padding(.horizontal, 9).padding(.vertical, 5).captionBacking()
    }
}

/// A warning-colour dot and "{n} h ago" beside any timestamp older than the six-hour stale rule.
struct StaleBadge: View {
    let fetchedAt: Date
    var body: some View {
        HStack(spacing: 4) { WarningDot(size: 5); Text(Copy.hoursAgo(fetchedAt, now: Date())) }
            .font(.system(size: 10)).foregroundStyle(Tokens.statusWarning)
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
        .font(.system(size: 9.5, weight: .medium))
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

/// The popover's secondary button (Refresh, All targets): a filled surface.button pill with primary text, so it reads as a
/// button rather than a caption. One style, so the two can never drift apart.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium)).foregroundStyle(Tokens.textPrimary)
            .padding(.horizontal, 10).frame(minWidth: 44, minHeight: 22)
            .background(Tokens.surfaceButton.opacity(configuration.isPressed ? 0.6 : 1), in: RoundedRectangle(cornerRadius: 6))
            .contentShape(RoundedRectangle(cornerRadius: 6))
    }
}

