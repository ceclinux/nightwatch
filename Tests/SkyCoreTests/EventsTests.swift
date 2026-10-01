import Testing
import Foundation
@testable import SkyCore

private let site = Site(name: "Sheffield", latitude: 53.38, longitude: -1.47, elevationM: 100, timeZoneID: "Europe/London", bortle: 5)

@Test func bundledShowersLoad() throws {
    let s = try MeteorShowers.bundled()
    #expect(s.count == 12)
    #expect(s.contains { $0.id == "gem" && $0.zhr == 150 })
}

@Test func activeShowersOnSeptember23IncludeSouthernTaurids() throws {
    let s = try MeteorShowers.bundled()
    let active = MeteorShowers.active(on: utc(2026, 9, 23, 12, 0), calendar: site.calendar, showers: s)
    #expect(active.map(\.id) == ["sta"])
}

@Test func quadrantidsSpanTheNewYear() throws {
    let s = try MeteorShowers.bundled()
    #expect(MeteorShowers.active(on: utc(2026, 12, 30, 12, 0), calendar: site.calendar, showers: s).contains { $0.id == "qua" })
    #expect(MeteorShowers.active(on: utc(2027, 1, 2, 12, 0), calendar: site.calendar, showers: s).contains { $0.id == "qua" })
    #expect(!MeteorShowers.active(on: utc(2027, 1, 20, 12, 0), calendar: site.calendar, showers: s).contains { $0.id == "qua" })
}

@Test func peakDetection() throws {
    let gem = try #require(try MeteorShowers.bundled().first { $0.id == "gem" })
    #expect(MeteorShowers.isPeak(gem, on: utc(2026, 12, 14, 12, 0), calendar: site.calendar))
    #expect(!MeteorShowers.isPeak(gem, on: utc(2026, 12, 10, 12, 0), calendar: site.calendar))
}

@Test func showerEventsCarryRadiantAndTitle() throws {
    let night = try Ephemeris.night(localDate: utc(2026, 12, 14, 12, 0), site: site)
    let ev = Events.showers(night: night, site: site, showers: try MeteorShowers.bundled())
    let gem = try #require(ev.first { $0.id == "shower-gem" })
    #expect(gem.kind == .meteorShower)
    #expect(gem.title.contains("Geminids"))
    #expect(gem.detail.contains("peak"))
    #expect(gem.raHours == 7.5)
}

@Test func eclipseEventsWithinAYearExist() {
    let ev = Events.eclipses(after: utc(2026, 9, 23, 0, 0), site: site, withinDays: 400)
    #expect(ev.contains { $0.kind == .lunarEclipse })
}

@Test func conjunctionsAreSymmetricAndBounded() {
    let ev = Events.conjunctions(at: utc(2026, 9, 23, 23, 0), site: site, maxSeparationDeg: 180)
    // 7 planets + Moon = 8 bodies -> 28 pairs
    #expect(ev.count == 28)
    let tight = Events.conjunctions(at: utc(2026, 9, 23, 23, 0), site: site, maxSeparationDeg: 3)
    #expect(tight.count <= 28)
    #expect(tight.allSatisfy { $0.kind == .conjunction })
    let seps = ev.map { Double($0.detail.split(separator: "°")[0])! }
    #expect(zip(seps, seps.dropFirst()).allSatisfy { $0 <= $1 })
}

// MARK: richer events (v1.0.1)

private let dwarfMini = FieldOfView(widthDeg: 2.1, heightDeg: 1.2)

@Test func constellationsComeFromTheIAUBoundaries() {
    #expect(Ephemeris.constellation(raHours: 5.278, decDeg: 46.0).name == "Auriga")     // Capella
    #expect(Ephemeris.constellation(raHours: 18.616, decDeg: 38.78).name == "Lyra")     // Vega
    #expect(Ephemeris.constellation(raHours: 5.919, decDeg: 7.41).name == "Orion")      // Betelgeuse
}

