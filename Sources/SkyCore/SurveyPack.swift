import Foundation

/// The pre-built set of target pictures: one 480 x 274 WebP of colour DSS2 for each target the app lists, cut once (scripts/build-survey-set.py) from the
/// survey's HiPS tiles and published as one file on a GitHub release. It exists so that an outage of CDS (hips2fits was down for days from 26 October
/// 2026 and every card fell back to its icon) never empties the cards again, and so each user's first view of a target is a local lookup.
///
/// File layout: the 8 bytes `NWSURV1\n`, a little-endian UInt32 length N, N bytes of JSON `{"entries": {key: [offset, length]}}`, then the pictures;
/// offsets count from the first picture byte. A key is the card request's own numbers, `ra|dec|fov|width|height` as the app prints them into the
/// hips2fits address, so a lookup needs no catalogue and a request for any other field of view or size simply misses.
public struct SurveyPack: Sendable {
    public static let magic = Data("NWSURV1\n".utf8)

    private let data: Data
    private let base: Int
    private let entries: [String: [Int]]

    public init?(_ data: Data) {
        let head = Self.magic.count + 4
        guard data.count > head, data.prefix(Self.magic.count) == Self.magic else { return nil }
        let n = (0..<4).reduce(0) { $0 | Int(data[data.startIndex + Self.magic.count + $1]) << (8 * $1) }
        guard n > 0, head + n <= data.count,
              let json = try? JSONSerialization.jsonObject(with: data.subdata(in: (data.startIndex + head)..<(data.startIndex + head + n))) as? [String: Any],
              let entries = json["entries"] as? [String: [Int]] else { return nil }
        let base = head + n, size = data.count
        self.data = data
        self.base = base
        self.entries = entries.filter { $0.value.count == 2 && $0.value[0] >= 0 && $0.value[1] > 0 && base + $0.value[0] + $0.value[1] <= size }
    }

    public var count: Int { entries.count }

    public func picture(forKey key: String) -> Data? {
        guard let e = entries[key] else { return nil }
        return data.subdata(in: (data.startIndex + base + e[0])..<(data.startIndex + base + e[0] + e[1]))
    }

    /// The key for a hips2fits card request: nil for any other address.
    public static func key(for url: URL) -> String? {
        guard url.host == "alasky.cds.unistra.fr", let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        let parts = ["ra", "dec", "fov", "width", "height"].map { n in q.first { $0.name == n }?.value }
        return parts.contains { $0 == nil } ? nil : parts.compactMap { $0 }.joined(separator: "|")
    }
}

/// Keeps the pack on disk and serves pictures from it. The file is fetched once, the first time a card asks (the callers only ask when optional
/// downloads are allowed), and kept in the caches folder, which the system may empty: the next request then fetches it again. A failed fetch is not
/// repeated for an hour, so a screen of cards does not each wait out a timeout.
public actor SurveyPackStore {
    public static let shared = SurveyPackStore()
    public typealias Get = @Sendable (URL, TimeInterval) async throws -> Data

    /// A prerelease, so GitHub's "latest release" (the app's update check and the disk image link) stays the app's own.
    public static let source = URL(string: "https://github.com/rsutcliffe/nightwatch/releases/download/survey-set-1/survey-set.nwsp")!
    static let retryAfter: TimeInterval = 3600
    static let maxBytes = 100_000_000

    private let file: URL
    private let source: URL
    private let get: Get
    private var pack: SurveyPack?
    private var loading: Task<SurveyPack?, Never>?
    private var failedAt = Date.distantPast

    public init(file: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("Nightwatch", isDirectory: true).appendingPathComponent("survey-set.nwsp"),
                source: URL = SurveyPackStore.source,
                get: @escaping Get = { try await URLSessionFetcher(timeout: $1).get($0) }) {
        self.file = file; self.source = source; self.get = get
    }

    /// The pack's picture for a hips2fits card request, or nil when the pack has none (or cannot be had).
    public func picture(for url: URL, now: Date = Date()) async -> Data? {
        guard let key = SurveyPack.key(for: url) else { return nil }
        return await available(now: now)?.picture(forKey: key)
    }

    private func available(now: Date) async -> SurveyPack? {
        if let pack { return pack }
        if let task = loading { return await task.value }
        if let data = try? Data(contentsOf: file, options: .mappedIfSafe), let p = SurveyPack(data) { pack = p; return p }
        guard now.timeIntervalSince(failedAt) > Self.retryAfter else { return nil }
        let (file, source, get) = (file, source, get)
        let task = Task<SurveyPack?, Never> {
            guard let data = try? await get(source, 120), data.count < Self.maxBytes, let p = SurveyPack(data) else { return nil }
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
            return p
        }
        loading = task
        let p = await task.value
        loading = nil
        if let p { pack = p } else { failedAt = now }
        return p
    }
}
