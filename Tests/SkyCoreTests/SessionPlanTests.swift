import Testing
import Foundation
@testable import SkyCore

// Tonight's plan (#57) on a real late-September night: the Crescent (Cygnus) is best early, the Bubble and the Pacman
// (Cassiopeia) later, as in the owner-approved mock-up.
private let dwarfMini = FieldOfView(widthDeg: 2.1, heightDeg: 1.2)
private let crescent = DeepSkyObject(id: "NGC6888", commonName: "Crescent Nebula", messier: nil, typeCode: "EmN", group: .nebulae,
                                     raHours: 20.20, decDeg: 38.35, majAxisArcmin: 18, minAxisArcmin: 13, magnitude: 7.4, constellation: "Cyg")
private let bubble = DeepSkyObject(id: "NGC7635", commonName: "Bubble Nebula", messier: nil, typeCode: "EmN", group: .nebulae,
                                   raHours: 23.35, decDeg: 61.2, majAxisArcmin: 15, minAxisArcmin: 8, magnitude: 10, constellation: "Cas")
private let pacman = DeepSkyObject(id: "NGC281", commonName: "Pacman Nebula", messier: nil, typeCode: "EmN", group: .nebulae,
                                   raHours: 0.88, decDeg: 56.6, majAxisArcmin: 35, minAxisArcmin: 30, magnitude: 7.4, constellation: "Cas")
private let veil = DeepSkyObject(id: "NGC6960", commonName: "Western Veil", messier: nil, typeCode: "SNR", group: .nebulae,
                                 raHours: 20.76, decDeg: 30.7, majAxisArcmin: 180, minAxisArcmin: 20, magnitude: 7, constellation: "Cyg")

