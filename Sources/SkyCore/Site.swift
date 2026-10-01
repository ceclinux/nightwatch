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
    /// mock-up, 1 October 2026). Nil: open sky, the go rule's "Targets must reach" height all round. Optional, so a site
    /// saved before it existed still decodes.
    public var horizon: [Double]? = nil

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

    /// The height a target must clear towards `azimuthDeg`. One held to the go rule (`replacesFloor`) takes the horizon
    /// in its place, lower or higher; one with its own lower floor (the Moon, a constellation's centre, an event) is only
    /// raised by it.
    public func floorDeg(azimuthDeg az: Double, minAlt: Double, replacesFloor: Bool) -> Double {
        guard let h = horizonDeg(azimuthDeg: az) else { return minAlt }
        return replacesFloor ? h : max(minAlt, h)
    }

    var observer: astro_observer_t { Astronomy_MakeObserver(latitude, longitude, elevationM) }
}

/// Plain names for the Bortle scale (v0.6.5), so a sky's darkness is chosen by what it looks like, not a bare number.
public enum Bortle {
    public static func name(_ level: Int) -> String {
        switch level {
        case ...1: "Pristine"
        case 2: "Truly dark"
        case 3: "Rural"
        case 4: "Rural and suburban edge"
        case 5: "Suburban"
        case 6: "Bright suburban"
        case 7: "Suburban and urban edge"
        case 8: "City"
        default: "Inner city"
        }
    }
}