@Test func aShowerSaysWhenItPeaksWhereToLookAndWhatTheMoonDoes() throws {
    let night = try Ephemeris.night(localDate: utc(2026, 9, 27, 12, 0), site: site)   // full Moon
    let sta = try #require(Events.showers(night: night, site: site, showers: try MeteorShowers.bundled()).first { $0.id == "shower-sta" })
    let radiant = Ephemeris.constellation(raHours: 3.5, decDeg: 15).name
    #expect(sta.detail.hasPrefix("Peak night 4–5 November, in 38 days · radiant in \(radiant), best "))
    #expect(sta.facts.map(\.label) == ["Peak", "Radiant", "At peak, from here", "Moon", "Speed", "Parent"])
    #expect(sta.facts[0].value == "Night of 4–5 November, ZHR 7")
    #expect(sta.facts[3].value.contains("hide all but the brightest meteors"))
    let best = try #require(sta.best)
    #expect(best >= night.darkStart! && best <= night.darkEnd!)
    #expect(sta.when == best)
    #expect(sta.brief == "Peak night 4–5 November, in 38 days · radiant in \(radiant)")   // the card's line, without the best time
}

@Test func showerPeakWordingTonightAndAfter() throws {
    let showers = try MeteorShowers.bundled()
    let gemNight = try Ephemeris.night(localDate: utc(2026, 12, 14, 12, 0), site: site)
    let gem = try #require(Events.showers(night: gemNight, site: site, showers: showers).first { $0.id == "shower-gem" })
    #expect(gem.detail.hasPrefix("At peak tonight · radiant in Gemini"))
    let rate = try #require(gem.facts.first { $0.label == "At peak, from here" }?.value)
    let n = try #require(Int(rate.split(separator: " ")[3]))                          // "Up to about N an hour…"
    #expect(n > 0 && n <= 150)
    let quaNight = try Ephemeris.night(localDate: utc(2027, 1, 8, 12, 0), site: site)
    let qua = try #require(Events.showers(night: quaNight, site: site, showers: showers).first { $0.id == "shower-qua" })
    #expect(qua.detail.hasPrefix("Past its peak (night of 2–3 January)"))
}

/// Both nights either side of a peak date say "tonight"; the countdown is to the first of them, across the new year too.
@Test func showerPeakCountdownByNight() throws {
    let showers = try MeteorShowers.bundled()
    func detail(_ id: String, _ y: Int, _ m: Int, _ d: Int) throws -> String {
        let n = try Ephemeris.night(localDate: utc(y, m, d, 12, 0), site: site)
        return try #require(Events.showers(night: n, site: site, showers: showers).first { $0.id == "shower-\(id)" }).detail
    }
    #expect(try detail("gem", 2026, 12, 12).hasPrefix("Peak tomorrow night (13–14 December)"))
    #expect(try detail("gem", 2026, 12, 13).hasPrefix("At peak tonight"))
    #expect(try detail("gem", 2026, 12, 14).hasPrefix("At peak tonight"))
    #expect(try detail("gem", 2026, 12, 15).hasPrefix("Past its peak (night of 13–14 December)"))
    #expect(try detail("qua", 2026, 12, 28).hasPrefix("Peak night 2–3 January, in 5 days"))
    // Across a month end the month is named twice.
    let early = MeteorShower(id: "x", name: "Test", startMonth: 10, startDay: 20, endMonth: 11, endDay: 10, peakMonth: 11, peakDay: 1,
                             zhr: 10, raHours: 3, decDeg: 20, parent: "none", velocityKms: 30)
    let n = try Ephemeris.night(localDate: utc(2026, 10, 25, 12, 0), site: site)
    #expect(try #require(Events.showers(night: n, site: site, showers: [early]).first).detail.hasPrefix("Peak night 31 October–1 November, in 6 days"))
}

@Test func eclipsesGiveLocalTimesAndHeight() throws {
    let lunar = try #require(Events.eclipses(after: utc(2026, 9, 23, 0, 0), site: site, withinDays: 400).first { $0.kind == .lunarEclipse })
    #expect(lunar.facts.map(\.label).prefix(3) == ["Begins", "Peak", "Ends"])
    #expect(lunar.facts.last?.label == "Moon at peak")
    let l = try #require(Ephemeris.nextLunarEclipse(after: utc(2026, 9, 23, 0, 0)))
    let begin = try #require(l.begin), end = try #require(l.end)
    #expect(begin < l.peak && l.peak < end)
    #expect(abs(l.peak.timeIntervalSince(begin) - end.timeIntervalSince(l.peak)) < 1)          // symmetric about the peak
    #expect(end.timeIntervalSince(begin) > 30 * 60 && end.timeIntervalSince(begin) < 6 * 3600)
    let moon = try #require(lunar.facts.last?.value)
    #expect(moon.hasSuffix("° up") || moon.hasPrefix("Below the horizon"))
}

