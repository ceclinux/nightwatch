import Foundation
import ImageIO

/// "Measure from a photo" (owner-approved mock-up, 1 October 2026): a phone photo taken where the telescope stands
/// gives the height of the roof or trees in the direction it faces. The photo says which way it faced (GPS image
/// direction), how wide the lens sees (35 mm-equivalent focal length) and, on an iPhone, how the phone was tilted
/// (Apple's gravity vector, maker-note key "8", undocumented). The person marks the skyline; this does the sums.
/// A guide, not a survey.
public struct HorizonPhoto: Equatable, Sendable {
    /// The photo as shown, after its orientation is applied, in pixels.
    public let width: Double
    public let height: Double
    /// Degrees clockwise from north; nil when the photo has no compass direction.
    public let bearingDeg: Double?
    /// Degrees the camera pointed above level (negative: below); nil when the photo has no tilt reading.
    public let pitchDeg: Double?
    /// The focal length in pixels; nil when the photo has no lens details.
    public let focalPx: Double?

    public init(width: Double, height: Double, bearingDeg: Double?, pitchDeg: Double?, focal35mm: Double?) {
        self.width = width; self.height = height; self.bearingDeg = bearingDeg; self.pitchDeg = pitchDeg
        // 35 mm equivalence is by the diagonal (43.27 mm), which holds for a 4:3 phone sensor as for 3:2 film.
        focalPx = focal35mm.flatMap { $0 > 0 ? (width * width + height * height).squareRoot() * $0 / 43.27 : nil }
    }

    /// Reads a photo's metadata as ImageIO reports it.
    public init(properties p: [CFString: Any]) {
        var w = (p[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? 0
        var h = (p[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? 0
        if let o = (p[kCGImagePropertyOrientation] as? NSNumber)?.intValue, (5...8).contains(o) { swap(&w, &h) }   // turned a quarter
        let gps = p[kCGImagePropertyGPSDictionary] as? [CFString: Any]
        let exif = p[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let apple = p[kCGImagePropertyMakerAppleDictionary] as? [String: Any]
        let g = (apple?["8"] as? [Any])?.compactMap { ($0 as? NSNumber)?.doubleValue ?? Double("\($0)") }
        self.init(width: w, height: h,
                  bearingDeg: (gps?[kCGImagePropertyGPSImgDirection] as? NSNumber)?.doubleValue,
                  pitchDeg: g.flatMap(Self.pitch(gravity:)),
                  focal35mm: (exif?[kCGImagePropertyExifFocalLenIn35mmFilm] as? NSNumber)?.doubleValue)
    }

    /// The camera's tilt from the gravity vector in the phone's own axes: x across the screen, y up it, z out of it.
    /// Tilting the camera up gives gravity a positive z (checked on the owner's photos, 1 October 2026).
    static func pitch(gravity g: [Double]) -> Double? {
        guard g.count == 3 else { return nil }
        let n = (g[0] * g[0] + g[1] * g[1] + g[2] * g[2]).squareRoot()
        guard n > 0.5 else { return nil }
        return asin(max(-1, min(1, g[2] / n))) * 180 / .pi
    }

    /// The height above level of a point `y` pixels down the photo, on its centre line. Level when there is no tilt reading.
    public func altitude(atY y: Double) -> Double? {
        guard let f = focalPx else { return nil }
        return (pitchDeg ?? 0) + atan((height / 2 - y) / f) * 180 / .pi
    }

    /// Where level (0°) falls, in pixels down the photo; nil off the photo or without lens details.
    public var levelY: Double? {
        guard let f = focalPx else { return nil }
        let y = height / 2 + f * tan((pitchDeg ?? 0) * .pi / 180)
        return (0...height).contains(y) ? y : nil
    }

    /// The direction the photo faces, as an index into `Site.horizonDirections`.
    public var direction: Int? { bearingDeg.map { Int((($0.truncatingRemainder(dividingBy: 360) + 360 + 22.5) / 45)) % 8 } }

    /// The bearings at the photo's left and right edges.
    public var covers: (from: Double, to: Double)? {
        guard let b = bearingDeg, let f = focalPx else { return nil }
        let half = atan(width / 2 / f) * 180 / .pi
        func wrap(_ a: Double) -> Double { (a.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) }
        return (wrap(b - half), wrap(b + half))
    }

    /// A measured height as the horizon stores it: up to the next 5°, so a target counts as up only once clear of it.
    public static func horizonValue(_ alt: Double) -> Double { min(80, max(0, (alt / 5).rounded(.up) * 5)) }
}
