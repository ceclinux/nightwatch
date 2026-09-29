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

private func make(_ p: NightPlan, preset: String? = "dwarf-mini", battery: Double? = 4, stopBy: StopBy = StopBy(),
                  favourites: [String] = [], added: [String] = [], removed: Set<String> = [], now: Date? = nil) -> SessionPlan? {
    SessionPlanner.make(plan: p, presetID: preset, batteryHours: battery, stopBy: stopBy, favourites: favourites,
                        added: added, removed: removed, now: now, site: sheffield)
}

/// The same night's targets over a window of our choosing.
private func withWindow(_ p: NightPlan, _ w: ClearWindow) -> NightPlan {
    let targets = Planner.rank(catalog: Catalog(objects: [crescent, bubble, pacman, veil, crab]), constellations: [], window: w, site: sheffield,
                               fov: dwarfMini, rule: GoRule())
    return NightPlan(night: p.night, windows: [w], primary: w, score: 80, qualifies: true, moonIllumination: 0, moonRise: nil,
                     moonSet: nil, darkHours: [], targets: targets, best: [], seeingAvailable: false)
}
private let crab = DeepSkyObject(id: "NGC1952", commonName: "Crab Nebula", messier: 1, typeCode: "SNR", group: .nebulae,
                                 raHours: 5.575, decDeg: 22.0, majAxisArcmin: 8, minAxisArcmin: 4, magnitude: 8.4, constellation: "Tau")

@Test func thePlanRunsInBestViewingOrderWithStackLongSlots() throws {
    let p = try septemberPlan()
    let s = try #require(make(p))
    #expect(s.slots.first?.id == "NGC6888")                                   // Cygnus first: it is best early
    #expect(Set(s.slots.map(\.id)).isSuperset(of: ["NGC7635", "NGC281"]))
    #expect(!s.slots.contains { $0.id == "NGC6960" })                          // the Veil does not fit a DWARF Mini's frame
    #expect(s.slots.allSatisfy { $0.end.timeIntervalSince($0.start) == 100 * 60 })   // 200 × 30 s
    #expect(zip(s.slots, s.slots.dropFirst()).allSatisfy { $0.end == $1.start })
    #expect(s.slots.first?.start == p.primary?.start && (s.slots.last?.end ?? .distantFuture) <= s.end)
    for slot in s.slots {                                                      // every slot inside the target's viewable span
        let v = try #require(slot.target.viewable)
        #expect(v.start <= slot.start && slot.end <= v.end)
    }
}

@Test func thePlanSaysWhenItOutlastsTheBatteryButIsNotCutShort() throws {
    let s = try #require(make(try septemberPlan()))
    #expect(s.slots.count == 3 && s.hours == 5)                                // three stacks, 5 h, past a 4 h battery
    #expect(s.outlastsBatteryHours == 4)
    #expect(make(try septemberPlan(), battery: nil)?.outlastsBatteryHours == nil)   // a camera: no note
    #expect(make(try septemberPlan(), battery: 6)?.outlastsBatteryHours == nil)
    let left = try #require(s.leftover)                                        // only three targets fit: the rest is free
    #expect(left.start == s.slots.last?.end && left.end == s.end && !s.leftoverTooShort)
    #expect(try #require(make(try septemberPlan(), stopBy: StopBy(enabled: true, minutes: 90))).leftoverTooShort)   // 01:30: under a stack left
}

@Test func stopByEndsThePlanAndItsText() throws {
    let p = try septemberPlan()
    let stop = StopBy(enabled: true, minutes: 30)                              // 00:30
    let s = try #require(make(p, stopBy: stop))
    let stopAt = stop.date(night: p.night, site: sheffield)
    #expect(s.end == stopAt && s.slots.allSatisfy { $0.end <= stopAt })
    #expect(s.slots.count == 2)
    #expect(Copy.hhmm(stopAt, site: sheffield) == "00:30" && stopAt > p.night.sunset)
}