@Test func aSolarEclipseCarriesTheSafetyLine() throws {
    let solar = try #require(Events.eclipses(after: utc(2026, 9, 23, 0, 0), site: site, withinDays: 2000).first { $0.kind == .solarEclipse })
    #expect(solar.facts.contains { $0.label == "Safety" && $0.value.contains("certified solar filter") })
    let sun = try #require(solar.facts.first { $0.label == "Sun at peak" }?.value)
    #expect(sun.hasSuffix("° up") || sun.hasPrefix("Below the horizon"))
    #expect(!sun.hasPrefix("-"))
}

@Test func theFrameFitAllowsForTheMoonsWidth() {
    #expect(Events.fits(separationDeg: 1.8, fov: dwarfMini, includesMoon: false))    // 1.8 ≤ 2.1 × 0.9
    #expect(!Events.fits(separationDeg: 1.9, fov: dwarfMini, includesMoon: false))
    #expect(Events.fits(separationDeg: 1.6, fov: dwarfMini, includesMoon: true))     // 1.6 + 0.26 ≤ 1.89
    #expect(!Events.fits(separationDeg: 1.7, fov: dwarfMini, includesMoon: true))    // the Moon's far limb would be cut off
}

@Test func conjunctionsSayWhetherTheyFitTheFrame() throws {
    let night = try Ephemeris.night(localDate: utc(2026, 9, 23, 12, 0), site: site)
    let ev = Events.conjunctions(at: utc(2026, 9, 23, 23, 0), site: site, maxSeparationDeg: 180, night: night, fov: dwarfMini)
    #expect(ev.count == 28)
    for e in ev {
        let sep = try #require(e.separationDeg), fits = try #require(e.fits)
        #expect(fits == Events.fits(separationDeg: sep, fov: dwarfMini, includesMoon: e.title.contains("Moon")))
        #expect(e.detail.contains(fits ? "fits your field of view" : "wider than your field of view"))
        if e.best != nil { #expect(e.brief.map { !$0.contains(" · best ") && e.detail.hasPrefix($0) } == true) }
        #expect(e.facts.map(\.label).starts(with: ["Separation", "Your field of view", "Best"]))
    }
}

@Test func anISSPassSaysWhereToLook() {
    let p = SatellitePass(rise: utc(2026, 9, 27, 20, 10), peak: utc(2026, 9, 27, 20, 14), set: utc(2026, 9, 27, 20, 18),
                          maxElevationDeg: 62, peakAzimuthDeg: 180, riseAzimuthDeg: 270, setAzimuthDeg: 90)
    let e = Events.issPass(p, site: site)
    #expect(e.detail == "Rises W 21:10 · 62° up in the S 21:14 · sets E 21:18")
    #expect(e.best == p.peak)
    #expect(e.facts.last?.value == "About 8 minutes")
    // An evening pass that runs into Earth's shadow fades before it sets, and is visible for less time.
    var f = p; f.appears = p.rise; f.appearsAzimuthDeg = 270; f.vanishes = utc(2026, 9, 27, 20, 16); f.vanishesAzimuthDeg = 135
    let faded = Events.issPass(f, site: site)
    #expect(faded.detail == "Rises W 21:10 · 62° up in the S 21:14 · fades SE 21:16")
    #expect(faded.facts.map(\.label) == ["Rises", "Highest", "Fades", "Visible for"])
    #expect(faded.facts.last?.value == "About 6 minutes")
    // The compass drawing's path (v1.0.1): where it rises, its highest point, and where it fades, at the right heights.
    #expect(e.path.map(\.label) == ["Rises", "Highest", "Sets"] && e.path.map(\.altitudeDeg) == [0, 62, 0])
    #expect(e.path.map(\.azimuthDeg) == [270, 180, 90])
    f.vanishesElevationDeg = 25
    #expect(Events.issPass(f, site: site).path.last == SkyPathPoint(label: "Fades", time: utc(2026, 9, 27, 20, 16), azimuthDeg: 135, altitudeDeg: 25))
    // A morning pass that comes out of Earth's shadow partway: it "appears", at its own height.
    var m = p; m.appears = utc(2026, 9, 27, 20, 12); m.appearsAzimuthDeg = 250; m.appearsElevationDeg = 30; m.vanishes = p.set; m.vanishesAzimuthDeg = 90
    let appears = Events.issPass(m, site: site)
    #expect(appears.detail.hasPrefix("Appears WSW 21:12 · 62° up in the S 21:14"))
    #expect(appears.path.first == SkyPathPoint(label: "Appears", time: utc(2026, 9, 27, 20, 12), azimuthDeg: 250, altitudeDeg: 30))
    // Peaking in shadow: it appears after its peak, so its highest visible point is where it appears, and no hidden peak is drawn.
    var late = p; late.appears = utc(2026, 9, 27, 20, 15); late.appearsAzimuthDeg = 160; late.appearsElevationDeg = 55; late.vanishes = p.set
    late.vanishesAzimuthDeg = 90
    let hidden = Events.issPass(late, site: site)
    #expect(hidden.detail == "Appears SSE 21:15 · 55° up in the SSE 21:15 · sets E 21:18")
    #expect(hidden.path.map(\.label) == ["Appears", "Sets"] && hidden.best == late.appears)
}

@Test func aCometSaysWhereItIsAndWhetherItIsBrightening() throws {
    let night = try Ephemeris.night(localDate: utc(2026, 9, 27, 12, 0), site: site)
    let here = CometPosition(raHours: 5.278, decDeg: 46.0, magnitude: 9.1, deltaAU: 1.2, rAU: 1.5)   // Capella's place: high before dawn
    let c = try #require(Events.comet(designation: "C/2026 X1", pos: here, later: CometPosition(raHours: 5.3, decDeg: 46, magnitude: 8.8, deltaAU: 1.1, rAU: 1.4),
                                      night: night, site: site))
    #expect(c.detail.hasPrefix("mag 9.1 · in Auriga · best "))
    #expect(c.facts.first?.value == "9.1, brightening (8.8 in a week)")
    #expect(c.brief?.hasPrefix("mag 9.1 · in Auriga, ") == true && c.brief?.contains("best ") == false)
    let fading = Events.comet(designation: "x", pos: here, later: CometPosition(raHours: 5.3, decDeg: 46, magnitude: 9.6, deltaAU: 1.3, rAU: 1.6),
                              night: night, site: site)
    #expect(fading?.facts.first?.value == "9.1, fading (9.6 in a week)")
    let steady = Events.comet(designation: "z", pos: here, later: CometPosition(raHours: 5.3, decDeg: 46, magnitude: 9.15, deltaAU: 1.2, rAU: 1.5),
                              night: night, site: site)
    #expect(steady?.facts.first?.value == "9.1, steady")
    let south = CometPosition(raHours: 5.0, decDeg: -60, magnitude: 7, deltaAU: 1, rAU: 1)   // never rises at 53° N
    #expect(Events.comet(designation: "y", pos: south, later: nil, night: night, site: site) == nil)
}