private func septemberPlan(objects: [DeepSkyObject] = [crescent, bubble, pacman, veil], favourites: [String] = []) throws -> NightPlan {
    let night = try Ephemeris.night(localDate: utc(2026, 9, 29, 12, 0), site: sheffield)
    let w = ClearWindow(start: try #require(night.darkStart), end: try #require(night.darkEnd))
    let targets = Planner.rank(catalog: Catalog(objects: objects), constellations: [], window: w, site: sheffield, fov: dwarfMini, rule: GoRule())
    var p = NightPlan(night: night, windows: [w], primary: w, score: 80, qualifies: true, moonIllumination: 0, moonRise: nil,
                      moonSet: nil, darkHours: [], targets: targets, best: [], seeingAvailable: false)
    p.favourites = favourites.compactMap { id in targets.first { $0.id == id }.map { FavouriteTarget(target: $0, notTonight: nil) } }
    return p
}

private func make(_ p: NightPlan, favourites: [String], choices: PlanChoices = PlanChoices(), stopBy: StopBy = StopBy()) -> SessionPlan? {
    SessionPlanner.make(plan: p, favourites: favourites, choices: choices, stopBy: stopBy, site: sheffield)
}

/// A target with a best time of our choosing, up across the whole window.
private func target(_ id: String, _ name: String?, best: Date, window w: ClearWindow, moonWashed: Bool = false) -> RankedTarget {
    var t = RankedTarget(id: id, name: name.map { "\(id) \($0)" } ?? id, subtitle: "", group: .nebulae, raHours: 0, decDeg: 0, sizeArcmin: 10,
                         magnitude: 8, fit: .fits, peakAltDeg: 70, peakTime: best, moonSepDeg: 90, moonWashed: moonWashed, visibleFraction: 1)
    t.catalogueID = id; t.commonName = name; t.viewable = w; t.typeName = "Emission nebula"
    return t
}

private func nightWith(_ targets: [RankedTarget], favourites: [FavouriteTarget] = []) throws -> NightPlan {
    let night = try Ephemeris.night(localDate: utc(2026, 9, 29, 12, 0), site: sheffield)
    let w = ClearWindow(start: try #require(night.darkStart), end: try #require(night.darkEnd))
    var p = NightPlan(night: night, windows: [w], primary: w, score: 80, qualifies: true, moonIllumination: 0.78, moonRise: nil,
                      moonSet: nil, darkHours: [], targets: targets, best: [], seeingAvailable: false)
    p.favourites = favourites.isEmpty ? targets.map { FavouriteTarget(target: $0, notTonight: nil) } : favourites
    return p
}

// Tonight's plan, redesigned at the owner's UAT (29 September 2026): favourites up in the clear window, by best time.
@Test func thePlanIsTheFavouritesUpInTheWindowInBestTimeOrder() throws {
    let p = try septemberPlan(favourites: ["NGC281", "NGC6888", "NGC7635"])
    let s = try #require(make(p, favourites: ["NGC281", "NGC6888", "NGC7635"]))
    #expect(s.items.map(\.id).first == "NGC6888")                              // Cygnus is best first
    #expect(Set(s.items.map(\.id)) == ["NGC281", "NGC6888", "NGC7635"])        // favourites only, not the rest of the night
    #expect(zip(s.items, s.items.dropFirst()).allSatisfy { $0.target.peakTime <= $1.target.peakTime })
    #expect(s.items.allSatisfy { !$0.added } && s.takenOff.isEmpty)
    #expect(make(p, favourites: []).map { $0.items.isEmpty && $0.omitted.isEmpty } == true)   // no favourites: an empty plan, not none
}

@Test func favouritesBestWithinHalfAnHourAreFlaggedToChooseBetween() throws {
    let w0 = try nightWith([])
    let w = try #require(w0.primary)
    let a = target("NGC6992", "Eastern Veil", best: w.start.addingTimeInterval(3600), window: w)
    let b = target("NGC6888", "Crescent Nebula", best: w.start.addingTimeInterval(3600 + 20 * 60), window: w)
    let c = target("M31", nil, best: w.start.addingTimeInterval(3 * 3600), window: w)
    let s = try #require(make(try nightWith([c, a, b]), favourites: ["M31", "NGC6992", "NGC6888"]))
    #expect(s.items.map(\.id) == ["NGC6992", "NGC6888", "M31"])
    #expect(Copy.planClash(s.items[0]) == "Best at the same time as the Crescent Nebula")
    #expect(Copy.planClash(s.items[1]) == "Best at the same time as the Eastern Veil")
    #expect(Copy.planClash(s.items[2]) == nil)
}

@Test func takenOffPutBackAndAddedForOneNight() throws {
    let base = try nightWith([])
    let w = try #require(base.primary)
    let fav = target("NGC7000", "North America Nebula", best: w.start.addingTimeInterval(1800), window: w)
    let other = target("M33", "Triangulum Galaxy", best: w.start.addingTimeInterval(7200), window: w)
    let p = try nightWith([fav, other], favourites: [FavouriteTarget(target: fav, notTonight: nil)])
    var c = SessionPlanner.choose("NGC7000", on: false, isFavourite: true, in: PlanChoices())
    #expect(c.removed == ["NGC7000"])
    var s = try #require(make(p, favourites: ["NGC7000"], choices: c))
    #expect(s.items.isEmpty && s.takenOff.map(\.id) == ["NGC7000"])
    c = SessionPlanner.choose("NGC7000", on: true, isFavourite: true, in: c)       // Put back
    c = SessionPlanner.choose("M33", on: true, isFavourite: false, in: c)          // Add to plan, this night only
    #expect(c == PlanChoices(added: ["M33"], removed: []))
    s = try #require(make(p, favourites: ["NGC7000"], choices: c))
    #expect(s.items.map(\.id) == ["NGC7000", "M33"] && s.items[1].added && !s.items[0].added)
    #expect(Copy.planDetail(s.items[1], presetID: nil, site: sheffield).hasPrefix("Added for this night · Up "))
    #expect(Copy.planDetail(s.items[0], presetID: "dwarf-mini", site: sheffield).hasSuffix("at 70° · Duo-Band · 200 × 30 s"))
    #expect(SessionPlanner.choose("M33", on: false, isFavourite: false, in: c) == PlanChoices())
}

@Test func favouritesThatCannotBeInThePlanSayWhy() throws {
    let base = try nightWith([])
    let w = try #require(base.primary)
    let low = target("NGC2024", "Flame Nebula", best: w.start, window: w)
    let washed = target("IC1805", "Heart Nebula", best: w.start, window: w, moonWashed: true)
    let late = target("M42", "Orion Nebula", best: w.end, window: ClearWindow(start: w.end.addingTimeInterval(-1800), end: w.end))
    let p = try nightWith([washed, late], favourites: [FavouriteTarget(target: low, notTonight: "Below 30° in tonight's window"),
                                                       FavouriteTarget(target: washed, notTonight: nil), FavouriteTarget(target: late, notTonight: nil)])
    let stop = StopBy(enabled: true, minutes: 30)   // 00:30, before M42 is up
    let s = try #require(make(p, favourites: ["NGC2024", "IC1805", "M42"], stopBy: stop))
    #expect(s.items.isEmpty)
    #expect(s.omitted.map(\.reason) == ["Below 30° in tonight's window", "Washed out by the Moon", "Up only after your finish time, 00:30"])
    #expect(Copy.planSummary(s, plan: p, site: sheffield).contains(" · finish by 00:30 · ") && Copy.planSummary(s, plan: p, site: sheffield).hasSuffix("· Moon 78%"))
}

@Test func planChoicesAreKeptPerNightAndSyncWithTheSettings() throws {
    let all = ["2026-09-28": PlanChoices(removed: ["M31"]), "2026-09-29": PlanChoices(added: ["M33"]), "2026-09-30": PlanChoices(removed: ["NGC7000"]),
               "2026-10-01": PlanChoices()]
    #expect(Set(SessionPlanner.pruned(all, from: "2026-09-29").keys) == ["2026-09-29", "2026-09-30"])   // earlier and empty nights go
    let old = try JSONDecoder().decode(Config.self, from: Data("{}".utf8))
    #expect(old.planChoices.isEmpty && old.stopBy == StopBy() && old.showPlan)
    var c = Config(); c.planChoices = ["2026-09-30": PlanChoices(removed: ["NGC7000"])]; c.stopBy = StopBy(enabled: true, minutes: 23 * 60)
    let back = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(c))
    #expect(back.planChoices == c.planChoices && back.stopBy.minutes == 1380)
    #expect(SettingsSync.outgoing(c, at: Date()).config.planChoices == c.planChoices)          // travels to the other Macs
    // A night's choices made the day before still apply when that night comes.
    let p = try septemberPlan(favourites: ["NGC6888"])
    #expect(make(p, favourites: ["NGC6888"], choices: PlanChoices(removed: ["NGC6888"]))?.takenOff.map(\.id) == ["NGC6888"])
}

@Test func noPlanWithoutAWindowOrOnABrightNight() throws {
    var p = try septemberPlan()
    p.mode = .bright
    #expect(make(p, favourites: ["NGC6888"]) == nil)
    let none = NightPlan(night: p.night, windows: [], primary: nil, score: 10, qualifies: false, moonIllumination: 0, moonRise: nil,
                         moonSet: nil, darkHours: [], targets: p.targets, best: [], seeingAvailable: false)
    #expect(make(none, favourites: ["NGC6888"]) == nil)
    // A Stop by before the window opens: nothing to plan.
    let night = try Ephemeris.night(localDate: utc(2026, 9, 29, 12, 0), site: sheffield)
    let late = NightPlan(night: night, windows: [], primary: ClearWindow(start: utc(2026, 9, 30, 0, 0), end: utc(2026, 9, 30, 4, 0)), score: 80,
                         qualifies: true, moonIllumination: 0, moonRise: nil, moonSet: nil, darkHours: [], targets: [], best: [], seeingAvailable: false)
    #expect(make(late, favourites: [], stopBy: StopBy(enabled: true, minutes: 30)) == nil)
    // The night the clocks go back (25 October 2026): 03:00 is still 03:00.
    let autumn = try Ephemeris.night(localDate: utc(2026, 10, 24, 12, 0), site: sheffield)
    #expect(Copy.hhmm(StopBy(enabled: true, minutes: 180).date(night: autumn, site: sheffield), site: sheffield) == "03:00")
    #expect([0, 1, 2, 3, 10, 11, 20].map(Copy.inPlan) == ["In the plan, 1st", "In the plan, 2nd", "In the plan, 3rd", "In the plan, 4th",
                                                         "In the plan, 11th", "In the plan, 12th", "In the plan, 21st"])
}

