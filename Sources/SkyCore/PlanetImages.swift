import Foundation

/// Bundled public-domain planet photographs (NASA missions via Wikimedia Commons; see NOTICE).
public enum PlanetImages {
    /// File URL for a planet's image, or nil when none is bundled.
    public static func url(for planet: Planet) -> URL? {
        Bundle.module.url(forResource: planet.rawValue, withExtension: "jpg", subdirectory: "Resources/planets")
    }

    /// The photograph's name for a target that has one: a planet's, or Pluto's or Ceres's (`MinorBody`).
    public static func name(forTargetID id: String) -> String? {
        planet(forTargetID: id)?.rawValue ?? MinorBody(targetID: id)?.imageName
    }
    /// File URL for the photograph called `name`, or nil when none is bundled.
    public static func url(named name: String) -> URL? {
        Bundle.module.url(forResource: name, withExtension: "jpg", subdirectory: "Resources/planets")
    }

    /// The planet behind a ranked-target id of the form "planet-<name>".
    public static func planet(forTargetID id: String) -> Planet? {
        guard id.hasPrefix("planet-") else { return nil }
        return Planet(rawValue: String(id.dropFirst("planet-".count)))
    }
}
