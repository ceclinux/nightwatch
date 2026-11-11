import Foundation
import Testing
@testable import SkyCore

private final class Hits: @unchecked Sendable {
    private let lock = NSLock(); private var n = 0
    func add() { lock.lock(); n += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return n }
}

@Suite struct SurveyPackTests {
    static let key = "83.82000|-5.39000|2.100|480|274"
    let url = URL(string: "https://alasky.cds.unistra.fr/hips-image-services/hips2fits?hips=CDS/P/DSS2/color&ra=83.82000&dec=-5.39000&fov=2.100&width=480&height=274&projection=TAN&format=jpg")!

    /// A pack file holding the given pictures, as scripts/build-survey-set.py writes it.
    static func pack(_ pictures: [String: Data]) -> Data {
        var body = Data(), entries: [String: [Int]] = [:]
        for (k, d) in pictures { entries[k] = [body.count, d.count]; body.append(d) }
        let json = try! JSONSerialization.data(withJSONObject: ["entries": entries])
        var out = SurveyPack.magic
        withUnsafeBytes(of: UInt32(json.count).littleEndian) { out.append(contentsOf: $0) }
        return out + json + body
    }

    @Test func aRequestsKeyIsItsOwnNumbers() {
        #expect(SurveyPack.key(for: url) == Self.key)
        #expect(SurveyPack.key(for: URL(string: "https://example.com/a?ra=1&dec=2&fov=3&width=4&height=5")!) == nil)
    }

    @Test func theFileIsReadAndAMissIsNil() {
        let a = Data("one".utf8), b = Data("two!".utf8)
        let pack = SurveyPack(Self.pack(["k1": a, "k2": b]))
        #expect(pack?.count == 2)
        #expect(pack?.picture(forKey: "k1") == a)
        #expect(pack?.picture(forKey: "k2") == b)
        #expect(pack?.picture(forKey: "other") == nil)
    }

    @Test func aDamagedFileIsRefused() {
        let good = Self.pack(["k": Data("picture".utf8)])
        #expect(SurveyPack(Data("not a pack".utf8)) == nil)
        #expect(SurveyPack(good.prefix(good.count - 3)).flatMap { $0.picture(forKey: "k") } == nil)   // a picture cut short is dropped, not served
    }

    @Test func theFileIsFetchedOnceThenKeptOnDisk() async {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("pack-\(UUID()).nwsp")
        let pic = Data("webp".utf8), hits = Hits()
        let bytes = Self.pack([Self.key: pic])
        let store = SurveyPackStore(file: file, get: { _, _ in hits.add(); return bytes })
        #expect(await store.picture(for: url) == pic)
        #expect(await store.picture(for: url) == pic)
        #expect(hits.count == 1)
        let later = SurveyPackStore(file: file, get: { _, _ in hits.add(); throw URLError(.timedOut) })   // a new run reads the file on disk
        #expect(await later.picture(for: url) == pic)
        #expect(hits.count == 1)
    }

    @Test func aFailedFetchIsNotRepeatedForAnHour() async {
        let hits = Hits(), now = Date()
        let store = SurveyPackStore(file: FileManager.default.temporaryDirectory.appendingPathComponent("pack-\(UUID()).nwsp"),
                                    get: { _, _ in hits.add(); throw URLError(.timedOut) })
        #expect(await store.picture(for: url, now: now) == nil)
        #expect(await store.picture(for: url, now: now.addingTimeInterval(60)) == nil)
        #expect(hits.count == 1)
        #expect(await store.picture(for: url, now: now.addingTimeInterval(3601)) == nil)
        #expect(hits.count == 2)
    }

    @Test func aTargetOutsideThePackMisses() async {
        let store = SurveyPackStore(file: FileManager.default.temporaryDirectory.appendingPathComponent("pack-\(UUID()).nwsp"),
                                    get: { _, _ in Self.pack(["other|key": Data("x".utf8)]) })
        #expect(await store.picture(for: url) == nil)
    }
}