@Test func eventsAreMarkedClearOrCloudyFromTheForecastHour() {
    func hour(_ h: Int, _ cloud: Int) -> HourlyConditions {
        HourlyConditions(time: utc(2026, 9, 27, h, 0), cloudTotal: cloud, cloudLow: nil, cloudMid: nil, cloudHigh: nil, tempC: nil,
                         dewPointC: nil, humidityPct: nil, windKmh: nil, gustKmh: nil, visibilityM: nil, seeing: nil, transparency: nil)
    }
    let hours = [hour(20, 10), hour(21, 80)]
    func ev(_ h: Int, _ m: Int) -> SkyEvent {
        SkyEvent(id: "\(h)\(m)", kind: .issPass, title: "", detail: "", time: utc(2026, 9, 27, h, m), endTime: nil, raHours: nil, decDeg: nil)
    }
    let marked = Events.markClear([ev(20, 30), ev(21, 5), ev(23, 0)], hours: hours, maxCloudPct: 25)
    #expect(marked.map(\.clear) == [true, false, nil])
}

@Test func eventTipsFitTheKindOfEvent() throws {
    func e(_ k: SkyEventKind, fits: Bool? = nil) -> SkyEvent {
        var x = SkyEvent(id: "x", kind: k, title: "", detail: "", time: utc(2026, 9, 27, 20, 10), endTime: nil, raHours: nil, decDeg: nil)
        x.fits = fits
        return x
    }
    func labels(_ x: SkyEvent) -> [String] { ShootingTips.tip(for: x, fov: dwarfMini, presetName: nil, site: site).rows.map(\.label) }
    #expect(labels(e(.meteorShower)) == ["Kit", "Aim", "Exposure"])
    #expect(labels(e(.issPass)) == ["Kit", "Timing"])
    #expect(labels(e(.solarEclipse)) == ["Safety"])
    let near = ShootingTips.tip(for: e(.conjunction, fits: true), fov: dwarfMini, presetName: nil, site: site).rows[0].text
    let far = ShootingTips.tip(for: e(.conjunction, fits: false), fov: dwarfMini, presetName: nil, site: site).rows[0].text
    #expect(near.hasPrefix("Both fit") && far.hasPrefix("Wider than"))
    // Camera work does not name the telescope; telescope work does.
    #expect(ShootingTips.tip(for: e(.meteorShower), fov: dwarfMini, presetName: "DwarfLab DWARF Mini", site: site).title == "How to shoot this")
    #expect(ShootingTips.tip(for: e(.comet), fov: dwarfMini, presetName: "DwarfLab DWARF Mini", site: site).title == "How to shoot this with your DwarfLab DWARF Mini")
}

