import AppKit
import SwiftUI
import SkyCore

/// DSS2 colour cutouts from CDS hips2fits at the user's field of view (or 1.5 × the object when it is bigger), cached per object and
/// FOV until not shown for 30 days.
enum Thumbnails {
    static let dir = Store.cacheDir.appendingPathComponent("thumbs", isDirectory: true)

    static func fovDeg(for t: RankedTarget, fov: FieldOfView) -> Double {
        let objectDeg = (t.sizeArcmin ?? 0) / 60
        return max(fov.widthDeg, objectDeg * 1.5, 0.05)
    }

    /// Cards use 480 px; the detail page fills the window, so it fetches 1600 px (hips2fits serves it, checked 25 Sep 2026).
    static let cardWidth = ThumbnailFiles.cardWidth, detailWidth = 1600

    /// `context` widens the view around the target (the detail page's dashed-box case).
    static func url(for t: RankedTarget, fov: FieldOfView, width: Int = cardWidth, context: Double = 1) -> URL {
        var c = URLComponents(string: "https://alasky.cds.unistra.fr/hips-image-services/hips2fits")!
        let f = fovDeg(for: t, fov: fov) * context
        c.queryItems = [
            .init(name: "hips", value: "CDS/P/DSS2/color"),
            .init(name: "ra", value: String(format: "%.5f", t.raHours * 15)),
            .init(name: "dec", value: String(format: "%.5f", t.decDeg)),
            .init(name: "fov", value: String(format: "%.3f", f)),
            .init(name: "width", value: String(width)),
            .init(name: "height", value: String(Int(Double(width) * max(0.05, fov.heightDeg) / max(0.05, fov.widthDeg)))),
            .init(name: "projection", value: "TAN"),
            .init(name: "format", value: "jpg")
        ]
        return c.url!
    }

    /// Card images keep their original names, so the existing cache stays valid; larger ones add their width.
    static func file(for t: RankedTarget, fov: FieldOfView, width: Int = cardWidth, context: Double = 1) -> URL {
        dir.appendingPathComponent(ThumbnailFiles.name(id: t.id, fovWidthDeg: fov.widthDeg, fovHeightDeg: fov.heightDeg, width: width, context: context))
    }

    /// When the images were last pruned: at most once a day, after a new image is saved.
    nonisolated(unsafe) private static var prunedAt = Date.distantPast

    /// Drops card and detail images not shown for 30 days.
    static func pruneStaleImages(now: Date = Date()) {
        guard now.timeIntervalSince(prunedAt) > 86_400 else { return }
        prunedAt = now
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return }
        var modified: [String: Date] = [:]
        for n in names { modified[n] = (try? fm.attributesOfItem(atPath: dir.appendingPathComponent(n).path))?[.modificationDate] as? Date }
        for n in ThumbnailFiles.staleImages(names: names, modified: modified, now: now) { try? fm.removeItem(at: dir.appendingPathComponent(n)) }
    }

    /// A saved image, its date refreshed as it is shown again, so pruning keeps it; nil when not saved.
    static func cached(_ f: URL) -> NSImage? {
        guard let img = NSImage(contentsOf: f) else { return nil }
        let fm = FileManager.default, now = Date()
        if ThumbnailFiles.needsTouch(modified: (try? fm.attributesOfItem(atPath: f.path))?[.modificationDate] as? Date, now: now) {
            try? fm.setAttributes([.modificationDate: now], ofItemAtPath: f.path)
        }
        return img
    }

    static func image(for t: RankedTarget, fov: FieldOfView, width: Int = cardWidth, context: Double = 1) async -> NSImage? {
        // Planets and the Moon get real photographs, not a survey cutout.
        if t.id == "moon" { return await MoonImages.image(at: t.peakTime) }
        if let p = PlanetImages.planet(forTargetID: t.id) { return PlanetImages.url(for: p).flatMap { NSImage(contentsOf: $0) } }
        guard t.group != .constellations, t.group != .planets else { return nil }
        let f = file(for: t, fov: fov, width: width, context: context)
        if let img = cached(f) { return img }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // hips2fits took 12.5 s for a 1600 px image with extra sky (25 Sep 2026), so the large fetch gets more than the usual 20 s.
        let fetcher = URLSessionFetcher(timeout: width == cardWidth ? 20 : 45)
        guard let data = try? await fetcher.get(url(for: t, fov: fov, width: width, context: context)), let img = NSImage(data: data) else { return nil }
        try? data.write(to: f, options: .atomic)
        pruneStaleImages()
        return img
    }
}

/// `art`: a constellation's artwork, loaded once per card in the same task as the photo thumbnails, never in `body`.
final class ThumbnailLoader: ObservableObject {
    @Published var image: NSImage?
    /// How many degrees `image` spans across, so the detail page can size the dashed box on it.
    @Published var imageFovDeg: Double?
    @Published var art: ConstellationArt?
}

struct ThumbnailView: View {
    @EnvironmentObject var store: Store
    let target: RankedTarget
    @StateObject private var loader = ThumbnailLoader()

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Color(red: 0.055, green: 0.063, blue: 0.094))
            if MilkyWay.isMilkyWay(target.id) {
                EventArt(name: "milky-way").padding(4)   // the owner's artwork (#114), whole rather than cropped
            } else if let image = loader.image {
                // The image lives in an overlay so its natural size never widens the layout; the card decides the size.
                Color.clear
                    .overlay(Image(nsImage: image).resizable().aspectRatio(contentMode: .fill))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if let art = loader.art {
                art.padding(4)
            } else {
                Image(systemName: Theme.glyph(for: target.group)).font(.title2).foregroundStyle(Theme.dim)
            }
        }
        .task(id: target.id) {
            if target.group == .constellations { loader.art = ConstellationArt(id: target.id); return }
            if MilkyWay.isMilkyWay(target.id) { return }
            loader.image = await Thumbnails.image(for: target, fov: store.config.fov)
        }
    }
}

/// The owner's constellation artwork (v0.6.2): the figure with its star plot on top, fitted rather than cropped.
/// The build copies Resources/Constellations into the app; `scripts/import-constellations.sh` makes the files.
struct ConstellationArt: View {
    let figure: NSImage
    let plot: NSImage

    init?(id: String) {
        func layer(_ name: String) -> NSImage? {
            Bundle.main.url(forResource: "\(id)-\(name)", withExtension: "heic", subdirectory: "Constellations").flatMap(NSImage.init(contentsOf:))
        }
        guard let f = layer("figure"), let p = layer("plot") else { return nil }
        figure = f; plot = p
    }

    var body: some View {
        ZStack {
            Image(nsImage: figure).resizable().aspectRatio(contentMode: .fit)
            Image(nsImage: plot).resizable().aspectRatio(contentMode: .fit)
        }
        .accessibilityHidden(true)
    }
}
