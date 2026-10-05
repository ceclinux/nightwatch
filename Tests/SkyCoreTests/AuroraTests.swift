import Testing
import Foundation
@testable import SkyCore

private let testSite = Site(name: "Test site", latitude: 54.0, longitude: -1.5, elevationM: 100, timeZoneID: "Europe/London", bortle: 5)
private let copy = Copy()

private func xml(_ level: String) -> Data {
    Data("""
    <?xml version='1.0' encoding='UTF-8' standalone='yes'?>
    <!DOCTYPE current_status PUBLIC "-//AuroraWatch-API//DTD REST 0.2.5//EN" "http://aurorawatch-api.lancs.ac.uk/0.2.5/aurorawatch-api.dtd">
    <current_status api_version="0.2.5"><updated><datetime>2026-09-24T20:33:32+0000</datetime></updated><site_status project_id="project:AWN" site_id="site:AWN:SUM" site_url="http://aurorawatch-api.lancs.ac.uk/0.2.5/project/awn/sum.xml" status_id="\(level)"/></current_status>
    """.utf8)
}

@Test func auroraWatchParsesEveryLevelAndTheTime() throws {
    for l in AuroraLevel.allCases {
        let s = try AuroraWatch.parse(xml(l.rawValue))
        #expect(s.level == l)
        #expect(s.updated == utc(2026, 9, 24, 20, 33).addingTimeInterval(32))
    }
    #expect(throws: (any Error).self) { try AuroraWatch.parse(Data("<current_status/>".utf8)) }
    #expect(AuroraLevel.green < .yellow && .yellow < .amber && .amber < .red)
}

private func hours(at t0: Date, cloud: Int) -> [HourlyConditions] {
    [HourlyConditions(time: t0, cloudTotal: cloud, cloudLow: nil, cloudMid: nil, cloudHigh: nil, tempC: nil, dewPointC: nil, humidityPct: nil,
                      windKmh: nil, gustKmh: nil, visibilityM: nil, seeing: nil, transparency: nil)]
}
private var on: AuroraSettings { var a = AuroraSettings(); a.enabled = true; return a }

@Test func auroraAlertRule() throws {
    let now = utc(2026, 9, 24, 22, 10)           // 23:10 BST: Sun far below -12 deg, outside default quiet hours
    let hr = hours(at: utc(2026, 9, 24, 22, 0), cloud: 10)
    func decide(_ level: AuroraLevel, at t: Date = now, hours h: [HourlyConditions]? = nil, settings: AuroraSettings? = nil, state: AuroraAlertState? = nil) -> (AlertNotification?, AuroraAlertState) {
        let r = AuroraAlert.decide(status: AuroraStatus(level: level, updated: t), now: t, site: testSite, nightKey: "2026-09-24", hours: h ?? hr,
                                   rule: GoRule(), settings: settings ?? on, alerts: AlertSettings(), state: state, copy: copy)
        return (r.notification, r.state)
    }
    #expect(decide(.amber, settings: AuroraSettings()).0 == nil)          // disabled
    #expect(decide(.yellow).0 == nil)                                     // below the amber threshold
    let (n, s) = decide(.amber)
    let note = try #require(n)
    #expect(note.kind == .aurora)
    #expect(note.title == "Aurora alert: amber · clear at Test site now")
    #expect(note.body == "AuroraWatch UK reports amber. Cloud 10% this hour.")
    #expect(decide(.amber, state: s).0 == nil)                            // once per level per night
    #expect(decide(.red, state: s).0?.title == "Aurora alert: red · clear at Test site now")   // a rise fires again
    #expect(decide(.amber, at: utc(2026, 9, 24, 13, 0), hours: hours(at: utc(2026, 9, 24, 13, 0), cloud: 10)).0 == nil)   // daylight
    #expect(decide(.amber, hours: hours(at: utc(2026, 9, 24, 22, 0), cloud: 80)).0 == nil)   // cloudy
    #expect(decide(.amber, hours: []).0 == nil)                           // no forecast for this hour
    #expect(decide(.amber, at: utc(2026, 9, 24, 23, 30), hours: hours(at: utc(2026, 9, 24, 23, 0), cloud: 10)).0 == nil)   // 00:30 BST, quiet hours
    let old = AuroraAlertState(nightKey: "2026-09-23", lastLevel: .red)
    #expect(decide(.amber, state: old).0 != nil)                          // a new night resets
}

