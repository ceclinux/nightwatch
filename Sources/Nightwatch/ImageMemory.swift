import AppKit

/// Pictures already read from disk, kept in memory so a card or tile can draw its picture in its first frame. Before this
/// (to 1.2.3) every card was drawn empty and read its file in a task afterwards, so even downloaded pictures popped in a
/// moment late, on every popover open and every scroll (owner, 3 October 2026). macOS empties it when memory is short.
enum ImageMemory {
    nonisolated(unsafe) private static let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.totalCostLimit = 64 * 1024 * 1024   // decoded bytes: about a hundred card photos, or a few page-sized ones
        return c
    }()

    /// The picture in `file`, from memory or else from disk; nil when there is no such file.
    static func image(at file: URL) -> NSImage? {
        if let hit = cache.object(forKey: file.path as NSString) { return hit }
        guard let img = NSImage(contentsOf: file) else { return nil }
        store(img, for: file)
        return img
    }

    /// Remembers a picture just downloaded, under the file it was saved to.
    static func store(_ img: NSImage, for file: URL) {
        let rep = img.representations.first
        cache.setObject(img, forKey: file.path as NSString, cost: (rep?.pixelsWide ?? 512) * (rep?.pixelsHigh ?? 512) * 4)
    }
}