/// Events saved before 1.0.1 lack the new fields and must still load.
@Test func anEventWithoutTheNewFieldsDecodes() throws {
    var x = SkyEvent(id: "x", kind: .comet, title: "C/1", detail: "d", time: utc(2026, 9, 27, 20, 0), endTime: nil, raHours: 1, decDeg: 2)
    x.best = x.time; x.facts = [EventFact("a", "b")]; x.clear = true; x.separationDeg = 1; x.fits = true
    x.atPeak = true; x.radiantConstellation = "Tau"; x.path = [SkyPathPoint(label: "Rises", time: x.time, azimuthDeg: 270, altitudeDeg: 0)]
    var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(x)) as! [String: Any]
    for k in ["best", "facts", "clear", "separationDeg", "fits", "atPeak", "radiantConstellation", "path", "brief"] { json.removeValue(forKey: k) }
    let old = try JSONDecoder().decode(SkyEvent.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(old.facts.isEmpty && old.best == nil && old.title == "C/1" && !old.atPeak && old.path.isEmpty)
    #expect(try JSONDecoder().decode(SkyEvent.self, from: JSONEncoder().encode(x)) == x)
}

@Test func showersCarryTheirPeakFlagAndRadiantForTheArtwork() throws {
    let showers = try MeteorShowers.bundled()
    let peak = try #require(Events.showers(night: try Ephemeris.night(localDate: utc(2026, 12, 13, 12, 0), site: site), site: site, showers: showers)
        .first { $0.id == "shower-gem" })
    #expect(peak.atPeak && peak.radiantConstellation == "Gem")
    let early = try #require(Events.showers(night: try Ephemeris.night(localDate: utc(2026, 12, 10, 12, 0), site: site), site: site, showers: showers)
        .first { $0.id == "shower-gem" })
    #expect(!early.atPeak)
    let after = try #require(Events.showers(night: try Ephemeris.night(localDate: utc(2026, 12, 15, 12, 0), site: site), site: site, showers: showers)
        .first { $0.id == "shower-gem" })
    #expect(!after.atPeak)                                              // the night after the peak date
}

