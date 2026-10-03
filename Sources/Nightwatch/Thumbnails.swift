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
    /// 1600 px stays (owner, 3 October 2026): the page's picture area is about 2,000 px wide on a Retina screen, and the
    /// survey's server takes 4 to 5 s for any size and about 3 s more for this one, once per target.
    static let cardWidth = ThumbnailFiles.cardWidth, detailWidth = 1600

    /// How much more sky a target's page photo shows than its card. None when the card already shows the whole field of
    /// view; for an object bigger than the field, 1.6, so the dashed box is at most 1/1.6 (62.5%) of the photo's width,
    /// and 1/(1.6 × 1.5) for an object much bigger than the field.
    static let boxContext = 1.6
    static func detailContext(for t: RankedTarget, fov: FieldOfView) -> Double {
        fovDeg(for: t, fov: fov) <= max(0.05, fov.widthDeg) + 1e-9 ? 1 : boxContext
    }

    /// True for a target pictured by a sky-survey photo: not the Moon, a planet, a constellation or the Milky Way.
    static func usesSurvey(_ t: RankedTarget) -> Bool {
        t.id != "moon" && PlanetImages.planet(forTargetID: t.id) == nil && t.group != .constellations && t.group != .planets
            && !MilkyWay.isMilkyWay(t.id)
    }

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
        guard let img = ImageMemory.image(at: f) else { return nil }
        let fm = FileManager.default, now = Date()
        if ThumbnailFiles.needsTouch(modified: (try? fm.attributesOfItem(atPath: f.path))?[.modificationDate] as? Date, now: now) {
            try? fm.setAttributes([.modificationDate: now], ofItemAtPath: f.path)
        }
        return img
    }

    static func image(for t: RankedTarget, fov: FieldOfView, width: Int = cardWidth, context: Double = 1) async -> NSImage? {
        // Planets and the Moon get real photographs, not a survey cutout.
        if t.id == "moon" { return await MoonImages.image(at: t.peakTime) }
        if let p = PlanetImages.planet(forTargetID: t.id) { return PlanetImages.url(for: p).flatMap(ImageMemory.image(at:)) }
        guard t.group != .constellations, t.group != .planets else { return nil }
        let f = file(for: t, fov: fov, width: width, context: context)
        if let img = cached(f) { return img }
        guard await download(for: t, fov: fov, width: width, context: context) else { return nil }
        return cached(f)
    }

    /// Fetches a survey photo to disk when it is not there yet; true when it is there afterwards. Kept apart from `image`
    /// so photos fetched ahead (Store.fetchPagePhotosAhead) go to disk without filling the memory cache.
    static func download(for t: RankedTarget, fov: FieldOfView, width: Int = cardWidth, context: Double = 1) async -> Bool {
        let f = file(for: t, fov: fov, width: width, context: context)
        if FileManager.default.fileExists(atPath: f.path) { return true }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // hips2fits took 12.5 s for a 1600 px image with extra sky (25 Sep 2026), so the large fetch gets more than the usual 20 s.
        let fetcher = URLSessionFetcher(timeout: width == cardWidth ? 20 : 45)
        guard let data = try? await fetcher.get(url(for: t, fov: fov, width: width, context: context)), NSImage(data: data) != nil,
              (try? data.write(to: f, options: .atomic)) != nil else { return false }
        pruneStaleImages()
        return true
    }

    /// A card's picture if it is already on this Mac, without waiting: for a view's first frame. Nil for a photo not yet
    /// downloaded (the task that follows fetches it) and for constellations, whose artwork is drawn separately.
    static func ready(for t: RankedTarget, fov: FieldOfView, width: Int = cardWidth, context: Double = 1) -> NSImage? {
        if t.id == "moon" { return MoonImages.ready(at: t.peakTime) }
        if let p = PlanetImages.planet(forTargetID: t.id) { return PlanetImages.url(for: p).flatMap(ImageMemory.image(at:)) }
        guard t.group != .constellations, t.group != .planets else { return nil }
        return ImageMemory.image(at: file(for: t, fov: fov, width: width, context: context))
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
                EventArt(name: target.id).padding(4)   // the owner's artwork (#114), named after the target, whole rather than cropped
            } else if let image = loader.image ?? Thumbnails.ready(for: target, fov: store.config.fov) {
                // The image lives in an overlay so its natural size never widens the layout; the card decides the size.
                Color.clear
                    .overlay(Image(nsImage: image).resizable().aspectRatio(contentMode: .fill))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if let art = loader.art ?? (target.group == .constellations ? ConstellationArt(id: target.id) : nil) {
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
            Bundle.main.url(forResource: "\(id)-\(name)", withExtension: "heic", subdirectory: "Constellations").flatMap(ImageMemory.image(at:))
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
