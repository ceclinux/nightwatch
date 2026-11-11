import Testing
import Foundation
import SkyCore
@testable import PhoneCore

final class TerrainCalls: @unchecked Sendable {
    var sites: [String] = []
    var failing = false
    var heights: [Double] = [0, 35, 0, 0, 0, 0, 52, 0]
}

@MainActor private func horizonStore(_ calls: TerrainCalls) -> PhoneStore {
    let store = PhoneStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("hz-\(UUID().uuidString)"),
                           provider: { site, now, _ in forecast(fetchedAt: now, source: nil, site: site) }, scheduler: FakeScheduler(),
                           clock: { utc(2026, 9, 23, 12) },
                           terrain: { site in calls.sites.append(site.name); if calls.failing { throw Failure() }; return calls.heights },
                           terrainPause: .milliseconds(1))
    store.config.sites = [sheffield]
    store.config.activeSiteName = "Sheffield"
    return store
}

/// Wait for the store's lookup to finish (it runs on the main actor, one site at a time).
@MainActor private func settle(_ store: PhoneStore) async {
    for _ in 0..<400 {
        let busy = !store.terrainChecking.isEmpty
        let waiting = store.config.sites.contains { $0.terrain == nil && !store.terrainFailed.contains($0.name) }
        if !busy && !waiting { break }
        try? await Task.sleep(for: .milliseconds(5))
    }
    try? await Task.sleep(for: .milliseconds(20))   // let the task clear itself
}

@MainActor @Test func aHorizonAtTheOpenHeightIsStoredAsOpenSky() {
    let store = horizonStore(TerrainCalls())
    store.setHorizon(siteNamed: "Sheffield", heights: Array(repeating: 10, count: 8))
    #expect(store.config.sites[0].horizon == nil)
}

@MainActor @Test func aRaisedHorizonIsKeptAndTheOpenOnesWithIt() {
    let store = horizonStore(TerrainCalls())
    let h: [Double] = [30, 30, 30, 30, 30, 30, 45, 30]
    store.setHorizon(siteNamed: "Sheffield", heights: h)
    #expect(store.config.sites[0].horizon == h)
}

@MainActor @Test func theHillsAreLookedUpOnceForASiteThatHasNone() async {
    let calls = TerrainCalls(); let store = horizonStore(calls)
    store.checkTerrain(); await settle(store)
    #expect(calls.sites == ["Sheffield"])
    #expect(store.config.sites[0].terrain == calls.heights)
    store.checkTerrain(); await settle(store)
    #expect(calls.sites.count == 1)
}

@MainActor @Test func aFailedLookupIsRememberedAndRetryTriesAgain() async {
    let calls = TerrainCalls(); calls.failing = true; let store = horizonStore(calls)
    store.checkTerrain(); await settle(store)
    #expect(store.terrainFailed.contains("Sheffield"))
    #expect(store.config.sites[0].terrain == nil)
    store.checkTerrain(); await settle(store)
    #expect(calls.sites.count == 1)          // not tried again by itself
    calls.failing = false
    store.retryTerrain(siteNamed: "Sheffield"); await settle(store)
    #expect(store.config.sites[0].terrain == calls.heights)
    #expect(store.terrainFailed.isEmpty)
}

@MainActor @Test func raisingToTheHillsLiftsOnlyTheDirectionsTheyStandAbove() async throws {
    let calls = TerrainCalls(); let store = horizonStore(calls)
    store.checkTerrain(); await settle(store)
    store.raiseToTerrain(siteNamed: "Sheffield")
    let h = try #require(store.config.sites[0].horizon)
    #expect(h[1] == 40)        // north-east: hills reach 35, raised to the next 5 degrees above them
    #expect(h[6] == 55)        // west: hills reach 52
    #expect(h[0] == store.openDeg && h[4] == store.openDeg)   // elsewhere the open height stands
}

