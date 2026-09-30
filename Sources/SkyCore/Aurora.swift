import Foundation

/// AuroraWatch UK alert levels, lowest first.
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

public struct AuroraStatus: Codable, Equatable, Sendable {
    public var level: AuroraLevel
    public var updated: Date
    public init(level: AuroraLevel, updated: Date) { self.level = level; self.updated = updated }
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
    /// and AuroraWatch UK published the status within the last hour.
    public static func decide(status: AuroraStatus, now: Date, site: Site, nightKey: String, hours: [HourlyConditions], rule: GoRule,
                              settings: AuroraSettings, alerts: AlertSettings, state: AuroraAlertState?, copy: Copy) -> (notification: AlertNotification?, state: AuroraAlertState) {
        let s = (state?.nightKey == nightKey) ? state! : AuroraAlertState(nightKey: nightKey, lastLevel: nil)
        guard settings.shows(status),
              AuroraSettings.isFresh(status, now: now),   // a status cached from an earlier night must never fire

              Ephemeris.sunAltitude(at: now, site: site) <= sunBelowDeg,
              let hour = hours.first(where: { $0.time <= now && now < $0.time.addingTimeInterval(3600) }), hour.effectiveCloud <= rule.maxCloudPct,
              !AlertEngine.inQuietHours(now, site: site, settings: alerts),
              s.lastLevel.map({ status.level > $0 }) ?? true
        else { return (nil, s) }
        let note = AlertNotification(kind: .aurora, title: "Aurora alert: \(status.level.rawValue) · clear at \(site.name) now",
                                     body: "AuroraWatch UK reports \(status.level.rawValue). Cloud \(hour.cloudTotal)% this hour.")
        return (note, AuroraAlertState(nightKey: nightKey, lastLevel: status.level))
    }
}

extension AuroraSettings {
    /// The one rule for showing aurora anywhere (popover, widget, alerts): alerts on and the level at or above the chosen one.
    public func shows(_ status: AuroraStatus) -> Bool { enabled && status.level >= threshold }
    /// A status is news for an hour after AuroraWatch UK publishes it; after that it may be from an earlier night.
    public static let freshFor: TimeInterval = 3600
    public static func isFresh(_ status: AuroraStatus, now: Date) -> Bool { now.timeIntervalSince(status.updated) < freshFor }
    /// How often the app rewrites the widget while it shows aurora: well inside `freshFor`, so a live aurora never lapses.
    public static let widgetRefresh: TimeInterval = 30 * 60
}