@Test func favouritesAndAddedTargetsGoFirstAndRemovedOnesNever() throws {
    let p = try septemberPlan(favourites: ["NGC281"])
    #expect(make(p, favourites: ["NGC281"])?.slots.first?.id == "NGC281")
    #expect(make(p, added: ["NGC7635"])?.slots.first?.id == "NGC7635")
    #expect(make(p, added: ["NGC6960"])?.slots.first?.id == "NGC6960")        // added by hand: its frame is the user's call
    #expect(make(p, removed: ["NGC6888"])?.slots.contains { $0.id == "NGC6888" } == false)
    let star = RankedTarget(id: "HIP102098", name: "Deneb", subtitle: "Star", group: .stars, raHours: 20.69, decDeg: 45.3, sizeArcmin: nil,
                            magnitude: 1.25, fit: .small, peakAltDeg: 85, peakTime: p.primary!.start, moonSepDeg: 90, moonWashed: false,
                            visibleFraction: 1, viewable: p.primary)
    var withStar = p; withStar.favourites.append(FavouriteTarget(target: star, notTonight: nil))
    #expect(!SessionPlanner.canTake(star) && make(withStar, added: ["HIP102098"])?.slots.contains { $0.id == "HIP102098" } == false)
}

@Test func withoutAMakerFrameCountATargetGetsTheTimeItIsUp() throws {
    let s = try #require(make(try septemberPlan(), preset: "seestar-s50", battery: 6))
    #expect(s.slots.first.map { $0.end.timeIntervalSince($0.start) >= 3600 } == true)
    #expect(s.slots.last?.end == s.end || s.leftover != nil)
}

@Test func noPlanWithoutAWindowOrOnABrightNight() throws {
    var p = try septemberPlan()
    p.mode = .bright
    #expect(make(p) == nil)
    let none = NightPlan(night: p.night, windows: [], primary: nil, score: 10, qualifies: false, moonIllumination: 0, moonRise: nil,
                         moonSet: nil, darkHours: [], targets: p.targets, best: [], seeingAvailable: false)
    #expect(make(none) == nil)
    #expect(make(try septemberPlan(objects: [veil])) == nil)                   // nothing that fits
}

@Test func thePresetsCarryTheMakersBatteryFigures() throws {
    let b = Dictionary(uniqueKeysWithValues: try TelescopePresets.bundled().map { ($0.id, $0.batteryHours) })
    #expect(b["dwarf-mini"] == 4 && b["dwarf-3"] == 5.5 && b["seestar-s50"] == 6)
    #expect(b["dslr-apsc-200"] == .some(nil))
}

@Test func stopByAndShowPlanDefaultAndDecodeFromOlderConfigs() throws {
    let old = try JSONDecoder().decode(Config.self, from: Data("{}".utf8))
    #expect(old.stopBy == StopBy() && !old.stopBy.enabled && old.showPlan)
    var c = Config(); c.stopBy = StopBy(enabled: true, minutes: 23 * 60); c.showPlan = false
    let back = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(c))
    #expect(back.stopBy.minutes == 1380 && back.stopBy.enabled && !back.showPlan)
}

@Test func thePlanReadsAsInTheMockUp() throws {
    let p = try septemberPlan()
    let s = try #require(make(p))
    let w = try #require(p.primary)
    #expect(Copy.planHeader(s, window: w, site: sheffield).hasSuffix("· three targets, 5 h"))
    #expect(Copy.planHeader(try #require(make(p, stopBy: StopBy(enabled: true, minutes: 30))), window: w, site: sheffield)
            .contains("· stop by 00:30 · two targets, 3 h 20 min"))
    let cyg = Constellation(id: "Cyg", name: "Cygnus", raHours: 20.6, decDeg: 42, lines: [])
    #expect(Copy.slotName(s.slots[0].target, constellations: [cyg]) == "Crescent Nebula, in Cygnus")
    #expect(Copy.slotName(s.slots[0].target, constellations: []) == "Crescent Nebula")
    #expect(Copy.slotDetail(s.slots[0], index: 0, presetID: "dwarf-mini", site: sheffield).hasSuffix(", so first · Duo-Band · 200 × 30 s"))
    #expect(Copy.slotDetail(s.slots[0], index: 1, presetID: nil, site: sheffield).hasSuffix(", so second"))
    #expect(Copy.planBattery(s, telescope: "DwarfLab DWARF Mini")
            == "This plan runs 5 h, longer than a DwarfLab DWARF Mini battery (about 4 h): you may need a power bank or a spare battery.")
    #expect(Copy.planLeftover(try #require(make(p, stopBy: StopBy(enabled: true, minutes: 90))), site: sheffield)?
            .hasSuffix(" min left, too short for another stack.") == true)
    #expect([0, 1, 2, 3, 10, 11, 20].map(Copy.inPlan) == ["In the plan, 1st", "In the plan, 2nd", "In the plan, 3rd", "In the plan, 4th",
                                                         "In the plan, 11th", "In the plan, 12th", "In the plan, 21st"])
    #expect(Copy.duration(40 * 60) == "40 min" && Copy.duration(100 * 60) == "1 h 40 min")
}