@Test func theHeadsUpNamesThePlanAndDewOnlyWhenLikely() throws {
    var p = try septemberPlan(favourites: ["NGC6888", "NGC7635"])
    let s = try #require(make(p, favourites: ["NGC6888", "NGC7635"]))
    let a = s.items[0].target, b = s.items[1].target
    let expected = "Your plan: the \(try #require(a.commonName)), best at \(Copy.hhmm(a.peakTime, site: sheffield)), then the \(try #require(b.commonName)), best at \(Copy.hhmm(b.peakTime, site: sheffield))."
    #expect(Copy.headsUpPlan(s, plan: p, site: sheffield) == expected)
    let damp = b.peakTime
    p = NightPlan(night: p.night, windows: p.windows, primary: p.primary, score: 80, qualifies: true, moonIllumination: 0, moonRise: nil, moonSet: nil,
                  darkHours: [HourlyConditions(time: damp, cloudTotal: 0, cloudLow: nil, cloudMid: nil, cloudHigh: nil, tempC: 6, dewPointC: 5,
                                               humidityPct: nil, windKmh: nil, gustKmh: nil, visibilityM: nil, seeing: nil, transparency: nil)],
                  targets: p.targets, best: [], seeingAvailable: false)
    #expect(Copy.headsUpPlan(s, plan: p, site: sheffield) == expected + " Fit the dew heater: dew likely after \(Copy.hhmm(damp, site: sheffield)).")
    #expect(Copy.headsUpPlan(try #require(make(p, favourites: [])), plan: p, site: sheffield) == nil)   // an empty plan says nothing
}