/// Every shower's radiant has constellation artwork, so its event page never falls back for want of a picture.
@Test func everyRadiantHasConstellationArtwork() throws {
    let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../Resources/Constellations").standardized
    for s in try MeteorShowers.bundled() {
        let sym = Ephemeris.constellation(raHours: s.raHours, decDeg: s.decDeg).symbol
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("\(sym)-figure.heic").path), "\(s.name): \(sym)")
    }
}

/// The compass drawing's projection: north up, east to the LEFT, the zenith at the centre, the horizon on the rim.
@Test func theSkyChartProjection() {
    func o(_ az: Double, _ alt: Double) -> (Double, Double) {
        let v = SkyPathPoint(label: "", time: .now, azimuthDeg: az, altitudeDeg: alt).chartOffset(radius: 100); return (v.dx, v.dy)
    }
    func near(_ a: (Double, Double), _ b: (Double, Double)) -> Bool { abs(a.0 - b.0) < 1e-9 && abs(a.1 - b.1) < 1e-9 }
    #expect(near(o(0, 0), (0, -100)))      // north, top
    #expect(near(o(90, 0), (-100, 0)))     // east, left
    #expect(near(o(180, 0), (0, 100)))     // south, bottom
    #expect(near(o(270, 45), (50, 0)))     // west, half way in at 45° up
    #expect(near(o(123, 90), (0, 0)))      // zenith
    #expect(near(o(0, -10), (0, -100)))    // below the horizon clamps to the rim
}

@Test func eventsSortByTimeOrClearSkyFirst() {
    func ev(_ id: String, _ h: Int, _ clear: Bool?) -> SkyEvent {
        var e = SkyEvent(id: id, kind: .issPass, title: id, detail: "", time: utc(2026, 9, 27, h, 0), endTime: nil, raHours: nil, decDeg: nil)
        e.clear = clear
        return e
    }
    let es = [ev("a", 23, false), ev("b", 21, nil), ev("c", 22, true), ev("d", 20, false)]
    #expect(Events.sorted(es, by: .time).map(\.id) == ["d", "b", "c", "a"])
    #expect(Events.sorted(es, by: .clearFirst).map(\.id) == ["c", "b", "d", "a"])   // clear, unknown, then cloudy, each by time
}

@Test func anEventCardsTimelineTracksItsSkyPosition() throws {
    let night = try Ephemeris.night(localDate: utc(2026, 9, 27, 12, 0), site: site)
    let w = ClearWindow(start: try #require(night.darkStart), end: try #require(night.darkEnd))
    let t = Planner.skyTrack(id: "x", name: "Southern Taurids", raHours: 3.5, decDeg: 15, window: w, site: site, minAlt: 0)
    #expect(t.altitudeSamples.count == 9 && t.viewable != nil)
    #expect(t.peakAltDeg > 45 && t.peakAltDeg < 53)                     // culminates at about 51.6° from 53.4° N
}

@Test func aShowerAheadOfItsPeakGoesInTheCalendarOnItsPeakNight() throws {
    let night = try Ephemeris.night(localDate: utc(2026, 10, 1, 12, 0), site: site)
    let sta = try #require(Events.showers(night: night, site: site, showers: try MeteorShowers.bundled()).first { $0.id == "shower-sta" })
    let span = try #require(sta.calendarSpan)
    let peakNight = try Ephemeris.night(localDate: utc(2026, 11, 4, 12, 0), site: site)
    #expect(span.title == "Southern Taurids peak")
    #expect(span.start == (peakNight.darkStart ?? peakNight.sunset) && span.end == (peakNight.darkEnd ?? peakNight.sunrise))
    #expect(span.notes.hasPrefix("Radiant in ") && span.notes.contains(", highest at ") && span.notes.contains("ZHR"))
    let ics = CalendarFile.ics(for: sta, site: site, now: night.sunset)
    #expect(ics.contains("SUMMARY:Southern Taurids peak\r\n"))
    #expect(ics.contains("DTSTART:\(CalendarFile.stamp(span.start))\r\n"))
    #expect(!ics.contains("in 3"))   // tonight's countdown stays out of the calendar
    let atPeak = try #require(Events.showers(night: peakNight, site: site, showers: try MeteorShowers.bundled()).first { $0.id == "shower-sta" })
    #expect(atPeak.calendarSpan == nil)   // at its peak, tonight is the night
}