@Test func theHeadsUpNamesWhereToStartAndDewOnlyWhenLikely() throws {
    var p = try septemberPlan()
    let s = try #require(make(p))
    let first = Copy.hhmm(s.slots[0].start, site: sheffield), second = Copy.hhmm(s.slots[1].start, site: sheffield)
    let expected = "Start with the Crescent Nebula at \(first), then the \(try #require(s.slots[1].target.commonName)) at \(second)."
    #expect(Copy.headsUpPlan(s, plan: p, site: sheffield) == expected)
    let damp = s.slots[1].start.addingTimeInterval(1800)
    p = NightPlan(night: p.night, windows: p.windows, primary: p.primary, score: 80, qualifies: true, moonIllumination: 0, moonRise: nil, moonSet: nil,
                  darkHours: [HourlyConditions(time: damp, cloudTotal: 0, cloudLow: nil, cloudMid: nil, cloudHigh: nil, tempC: 6, dewPointC: 5,
                                               humidityPct: nil, windKmh: nil, gustKmh: nil, visibilityM: nil, seeing: nil, transparency: nil)],
                  targets: p.targets, best: [], seeingAvailable: false)
    #expect(Copy.headsUpPlan(s, plan: p, site: sheffield) == expected + " Fit the dew heater: dew likely after \(Copy.hhmm(damp, site: sheffield)).")
}

@Test func notTonightSilencesTheRestOfTheNight() throws {
    let p = try septemberPlan()
    let now = p.night.sunset.addingTimeInterval(-1800)
    let quiet = AlertState(nightKey: p.night.key, stage: .idle, silenced: true)
    let r = AlertEngine.step(now: now, tonight: p, tomorrow: nil, state: quiet, settings: AlertSettings(), forecastFetchedAt: now,
                             site: sheffield, copy: Copy())
    #expect(r.notification == nil && r.state == quiet)
    let s = try #require(make(p))
    let heads = AlertEngine.step(now: now, tonight: p, tomorrow: nil, state: nil, settings: AlertSettings(), forecastFetchedAt: now,
                                 site: sheffield, copy: Copy(), session: s)
    #expect(heads.notification?.kind == .headsUp && heads.notification?.body.hasPrefix("Start with the Crescent Nebula") == true)
}

@Test func stopByBelongsToTheNightNotToTheWindow() throws {
    let p = try septemberPlan()
    // A window opening at 01:00 with Stop by 00:30, or at 23:30 with Stop by 23:00: nothing to plan, not a plan to 04:20.
    #expect(make(withWindow(p, ClearWindow(start: utc(2026, 9, 30, 0, 0), end: utc(2026, 9, 30, 4, 0))), stopBy: StopBy(enabled: true, minutes: 30)) == nil)
    #expect(make(withWindow(p, ClearWindow(start: utc(2026, 9, 29, 22, 30), end: utc(2026, 9, 30, 3, 0))), stopBy: StopBy(enabled: true, minutes: 23 * 60)) == nil)
    // The night the clocks go back (25 October 2026): 03:00 is still 03:00.
    let autumn = try Ephemeris.night(localDate: utc(2026, 10, 24, 12, 0), site: sheffield)
    #expect(Copy.hhmm(StopBy(enabled: true, minutes: 180).date(night: autumn, site: sheffield), site: sheffield) == "03:00")
}

