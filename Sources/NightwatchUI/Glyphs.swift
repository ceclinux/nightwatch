import SkyCore

extension TargetGroup {
    /// The SF Symbol for a target group, shared by the Targets sidebar, the thumbnails and the widget.
    public var symbolName: String {
        switch self {
        case .nebulae: "cloud.fill"
        case .galaxies: "hurricane"
        case .clusters: "sparkles"
        case .stars: "star.fill"
        case .planets: "circle.circle"
        case .events: "calendar"
        case .constellations: "point.3.connected.trianglepath.dotted"
        }
    }
}
