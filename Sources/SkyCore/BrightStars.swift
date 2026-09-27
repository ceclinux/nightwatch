import Foundation

/// A named bright star (v1.0.1): the 49 named stars of magnitude 2.0 or brighter, from d3-celestial's catalogue and names
/// (BSD-3-Clause), built by scripts/build-bright-stars.py. Targets for focusing, alignment and finding your way.
public struct BrightStar: Codable, Equatable, Sendable, Identifiable {
    /// "HIP24608"
    public let id: String
    /// "Capella"
    public let name: String
    /// "α Aur"
    public let designation: String
    public let magnitude: Double
    public let raHours: Double
    public let decDeg: Double
}

public enum BrightStars {
    public static func bundled() throws -> [BrightStar] {
        guard let url = Bundle.module.url(forResource: "bright", withExtension: "json", subdirectory: "Resources/stars") else {
            throw CatalogError.missingResource("stars")
        }
        return try JSONDecoder().decode([BrightStar].self, from: Data(contentsOf: url))
    }
}