@Test func thePlanWaitsForATargetThatRisesLater() throws {
    // 23:00 to 05:00 BST: the Crescent, then the Pacman and the Bubble, and the Crab once it is up, not an early stop.
    let p = withWindow(try septemberPlan(), ClearWindow(start: utc(2026, 9, 29, 22, 0), end: utc(2026, 9, 30, 4, 0)))
    let s = try #require(make(p, removed: ["NGC7635", "NGC281"]))
    #expect(s.slots.map(\.id) == ["NGC6888", "NGC1952"])
    let crabUp = try #require(s.slots.last?.target.viewable?.start)
    #expect(s.slots[1].start >= crabUp && s.slots[1].start > s.slots[0].end)
}

@Test func onTheRealCatalogueThePlanChoosesTheNightsBestTargets() throws {
    let night = try Ephemeris.night(localDate: utc(2026, 9, 29, 12, 0), site: sheffield)
    let w = ClearWindow(start: try #require(night.darkStart), end: try #require(night.darkEnd))
    let targets = Planner.rank(catalog: try Catalog.bundled(), constellations: [], window: w, site: sheffield, fov: dwarfMini, rule: GoRule())
    let p = NightPlan(night: night, windows: [w], primary: w, score: 80, qualifies: true, moonIllumination: 0, moonRise: nil,
                      moonSet: nil, darkHours: [], targets: targets, best: [], seeingAvailable: false)
    let s = try #require(make(p))
    #expect(s.slots.count >= 3)
    #expect(s.slots.allSatisfy { $0.target.commonName != nil })              // well-known targets, not whatever is highest
    #expect(s.slots.allSatisfy { $0.target.fit == .fits && !$0.target.moonWashed && $0.reason == .bestPlaced })
    let seestar = try #require(make(p, preset: "seestar-s50", battery: 6))   // about 1,000 × 10 s: several, not one all night
    #expect(seestar.slots.count >= 2 && seestar.slots.allSatisfy { abs($0.end.timeIntervalSince($0.start) - 10_000) < 1 })
    let camera = try #require(make(p, preset: "dslr-apsc-200", battery: nil)) // no frame count: while well placed
    #expect(camera.slots.count >= 2)
}

@Test func onceTheWindowHasStartedThePlanRunsFromNow() throws {
    let p = try septemberPlan()
    let now = p.primary!.start.addingTimeInterval(2 * 3600 + 7 * 60)
    let s = try #require(make(p, now: now))
    #expect(s.slots[0].start >= now && s.slots[0].start.timeIntervalSince(now) < 300)
}

@Test func aFavouriteOrAddedTargetSaysWhyItIsThere() throws {
    let p = try septemberPlan(favourites: ["NGC281"])
    let s = try #require(make(p, favourites: ["NGC281"]))
    #expect(s.slots[0].reason == .favourite && Copy.slotDetail(s.slots[0], index: 0, presetID: nil, site: sheffield).hasPrefix("Favourite · best "))
    let a = try #require(make(p, added: ["NGC7635"]))
    #expect(Copy.slotDetail(a.slots[0], index: 0, presetID: nil, site: sheffield).hasPrefix("Added by you · best "))
}

@Test func siriReadsTonightsPlanWhenThereIsOne() throws {
    let p = try septemberPlan()
    let s = try #require(make(p))
    let snap = WidgetSnapshot.make(plan: p, tomorrow: nil, fetchedAt: p.night.sunset, site: sheffield, rule: GoRule(), bright: BrightSettings(),
                                   alerts: AlertSettings(), copy: Copy())
    let text = Copy.siriBest(snap, session: s, site: sheffield)
    #expect(text.hasPrefix("Tonight's plan: Crescent Nebula at \(Copy.hhmm(s.slots[0].start, site: sheffield)), then "))
    #expect(text.components(separatedBy: ", then ").count == s.slots.count)
}
