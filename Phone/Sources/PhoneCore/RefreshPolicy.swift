import Foundation
import SkyCore

/// What the connection allows, as the system reports it (NWPath): online or not, and whether the path is expensive
/// (cellular, or a Personal Hotspot) or constrained (Low Data Mode).
public struct Connectivity: Equatable, Sendable {
    public var isOnline: Bool
    public var isExpensive: Bool
    public var isConstrained: Bool

    public init(isOnline: Bool = true, isExpensive: Bool = false, isConstrained: Bool = false) {
        self.isOnline = isOnline; self.isExpensive = isExpensive; self.isConstrained = isConstrained
    }

    public static let offline = Connectivity(isOnline: false)

    /// Anything bigger than a forecast (sky-survey thumbnails, a forecast for each dark site) waits for a cheap connection.
    public var allowsOptionalDownloads: Bool { isOnline && !isExpensive && !isConstrained }

    /// What iOS says about one network path.
    public struct Path: Equatable, Sendable {
        public var isOnline: Bool, isExpensive: Bool, isConstrained: Bool
        public init(isOnline: Bool, isExpensive: Bool, isConstrained: Bool) { self.isOnline = isOnline; self.isExpensive = isExpensive; self.isConstrained = isConstrained }
    }

    /// The default path says "expensive" whenever cellular is merely available beside Wi-Fi (seen on the owner's iPhone: Wi-Fi and cellular
    /// both listed, expensive true, while on Wi-Fi). So when Wi-Fi is usable, judge by the Wi-Fi link alone: a hotspot or a Low Data Mode
    /// network still reports itself expensive or constrained there. Without Wi-Fi, the default path decides.
    public static func resolve(defaultPath: Path, wifi: Path?) -> Connectivity {
        if let w = wifi, w.isOnline { return Connectivity(isOnline: true, isExpensive: w.isExpensive, isConstrained: w.isConstrained || defaultPath.isConstrained) }
        return Connectivity(isOnline: defaultPath.isOnline, isExpensive: defaultPath.isExpensive, isConstrained: defaultPath.isConstrained)
    }
}

public enum RefreshDecision: Equatable, Sendable {
    /// Ask the forecast services.
    case fetch
    /// The saved forecast is fresh enough, or the connection says to spare data: draw from it.
    case useSaved
    /// No connection: draw from the saved forecast, if there is one, and say how old it is.
    case offline
}

/// When to fetch. The core forecast is a few kilobytes, so the rule is the Mac's (thirty minutes, five when Apple Weather
/// had answered and this forecast fell back to Open-Meteo) and Low Data Mode only stretches the wait.
public enum RefreshPolicy {
    /// Under Low Data Mode a forecast is left alone this long unless the person asks for a refresh.
    public static let constrainedMaxAge: TimeInterval = 2 * 3600

    public static func decision(now: Date, forecast: Forecast?, site: Site, pause: PrimaryPause, force: Bool,
                                connectivity: Connectivity) -> RefreshDecision {
        guard connectivity.isOnline else { return .offline }
        guard let forecast, ForecastStore.matches(forecast, site: site) else { return .fetch }
        if force { return .fetch }
        var maxAge = pause.maxAge(fromPrimary: forecast.cloudSource == "Apple Weather")
        if connectivity.isConstrained { maxAge = max(maxAge, constrainedMaxAge) }
        return now.timeIntervalSince(forecast.fetchedAt) > maxAge ? .fetch : .useSaved
    }
}
