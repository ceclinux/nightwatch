import Foundation

/// Survey photos: the pre-built set (SurveyPack) when it holds the card, then CDS's hips2fits. When CDS cannot be reached (it was down for days
/// from 26 October 2026) a target outside the set shows its icon: a greyscale stand-in from NASA's SkyView was tried in 1.7.2 and 1.0.1 and then
/// removed (owner, 4 November 2026), because on a target's page the large grey picture replaced the colour card picture. Once CDS has failed it is
/// not tried again for ten minutes, so a screen of cards does not each wait out a timeout.
public actor SurveyFetch {
    public static let shared = SurveyFetch()
    public typealias Get = @Sendable (URL, TimeInterval) async throws -> Data

    static let retryAfter: TimeInterval = 600
    private var cdsDownUntil = Date.distantPast
    private let pack: SurveyPackStore

    public init(pack: SurveyPackStore = .shared) { self.pack = pack }

    public func image(_ url: URL, timeout: TimeInterval, now: Date = Date(),
                      get: Get = { try await URLSessionFetcher(timeout: $1).get($0) }) async -> Data? {
        guard SurveyPack.key(for: url) != nil else { return try? await get(url, timeout) }   // not a hips2fits request
        if let pic = await pack.picture(for: url) { return pic }
        guard now >= cdsDownUntil else { return nil }
        if let data = try? await get(url, timeout), !data.isEmpty { return data }
        cdsDownUntil = now.addingTimeInterval(Self.retryAfter)
        return nil
    }
}
