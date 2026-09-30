import Foundation

public struct CertifiedSite: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable { case park, reserve, sanctuary, community, urban, discovery }
    public let id: String
    public let name: String
    public let kind: Kind
    public let country: String?
    public let latitude: Double
    public let longitude: Double
    public let designated: Int?
    public let bortle: Int?
    public let source: String
    public let wikidata: String?
    public var coordinate: Coordinate { Coordinate(latitude: latitude, longitude: longitude) }
}

public struct DarkSite: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let kind: String
    public let coordinate: Coordinate
    public let distanceKm: Double
    public let bearingDeg: Double
    public let band: DarknessBand?
    public let bortle: Int?
    public let source: String?
    public let isComputed: Bool
    public var compass: String { Geo.compass(bearingDeg) }
    /// The same site under another name: a computed dark spot once its nearest place is known.
    public func named(_ name: String) -> DarkSite {
        DarkSite(id: id, name: name, kind: kind, coordinate: coordinate, distanceKm: distanceKm, bearingDeg: bearingDeg,
                 band: band, bortle: bortle, source: source, isComputed: isComputed)
    }

    public init(id: String, name: String, kind: String, coordinate: Coordinate, distanceKm: Double, bearingDeg: Double,
                band: DarknessBand?, bortle: Int?, source: String?, isComputed: Bool) {
        self.id = id; self.name = name; self.kind = kind; self.coordinate = coordinate; self.distanceKm = distanceKm
        self.bearingDeg = bearingDeg; self.band = band; self.bortle = bortle; self.source = source; self.isComputed = isComputed
    }
}

public enum DarkSites {
    public static func bundledCertified() throws -> [CertifiedSite] {
        guard let url = Bundle.module.url(forResource: "certified", withExtension: "json", subdirectory: "Resources/darksky") else {
            throw CatalogError.missingResource("certified")
        }
        return try JSONDecoder().decode([CertifiedSite].self, from: Data(contentsOf: url))
    }

    /// Certified places within the radius plus up to `maxSpots` computed dark spots, sorted by distance.
    public static func sites(near home: Coordinate, radiusKm: Double, certified: [CertifiedSite], grids: [LPGrid], maxSpots: Int) -> [DarkSite] {
        var out: [DarkSite] = []
        for c in certified {
            let d = Geo.distanceKm(home, c.coordinate)
            guard d <= radiusKm else { continue }
            let band = LPGrids.radiance(at: c.coordinate, in: grids).map { DarknessBand.from(radiance: $0) }
            out.append(DarkSite(id: c.id, name: c.name, kind: c.kind.rawValue, coordinate: c.coordinate, distanceKm: d,
                                bearingDeg: Geo.bearingDeg(from: home, to: c.coordinate), band: band, bortle: c.bortle, source: c.source, isComputed: false))
        }
        if maxSpots > 0 {
            let spots = grids.flatMap { $0.darkestSpots(center: home, radiusKm: radiusKm, count: maxSpots, minSpacingKm: 10) }
                .sorted { ($0.radiance, Geo.distanceKm(home, $0.coordinate)) < ($1.radiance, Geo.distanceKm(home, $1.coordinate)) }.prefix(maxSpots)
            for s in spots {
                let d = Geo.distanceKm(home, s.coordinate), b = Geo.bearingDeg(from: home, to: s.coordinate)
                let name = String(format: "Dark spot %.3f, %.3f", s.coordinate.latitude, s.coordinate.longitude)
                out.append(DarkSite(id: String(format: "spot-%.3f-%.3f", s.coordinate.latitude, s.coordinate.longitude), name: name, kind: "spot",
                                    coordinate: s.coordinate, distanceKm: d, bearingDeg: b, band: s.band, bortle: nil, source: nil, isComputed: true))
            }
        }
        return out.sorted { $0.distanceKm < $1.distanceKm }
    }

    /// "Dark spot near Kielder" from Apple Maps' "Kielder, Northumberland": the town alone, as the card already
    /// gives the distance and direction. Nil for a blank place, and the spot keeps its coordinates.
    public static func spotName(place: String, lead: String = "Dark spot") -> String? {
        let town = place.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        if town.isEmpty { return nil }
        // Already says where it is ("Malham car park"), or already named: left alone, so renaming twice is harmless.
        return lead.localizedCaseInsensitiveContains(town) ? lead : "\(lead) near \(town)"
    }

    /// A computed spot moves to a car park (owner's UAT, 29 September 2026). It must still be about as dark: no more than one
    /// band brighter than the spot. Unknown darkness at either end is let through.
    public static func darkEnough(_ candidate: DarknessBand?, spot: DarknessBand?) -> Bool {
        guard let c = candidate, let s = spot, let ci = DarknessBand.allCases.firstIndex(of: c), let si = DarknessBand.allCases.firstIndex(of: s) else { return true }
        return ci <= si + 1
    }

    /// The car park's own name ("Hafren Forest Car Park and Toilet Block"), or "Car park" when Apple Maps only calls it that,
    /// so the town can be added ("Car park near Kettlewell").
    public static func carParkName(_ name: String?) -> String {
        let n = (name ?? "").trimmingCharacters(in: .whitespaces)
        return ["", "car park", "parking", "car parking", "parking lot", "car park (public)"].contains(n.lowercased()) ? genericCarPark : n
    }
    public static let genericCarPark = "Car park"

    /// The sky's darkness at a place being added, from the bundled light-pollution grid; nil outside its coverage (Great
    /// Britain and Ireland), where the person chooses (place search, owner-approved mock-up, 30 September 2026).
    public static func suggestedBortle(at c: Coordinate, grids: [LPGrid]) -> Int? {
        LPGrids.radiance(at: c, in: grids).map { DarknessBand.from(radiance: $0).bortle }
    }

    /// A computed car park within 1 km of a certified site is that site again ("Car park near Malham" beside Malham
    /// National Park car park, owner's UAT, 30 September 2026): the certified one stays, with its source.
    public static func withoutDuplicates(_ sites: [DarkSite], withinKm: Double = 1) -> [DarkSite] {
        let certified = sites.filter { !$0.isComputed }
        return sites.filter { s in !s.isComputed || !certified.contains { Geo.distanceKm($0.coordinate, s.coordinate) <= withinKm } }
    }

    public static func toSite(_ s: DarkSite, timeZoneID: String) -> Site {
        Site(name: s.name, latitude: s.coordinate.latitude, longitude: s.coordinate.longitude, elevationM: 0, timeZoneID: timeZoneID,
             bortle: s.bortle ?? s.band?.bortle ?? 5)
    }
}
