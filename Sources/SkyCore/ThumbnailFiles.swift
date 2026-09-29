import Foundation

/// Names of cached survey images. Card images keep the name they have always had (`<id>-<w>x<h>.jpg`), so the existing
/// cache stays valid; the detail page's larger images add their width, and their extra sky (v0.6.4).
public enum ThumbnailFiles {
    public static let cardWidth = 480

    public static func name(id: String, fovWidthDeg: Double, fovHeightDeg: Double, width: Int = cardWidth, context: Double = 1) -> String {
        let size = width == cardWidth ? "" : "-w\(width)", wider = context == 1 ? "" : String(format: "-c%.1f", context)
        return "\(id)-\(String(format: "%.2fx%.2f", fovWidthDeg, fovHeightDeg))\(size)\(wider).jpg"
    }

    /// Images not shown for `maxAge` (30 days), cards and detail pages alike: a shown image has its date refreshed, so an
    /// old date means unused (owner, 29 September 2026: each telescope's field of view kept its own set of cards forever).
    /// Only Nightwatch's own `.jpg` images; a file whose date is unknown is kept.
    public static func staleImages(names: [String], modified: [String: Date], now: Date, maxAge: TimeInterval = 30 * 86_400) -> [String] {
        names.filter { n in
            guard n.hasSuffix(".jpg"), let m = modified[n] else { return false }
            return now.timeIntervalSince(m) > maxAge
        }
    }

    /// A shown image's date is refreshed once it is a day old, so browsing does not rewrite it every time.
    public static func needsTouch(modified: Date?, now: Date) -> Bool {
        modified.map { now.timeIntervalSince($0) > 86_400 } ?? false
    }
}