@Test func auroraSettingsDecodeLeniently() throws {
    #expect(Config.default.aurora == AuroraSettings())
    #expect(!AuroraSettings().enabled && AuroraSettings().threshold == .amber)
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("config.json")
    try Data(#"{"aurora":{"enabled":true,"threshold":"purple"}}"#.utf8).write(to: url)
    let c = try ConfigStore.load(from: url)
    #expect(c.aurora.enabled && c.aurora.threshold == .amber)
    try Data(#"{"sites":[]}"#.utf8).write(to: url)
    #expect(try ConfigStore.load(from: url).aurora == AuroraSettings())
}

@Test func auroraStatusFromAnEarlierNightNeverAlerts() {
    let now = utc(2026, 9, 24, 22, 10)
    let stale = AuroraStatus(level: .red, updated: now.addingTimeInterval(-15 * 3600))   // cached at dawn, Mac woke offline
    let r = AuroraAlert.decide(status: stale, now: now, site: testSite, nightKey: "2026-09-24", hours: hours(at: utc(2026, 9, 24, 22, 0), cloud: 10),
                               rule: GoRule(), settings: on, alerts: AlertSettings(), state: nil, copy: copy)
    #expect(r.notification == nil)
}

@Test func auroraThresholdIsNeverBelowYellow() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("config.json")
    try Data(#"{"aurora":{"enabled":true,"threshold":"green"}}"#.utf8).write(to: url)
    #expect(try ConfigStore.load(from: url).aurora.threshold == .yellow)
}

/// AuroraWatch UK's own colours, from https://aurorawatch-api.lancs.ac.uk/0.2/status-descriptions.xml (owner ruling
/// 25 September 2026: the popover uses them as published).
@Test func auroraLevelsUseAuroraWatchColours() {
    #expect(AuroraLevel.allCases.map(\.hex) == [0x33FF33, 0xFFFF00, 0xFF9900, 0xFF0000])
}

@Test func oneRuleDecidesWhenAuroraShows() {
    var s = AuroraSettings(); s.enabled = true; s.threshold = .amber
    let t = Date(), amber = AuroraStatus(level: .amber, updated: t)
    #expect(s.shows(amber) && !s.shows(AuroraStatus(level: .yellow, updated: t)))
    s.enabled = false
    #expect(!s.shows(amber))
    #expect(AuroraSettings.isFresh(amber, now: t.addingTimeInterval(3599)) && !AuroraSettings.isFresh(amber, now: t.addingTimeInterval(3600)))
    // The widget is refreshed well inside the freshness window, so a live aurora never drops off it early.
    #expect(AuroraSettings.widgetRefresh < AuroraSettings.freshFor)
}

// MARK: Aurora outside the UK and Ireland (1.4): NOAA's 30-minute forecast

private func place(_ name: String, _ lat: Double, _ lon: Double) -> Site {
    Site(name: name, latitude: lat, longitude: lon, elevationM: 0, timeZoneID: "UTC", bortle: 3)
}
private let yorkshire = place("Yorkshire", 54.0, -1.5), tromso = place("Tromsø", 69.65, 18.96), fairbanks = place("Fairbanks", 64.84, -147.72)

/// NOAA's file as it is published: every whole degree, longitude 0 to 359 then latitude -90 to 90, [longitude, latitude, value].
private func ovation(_ values: [String: Int] = [:], observed: String = "2026-10-05T08:48:00Z", whole: Bool = true) -> Data {
    var rows: [String] = []
    if whole {
        for lon in 0..<360 { for lat in -90...90 { rows.append("[\(lon), \(lat), \(values["\(lon),\(lat)"] ?? 0)]") } }
    } else {
        rows = values.map { "[\($0.key.replacingOccurrences(of: ",", with: ", ")), \($0.value)]" }
    }
    return Data(#"{"Observation Time": "\#(observed)", "Forecast Time": "2026-10-05T09:38:00Z", "Data Format": "[Longitude, Latitude, Aurora]", "coordinates": [\#(rows.joined(separator: ", "))], "type": "MultiPoint"}"#.utf8)
}

@Test func theSourceFollowsTheSite() {
    // AuroraWatch UK measures what is visible from Britain, so the UK and Ireland keep it; everywhere else is NOAA's.
    for s in [yorkshire, place("Shetland", 60.4, -1.2), place("Dublin", 53.35, -6.26), place("Dingle", 52.14, -10.27), place("Jersey", 49.2, -2.1)] {
        #expect(AuroraSource.for(s) == .auroraWatchUK, "\(s.name)")
    }
    for s in [tromso, fairbanks, place("Reykjavik", 64.15, -21.94), place("Madrid", 40.4, -3.7), place("Tenerife", 28.3, -16.6), place("Hobart", -42.9, 147.3), place("Tórshavn", 62.0, -6.8)] {
        #expect(AuroraSource.for(s) == .noaa, "\(s.name)")
    }
}

@Test func noaaForecastIsReadAtTheSitesGridPoint() throws {
    // Tromsø is the cell at 19° E, 70° N; Fairbanks, west of Greenwich, is 212° E (360 − 148), 65° N.
    let data = ovation(["19,70": 35, "212,65": 72, "18,70": 99, "19,69": 99])
    let t = try Ovation.parse(data, site: tromso)
    #expect(t.source == .noaa && t.percent == 35 && t.level == .amber)
    #expect(t.updated == utc(2026, 10, 5, 8, 48))                      // the observation time: the status is news for an hour after it
    let f = try Ovation.parse(data, site: fairbanks)
    #expect(f.percent == 72 && f.level == .red)
    #expect(try Ovation.parse(data, site: place("Hobart", -42.9, 147.3)).level == .green)
    // A file that is not the whole grid, or is in another order, is still read by its coordinates.
    #expect(try Ovation.parse(ovation(["212,65": 12, "19,70": 5], whole: false), site: fairbanks).percent == 12)
    #expect(throws: (any Error).self) { try Ovation.parse(ovation(["0,0": 1], whole: false), site: tromso) }   // the site's cell is missing
    #expect(throws: (any Error).self) { try Ovation.parse(Data("{}".utf8), site: tromso) }
    #expect(throws: (any Error).self) { try Ovation.parse(ovation(observed: "yesterday"), site: tromso) }
}

@Test func noaaPercentMapsOntoTheThreeLevels() {
    // Nightwatch's own bands (owner, 5 October 2026: start at 10, 30 and 60, to be tuned), not NOAA's.
    #expect([0, 9].map(Ovation.level) == [.green, .green])
    #expect([10, 29].map(Ovation.level) == [.yellow, .yellow])
    #expect([30, 59].map(Ovation.level) == [.amber, .amber])
    #expect([60, 100].map(Ovation.level) == [.red, .red])
}

@Test func aStatusOnlyAppliesWhereItWasReadFor() throws {
    let uk = AuroraStatus(level: .amber, updated: Date())
    #expect(uk.source == .auroraWatchUK && uk.applies(to: yorkshire) && !uk.applies(to: tromso))   // a UK status never alerts abroad
    let t = try Ovation.parse(ovation(["19,70": 35]), site: tromso)
    #expect(t.applies(to: tromso) && !t.applies(to: fairbanks) && !t.applies(to: yorkshire))
    #expect(t.applies(to: place("Near Tromsø", 69.9, 19.3)))           // the same grid point
    // A status cached by 1.3 has no source: it is AuroraWatch UK's.
    let old = try JSONDecoder().decode(AuroraStatus.self, from: Data(#"{"level":"amber","updated":0}"#.utf8))
    #expect(old.source == .auroraWatchUK && old.percent == nil)
    #expect(try JSONDecoder().decode(AuroraStatus.self, from: JSONEncoder().encode(t)) == t)
}

@Test func theWordingNamesTheSource() throws {
    let now = utc(2026, 10, 5, 22, 10)                                // dark at Tromsø and in Yorkshire, outside quiet hours (UTC)
    let hr = hours(at: utc(2026, 10, 5, 22, 0), cloud: 10)
    func note(_ status: AuroraStatus, at site: Site) -> AlertNotification? {
        AuroraAlert.decide(status: status, now: now, site: site, nightKey: "2026-10-05", hours: hr, rule: GoRule(), settings: on,
                           alerts: AlertSettings(), state: nil, copy: copy).notification
    }
    var noaa = try Ovation.parse(ovation(["19,70": 35]), site: tromso)
    noaa.updated = now
    let n = try #require(note(noaa, at: tromso))
    #expect(n.title == "Aurora alert: amber · clear at Tromsø now")
    #expect(n.body == "NOAA's aurora forecast for here is 35% (amber). Cloud 10% this hour.")
    #expect(noaa.line == "Aurora: amber, 35% (NOAA forecast) ↗" && noaa.source.name == "NOAA")
    let uk = AuroraStatus(level: .amber, updated: now)
    #expect(uk.line == "Aurora: amber (AuroraWatch UK) ↗")
    #expect(note(uk, at: place("Yorkshire", 54.0, -1.5))?.body == "AuroraWatch UK reports amber. Cloud 10% this hour.")
    // The fault this closes: a UK status must not alert at a site abroad, nor NOAA's for another place.
    #expect(note(uk, at: tromso) == nil)
    #expect(note(noaa, at: fairbanks) == nil)
}

@Test func noaaIsAskedLessOftenThanAuroraWatch() {
    #expect(AuroraSource.auroraWatchUK.minFetchGap == 180)             // their terms: no more often than every 3 minutes
    #expect(AuroraSource.noaa.minFetchGap == 15 * 60)                  // a 920 KB file that looks 30 minutes or more ahead
    #expect(AuroraSource.noaa.minFetchGap < AuroraSettings.freshFor)   // so a live forecast never lapses between fetches
}
