import Testing
import Foundation
@testable import SkyCore

@Test func pruneKeepsCurrentFreshFilesOnly() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let names = ["gb-a.json", "gb-b.json", "spot-1.json", "notes.txt", "gb-c.json"]
    let modified = ["gb-a.json": now.addingTimeInterval(-600), "gb-b.json": now.addingTimeInterval(-2 * 86_400),
                    "spot-1.json": now.addingTimeInterval(-60), "notes.txt": now]   // gb-c.json has no date: kept
    let out = CachePruning.filesToDelete(names: names, modified: modified, keepIDs: ["gb-a", "gb-b", "gb-c"], now: now)
    #expect(Set(out) == ["gb-b.json", "spot-1.json", "notes.txt"])
}

@Test func pruneDeletesFilesOnDisk() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for n in ["keep.json", "gone.json"] { try Data("{}".utf8).write(to: dir.appendingPathComponent(n)) }
    CachePruning.prune(directory: dir, keepIDs: ["keep"], now: Date())
    #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted() == ["keep.json"])
    CachePruning.prune(directory: dir.appendingPathComponent("missing"), keepIDs: [], now: Date())   // no throw on a missing folder
}

@Test func cardThumbnailNamesAreUnchanged() {
    #expect(ThumbnailFiles.name(id: "NGC7000", fovWidthDeg: 2.1, fovHeightDeg: 1.2) == "NGC7000-2.10x1.20.jpg")   // the pre-v0.6.4 name
    #expect(ThumbnailFiles.name(id: "NGC7000", fovWidthDeg: 2.1, fovHeightDeg: 1.2, width: 1600) == "NGC7000-2.10x1.20-w1600.jpg")
    #expect(ThumbnailFiles.name(id: "NGC7000", fovWidthDeg: 2.1, fovHeightDeg: 1.2, width: 1600, context: 1.6) == "NGC7000-2.10x1.20-w1600-c1.6.jpg")
}

@Test func imagesNotShownFor30DaysArePrunedCardsIncluded() {
    let now = Date(), old = now.addingTimeInterval(-31 * 86_400), recent = now.addingTimeInterval(-86_400)
    let names = ["M31-2.10x1.20.jpg", "M31-2.10x1.20-w1600.jpg", "NGC7000-2.10x1.20-w1600-c1.6.jpg", "M42-2.10x1.20-w1600.jpg",
                 "M42-1.65x1.24.jpg", "notes.txt", "M1-2.10x1.20.jpg"]
    let modified = [names[0]: old, names[1]: old, names[2]: old, names[3]: recent, names[4]: recent, names[5]: old]   // M1: no date, kept
    #expect(ThumbnailFiles.staleImages(names: names, modified: modified, now: now) == [names[0], names[1], names[2]])
    // A shown image's date is refreshed once a day, not every time.
    #expect(ThumbnailFiles.needsTouch(modified: old, now: now) && !ThumbnailFiles.needsTouch(modified: now.addingTimeInterval(-3600), now: now))
    #expect(!ThumbnailFiles.needsTouch(modified: nil, now: now))
}
