import Testing
import Foundation
import SkyCore
@testable import PhoneCore

@MainActor private func readyStore() async -> PhoneStore {
    let store = makeStore(clock: Clock(utc(2026, 9, 23, 12)), calls: Calls())
    await store.refresh()
    return store
}

@MainActor @Test func theWeekStartsTonightAndRunsAsFarAsTheForecastReaches() async {
    let store = await readyStore()
    // The test forecast covers four days; a real one covers ten, and the week is capped at Planner.weekNights.
    let nights = store.planning?.week.count ?? 0
    #expect(nights >= 1 && nights <= Planner.weekNights)   // nights past the forecast's end are left out
    #expect(store.planning?.week.first?.daysAhead == 0)
}

@MainActor @Test func aHeartedTargetIsInTonightsPlanAndTheHeartIsKept() async throws {
    let store = await readyStore()
    let id = try #require(store.planning?.tonight.best.first?.id)
    #expect(store.isFavourite(id) == false)
    store.toggleFavourite(id)
    #expect(store.isFavourite(id))
    await store.recompute(now: utc(2026, 9, 23, 12))
    #expect(store.isInPlan(id))
    store.toggleFavourite(id)
    #expect(store.isFavourite(id) == false)
}

@MainActor @Test func takingAFavouriteOffTonightLeavesItAFavouriteAndPutsItBack() async throws {
    let store = await readyStore()
    let id = try #require(store.planning?.tonight.best.first?.id)
    store.toggleFavourite(id)
    await store.recompute(now: utc(2026, 9, 23, 12))
    store.setInPlan(id, on: false)
    await store.recompute(now: utc(2026, 9, 23, 12))
    #expect(store.isFavourite(id))
    #expect(store.isInPlan(id) == false)
    #expect(store.session()?.takenOff.contains { $0.id == id } == true)
    store.setInPlan(id, on: true)
    await store.recompute(now: utc(2026, 9, 23, 12))
    #expect(store.isInPlan(id))
}

@MainActor @Test func aTargetAddedForTheNightIsInThatNightsPlanOnly() async throws {
    let store = await readyStore()
    let id = try #require(store.planning?.tonight.best.first?.id)
    store.setInPlan(id, on: true)
    await store.recompute(now: utc(2026, 9, 23, 12))
    #expect(store.isInPlan(id))
    #expect(store.isFavourite(id) == false)
    let tonightKey = try #require(store.planning?.tonight.night.key)
    #expect(store.config.planChoices[tonightKey]?.added == [id])
}

@MainActor @Test func choicesForEarlierNightsAreDroppedSoTheSettingsStaySmall() async throws {
    let store = await readyStore()
    store.config.planChoices["2020-01-01"] = PlanChoices(added: ["x"])
    let id = try #require(store.planning?.tonight.best.first?.id)
    store.setInPlan(id, on: true)
    #expect(store.config.planChoices["2020-01-01"] == nil)
}
