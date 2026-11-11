import Testing
import Foundation
import SkyCore
@testable import PhoneCore

final class FakeLive: LiveActivityScheduling, @unchecked Sendable {
    var cards: [ClearWindowCard?] = []
    func reconcile(_ card: ClearWindowCard?) async { cards.append(card) }
}

@Test func aQualifyingNightGetsACardForItsClearWindow() throws {
    let p = try plans(cloud: 5)
    let w = try #require(p.tonight.primary)
    let card = try #require(ClearWindowCardPlanner.card(now: w.start.addingTimeInterval(-3600), plan: p.tonight, headline: "Clear window tonight",
                                                        siteName: "Sheffield", forecastAt: utc(2026, 9, 23, 9)))
    #expect(card.windowStart == w.start && card.windowEnd == w.end)
    #expect(card.score == p.tonight.score && card.siteName == "Sheffield" && card.forecastAt == utc(2026, 9, 23, 9))
}

@Test func aCardStillStandsInsideTheWindowAndGoesOnceItHasClosed() throws {
    let p = try plans(cloud: 5)
    let w = try #require(p.tonight.primary)
    #expect(ClearWindowCardPlanner.card(now: w.start.addingTimeInterval(60), plan: p.tonight, headline: "x", siteName: "S", forecastAt: .now) != nil)
    #expect(ClearWindowCardPlanner.card(now: w.end.addingTimeInterval(1), plan: p.tonight, headline: "x", siteName: "S", forecastAt: .now) == nil)
}

@Test func aCloudyNightGetsNoCard() throws {
    let p = try plans(cloud: 90)
    #expect(!p.tonight.qualifies)
    #expect(ClearWindowCardPlanner.card(now: utc(2026, 9, 23, 12), plan: p.tonight, headline: "x", siteName: "S", forecastAt: .now) == nil)
}

@MainActor @Test func everyRefreshReconcilesTheCardSoAWorseForecastRemovesIt() async throws {
    let calls = Calls(), live = FakeLive()
    let store = makeStore(clock: Clock(utc(2026, 9, 23, 12)), calls: calls, live: live)
    await store.refresh()
    let first = try #require(live.cards.last ?? nil)
    #expect(first.siteName == "Sheffield" && first.windowEnd > first.windowStart && !first.headline.hasSuffix("."))
    calls.cloud = 90
    await store.refresh(force: true)
    #expect(live.cards.count >= 2)
    #expect(live.cards.last! == nil)   // the forecast turned: the card goes, not just the alert
}
