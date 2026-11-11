import Foundation
import SkyCore

/// One of tonight's best targets as the Mac's popover shows it: a picture, the catalogue ID, the name people know, and when it
/// is highest. The picture is chosen the way the Mac chooses it (`Thumbnails` and `ThumbnailView` in the Mac app): the Moon
/// from NASA's picture for its peak hour, a planet from its bundled photograph, a constellation or the Milky Way from the
/// owner's artwork, anything else from the DSS2 survey at the telescope's field of view, and a group symbol where none applies.
public struct TargetPick: Equatable, Sendable, Identifiable {
    public enum Picture: Equatable, Sendable {
        case moon(at: Date)
        case planet(String)
        case constellation(String)
        case milkyWay(String)
        case survey(url: URL, cacheName: String)
        case symbol
    }

    public let id: String
    public let title: String
    public let line: String
    public let best: String
    public let group: TargetGroup
    public let picture: Picture

    public static func make(_ t: RankedTarget, site: Site, fov: FieldOfView) -> TargetPick {
        TargetPick(id: t.id, title: t.catalogueID.plainDashes, line: (t.commonName ?? t.typeName).plainDashes,
                   best: "\(Copy.hhmm(t.peakTime, site: site)) · \(Copy.peakHeight(t, site: site))", group: t.group,   // no "Best": the heading says it, as on the Mac
                   picture: picture(for: t, fov: fov))
    }

    static func picture(for t: RankedTarget, fov: FieldOfView) -> Picture {
        if t.id == "moon" { return .moon(at: t.peakTime) }
        if let p = PlanetImages.planet(forTargetID: t.id) { return .planet(p.rawValue) }
        if MilkyWay.isMilkyWay(t.id) { return .milkyWay(t.id) }
        if t.group == .constellations { return .constellation(t.id) }
        if t.group == .planets { return .symbol }
        return .survey(url: SurveyThumbnail.url(raHours: t.raHours, decDeg: t.decDeg, sizeArcmin: t.sizeArcmin, fov: fov),
                       cacheName: ThumbnailFiles.name(id: t.id, fovWidthDeg: fov.widthDeg, fovHeightDeg: fov.heightDeg))
    }
}

public extension TargetPick {
    /// The sharp picture for a target's own page: the same cutout at 1600 px, as the Mac's page asks for it (the page's picture area is large). Only a
    /// deep-sky target has one; the Moon, planets, constellations and the Milky Way use their own art.
    static func sharp(_ t: RankedTarget, site: Site, fov: FieldOfView) -> (url: URL, cacheName: String)? {
        guard case .survey = make(t, site: site, fov: fov).picture else { return nil }
        return (SurveyThumbnail.url(raHours: t.raHours, decDeg: t.decDeg, sizeArcmin: t.sizeArcmin, fov: fov, width: sharpWidth),
                "sharp-v2-" + ThumbnailFiles.name(id: t.id, fovWidthDeg: fov.widthDeg, fovHeightDeg: fov.heightDeg))
    }
    static let sharpWidth = 1600
    /// hips2fits took 12.5 s for a 1600 px image with extra sky, so this one gets longer than the card photos' 20 s.
    static let sharpTimeout: TimeInterval = 45
}

/// DSS2 colour cutouts from CDS hips2fits at the user's field of view (or 1.5 times the object when it is bigger), 480 px
/// wide: the same request the Mac app makes.
public enum SurveyThumbnail {
    public static func fovDeg(sizeArcmin: Double?, fov: FieldOfView) -> Double {
        max(fov.widthDeg, ((sizeArcmin ?? 0) / 60) * 1.5, 0.05)
    }

    public static func url(raHours: Double, decDeg: Double, sizeArcmin: Double?, fov: FieldOfView, width: Int = ThumbnailFiles.cardWidth) -> URL {
        var c = URLComponents(string: "https://alasky.cds.unistra.fr/hips-image-services/hips2fits")!
        c.queryItems = [
            .init(name: "hips", value: "CDS/P/DSS2/color"),
            .init(name: "ra", value: String(format: "%.5f", raHours * 15)),
            .init(name: "dec", value: String(format: "%.5f", decDeg)),
            .init(name: "fov", value: String(format: "%.3f", fovDeg(sizeArcmin: sizeArcmin, fov: fov))),
            .init(name: "width", value: String(width)),
            .init(name: "height", value: String(Int(Double(width) * max(0.05, fov.heightDeg) / max(0.05, fov.widthDeg)))),
            .init(name: "projection", value: "TAN"),
            .init(name: "format", value: "jpg")
        ]
        return c.url!
    }
}