@MainActor @Test func hillsLowerThanTheOpenHeightChangeNothing() async {
    let calls = TerrainCalls(); calls.heights = [0, 3, 0, 0, 0, 0, 7, 0]; let store = horizonStore(calls)
    store.checkTerrain(); await settle(store)
    store.raiseToTerrain(siteNamed: "Sheffield")
    #expect(store.config.sites[0].horizon == nil)
}

@MainActor @Test func aHighHorizonTakesAHeartedTargetOutOfThePlanWithTheReason() async throws {
    let store = horizonStore(TerrainCalls())
    await store.refresh()
    let id = try #require(store.planning?.tonight.best.first?.id)
    store.toggleFavourite(id)
    await store.recompute(now: utc(2026, 9, 23, 12))
    #expect(store.isInPlan(id))
    store.setHorizon(siteNamed: "Sheffield", heights: Array(repeating: 80, count: 8))
    await store.recompute(now: utc(2026, 9, 23, 12))
    #expect(store.isInPlan(id) == false)
    #expect(store.session()?.omitted.contains { $0.target.id == id && $0.reason.contains("horizon") } == true)
}

@MainActor @Test func movingASiteClearsItsHillsAndKeepsItsName() async {
    let store = makeStore(clock: Clock(utc(2026, 9, 23, 12)), calls: Calls())
    store.config.sites[0].terrain = [10, 10, 10, 10, 10, 10, 10, 10]
    store.moveSite(named: "Sheffield", to: Coordinate(latitude: 53.4, longitude: -1.5))
    #expect(store.config.sites[0].name == "Sheffield")
    #expect(store.config.sites[0].latitude == 53.4 && store.config.sites[0].longitude == -1.5)
    #expect(store.config.sites[0].terrain == nil)
}

final class HillCalls: @unchecked Sendable { var sites: [String] = []; var failure: Error? }

@MainActor private func terrainStore(dir: URL, calls: HillCalls, names: [String]) -> PhoneStore {
    let s = PhoneStore(directory: dir, provider: { site, now, _ in forecast(fetchedAt: now, site: site) }, scheduler: FakeScheduler(),
                       clock: { utc(2026, 9, 23, 12) },
                       terrain: { site in calls.sites.append(site.name); if let f = calls.failure { throw f }; return Array(repeating: 10, count: 8) },
                       terrainPause: .milliseconds(1), occultations: false, darkLookups: nil)
    s.config.sites = names.map { Site(name: $0, latitude: 53.4 + Double($0.count), longitude: -1.5, elevationM: 0, timeZoneID: "Europe/London", bortle: 4) }
    return s
}

@MainActor @Test func hillsAreLookedUpOnceAndAFailureIsNotRetriedByARelaunchWithinADay() async {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("terrain-\(UUID().uuidString)")
    let calls = HillCalls(); calls.failure = URLError(.timedOut)
    let first = terrainStore(dir: dir, calls: calls, names: ["A"])
    first.checkTerrain(); await first.terrainFinished()
    #expect(calls.sites == ["A"])
    let relaunch = terrainStore(dir: dir, calls: calls, names: ["A"])             // same folder, so the attempt is remembered
    relaunch.checkTerrain(); await relaunch.terrainFinished()
    #expect(calls.sites == ["A"])                                                  // not asked again
    calls.failure = nil
    relaunch.retryTerrain(siteNamed: "A"); await relaunch.terrainFinished()        // Try again overrides
    #expect(calls.sites == ["A", "A"])
    #expect(relaunch.config.sites[0].terrain != nil)
    relaunch.checkTerrain(); await relaunch.terrainFinished()
    #expect(calls.sites == ["A", "A"])                                             // hills found: never again
}

@MainActor @Test func aRefusalForTheFirstSiteStopsTheRunSoTheSecondIsNotAsked() async {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("terrain2-\(UUID().uuidString)")
    let calls = HillCalls(); calls.failure = HTTPFailure(status: 429, reason: "Daily API request limit exceeded.")
    let s = terrainStore(dir: dir, calls: calls, names: ["A", "BB"])
    s.checkTerrain(); await s.terrainFinished()
    #expect(calls.sites == ["A"])
}
