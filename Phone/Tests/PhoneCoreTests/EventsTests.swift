import Testing
import Foundation
import SkyCore
@testable import PhoneCore

final class FeedCalls: @unchecked Sendable { var urls: [URL] = [] }

@MainActor private func store(on day: Date, clock: Clock, feedCalls: FeedCalls) -> PhoneStore {
    let s = PhoneStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("events-\(UUID().uuidString)"),
                       provider: { site, now, _ in forecast(fetchedAt: now, from: utc(2026, 8, 11), site: site) },
                       scheduler: FakeScheduler(), clock: { clock.now },
                       feeds: { url in feedCalls.urls.append(url); return Data() }, occultations: false, darkLookups: nil)
    s.config.sites = [sheffield]
    s.config.activeSiteName = "Sheffield"
    return s
}

@MainActor @Test func thePerseidsAreTonightsEventAtTheirPeak() async {
    let s = store(on: utc(2026, 8, 12, 12), clock: Clock(utc(2026, 8, 12, 12)), feedCalls: FeedCalls())
    await s.refresh()
    let showers = s.events.filter { $0.kind == .meteorShower }
    #expect(showers.contains { $0.title.contains("Perseid") }, "showers tonight: \(showers.map(\.title))")
}

@MainActor @Test func aQuietNightHasNoShowerEvent() async {
    let s = store(on: utc(2026, 6, 1, 12), clock: Clock(utc(2026, 6, 1, 12)), feedCalls: FeedCalls())
    await s.refresh()
    #expect(s.events.contains { $0.kind == .meteorShower } == false)
}

@MainActor @Test func cometsAreAskedForDailyAndTheStationEveryTwoHours() async {
    let clock = Clock(utc(2026, 8, 12, 12)), calls = FeedCalls()
    let s = store(on: clock.now, clock: clock, feedCalls: calls)
    await s.refresh(force: true)
    #expect(calls.urls.count == 2)                       // comets and the station, once each
    clock.now = clock.now.addingTimeInterval(3600)
    await s.refresh(force: true)
    #expect(calls.urls.count == 2)                       // too soon for either
    clock.now = clock.now.addingTimeInterval(3 * 3600)
    await s.refresh(force: true)
    #expect(calls.urls.count == 3 && calls.urls.last == Satellites.issURL)   // the station only
}

@MainActor @Test func theFeedsWaitForACheapConnection() async {
    let calls = FeedCalls()
    let s = store(on: utc(2026, 8, 12, 12), clock: Clock(utc(2026, 8, 12, 12)), feedCalls: calls)
    await s.refresh(force: true, connectivity: Connectivity(isOnline: true, isExpensive: true, isConstrained: false))
    #expect(calls.urls.isEmpty)
}

@MainActor @Test func theEyeListHoldsOnlyWhatNeedsNoTelescopeAndEveryoneIsLabelled() async {
    let s = store(on: utc(2026, 8, 12, 12), clock: Clock(utc(2026, 8, 12, 12)), feedCalls: FeedCalls())
    await s.refresh()
    for t in s.eyeTargets { #expect(s.eyeView(t) != nil) }
    #expect(s.eyeEvents.allSatisfy(EyeViews.includes))
    // A faint galaxy needs a telescope at Bortle 8, so it is never listed.
    #expect(s.eyeTargets.contains { $0.id == "m33" } == false)
}

@Test func everyWidgetLinkRoutesToAPageAndATargetIdSurvivesItsTrip() throws {
    #expect(WidgetLink(url: URL(string: "nightwatch://plan")!)?.phoneRoute == .plan)
    #expect(WidgetLink(url: URL(string: "nightwatch://targets")!)?.phoneRoute == .targets)
    #expect(WidgetLink(url: URL(string: "nightwatch://search?q=andromeda")!)?.phoneRoute == .targets)
    let link = WidgetLink.target("m 31/x")                       // an id with a space and a slash
    #expect(WidgetLink(url: link.url) == link)
    #expect(link.phoneRoute == .targets)
}

@MainActor @Test func aTargetIsFoundByIdFromTonightsLists() async throws {
    let s = store(on: utc(2026, 8, 12, 12), clock: Clock(utc(2026, 8, 12, 12)), feedCalls: FeedCalls())
    await s.refresh()
    let id = try #require(s.planning?.tonight.best.first?.id)
    #expect(s.target(withID: id)?.id == id)
    #expect(s.target(withID: "no-such-thing") == nil)
}

@MainActor @Test func aTargetsNameIsFoundFromTheWholeCatalogueNotOnlyTonightsList() async {
    let s = store(on: utc(2026, 8, 12, 12), clock: Clock(utc(2026, 8, 12, 12)), feedCalls: FeedCalls())
    await s.refresh()
    #expect(s.targetName(id: "moon") == "Moon")
    #expect(s.targetName(id: "planet-saturn") == "Saturn")
    #expect(s.targetName(id: "no-such-thing") == nil)
}

@MainActor @Test func anAnswerWaitsForTheFirstPlanWhenAskedBeforeThePageExists() async {
    let s = store(on: utc(2026, 8, 12, 12), clock: Clock(utc(2026, 8, 12, 12)), feedCalls: FeedCalls())
    #expect(s.tonight == nil)                                  // as when an action launches the app in the background
    let snap = await s.snapshotForAnswer()
    #expect(snap != nil && snap?.siteName == "Sheffield")
}
