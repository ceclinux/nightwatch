import Foundation
import Testing
@testable import SkyCore

private final class Calls: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []
    func add(_ u: URL) { lock.lock(); urls.append(u); lock.unlock() }
    var hosts: [String] { lock.lock(); defer { lock.unlock() }; return urls.compactMap(\.host) }
}

/// A fetcher whose pack cannot be had, so these tests never touch the network or the real caches folder.
private func noPack() -> SurveyFetch {
    SurveyFetch(pack: SurveyPackStore(file: FileManager.default.temporaryDirectory.appendingPathComponent("no-pack-\(UUID()).nwsp"),
                                      get: { _, _ in throw URLError(.notConnectedToInternet) }))
}

@Suite struct SurveyFetchTests {
    let cds = URL(string: "https://alasky.cds.unistra.fr/hips-image-services/hips2fits?hips=CDS/P/DSS2/color&ra=83.82000&dec=-5.39000&fov=2.100&width=480&height=270&projection=TAN&format=jpg")!
    let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00])

    @Test func cdsAnsweringIsEnough() async {
        let calls = Calls()
        let data = await noPack().image(cds, timeout: 1) { u, _ in calls.add(u); return self.jpeg }
        #expect(data == jpeg)
        #expect(calls.hosts == ["alasky.cds.unistra.fr"])
    }

    @Test func whenCdsFailsThereIsNoPictureAndNoOtherServiceIsAsked() async {
        let calls = Calls()
        let data = await noPack().image(cds, timeout: 1) { u, _ in calls.add(u); throw URLError(.timedOut) }
        #expect(data == nil)
        #expect(calls.hosts == ["alasky.cds.unistra.fr"])   // in particular, never a greyscale stand-in from another service
    }

    @Test func cdsIsLeftAloneForTenMinutesAfterItFails() async {
        let calls = Calls(), jpeg = self.jpeg
        let fetch = noPack(), now = Date()
        let get: SurveyFetch.Get = { u, _ in calls.add(u); throw URLError(.timedOut) }
        _ = await fetch.image(cds, timeout: 1, now: now, get: get)
        _ = await fetch.image(cds, timeout: 1, now: now.addingTimeInterval(60), get: get)
        #expect(calls.hosts.count == 1)
        let back = await fetch.image(cds, timeout: 1, now: now.addingTimeInterval(601)) { u, _ in calls.add(u); return jpeg }
        #expect(back == jpeg && calls.hosts.count == 2)
    }

    @Test func aPictureInThePackIsUsedAndNothingIsAsked() async throws {
        let calls = Calls(), pic = Data("webp".utf8)
        let store = SurveyPackStore(file: FileManager.default.temporaryDirectory.appendingPathComponent("pack-\(UUID()).nwsp"),
                                    get: { [cds] _, _ in SurveyPackTests.pack([SurveyPack.key(for: cds)!: pic]) })
        let data = await SurveyFetch(pack: store).image(cds, timeout: 1) { u, _ in calls.add(u); return self.jpeg }
        #expect(data == pic)
        #expect(calls.hosts.isEmpty)
    }

    @Test func aLargePictureNeverComesFromThePackOrAGreyStandIn() async {
        let big = URL(string: cds.absoluteString.replacingOccurrences(of: "width=480&height=270", with: "width=1600&height=900"))!
        let calls = Calls()
        let data = await noPack().image(big, timeout: 1) { u, _ in calls.add(u); throw URLError(.timedOut) }
        #expect(data == nil)
        #expect(calls.hosts == ["alasky.cds.unistra.fr"])
    }

    @Test func anyOtherAddressIsFetchedAsAsked() async {
        let other = URL(string: "https://example.com/a.jpg")!
        let data = await noPack().image(other, timeout: 1) { _, _ in self.jpeg }
        #expect(data == jpeg)
    }
}
