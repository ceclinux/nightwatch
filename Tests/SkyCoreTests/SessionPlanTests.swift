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
    #expect(Copy.planDetail(s.items[0], presetID: "dwarf-mini", site: sheffield).hasSuffix(" · Duo-Band · 200 × 30 s"))
    #expect(Copy.planDetail(s.items[0], presetID: "dwarf-mini", site: sheffield).contains("at 70° in the "))
    // Taken off again, a target added for the night just leaves the plan: only a favourite keeps a taken-off row.
    c = SessionPlanner.choose("M33", on: false, isFavourite: false, in: c)
    #expect(c == PlanChoices())
    s = try #require(make(p, favourites: ["NGC7000"], choices: c))
    #expect(s.items.map(\.id) == ["NGC7000"] && s.takenOff.isEmpty)
    // A choice saved by the build that remembered every target taken off is ignored, not shown as a row.
    s = try #require(make(p, favourites: ["NGC7000"], choices: PlanChoices(removed: ["M33"])))
    #expect(s.items.map(\.id) == ["NGC7000"] && s.takenOff.isEmpty)
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

// Owner, 9 October 2026, on a plan reading "finish by 00:30" above the Pleiades, best at 03:48: "Doesn't respect the
// night time end setting?" A row's times now end at the finish time.
@Test func aFinishTimeEndsEveryRowsTimes() throws {
    let ids = ["NGC6888", "NGC7635", "NGC281"]
    let p = try septemberPlan(favourites: ids)
    let whole = try #require(make(p, favourites: ids))
    let pacman = try #require(whole.items.first { $0.id == "NGC281" }).target
    let stop = StopBy(enabled: true, minutes: 23 * 60), finish = stop.date(night: p.night, site: sheffield)
    #expect(pacman.peakTime > finish)                                               // the Pacman is best after 23:00
    let s = try #require(make(p, favourites: ids, stopBy: stop))
    #expect(s.window.end == finish && Set(s.items.map(\.id)) == Set(ids))            // still in the plan: it is up before the finish
    #expect(s.items.allSatisfy { $0.target.peakTime <= finish && ($0.target.viewable?.end ?? .distantFuture) <= finish })
    let capped = try #require(s.items.first { $0.id == "NGC281" }).target
    #expect(capped.peakAltDeg < pacman.peakAltDeg && capped.peakAltDeg >= GoRule().minAltitudeDeg)   // lower than at its best, and above the floor
    #expect(Copy.planDetail(s.items[0], presetID: nil, site: sheffield).contains("–23:00 · best "))
    // The Crescent, best early in the evening, is as it was.
    #expect(s.items.first { $0.id == "NGC6888" }?.target.peakTime == whole.items.first { $0.id == "NGC6888" }?.target.peakTime)
    // With no finish time nothing is tracked again.
    #expect(whole.items.map(\.target) == ids.compactMap { id in p.targets.first { $0.id == id } }.sorted { $0.peakTime < $1.peakTime })
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
    #expect(b["seestar-s30"] == 6 && b["seestar-s50-pro"] == 9)
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

// A long gap in the plan (owner, 9 October 2026): with Cygnus best at 20:18 and the Pleiades at 03:48, seven and a half
// hours pass with nothing planned. Show suggestions offers a target for it, to add or to leave.

/// A target best `hours` after the window opens, `alt` degrees up, up all window.
private func at(_ id: String, _ hours: Double, alt: Double, in w: ClearWindow, group: TargetGroup = .nebulae, fit: FrameFit = .fits,
                mag: Double = 8, size: Double = 10, moonWashed: Bool = false) -> RankedTarget {
    var t = RankedTarget(id: id, name: id, subtitle: "", group: group, raHours: 0, decDeg: 0, sizeArcmin: size, magnitude: mag, fit: fit,
                         peakAltDeg: alt, peakTime: w.start.addingTimeInterval(hours * 3600), moonSepDeg: 90, moonWashed: moonWashed, visibleFraction: 1)
    t.catalogueID = id; t.viewable = w; t.typeName = "Emission nebula"
    return t
}
/// A and B are the favourites, best 7 h 30 min apart; the rest are that night's other targets.
private func gapNight(_ others: (ClearWindow) -> [RankedTarget], apart: Double = 7.5) throws -> (NightPlan, ClearWindow) {
    let w = try #require(try nightWith([]).primary)
    let a = at("A", 0, alt: 86, in: w), b = at("B", apart, alt: 60, in: w)
    return (try nightWith([a, b] + others(w), favourites: [a, b].map { FavouriteTarget(target: $0, notTonight: nil) }), w)
}
private func kinds(_ rows: [PlanRow]) -> String {
    rows.map { switch $0 { case .item: "in"; case .suggestion: "suggested"; case .takenOff: "off" } }.joined(separator: " ")
}

@Test func aLongGapOffersTheHighestTargetBestInsideIt() throws {
    let (p, _) = try gapNight { w in
        var brief = at("brief", 4, alt: 88, in: w)                                  // clear of the horizon for an hour: no time to image it
        brief.viewable = ClearWindow(start: w.start.addingTimeInterval(3.5 * 3600), end: w.start.addingTimeInterval(4.5 * 3600))
        return [at("C", 4, alt: 60, in: w), at("D", 3, alt: 80, in: w), brief,
                at("early", 2, alt: 89, in: w), at("late", 5, alt: 88, in: w),      // under three hours from a favourite
                at("washed", 4, alt: 87, in: w, moonWashed: true), at("wide", 4, alt: 86, in: w, fit: .mosaic),
                at("speck", 4, alt: 85, in: w, fit: .small), at("star", 4, alt: 84, in: w, group: .stars)]
    }
    let s = try #require(make(p, favourites: ["A", "B"]))
    #expect(s.items.map(\.id) == ["A", "B"])                                       // the plan itself is untouched
    // D is the highest that qualifies, three hours after A. C, an hour after D, is not offered as well: one target for
    // three hours or so of imaging, not a list to pick through.
    #expect(s.suggestions.map(\.id) == ["D"])
    #expect(s.rows.map(\.id) == ["A", "D", "B"] && kinds(s.rows) == "in suggested in")
    #expect(Copy.planOffDetail(s.rows[1], nightWords: "tonight", presetID: nil, site: sheffield)?.hasPrefix("Suggested · Up ") == true)
    #expect(Copy.planOffDetail(s.rows[0], nightWords: "tonight", presetID: nil, site: sheffield) == nil)   // a plan row has its own wording
}

// Owner, 9 October 2026: "most deep space object need 3-4 hours of time to capture all the pictures required for image
// stacking, you're typically not tracking more than 3 or 4 objects in one night."
@Test func aSuggestionIsThreeHoursFromEveryOtherRow() throws {
    let filler: (ClearWindow) -> [RankedTarget] = { w in [at("mid", 3, alt: 70, in: w)] }
    let (short, _) = try gapNight(filler, apart: 5.99)
    #expect(try #require(make(short, favourites: ["A", "B"])).suggestions.isEmpty)
    let (exact, _) = try gapNight(filler, apart: 2 * SessionPlanner.gapHours)
    #expect(try #require(make(exact, favourites: ["A", "B"])).suggestions.map(\.id) == ["mid"])
    // A gap with nothing best inside it offers nothing.
    let (bare, _) = try gapNight({ _ in [] })
    #expect(try #require(make(bare, favourites: ["A", "B"])).suggestions.isEmpty)
    // A good target best every hour of a night with no favourites: the rows are still three hours apart, four at most.
    let w = try #require(try nightWith([]).primary)
    let length = w.end.timeIntervalSince(w.start) / 3600
    var none = try nightWith((0...Int(length)).map { at("T\($0)", Double($0), alt: 60 + Double($0 % 5), in: w) }); none.favourites = []
    let s = try #require(make(none, favourites: []))
    #expect(s.items.isEmpty && (2...4).contains(s.suggestions.count))               // the whole window is one stretch
    #expect(zip(s.suggestions, s.suggestions.dropFirst()).allSatisfy { $1.peakTime.timeIntervalSince($0.peakTime) >= SessionPlanner.gapHours * 3600 })
    // Owner, the same day: "If there are no favourites at all but the night is clear we should add the suggestions for
    // the user to review and agree or remove." Adding one makes it a plan row where it stood.
    let added = try #require(make(none, favourites: [], choices: PlanChoices(added: [s.suggestions[0].id])))
    #expect(added.items.map(\.id) == [s.suggestions[0].id] && added.rows.map(\.id) == s.rows.map(\.id))
}

// The owner's recording, 9 October 2026: suggestions he had not touched left and others arrived each time he added a row,
// took one off or put one back, a suggestion taken off brought up a replacement, and with every row taken off there were
// none. The night now has one set, built from the favourites and the window, and every row keeps its place.
@Test func theSuggestionsAreOneSetWhateverIsAddedOrTakenOff() throws {
    let (p, _) = try gapNight { w in [at("C", 4.5, alt: 60, in: w), at("D", 3, alt: 80, in: w), at("E", 3.2, alt: 70, in: w), at("X", 7, alt: 50, in: w)] }
    let order = ["A", "D", "B"]
    func rows(_ c: PlanChoices) throws -> [PlanRow] { try #require(make(p, favourites: ["A", "B"], choices: c)).rows }
    #expect(try rows(PlanChoices()).map(\.id) == order && kinds(try rows(PlanChoices())) == "in suggested in")
    // Add to plan on D: it is a plan row where it stood.
    var c = SessionPlanner.choose("D", on: true, isFavourite: false, in: PlanChoices())
    #expect(try rows(c).map(\.id) == order && kinds(try rows(c)) == "in in in")
    #expect(try #require(make(p, favourites: ["A", "B"], choices: c)).items[1].added)
    // "Not tonight" on D: the suggestion again, in the same place. E, the next best, does not take its turn.
    c = SessionPlanner.choose("D", on: false, isFavourite: false, in: c)
    #expect(c == PlanChoices())
    #expect(try rows(c).map(\.id) == order && kinds(try rows(c)) == "in suggested in")
    // A favourite taken off stays where it was with Put back, and the gap it leaves is not filled with new suggestions.
    c = SessionPlanner.choose("B", on: false, isFavourite: true, in: c)
    #expect(try rows(c).map(\.id) == order && kinds(try rows(c)) == "in suggested off")
    #expect(Copy.planOffDetail(try rows(c)[2], nightWords: "tomorrow night", presetID: nil, site: sheffield)?.hasPrefix("Taken off tomorrow night · Up ") == true)
    // Every favourite taken off: the suggestion is still there.
    c = SessionPlanner.choose("A", on: false, isFavourite: true, in: c)
    #expect(try rows(c).map(\.id) == order && kinds(try rows(c)) == "off suggested off")
    // A target added from its own page takes its place by best time and moves nothing else; taken off, it leaves and
    // nothing else moves.
    c = SessionPlanner.choose("X", on: true, isFavourite: false, in: c)
    #expect(try rows(c).map(\.id) == ["A", "D", "X", "B"] && kinds(try rows(c)) == "off suggested in off")
    c = SessionPlanner.choose("X", on: false, isFavourite: false, in: c)
    #expect(try rows(c).map(\.id) == order && kinds(try rows(c)) == "off suggested off")
}

@Test func aSuggestionIsNeverAFavourite() throws {
    let w = try #require(try nightWith([]).primary)
    let a = at("A", 0, alt: 86, in: w), b = at("B", 7.5, alt: 60, in: w), x = at("X", 6, alt: 85, in: w)
    let d = at("D", 3, alt: 80, in: w), y = at("Y", 4.5, alt: 89, in: w)
    let p = try nightWith([a, b, x, d, y], favourites: [a, b, x].map { FavouriteTarget(target: $0, notTonight: nil) })
    // X is a favourite taken off for the night: it is a taken-off row, never a suggestion, and still marks the end of the
    // stretch D is offered for. Y, higher than D, is under three hours from X whether X is in the plan or not.
    let s = try #require(make(p, favourites: ["A", "B", "X"], choices: PlanChoices(removed: ["X"])))
    #expect(s.takenOff.map(\.id) == ["X"] && s.suggestions.map(\.id) == ["D"])
    #expect(s.suggestions == (try #require(make(p, favourites: ["A", "B", "X"]))).suggestions)
}

@Test func aSuggestionEndsWithThePlanAndFollowsTheHazeRule() throws {
    let (p, w) = try gapNight { w in [at("high-faint", 3, alt: 80, in: w, mag: 9), at("low-bright", 4, alt: 60, in: w, mag: 5)] }
    let anchors = try #require(make(p, favourites: ["A", "B"])).items.map(\.target)
    func offer(_ plan: NightPlan, end: Date) -> [String] {
        SessionPlanner.suggestions(anchors: anchors, plan: plan, excluding: ["A", "B"], window: ClearWindow(start: w.start, end: end)).map(\.id)
    }
    #expect(offer(p, end: w.end) == ["high-faint"])                 // the highest
    // A finish time before a target's best moment rules it out.
    #expect(offer(p, end: w.start.addingTimeInterval(3.5 * 3600)) == ["high-faint"])
    #expect(offer(p, end: w.start.addingTimeInterval(2.5 * 3600)).isEmpty)
    // In haze the brightest is chosen, not the highest.
    var hazy = p; hazy.hazeDepth = 1.0
    #expect(hazy.hazy && offer(hazy, end: w.end) == ["low-bright"])
}

// The owner, on seeing the first version: "cover the gaps before the first row and after the last too".
@Test func theHoursBeforeTheFirstFavouriteAndAfterTheLastAreGapsToo() throws {
    let w = try #require(try nightWith([]).primary)
    let length = w.end.timeIntervalSince(w.start) / 3600
    // One favourite, best four hours in: over three hours free before it, and over three after it on a late-September night.
    let only = at("only", 4, alt: 70, in: w)
    let before = at("before", 1, alt: 75, in: w), opening = at("opening", 0, alt: 60, in: w), tooClose = at("too-close", 2, alt: 89, in: w)
    let after = at("after", 7.1, alt: 72, in: w), closing = at("closing", length, alt: 65, in: w)
    let p = try nightWith([only, before, opening, tooClose, after, closing], favourites: [FavouriteTarget(target: only, notTonight: nil)])
    #expect(length >= 7.1)
    #expect(try #require(make(p, favourites: ["only"])).rows.map(\.id) == ["before", "only", "after"])
    // A target best as the window opens, or as it closes, can fill an end: there is no neighbour there to keep clear of.
    let ends = try nightWith([only, opening, closing], favourites: [FavouriteTarget(target: only, notTonight: nil)])
    #expect(try #require(make(ends, favourites: ["only"])).rows.map(\.id) == ["opening", "only", "closing"])
    // A first favourite best as the window opens leaves nothing before it.
    let early = at("early", 0, alt: 70, in: w)
    let flush = try nightWith([early, before, after], favourites: [FavouriteTarget(target: early, notTonight: nil)])
    #expect(try #require(make(flush, favourites: ["early"])).rows.map(\.id) == ["early", "after"])
}

// Owner, 10 October 2026: "Now mix in nebulae and galaxies please."
@Test func suggestionsAreAMixOfKinds() throws {
    let w = try #require(try nightWith([]).primary)
    // A cluster and a galaxy are both best in each half of a night with no favourites, the clusters higher.
    let c1 = at("cluster-1", 1, alt: 85, in: w, group: .clusters), g1 = at("galaxy-1", 1.2, alt: 70, in: w, group: .galaxies)
    let c2 = at("cluster-2", 5, alt: 84, in: w, group: .clusters), g2 = at("galaxy-2", 5.2, alt: 60, in: w, group: .galaxies)
    var p = try nightWith([c1, g1, c2, g2]); p.favourites = []
    // The highest first, a cluster; then the galaxy in the other half, though a cluster there is higher.
    #expect(try #require(make(p, favourites: [])).suggestions.map(\.id) == ["cluster-1", "galaxy-2"])
    // A favourite counts: with a cluster already a favourite, the one suggestion is the galaxy.
    let fav = at("fav", 0, alt: 80, in: w, group: .clusters)
    let q = try nightWith([fav, c2, g2], favourites: [FavouriteTarget(target: fav, notTonight: nil)])
    #expect(try #require(make(q, favourites: ["fav"])).suggestions.map(\.id) == ["galaxy-2"])
}

@Test func suggestionsPreferMessierAndCaldwellObjects() throws {
    let w = try #require(try nightWith([]).primary)
    var messier = at("NGC224", 3.5, alt: 55, in: w); messier.catalogueID = "M31"
    var caldwell = at("NGC869", 4.5, alt: 50, in: w); caldwell.caldwell = 14
    let overhead = at("NGC744", 3.2, alt: 88, in: w), alsoHigh = at("NGC7789", 4.4, alt: 87, in: w)
    #expect(messier.isShowpiece && caldwell.isShowpiece && !overhead.isShowpiece)
    var moon = at("moon", 3, alt: 40, in: w, group: .planets); moon.catalogueID = "Moon"
    #expect(!moon.isShowpiece)                                                              // "Moon" is not a Messier number
    let a = at("A", 0, alt: 86, in: w), b = at("B", 7.5, alt: 60, in: w)
    let p = try nightWith([a, b, messier, caldwell, overhead, alsoHigh], favourites: [a, b].map { FavouriteTarget(target: $0, notTonight: nil) })
    // The Messier object is 33 degrees lower than the cluster overhead and is still the one offered.
    #expect(try #require(make(p, favourites: ["A", "B"])).suggestions.map(\.id) == ["NGC224"])
    // With no showpiece best in the gap, the highest is offered.
    let plain = try nightWith([a, b, overhead, alsoHigh], favourites: [a, b].map { FavouriteTarget(target: $0, notTonight: nil) })
    #expect(try #require(make(plain, favourites: ["A", "B"])).suggestions.map(\.id) == ["NGC744"])
}

// What the rule picks on a real night, since a ranking rule is only as good as its picks: the bundled catalogue from
// Sheffield on 10 October 2026 with a DWARF mini's frame and no favourites.
@Test func onARealNightTheSuggestionsAreAFewWellKnownObjectsHoursApart() throws {
    let night = try Ephemeris.night(localDate: utc(2026, 10, 10, 12, 0), site: sheffield)
    let w = ClearWindow(start: try #require(night.darkStart), end: try #require(night.darkEnd))
    let targets = Planner.rank(catalog: try Catalog.bundled(), constellations: [], window: w, site: sheffield, fov: dwarfMini, rule: GoRule())
    let p = NightPlan(night: night, windows: [w], primary: w, score: 80, qualifies: true, moonIllumination: 0, moonRise: nil,
                      moonSet: nil, darkHours: [], targets: targets, best: [], seeingAvailable: false)
    let s = try #require(make(p, favourites: [])).suggestions
    print("REAL NIGHT", Copy.span(w.start, w.end, site: sheffield), s.map { "\(Copy.hhmm($0.peakTime, site: sheffield)) \($0.name) \(Int($0.peakAltDeg))°" })
    #expect((2...4).contains(s.count) && s.allSatisfy(\.isShowpiece))
    #expect(Set(s.map(\.group)).count == s.count)                                          // one of each kind, not three clusters
    #expect(zip(s, s.dropFirst()).allSatisfy { $1.peakTime.timeIntervalSince($0.peakTime) >= SessionPlanner.gapHours * 3600 })
}