@Test func notTonightSilencesTheRestOfTheNight() throws {
    let p = try septemberPlan(favourites: ["NGC6888"])
    let now = p.night.sunset.addingTimeInterval(-1800)
    let quiet = AlertState(nightKey: p.night.key, stage: .idle, silenced: true, firstClearSaid: true)
    let r = AlertEngine.step(now: now, tonight: p, tomorrow: nil, state: quiet, settings: AlertSettings(), forecastFetchedAt: now,
                             site: sheffield, copy: Copy())
    #expect(r.notification == nil && r.state == quiet)
    let s = try #require(make(p, favourites: ["NGC6888"]))
    let heads = AlertEngine.step(now: now, tonight: p, tomorrow: nil, state: AlertState(nightKey: "earlier", stage: .done, firstClearSaid: true),
                                 settings: AlertSettings(), forecastFetchedAt: now, site: sheffield, copy: Copy(), session: s)
    #expect(heads.notification?.kind == .headsUp && heads.notification?.body.hasPrefix("Your plan: the Crescent Nebula") == true)
    #expect(heads.notification?.planNight == p.night.key)
}

@Test func siriReadsTonightsPlanWhenThereIsOne() throws {
    let p = try septemberPlan(favourites: ["NGC6888", "NGC7635"])
    let s = try #require(make(p, favourites: ["NGC6888", "NGC7635"]))
    let snap = WidgetSnapshot.make(plan: p, tomorrow: nil, fetchedAt: p.night.sunset, site: sheffield, rule: GoRule(), bright: BrightSettings(),
                                   alerts: AlertSettings(), copy: Copy())
    let text = Copy.siriBest(snap, session: s, site: sheffield)
    #expect(text == "Tonight's plan: Crescent Nebula at \(Copy.hhmm(s.items[0].target.peakTime, site: sheffield)), then \(try #require(s.items[1].target.commonName)) at \(Copy.hhmm(s.items[1].target.peakTime, site: sheffield)).")
}

