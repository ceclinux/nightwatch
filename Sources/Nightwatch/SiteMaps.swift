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

    static func image(for s: DarkSite) async -> NSImage? {
        let f = file(for: s)
        if let img = Thumbnails.cached(f) { return img }
        let o = MKMapSnapshotter.Options()
        o.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: s.coordinate.latitude, longitude: s.coordinate.longitude),
                                      latitudinalMeters: widthMetres * size.height / size.width, longitudinalMeters: widthMetres)
        o.size = size
        o.appearance = NSAppearance(named: .darkAqua)
        guard let snap = try? await MKMapSnapshotter(options: o).start() else { return nil }
        let img = snap.image
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

/// The map at the top of a dark-site card, with a pin on the site; the card's words carry it for VoiceOver.
struct SiteMapView: View {
    let site: DarkSite
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Tokens.surfaceTile)
            if let image {
                Color.clear.overlay(Image(nsImage: image).resizable().aspectRatio(contentMode: .fill))
                Circle().fill(Tokens.controlOn).frame(width: 16, height: 16).overlay(Circle().stroke(.white, lineWidth: 2.5))
            } else {
                Image(systemName: "moon.stars").font(.title2).foregroundStyle(Theme.dim)
            }
        }
        .frame(height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityHidden(true)
        .task(id: site.id) { image = await SiteMaps.image(for: site) }
    }
}
