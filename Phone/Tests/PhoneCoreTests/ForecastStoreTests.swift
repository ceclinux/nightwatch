import Testing
import Foundation
import SkyCore
@testable import PhoneCore

private func tempFile() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("phonecore-\(UUID().uuidString)/forecast.json")
}

@Test func aSavedForecastComesBackIdentical() throws {
    let store = ForecastStore(url: tempFile())
    let fc = forecast(fetchedAt: utc(2026, 9, 23, 9))
    try store.save(fc)
    #expect(store.load() == fc)
}

@Test func nothingSavedOrAnUnreadableFileIsJustAMiss() throws {
    let url = tempFile()
    let store = ForecastStore(url: url)
    #expect(store.load() == nil)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("not json".utf8).write(to: url)
    #expect(store.load() == nil)
}

@Test func aForecastBelongsToASiteWithinAHundredthOfADegree() {
    let fc = forecast(fetchedAt: utc(2026, 9, 23, 9))
    #expect(ForecastStore.matches(fc, site: sheffield))
    var near = sheffield; near.latitude += 0.009
    #expect(ForecastStore.matches(fc, site: near))
    var far = sheffield; far.longitude += 0.02
    #expect(!ForecastStore.matches(fc, site: far))
}

@Test func forecastAgeIsSaidInPlainWords() {
    let t = utc(2026, 9, 23, 12)
    func text(_ minutes: Double) -> String { ForecastAge(fetchedAt: t, now: t.addingTimeInterval(minutes * 60)).text }
    #expect(text(0) == "just now")
    #expect(text(12) == "12 min ago")
    #expect(text(60) == "1 hour ago")
    #expect(text(3 * 60 + 20) == "3 hours ago")
    #expect(text(3 * 24 * 60) == "3 days ago")
    #expect(ForecastAge(fetchedAt: t, now: t.addingTimeInterval(-5)).seconds == 0)   // a clock that ran backwards
}
