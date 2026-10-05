import Foundation

/// Aurora alert levels, lowest first: AuroraWatch UK's own, which NOAA's figure is also mapped onto (`Ovation.level`).
public enum AuroraLevel: String, Codable, Sendable, Comparable, CaseIterable {
    case green, yellow, amber, red
    public static func < (a: AuroraLevel, b: AuroraLevel) -> Bool { allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)! }
    public var displayName: String { rawValue.capitalized }
    /// AuroraWatch UK's own colour for the level, as its status-descriptions list publishes it. The owner chose these
    /// over the night palette (25 September 2026), so the aurora line is the one place Nightwatch shows green or pure red.
    public var hex: UInt32 {
        switch self { case .green: 0x33FF33; case .yellow: 0xFFFF00; case .amber: 0xFF9900; case .red: 0xFF0000 }
    }
}

/// Where an aurora status comes from (1.4). AuroraWatch UK measures what can be seen from Britain, so sites in the UK and
/// Ireland keep it; everywhere else reads NOAA's worldwide forecast.
public enum AuroraSource: String, Codable, Sendable {
    case auroraWatchUK, noaa
    public var name: String { self == .noaa ? "NOAA" : "AuroraWatch UK" }
    /// The source's own page, which the aurora line links to (AuroraWatch UK's terms ask for the link).
    public var link: URL { self == .noaa ? Ovation.page : URL(string: "https://aurorawatch.lancs.ac.uk/")! }
    /// The least time between two fetches. AuroraWatch UK's terms ask for 3 minutes or more; NOAA's file is 920 KB and
    /// looks 30 minutes or more ahead, so a quarter of an hour is often enough.
    public var minFetchGap: TimeInterval { self == .noaa ? 15 * 60 : 180 }
    /// The UK and Ireland, with Shetland and the Channel Islands. A box, so a sliver of northern France is inside it too.
    public static func `for`(_ site: Site) -> AuroraSource {
        (49.0...61.5).contains(site.latitude) && (-11.0...2.0).contains(site.longitude) ? .auroraWatchUK : .noaa
    }
}

public struct AuroraStatus: Codable, Equatable, Sendable {
    public var level: AuroraLevel
    public var updated: Date
    public var source: AuroraSource
    /// NOAA's figure at the site's grid point, 0 to 100; nil for AuroraWatch UK.
    public var percent: Int?
    /// The grid point a NOAA status was read at, as `Ovation.cell` gives it; nil for AuroraWatch UK, whose one status
    /// serves everywhere it covers.
    public var cell: [Int]?
    public init(level: AuroraLevel, updated: Date, source: AuroraSource = .auroraWatchUK, percent: Int? = nil, cell: [Int]? = nil) {
        self.level = level; self.updated = updated; self.source = source; self.percent = percent; self.cell = cell
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        level = try c.decode(AuroraLevel.self, forKey: .level)
        updated = try c.decode(Date.self, forKey: .updated)
        source = try c.decodeIfPresent(AuroraSource.self, forKey: .source) ?? .auroraWatchUK   // a status cached by 1.3
        percent = try c.decodeIfPresent(Int.self, forKey: .percent)
        cell = try c.decodeIfPresent([Int].self, forKey: .cell)
    }
    /// Whether this status says anything about `site`: its source is the site's, and a NOAA figure was read at the
    /// site's own grid point. A status kept from another site, or from the UK while abroad, must never show or alert.
    public func applies(to site: Site) -> Bool {
        source == AuroraSource.for(site) && (source == .auroraWatchUK || cell == Ovation.cell(site))
    }
    /// The popover's line: "Aurora: amber (AuroraWatch UK) ↗" or "Aurora: amber, 35% (NOAA forecast) ↗".
    public var line: String {
        source == .noaa ? "Aurora: \(level.rawValue), \(percent ?? 0)% (NOAA forecast) ↗" : "Aurora: \(level.rawValue) (AuroraWatch UK) ↗"
    }
}

public enum AuroraError: Error { case malformed }

/// AuroraWatch UK (Lancaster University) current status, API 0.2. Free, no key; non-commercial use with attribution,
/// and each client polls no more often than every 3 minutes.
public enum AuroraWatch {
    public static let url = URL(string: "https://aurorawatch-api.lancs.ac.uk/0.2/status/current-status.xml")!

    public static func parse(_ data: Data) throws -> AuroraStatus {
        let d = Delegate()
        let p = XMLParser(data: data)
        p.delegate = d
        guard p.parse(), let raw = d.statusID, let level = AuroraLevel(rawValue: raw), let text = d.datetime else { throw AuroraError.malformed }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        guard let updated = f.date(from: text.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw AuroraError.malformed }
        return AuroraStatus(level: level, updated: updated)
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var statusID: String?
        var datetime: String?
        private var inDatetime = false
        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            if name == "site_status" { statusID = attributes["status_id"] }
            if name == "datetime" { inDatetime = true; datetime = "" }
        }
        func parser(_ parser: XMLParser, foundCharacters string: String) { if inDatetime { datetime? += string } }
        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) { if name == "datetime" { inDatetime = false } }
    }
}

