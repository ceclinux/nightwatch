import Testing
import Foundation
import SkyCore
@testable import PhoneCore

private let settings = AlertSettings()

@Test func aClearEveningQueuesTheHeadsUpAndTheNudge() throws {
    let p = try plans()
    let due = AlertEngine.dueTimes(tonight: p.tonight, settings: settings)
    let now = due[0].addingTimeInterval(-2 * 3600)
    let r = AlertPlanner.plan(now: now, ledger: AlertLedger(), tonight: p.tonight, tomorrow: p.tomorrow, settings: settings,
                              forecastFetchedAt: now, site: sheffield)
    #expect(r.immediate == nil)
    #expect(r.ledger.scheduled.map(\.kind) == ["headsUp", "go"])
    #expect(r.ledger.scheduled.map(\.fireDate) == due)
    #expect(r.ledger.scheduled[0].id == "\(p.night.key).headsUp")
    #expect(r.ledger.scheduled[1].title.hasPrefix("Clear from"))
}

@Test func whatWentOutIsNotSentAgainOnTheNextRefresh() throws {
    let p = try plans()
    let due = AlertEngine.dueTimes(tonight: p.tonight, settings: settings)
    let early = due[0].addingTimeInterval(-3600)
    let first = AlertPlanner.plan(now: early, ledger: AlertLedger(), tonight: p.tonight, tomorrow: p.tomorrow, settings: settings,
                                  forecastFetchedAt: early, site: sheffield)
    // The app is opened again twenty minutes after the heads-up was due: the system has delivered it, so only the nudge is left.
    let later = due[0].addingTimeInterval(20 * 60)
    let second = AlertPlanner.plan(now: later, ledger: first.ledger, tonight: p.tonight, tomorrow: p.tomorrow, settings: settings,
                                   forecastFetchedAt: later, site: sheffield)
    #expect(second.immediate == nil)
    #expect(second.ledger.scheduled.map(\.kind) == ["go"])
    #expect(second.ledger.state?.stage == .headsUpSent)
}

@Test func aHeadsUpThatIsDueNowIsPostedAtOnce() throws {
    let p = try plans()
    let due = AlertEngine.dueTimes(tonight: p.tonight, settings: settings)
    let now = due[0].addingTimeInterval(60)
    let r = AlertPlanner.plan(now: now, ledger: AlertLedger(), tonight: p.tonight, tomorrow: p.tomorrow, settings: settings,
                              forecastFetchedAt: now, site: sheffield)
    #expect(r.immediate?.kind == .headsUp)
    #expect(r.ledger.scheduled.map(\.kind) == ["go"])
}

@Test func nothingIsQueuedFromAForecastMoreThanSixHoursOld() throws {
    let p = try plans()
    let due = AlertEngine.dueTimes(tonight: p.tonight, settings: settings)
    let now = due[0].addingTimeInterval(-2 * 3600)
    let r = AlertPlanner.plan(now: now, ledger: AlertLedger(), tonight: p.tonight, tomorrow: p.tomorrow, settings: settings,
                              forecastFetchedAt: now.addingTimeInterval(-7 * 3600), site: sheffield)
    #expect(r.immediate == nil)
    #expect(r.ledger.scheduled.isEmpty)
}

@Test func anAlertDueInQuietHoursIsDroppedNotDeferred() throws {
    let p = try plans()
    let due = AlertEngine.dueTimes(tonight: p.tonight, settings: settings)
    var quiet = settings
    quiet.quietStartHour = 12; quiet.quietEndHour = 20   // the heads-up falls at about 18:00 local
    let now = due[0].addingTimeInterval(-2 * 3600)
    let r = AlertPlanner.plan(now: now, ledger: AlertLedger(), tonight: p.tonight, tomorrow: p.tomorrow, settings: quiet,
                              forecastFetchedAt: now, site: sheffield)
    #expect(!r.ledger.scheduled.map(\.kind).contains("headsUp"))
}

@Test func aDullNightQueuesNothingToday() throws {
    let p = try plans(cloud: 90)
    let due = AlertEngine.dueTimes(tonight: p.tonight, settings: settings)
    let now = due[0].addingTimeInterval(-2 * 3600)
    let r = AlertPlanner.plan(now: now, ledger: AlertLedger(), tonight: p.tonight, tomorrow: p.tomorrow, settings: settings,
                              forecastFetchedAt: now, site: sheffield)
    #expect(r.ledger.scheduled.isEmpty)
}

@Test func theLedgerSurvivesBeingSavedAndRead() throws {
    let p = try plans()
    let due = AlertEngine.dueTimes(tonight: p.tonight, settings: settings)
    let now = due[0].addingTimeInterval(-3600)
    let r = AlertPlanner.plan(now: now, ledger: AlertLedger(), tonight: p.tonight, tomorrow: p.tomorrow, settings: settings,
                              forecastFetchedAt: now, site: sheffield)
    #expect(try JSONDecoder().decode(AlertLedger.self, from: JSONEncoder().encode(r.ledger)) == r.ledger)
}
