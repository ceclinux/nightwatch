import CAstronomyEngine
import Foundation

public struct Site: Codable, Equatable, Sendable {
    public var name: String
    public var latitude: Double
    public var longitude: Double
    public var elevationM: Double
    public var timeZoneID: String
    public var bortle: Int
    /// How high houses, trees or hills block the sky, in degrees, towards N, NE, E, SE, S, SW, W and NW (owner-approved
    /// mock-up, 1 October 2026). Nil: open sky. A height below the go rule's "Targets must reach" changes nothing (floorDeg). Optional, so a site
    /// saved before it existed still decodes.
    public var horizon: [Double]? = nil
    /// The hills' height in the same eight directions, from terrain data (#108), shown on the horizon dial; it raises the
    /// horizon only when the person chooses to. Nil until checked; cleared when the site moves.
    public var terrain: [Double]? = nil

    public static let horizonDirections = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

    public init(name: String, latitude: Double, longitude: Double, elevationM: Double, timeZoneID: String, bortle: Int) {
        self.name = name; self.latitude = latitude; self.longitude = longitude
        self.elevationM = elevationM; self.timeZoneID = timeZoneID; self.bortle = bortle
    }

    public var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .current }

    public var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        return c
    }

    /// The horizon's height towards `azimuthDeg` (0 north, 90 east), or nil when the site has none.
    public func horizonDeg(azimuthDeg az: Double) -> Double? {
        guard let h = horizon, h.count == 8 else { return nil }
        let a = (az.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        return h[Int((a + 22.5) / 45) % 8]
    }

    /// The height a target must clear towards `azimuthDeg`: its own floor (the go rule's "Targets must reach", which stands
    /// for the atmosphere, or the Moon's or a constellation's lower one), raised wherever the horizon is higher. The horizon
    /// only says what is in the way, so it never lowers the floor (owner, 1 October 2026: below about 20° there is three
    /// times the air or more, whatever is in the way).
    public func floorDeg(azimuthDeg az: Double, minAlt: Double) -> Double {
        max(minAlt, horizonDeg(azimuthDeg: az) ?? minAlt)
    }

    var observer: astro_observer_t { Astronomy_MakeObserver(latitude, longitude, elevationM) }
}

/// Plain names for the Bortle scale (v0.6.5), so a sky's darkness is chosen by what it looks like, not a bare number.
public enum Bortle {
    public static func name(_ level: Int) -> String {
        switch level {
        case ...1: L10n.text("Pristine")
        case 2: L10n.text("Truly dark")
        case 3: L10n.text("Rural")
        case 4: L10n.text("Rural and suburban edge")
        case 5: L10n.text("Suburban")
        case 6: L10n.text("Bright suburban")
        case 7: L10n.text("Suburban and urban edge")
        case 8: L10n.text("City")
        default: L10n.text("Inner city")
        }
    }
}