/// NOAA Space Weather Prediction Center's 30 to 90 minute aurora forecast (the OVATION model): one figure from 0 to 100
/// for every whole degree of the globe, both hemispheres, republished about every five minutes. Free, no key; National
/// Weather Service information is in the public domain. The whole world comes down, so nothing about the site is sent.
public enum Ovation {
    public static let url = URL(string: "https://services.swpc.noaa.gov/json/ovation_aurora_latest.json")!
    public static let page = URL(string: "https://www.spaceweather.gov/products/aurora-30-minute-forecast")!
    /// Nightwatch's own bands for NOAA's figure, so the one "Alert from" setting serves both sources (owner, 5 October
    /// 2026: start here and tune). They are not NOAA's, nor calibrated against AuroraWatch UK's levels.
    public static let yellowFrom = 10, amberFrom = 30, redFrom = 60
    public static func level(_ percent: Int) -> AuroraLevel {
        percent >= redFrom ? .red : percent >= amberFrom ? .amber : percent >= yellowFrom ? .yellow : .green
    }
    /// The site's grid point, [longitude 0...359, latitude -90...90], in whole degrees as the file gives them.
    /// ponytail: the site's own point only. NOAA says aurora can be seen up to 1,000 km from where it is overhead, so this
    /// under-alerts at mid-latitudes; take the highest figure within that distance towards the pole if it proves too quiet.
    public static func cell(_ site: Site) -> [Int] {
        [((Int(site.longitude.rounded()) % 360) + 360) % 360, Int(site.latitude.rounded())]
    }

    public static func parse(_ data: Data, site: Site) throws -> AuroraStatus {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let points = root["coordinates"] as? [[Double]],
              let observed = (root["Observation Time"] as? String).flatMap({ ISO8601DateFormatter().date(from: $0) }) else { throw AuroraError.malformed }
        let c = cell(site), lon = Double(c[0]), lat = Double(c[1])
        func isCell(_ p: [Double]) -> Bool { p.count == 3 && p[0] == lon && p[1] == lat }
        // The file runs longitude 0 to 359, each with latitude -90 to 90; if it ever does not, find the point by its coordinates.
        let i = c[0] * 181 + c[1] + 90
        guard let p = points.indices.contains(i) && isCell(points[i]) ? points[i] : points.first(where: isCell) else { throw AuroraError.malformed }
        let percent = min(100, max(0, Int(p[2].rounded())))
        return AuroraStatus(level: level(percent), updated: observed, source: .noaa, percent: percent, cell: c)
    }
}

/// Which aurora level was last notified tonight, so each level fires once and a rise fires again.
public struct AuroraAlertState: Codable, Equatable, Sendable {
    public var nightKey: String
    public var lastLevel: AuroraLevel?
    public init(nightKey: String, lastLevel: AuroraLevel?) { self.nightKey = nightKey; self.lastLevel = lastLevel }
}

public enum AuroraAlert {
    /// The Sun must be this far down for an aurora to be worth looking for.
    public static let sunBelowDeg = -12.0

    /// A notification when the status is at or above the threshold, the Sun is at least 12 degrees down, the forecast
    /// hour containing `now` is under the cloud limit, quiet hours do not apply, this level has not fired tonight,
    /// the status is for this site, and its source published it within the last hour.
    public static func decide(status: AuroraStatus, now: Date, site: Site, nightKey: String, hours: [HourlyConditions], rule: GoRule,
                              settings: AuroraSettings, alerts: AlertSettings, state: AuroraAlertState?, copy: Copy) -> (notification: AlertNotification?, state: AuroraAlertState) {
        let s = (state?.nightKey == nightKey) ? state! : AuroraAlertState(nightKey: nightKey, lastLevel: nil)
        guard settings.shows(status),
              status.applies(to: site),                   // never the UK's status abroad, nor NOAA's figure for another place
              AuroraSettings.isFresh(status, now: now),   // a status cached from an earlier night must never fire

              Ephemeris.sunAltitude(at: now, site: site) <= sunBelowDeg,
              let hour = hours.first(where: { $0.time <= now && now < $0.time.addingTimeInterval(3600) }), hour.effectiveCloud <= rule.maxCloudPct,
              !AlertEngine.inQuietHours(now, site: site, settings: alerts),
              s.lastLevel.map({ status.level > $0 }) ?? true
        else { return (nil, s) }
        let said = status.source == .noaa ? "NOAA's aurora forecast for here is \(status.percent ?? 0)% (\(status.level.rawValue))."
                                          : "AuroraWatch UK reports \(status.level.rawValue)."
        let note = AlertNotification(kind: .aurora, title: "Aurora alert: \(status.level.rawValue) · clear at \(site.name) now",
                                     body: "\(said) Cloud \(hour.cloudTotal)% this hour.")
        return (note, AuroraAlertState(nightKey: nightKey, lastLevel: status.level))
    }
}

extension AuroraSettings {
    /// The one rule for showing aurora anywhere (popover, widget, alerts): alerts on and the level at or above the chosen one.
    public func shows(_ status: AuroraStatus) -> Bool { enabled && status.level >= threshold }
    /// A status is news for an hour after its source publishes it; after that it may be from an earlier night.
    public static let freshFor: TimeInterval = 3600
    public static func isFresh(_ status: AuroraStatus, now: Date) -> Bool { now.timeIntervalSince(status.updated) < freshFor }
    /// How often the app rewrites the widget while it shows aurora: well inside `freshFor`, so a live aurora never lapses.
    public static let widgetRefresh: TimeInterval = 30 * 60
}
