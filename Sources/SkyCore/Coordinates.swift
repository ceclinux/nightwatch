import Foundation

/// Coordinates typed or pasted into "Add a site…" (location entry check, 30 September 2026): decimal degrees with an
/// optional degree sign and N, S, E or W, and a latitude and longitude pasted together as one pair, as maps copy them.
public enum Coordinates {
    /// One value in degrees: "53.381", "−1.470", "53.381° N", "1.470 W". A hemisphere letter sets the sign; the wrong
    /// letter for the axis (E on a latitude) is refused.
    public static func degrees(_ text: String, latitude: Bool) -> Double? {
        var s = text.trimmingCharacters(in: .whitespaces).uppercased()
            .replacingOccurrences(of: "−", with: "-").replacingOccurrences(of: "°", with: "")
        var sign = 1.0
        if let last = s.last, "NSEW".contains(last) {
            guard latitude ? "NS".contains(last) : "EW".contains(last) else { return nil }
            if last == "S" || last == "W" { sign = -1 }
            s.removeLast()
        }
        guard let v = Double(s.trimmingCharacters(in: .whitespaces)) else { return nil }
        let d = v * sign
        return abs(d) <= (latitude ? 90 : 180) ? d : nil
    }

    /// A pasted pair: "53.381, -1.470" or "53.381° N, 1.470° W". Nil when the text is not two valid values.
    public static func pair(_ text: String) -> (latitude: Double, longitude: Double)? {
        let parts = text.split(separator: ",").map(String.init)
        guard parts.count == 2, let lat = degrees(parts[0], latitude: true), let lon = degrees(parts[1], latitude: false) else { return nil }
        return (lat, lon)
    }
}
