import Foundation

/// A target's height through the night, from sunset to sunrise, as a target's page and Tonight's plan both draw it (#92):
/// one source, so the plan's chart matches each target's own chart at every time.
public struct AltitudeSample: Equatable, Sendable {
    /// How far through the night, 0 at sunset and 1 at sunrise.
    public let fraction: Double
    public let time: Date
    public let alt: Double
    /// The height to clear in the target's direction: the site's horizon there, else `minAlt` (Site.floorDeg).
    public let floor: Double

    /// In the clear window and clear of the floor: the part a chart draws bold.
    public func isClear(in window: ClearWindow) -> Bool { time >= window.start && time <= window.end && alt >= floor }
}

public enum AltitudeTrack {
    /// Every 10 minutes from sunset to sunrise, plus the clear window's own edges so a bold run starts and ends there.
    public static func samples(raHours: Double, decDeg: Double, night: Night, window: ClearWindow, site: Site, minAlt: Double) -> [AltitudeSample] {
        let span = night.sunrise.timeIntervalSince(night.sunset)
        guard span > 0 else { return [] }
        let times = (stride(from: 0.0, through: 1.0, by: 1.0 / 72).map { night.sunset.addingTimeInterval($0 * span) } + [window.start, window.end])
            .filter { $0 >= night.sunset && $0 <= night.sunrise }.sorted()
        return times.map { t in
            let (alt, az) = Ephemeris.altAz(raHours: raHours, decDeg: decDeg, at: t, site: site)
            return AltitudeSample(fraction: t.timeIntervalSince(night.sunset) / span, time: t, alt: alt,
                                  floor: site.floorDeg(azimuthDeg: az, minAlt: minAlt))
        }
    }

    /// The runs of consecutive clear samples, each to be drawn as one bold stretch.
    public static func clearRuns(_ samples: [AltitudeSample], window: ClearWindow) -> [[AltitudeSample]] {
        var runs: [[AltitudeSample]] = [], run: [AltitudeSample] = []
        for s in samples {
            if s.isClear(in: window) { run.append(s) } else if !run.isEmpty { runs.append(run); run = [] }
        }
        if !run.isEmpty { runs.append(run) }
        return runs
    }
}
