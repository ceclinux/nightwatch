import AppKit
import MapKit
import SwiftUI
import SkyCore
import NightwatchUI

/// Where a dark site is, on Apple Maps (owner's UAT and approved mock-up, 29 September 2026): "Dark spot near Hazlewood with
/// Storiths" still left people asking where. A small map for its card, drawn once and saved with the sky images (so the
/// 30-day pruning covers it too), and Open in Maps.
enum SiteMaps {
    /// About 5 km across, so the nearest roads and villages show, at the card's shape.
    static let widthMetres = 5000.0, size = CGSize(width: 560, height: 200)

    static func file(for s: DarkSite) -> URL { Thumbnails.dir.appendingPathComponent("map-\(s.id).jpg") }

    /// The picture's brightness on a coarse grid, for `MapSnapshot.isBlank`.
    private static func brightness(of img: NSImage) -> [Double] {
        guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return [] }
        let w = 32, h = 12
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var out: [Double] = []
        for i in stride(from: 0, to: px.count, by: 4) {
            let r = Double(px[i]), g = Double(px[i + 1]), b = Double(px[i + 2])
            out.append((0.2126 * r + 0.7152 * g + 0.0722 * b) / 255)
        }
        return out
    }
    static func isBlank(_ img: NSImage) -> Bool { MapSnapshot.isBlank(brightness: brightness(of: img)) }

    /// The map around a point, not saved: the add-site preview changes with every search or typed coordinate. Nil when Apple Maps
    /// could not load its tiles and drew its blank grid instead: the card shows its placeholder and asks again next time.
    static func snapshot(at c: Coordinate) async -> NSImage? {
        let o = MKMapSnapshotter.Options()
        o.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude),
                                      latitudinalMeters: widthMetres * size.height / size.width, longitudinalMeters: widthMetres)
        o.size = size
        o.appearance = NSAppearance(named: .darkAqua)
        guard let img = try? await MKMapSnapshotter(options: o).start().image, !isBlank(img) else { return nil }
        return img
    }

    static func image(for s: DarkSite) async -> NSImage? {
        let f = file(for: s)
        if let img = Thumbnails.cached(f) {
            if !isBlank(img) { return img }
            // A blank kept from a time Apple Maps could not load its tiles: forget it and ask again.
            try? FileManager.default.removeItem(at: f)
            ImageMemory.remove(f)
        }
        guard let img = await snapshot(at: s.coordinate) else { return nil }
        if let tiff = img.tiffRepresentation, let jpg = NSBitmapImageRep(data: tiff)?.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) {
            try? FileManager.default.createDirectory(at: Thumbnails.dir, withIntermediateDirectories: true)
            try? jpg.write(to: f, options: .atomic)
            Thumbnails.pruneStaleImages()
        }
        return img
    }

    /// Apple Maps at the site, pinned and labelled with its name.
    static func open(_ s: DarkSite) {
        let location = CLLocation(latitude: s.coordinate.latitude, longitude: s.coordinate.longitude)
        let item: MKMapItem
        if #available(macOS 26, *) { item = MKMapItem(location: location, address: nil) }
        else { item = MKMapItem(placemark: MKPlacemark(coordinate: location.coordinate)) }
        item.name = s.name
        item.openInMaps(launchOptions: nil)
    }
}

/// The map at the top of a dark-site card, and in Add a site, with a pin on the place; the words beside it carry it for
/// VoiceOver.
struct SiteMapView: View {
    private let key: String
    private let load: () async -> NSImage?
    @State private var image: NSImage?

    init(site: DarkSite) { key = site.id; load = { await SiteMaps.image(for: site) } }
    init(coordinate c: Coordinate) { key = String(format: "%.4f,%.4f", c.latitude, c.longitude); load = { await SiteMaps.snapshot(at: c) } }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Tokens.surfaceTile)
            if let image {
                Color.clear.overlay(Image(nsImage: image).resizable().aspectRatio(contentMode: .fill))
                Circle().fill(Tokens.ember).frame(width: 16, height: 16).overlay(Circle().stroke(.white, lineWidth: 2.5))
            } else {
                Image(systemName: "moon.stars").font(Font.scaled(.title2)).foregroundStyle(Theme.dim)
            }
        }
        .frame(height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityHidden(true)
        .task(id: key) { image = await load() }
    }
}
