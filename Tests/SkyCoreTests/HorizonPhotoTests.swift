import Testing
import Foundation
import ImageIO
@testable import SkyCore

/// An iPhone photo's metadata as ImageIO reports it: 24 mm equivalent, stored sideways (orientation 6), facing south-south-west.
private func iphone(tiltZ: Any = "0.0947", bearing: Double? = 197) -> [CFString: Any] {
    var p: [CFString: Any] = [kCGImagePropertyPixelWidth: 5712, kCGImagePropertyPixelHeight: 4284, kCGImagePropertyOrientation: 6,
                              kCGImagePropertyExifDictionary: [kCGImagePropertyExifFocalLenIn35mmFilm: 24] as [CFString: Any],
                              kCGImagePropertyMakerAppleDictionary: ["8": ["0.0015", "-0.9906", tiltZ]] as [String: Any]]
    if let bearing { p[kCGImagePropertyGPSDictionary] = [kCGImagePropertyGPSImgDirection: bearing] as [CFString: Any] }
    return p
}

@Test func aPhotoReadsItsDirectionLensAndTilt() throws {
    let photo = HorizonPhoto(properties: iphone())
    #expect(photo.width == 4284 && photo.height == 5712)                   // shown upright, as taken
    #expect(photo.direction == 4)                                           // 197° is S
    let pitch = try #require(photo.pitchDeg)
    #expect(abs(pitch - 5.46) < 0.05)                                       // tilted up a little
    let centre = try #require(photo.altitude(atY: 2856))
    #expect(abs(centre - pitch) < 0.001)                                    // the centre is where the camera pointed
    let top = try #require(photo.altitude(atY: 0))
    #expect(abs(top - (pitch + 35.8)) < 0.2)                                // half the long side of a 24 mm frame is about 36°
    let level = try #require(photo.levelY)
    let atLevel = try #require(photo.altitude(atY: level))
    #expect(level > 2856 && abs(atLevel) < 0.001)
    let c = try #require(photo.covers)
    #expect(abs(c.from - 168.6) < 0.3 && abs(c.to - 225.4) < 0.3)
}

@Test func aPhotoWithoutReadingsSaysWhatItLacks() {
    let bare = HorizonPhoto(properties: [kCGImagePropertyPixelWidth: 1200, kCGImagePropertyPixelHeight: 900])
    #expect(bare.bearingDeg == nil && bare.direction == nil && bare.pitchDeg == nil && bare.focalPx == nil)
    #expect(bare.altitude(atY: 0) == nil && bare.levelY == nil && bare.covers == nil)
    let level = HorizonPhoto(properties: iphone(tiltZ: "nonsense", bearing: nil))
    #expect(level.pitchDeg == nil && level.direction == nil)
    #expect(level.altitude(atY: level.height / 2) == 0)                     // assumed level
    #expect(HorizonPhoto(properties: iphone(tiltZ: NSNumber(value: -0.106))).pitchDeg.map { $0 < -6 } == true)
}

@Test func aMeasuredHeightRoundsUpToTheNextFiveDegrees() {
    #expect(HorizonPhoto.horizonValue(26.2) == 30 && HorizonPhoto.horizonValue(25) == 25)
    #expect(HorizonPhoto.horizonValue(-3) == 0 && HorizonPhoto.horizonValue(84) == 80)
}
