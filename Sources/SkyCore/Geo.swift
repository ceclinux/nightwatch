import Foundation

public struct Coordinate: Codable, Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public init(latitude: Double, longitude: Double) { self.latitude = latitude; self.longitude = longitude }
}

public enum DistanceUnit: String, Codable, Sendable {
    case km, mi
    public var displayName: String { self == .km ? L10n.text("Kilometres") : L10n.text("Miles") }
}

public enum Geo {
    public static let earthRadiusKm = 6371.0088
    private static let d2r = Double.pi / 180

    public static func distanceKm(_ a: Coordinate, _ b: Coordinate) -> Double {
        let p1 = a.latitude * d2r, p2 = b.latitude * d2r
        let dp = (b.latitude - a.latitude) * d2r, dl = (b.longitude - a.longitude) * d2r
        let h = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return 2 * earthRadiusKm * asin(min(1, sqrt(h)))
    }

    /// Initial bearing, degrees clockwise from north, 0 ..< 360.
    public static func bearingDeg(from a: Coordinate, to b: Coordinate) -> Double {
        let p1 = a.latitude * d2r, p2 = b.latitude * d2r, dl = (b.longitude - a.longitude) * d2r
        let y = sin(dl) * cos(p2)
        let x = cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dl)
        let deg = atan2(y, x) / d2r
        return (deg + 360).truncatingRemainder(dividingBy: 360)
    }

    public static func compass(_ deg: Double) -> String {
        let points = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let i = Int((deg / 22.5).rounded()) % 16
        return points[i]
    }

    public static func destination(from a: Coordinate, bearingDeg: Double, distanceKm: Double) -> Coordinate {
        let δ = distanceKm / earthRadiusKm, θ = bearingDeg * d2r
        let p1 = a.latitude * d2r, l1 = a.longitude * d2r
        let p2 = asin(sin(p1) * cos(δ) + cos(p1) * sin(δ) * cos(θ))
        let l2 = l1 + atan2(sin(θ) * sin(δ) * cos(p1), cos(δ) - sin(p1) * sin(p2))
        return Coordinate(latitude: p2 / d2r, longitude: ((l2 / d2r + 540).truncatingRemainder(dividingBy: 360)) - 180)
    }

    public static func format(km: Double, unit: DistanceUnit) -> String {
        let v = unit == .km ? km : km * 0.621371
        let s = v < 1 ? String(format: "%.1f", v) : String(format: "%.0f", v)
        return "\(s) \(unit.rawValue)"
    }
}
