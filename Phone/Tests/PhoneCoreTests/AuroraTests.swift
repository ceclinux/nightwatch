import Testing
import Foundation
import SkyCore
@testable import PhoneCore

/// What the fake aurora feed says, and how often it was asked.
final class AuroraFeed: @unchecked Sendable {
    var level = "amber"
    var updated = utc(2026, 9, 23, 21, 50)
    var asked: [URL] = []
    /// Only the aurora source (the app also reads comet and station feeds through the same door).
    func aurorawatchAsks() -> Int { asked.filter { $0 == AuroraWatch.url }.count }
    func data(for url: URL) -> Data {
        asked.append(url)
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return Data("<current_status><updated><datetime>\(f.string(from: updated))</datetime></updated><site_status project_id=\"project:AWN\" site_id=\"site:AWN\" status_id=\"\(level)\"/></current_status>".utf8)
    }
}

@MainActor private func auroraStore(at time: Date, cloud: Int = 5, feed: AuroraFeed, scheduler: FakeScheduler, clock: Clock,
                                   site: Site = sheffield) -> PhoneStore {
    let s = PhoneStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("aurora-\(UUID().uuidString)"),
                       provider: { site, now, _ in forecast(fetchedAt: now, cloud: cloud, site: site) }, scheduler: scheduler, clock: { clock.now },
                       feeds: { feed.data(for: $0) }, occultations: false, darkLookups: nil)
    s.config.sites = [site]; s.config.activeSiteName = site.name
    s.config.notifyEnabled = true
    s.config.aurora.enabled = true; s.config.aurora.threshold = .amber
    return s
}

@MainActor @Test func anAmberAuroraOnAClearDarkNightAlertsOnceAndAgainOnlyWhenItRises() async {
    let clock = Clock(utc(2026, 9, 23, 22)), feed = AuroraFeed(), sched = FakeScheduler()
    let s = auroraStore(at: clock.now, feed: feed, scheduler: sched, clock: clock)
    await s.refresh(force: true)
    #expect(sched.posted.filter { $0.kind == .aurora }.count == 1)
    clock.now = clock.now.addingTimeInterval(5 * 60); feed.updated = clock.now
    await s.pollAurora()
    #expect(sched.posted.filter { $0.kind == .aurora }.count == 1)       // same level, nothing new
    clock.now = clock.now.addingTimeInterval(5 * 60); feed.level = "red"; feed.updated = clock.now
    await s.pollAurora()
    #expect(sched.posted.filter { $0.kind == .aurora }.count == 2)       // a rise
}

@MainActor @Test func belowTheThresholdOrStaleOrOverCloudOrInDaylightThereIsNoAlert() async {
    // Yellow, with amber chosen.
    var clock = Clock(utc(2026, 9, 23, 22)), feed = AuroraFeed(), sched = FakeScheduler()
    feed.level = "yellow"
    var s = auroraStore(at: clock.now, feed: feed, scheduler: sched, clock: clock)
    await s.refresh(force: true)
    #expect(sched.posted.contains { $0.kind == .aurora } == false)
    // Published two hours ago.
    clock = Clock(utc(2026, 9, 23, 22)); feed = AuroraFeed(); sched = FakeScheduler(); feed.updated = clock.now.addingTimeInterval(-7200)
    s = auroraStore(at: clock.now, feed: feed, scheduler: sched, clock: clock)
    await s.refresh(force: true)
    #expect(sched.posted.contains { $0.kind == .aurora } == false)
    // Cloudy.
    clock = Clock(utc(2026, 9, 23, 22)); feed = AuroraFeed(); sched = FakeScheduler()
    s = auroraStore(at: clock.now, cloud: 95, feed: feed, scheduler: sched, clock: clock)
    await s.refresh(force: true)
    #expect(sched.posted.contains { $0.kind == .aurora } == false)
    // Midday: the source is not even asked.
    clock = Clock(utc(2026, 9, 23, 12)); feed = AuroraFeed(); sched = FakeScheduler()
    s = auroraStore(at: clock.now, feed: feed, scheduler: sched, clock: clock)
    await s.refresh(force: true)
    #expect(feed.aurorawatchAsks() == 0)
}

@MainActor @Test func aurorawatchIsAskedNoMoreOftenThanEveryThreeMinutes() async {
    let clock = Clock(utc(2026, 9, 23, 22)), feed = AuroraFeed(), sched = FakeScheduler()
    let s = auroraStore(at: clock.now, feed: feed, scheduler: sched, clock: clock)
    await s.refresh(force: true)
    await s.pollAurora()
    #expect(feed.aurorawatchAsks() == 1)
    clock.now = clock.now.addingTimeInterval(4 * 60)
    await s.pollAurora()
    #expect(feed.aurorawatchAsks() == 2)
}

@MainActor @Test func noaasBigFileWaitsForACheapConnectionAndWithoutAlertsNothingIsAsked() async {
    let iceland = Site(name: "Reykjavik", latitude: 64.1, longitude: -21.9, elevationM: 10, timeZoneID: "Atlantic/Reykjavik", bortle: 5)
    let clock = Clock(utc(2026, 9, 23, 23)), feed = AuroraFeed(), sched = FakeScheduler()
    let s = auroraStore(at: clock.now, feed: feed, scheduler: sched, clock: clock, site: iceland)
    await s.refresh(force: true, connectivity: Connectivity(isOnline: true, isExpensive: true, isConstrained: false))
    #expect(feed.asked.contains(Ovation.url) == false)
    let off = auroraStore(at: clock.now, feed: AuroraFeed(), scheduler: FakeScheduler(), clock: clock)
    off.config.aurora.enabled = false
    await off.refresh(force: true)
    #expect(off.aurora == nil)
}

@MainActor @Test func theWidgetSnapshotCarriesAnAuroraThatPassesTheThreshold() async {
    let clock = Clock(utc(2026, 9, 23, 22)), feed = AuroraFeed(), sched = FakeScheduler()
    let s = auroraStore(at: clock.now, feed: feed, scheduler: sched, clock: clock)
    await s.refresh(force: true)
    #expect(s.tonight?.snapshot.auroraLine(now: clock.now)?.text == "Aurora amber")
}
