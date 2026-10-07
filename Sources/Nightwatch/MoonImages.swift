import AppKit
import SwiftUI
import NightwatchUI
import SkyCore

/// Real Moon image for the hour in question, from NASA SVS Dial-a-Moon, cached per UTC hour.
enum MoonImages {
    static let dir = Store.cacheDir.appendingPathComponent("moon", isDirectory: true)

    private static func file(at date: Date) -> URL { dir.appendingPathComponent("\(MoonImage.hourKey(for: date)).jpg") }

    /// This hour's Moon if it is already on this Mac, without waiting: for a view's first frame.
    static func ready(at date: Date) -> NSImage? { ImageMemory.image(at: file(at: date)) }

    static func image(at date: Date) async -> NSImage? {
        let file = file(at: date)
        if let img = ImageMemory.image(at: file) { return img }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fetcher = URLSessionFetcher()
        guard let meta = try? await fetcher.get(MoonImage.apiURL(for: date)),
              let info = try? MoonImage.parse(meta),
              let data = try? await fetcher.get(info.imageURL),
              let img = NSImage(data: data) else { return nil }
        try? data.write(to: file, options: .atomic)
        ImageMemory.store(img, for: file)
        return img
    }
}

final class MoonLoader: ObservableObject { @Published var image: NSImage? }

/// The popover's Moon tile: the rendered Moon (32 pt, dark rim) beside "{n}%" and "Sets 06:10" (or "Down tonight" alone).
struct MoonTile: View {
    let value: String
    let line: String?
    let at: Date
    @StateObject private var loader = MoonLoader()

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(Color(red: 0.055, green: 0.063, blue: 0.094))
                if let img = loader.image ?? MoonImages.ready(at: at) {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fill).clipShape(Circle())
                } else {
                    Image(systemName: "moon").font(Font.scaled(.caption)).foregroundStyle(Tokens.textSecondary)
                }
            }
            .frame(width: 32, height: 32)
            .overlay(Circle().stroke(Color.black.opacity(0.6), lineWidth: 1.5))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.system(size: TextScale.pt(12.5), weight: .medium)).fixedSize(horizontal: false, vertical: true)
                if let line { Text(line).font(.system(size: TextScale.pt(9))).foregroundStyle(Tokens.textSecondary) }
            }
            Spacer(minLength: 0)
        }
        .padding(9).frame(maxWidth: .infinity, minHeight: 49.5, maxHeight: .infinity, alignment: .leading)   // fills its TileRow
        .accessibilityElement(children: .combine).accessibilityLabel(L10n.format("Moon, \(value)\(line.map { ", \($0)" } ?? "")"))
        // A plain translucent fill on the glass panel, not a second glass layer: measured live (25 Sep 2026), system glass
        // tinted surface.tile rendered #5A5D63 and left text.secondary at 2.9:1. The fill keeps it near #373A40 (spec §7).
        .background(Tokens.surfaceTile, in: RoundedRectangle(cornerRadius: 8))
        .task(id: MoonImage.hourKey(for: at)) { loader.image = await MoonImages.image(at: at) }
    }
}