@Test func thePresetsCarryTheMakersBatteryFigures() throws {
    let b = Dictionary(uniqueKeysWithValues: try TelescopePresets.bundled().map { ($0.id, $0.batteryHours) })
    #expect(b["dwarf-mini"] == 4 && b["dwarf-3"] == 5.5 && b["draco"] == 5 && b["seestar-s50"] == 6 && b["seestar-s30-pro"] == 6)
    #expect(b["dslr-apsc-200"] == .some(nil))
}


@Test func theFirstClearWindowIsNamedOnceAndNeverToSomeoneUpgrading() throws {
    let p = try septemberPlan()
    let now = p.night.sunset.addingTimeInterval(-1800)
    func step(_ state: AlertState?, at t: Date = now, plan: NightPlan? = nil) -> (AlertNotification?, AlertState) {
        let r = AlertEngine.step(now: t, tonight: plan ?? p, tomorrow: nil, state: state, settings: AlertSettings(), forecastFetchedAt: t,
                                 site: sheffield, copy: Copy())
        return (r.notification, r.state)
    }
    let line = Copy.firstClear(p.primary!, site: sheffield)
    #expect(line.hasPrefix("Your first clear window with Nightwatch: ") && line.hasSuffix("."))
    // A fresh install: the first heads-up opens with it.
    let (first, afterFirst) = step(nil)
    #expect(first?.body.hasPrefix(line + " ") == true && afterFirst.firstClearSaid == true)
    // The next clear night: never again.
    let next = try Ephemeris.night(localDate: utc(2026, 9, 30, 12, 0), site: sheffield)
    let w2 = ClearWindow(start: try #require(next.darkStart), end: try #require(next.darkEnd))
    let p2 = NightPlan(night: next, windows: [w2], primary: w2, score: 80, qualifies: true, moonIllumination: 0, moonRise: nil, moonSet: nil,
                       darkHours: [], targets: [], best: [], seeingAvailable: false)
    let (second, _) = step(afterFirst, at: next.sunset.addingTimeInterval(-1800), plan: p2)
    #expect(second?.kind == .headsUp && second?.body.contains("first clear window") == false)
    // Someone upgrading: an alerts file from before the field existed decodes it as nil, which counts as said.
    let old = try JSONDecoder().decode(AlertState.self, from: Data(#"{"nightKey":"2026-09-20","stage":"done"}"#.utf8))
    #expect(old.firstClearSaid == nil)
    #expect(step(old).0?.body.contains("first clear window") == false)
    // A cloudy first night says nothing and keeps it for the first clear one.
    let cloudy = NightPlan(night: p.night, windows: [], primary: nil, score: 10, qualifies: false, moonIllumination: 0, moonRise: nil,
                           moonSet: nil, darkHours: [], targets: [], best: [], seeingAvailable: false)
    #expect(step(nil, plan: cloudy).1.firstClearSaid == false)
}


@Test func aFirstClearLineDroppedInQuietHoursIsNotUsedUp() throws {
    let p = try septemberPlan()
    // After midnight, inside the default quiet hours (00:00–07:00), with the window still open: the go is dropped.
    let late = p.primary!.start.addingTimeInterval(4 * 3600)
    var quiet = AlertSettings(); quiet.quietStartHour = 0; quiet.quietEndHour = 7
    let r = AlertEngine.step(now: late, tonight: p, tomorrow: nil, state: nil, settings: quiet, forecastFetchedAt: late, site: sheffield, copy: Copy())
    #expect(r.notification == nil)
    #expect(r.state.firstClearSaid == false)
}
