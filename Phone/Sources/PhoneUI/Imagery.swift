import SwiftUI
import SkyCore
import PhoneCore

/// Whether optional downloads (Moon picture, target photos) are allowed on this connection: not on cellular, Personal
/// Hotspot or Low Data Mode. Set once, at the root.
private struct AllowsDownloadsKey: EnvironmentKey { static let defaultValue = true }
extension EnvironmentValues {
    var allowsOptionalDownloads: Bool {
        get { self[AllowsDownloadsKey.self] }
        set { self[AllowsDownloadsKey.self] = newValue }
    }
}

/// Small on-disk image cache in the app's Caches folder, shared by the Moon picture and the target photos.
enum ImageCache {
    static func directory(_ name: String) -> URL {
        URL.cachesDirectory.appendingPathComponent("Nightwatch", isDirectory: true).appendingPathComponent(name, isDirectory: true)
    }

    static func load(_ file: URL) -> Data? { try? Data(contentsOf: file) }

    static func save(_ data: Data, to file: URL) {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}

/// The Moon as NASA's Dial-a-Moon renders it for the hour, as the Mac's Moon tile shows it (SkyCore's `MoonImage`). Cached
/// per UTC hour; without a picture, or when downloads are not allowed, the moon symbol stands in.
@MainActor
final class MoonLoader: ObservableObject {
    @Published var data: Data?
    private var loading = false

    func load(at date: Date, allowDownload: Bool) async {
        let file = ImageCache.directory("moon").appendingPathComponent("\(MoonImage.hourKey(for: date)).jpg")
        if let cached = ImageCache.load(file) { data = cached; return }
        guard allowDownload, !loading else { return }
        loading = true; defer { loading = false }
        let fetcher = URLSessionFetcher()
        guard let meta = try? await fetcher.get(MoonImage.apiURL(for: date)), let info = try? MoonImage.parse(meta),
              let bytes = try? await fetcher.get(info.imageURL) else { return }
        ImageCache.save(bytes, to: file)
        data = bytes
    }
}
