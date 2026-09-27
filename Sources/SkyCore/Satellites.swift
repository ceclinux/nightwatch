import CAstronomyEngine
import Foundation
import SatelliteKit

public struct TLE: Codable, Equatable, Sendable {
    public let line0: String
    public let line1: String
    public let line2: String
    public init(line0: String, line1: String, line2: String) { self.line0 = line0; self.line1 = line1; self.line2 = line2 }
}

public struct SatellitePass: Codable, Equatable, Sendable {
    public let rise: Date
    public let peak: Date
    public let set: Date
    public let maxElevationDeg: Double
    public let peakAzimuthDeg: Double
    /// Where it rises and sets, degrees from north (v1.0.1).
    public var riseAzimuthDeg: Double? = nil
    public var setAzimuthDeg: Double? = nil
    /// When it can actually be seen: above the horizon and sunlit. A pass often starts or ends in Earth's shadow, so these
    /// can fall inside rise…set; set by `visiblePasses` only.
    public var appears: Date? = nil
    public var appearsAzimuthDeg: Double? = nil
    public var vanishes: Date? = nil
    public var vanishesAzimuthDeg: Double? = nil
    public var appearsElevationDeg: Double? = nil
    public var vanishesElevationDeg: Double? = nil
}

public enum SatelliteError: Error { case malformedTLE }

public enum Satellites {
    public static let issURL = URL(string: "https://celestrak.org/NORAD/elements/gp.php?CATNR=25544&FORMAT=TLE")!

    public static func parseTLE(_ text: String) throws -> TLE {
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard lines.count >= 3, lines[1].hasPrefix("1 "), lines[2].hasPrefix("2 ") else { throw SatelliteError.malformedTLE }
        return TLE(line0: lines[0], line1: lines[1], line2: lines[2])
    }

    /// Passes above the horizon between `from` and `to`, peak elevation at least `minPeakElevation` degrees.
    public static func passes(tle: TLE, site: Site, from: Date, to: Date, minPeakElevation: Double = 30, stepSeconds: TimeInterval = 30) throws -> [SatellitePass] {
        let sat = Satellite(withTLE: try Elements(tle.line0, tle.line1, tle.line2))
        let observer = LatLonAlt(site.latitude, site.longitude, site.elevationM / 1000)
        var out: [SatellitePass] = []
        var t = from
        var rise: Date? = nil
        var peakEl = -90.0, peakAz = 0.0, peakT = from, riseAz = 0.0, lastAz = 0.0
        while t <= to {
            let top = try sat.topPosition(julianDays: t.julianDate, observer: observer)
            if top.elev > 0 {
                if rise == nil { rise = t; peakEl = -90; riseAz = top.azim }
                if top.elev > peakEl { peakEl = top.elev; peakAz = top.azim; peakT = t }
                lastAz = top.azim
            } else if let r = rise {
                if peakEl >= minPeakElevation {
                    out.append(SatellitePass(rise: r, peak: peakT, set: t, maxElevationDeg: peakEl, peakAzimuthDeg: peakAz,
                                             riseAzimuthDeg: riseAz, setAzimuthDeg: lastAz))
                }
                rise = nil
            }
            t = t.addingTimeInterval(stepSeconds)
        }
        return out
    }

    /// True when the satellite at `date` is outside Earth's cylindrical shadow.
    static func isSunlit(_ sat: Satellite, at date: Date) throws -> Bool {
        let p = try sat.position(julianDays: date.julianDate)          // km, ECI (TEME; precession vs EQJ ignored)
        let sun = Astronomy_GeoVector(BODY_SUN, astro_time_t(date), NO_ABERRATION)
        guard sun.status == ASTRO_SUCCESS else { return true }
        let n = sqrt(sun.x * sun.x + sun.y * sun.y + sun.z * sun.z)
        let sx = sun.x / n, sy = sun.y / n, sz = sun.z / n
        let along = p.x * sx + p.y * sy + p.z * sz
        if along > 0 { return true }
        let px = p.x - along * sx, py = p.y - along * sy, pz = p.z - along * sz
        return sqrt(px * px + py * py + pz * pz) > 6371
    }

    /// Passes the observer can see: observer past civil dusk (Sun below −6°) and satellite sunlit at peak.
    public static func visiblePasses(tle: TLE, site: Site, from: Date, to: Date, minPeakElevation: Double = 30) throws -> [SatellitePass] {
        let sat = Satellite(withTLE: try Elements(tle.line0, tle.line1, tle.line2))
        let observer = LatLonAlt(site.latitude, site.longitude, site.elevationM / 1000)
        return try passes(tle: tle, site: site, from: from, to: to, minPeakElevation: minPeakElevation, stepSeconds: 30).filter { p in
            guard Ephemeris.sunAltitude(at: p.peak, site: site) < -6 else { return false }
            return try isSunlit(sat, at: p.peak)
        }.map { p in
            // The sunlit part of the pass, sampled every 10 s: evening passes fade into shadow, morning ones emerge from it.
            var q = p
            var t = p.rise
            while t <= p.set {
                let top = try sat.topPosition(julianDays: t.julianDate, observer: observer)
                if top.elev > 0, try isSunlit(sat, at: t) {
                    if q.appears == nil { q.appears = t; q.appearsAzimuthDeg = top.azim; q.appearsElevationDeg = top.elev }
                    q.vanishes = t; q.vanishesAzimuthDeg = top.azim; q.vanishesElevationDeg = top.elev
                }
                t = t.addingTimeInterval(10)
            }
            return q
        }
    }
}
