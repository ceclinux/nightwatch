import Testing
import Foundation
import SkyCore
@testable import PhoneCore

@MainActor @Test func switchingAlertsOffTakesWhatWasQueuedAway() async {
    let sched = FakeScheduler()
    let store = makeStore(clock: Clock(utc(2026, 9, 23, 12)), calls: Calls(), scheduler: sched)
    store.config.notifyEnabled = true
    await store.refresh()
    #expect(sched.queue.isEmpty == false)
    store.setNotifyEnabled(false)
    await store.recompute(now: utc(2026, 9, 23, 12))
    #expect(sched.queue.isEmpty)
}

@MainActor @Test func anAlertSettingTakesEffectAtOnceNotAtTheNextRefresh() async {
    let sched = FakeScheduler()
    let store = makeStore(clock: Clock(utc(2026, 9, 23, 12)), calls: Calls(), scheduler: sched)
    store.config.notifyEnabled = true
    await store.refresh()
    #expect(sched.queue.contains { $0.kind == "headsUp" })
    store.setAlerts { $0.headsUp = false }
    await store.recompute(now: utc(2026, 9, 23, 12))
    #expect(sched.queue.contains { $0.kind == "headsUp" } == false)
    #expect(store.config.alerts.headsUp == false)
}

@MainActor @Test func brightNightsTurnsOnMoonAndPlanetsWhenThereIsNoProperDarkness() async {
    let store = makeStore(clock: Clock(utc(2026, 6, 21, 12)), calls: Calls())
    await store.refresh()
    #expect(store.planning?.tonight.mode == .dark)
    store.setBrightNights { $0.enabled = true }
    await store.recompute(now: utc(2026, 6, 21, 12))
    #expect(store.planning?.tonight.mode == .bright)
}
