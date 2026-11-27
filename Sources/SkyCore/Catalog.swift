import Foundation

public enum TargetGroup: String, Codable, CaseIterable, Sendable {
    case nebulae, galaxies, clusters, stars, planets, events, constellations
    public var displayName: String {
        switch self {
        case .nebulae: L10n.text("Nebulae")
        case .galaxies: L10n.text("Galaxies")
        case .clusters: L10n.text("Star clusters")
        case .stars: L10n.text("Stars")
        case .planets: L10n.text("Planets and Moon")
        case .events: L10n.text("Events")
        case .constellations: L10n.text("Constellations")
        }
    }
}

public struct DeepSkyObject: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let commonName: String?
    public let messier: Int?
    public let typeCode: String
    public let group: TargetGroup
    public let raHours: Double
    public let decDeg: Double
    public let majAxisArcmin: Double?
    public let minAxisArcmin: Double?
    public let magnitude: Double?
    public let constellation: String
    /// The Caldwell number (1–109), from OpenNGC's "C 043" identifier or an addendum entry named "C009".
    public var caldwell: Int? = nil
    /// The Sharpless number (1–313), where SIMBAD or OpenNGC says which Sharpless region this is, or for a row of its own.
    public var sharpless: Int? = nil

    /// "M42" for a Messier object, else the catalogue number spaced and without leading zeros: "NGC 281", "IC 1340".
    /// An addendum entry that is only a Caldwell object reads "C14". Otherwise the NGC or IC number stays the ID even for
    /// a Caldwell object, because most are better known by it (NGC 7000 is C20); the C number joins the name instead.
    public var catalogueID: String {
        if let m = messier { return "M\(m)" }
        if let c = DeepSkyObject.caldwellNumber(name: id) { return "C\(c)" }
        return DeepSkyObject.spaced(id)
    }

    /// 43 for an addendum name "C043"; nil for anything else.
    static func caldwellNumber(name: String) -> Int? {
        guard name.count == 4, name.first == "C", name.dropFirst().allSatisfy(\.isNumber), let n = Int(name.dropFirst()) else { return nil }
        return n
    }

    /// 43 from OpenNGC's identifiers list ("2MASX J00031494+1608428,C 043,MCG +03-01-020").
    static func caldwellNumber(identifiers: String) -> Int? {
        for token in identifiers.split(separator: ",") {
            let t = token.trimmingCharacters(in: .whitespaces)
            if t.count == 5, t.hasPrefix("C "), let n = Int(t.dropFirst(2)) { return n }
        }
        return nil
    }

    /// 155 from OpenNGC's identifiers list ("LBN 529,SH 2-155").
    static func sharplessNumber(identifiers: String) -> Int? {
        for token in identifiers.split(separator: ",") {
            let t = token.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("SH 2-"), let n = Int(t.dropFirst(5)) { return n }
        }
        return nil
    }

    /// "{catalogue} {number}": letters, a space, then the number without leading zeros. ESO, PGC and UGC numbers are
    /// fixed-format and kept whole ("ESO 056-115"). An id with no letters or no number is returned as it is.
    static func spaced(_ id: String) -> String {
        let prefix = id.prefix { $0.isLetter }
        let rest = id.dropFirst(prefix.count)
        guard !prefix.isEmpty, rest.first?.isNumber == true else { return id }
        let number = ["ESO", "PGC", "UGC"].contains(String(prefix)) ? rest : rest.drop { $0 == "0" }
        return "\(prefix) \(number.isEmpty ? "0" : number)"
    }

    public var displayName: String {
        var parts: [String] = []
        if let m = messier { parts += ["M\(m)", DeepSkyObject.spaced(id)] } else { parts.append(catalogueID) }
        if let c = caldwell, catalogueID != "C\(c)" { parts.append("C\(c)") }
        if let c = commonName { parts.append(c) }
        // Last, so a narrow row (the widgets') cuts this short and not the name. A row of its own already reads "Sh 2-101".
        if let s = sharpless, !id.hasPrefix("Sh2-") { parts.append("Sh 2-\(s)") }
        return parts.joined(separator: " · ")
    }
}

public enum CatalogError: Error { case missingResource(String), badHeader }

public struct Catalog: Sendable {
    public let objects: [DeepSkyObject]
    public init(objects: [DeepSkyObject]) { self.objects = objects }

    static let groupByType: [String: TargetGroup] = [
        "G": .galaxies, "GPair": .galaxies, "GTrpl": .galaxies, "GGroup": .galaxies,
        "OCl": .clusters, "GCl": .clusters, "Cl+N": .clusters, "*Ass": .clusters,
        "PN": .nebulae, "HII": .nebulae, "EmN": .nebulae, "Neb": .nebulae, "RfN": .nebulae, "SNR": .nebulae, "DrkN": .nebulae
    ]

    /// OpenNGC type codes in words, for card subtitles ("Emission nebula").
    // Canonical values also drive filter and visibility rules; translate at presentation, never in these rules.
    public static let typeNames: [String: String] = [
        "G": "Galaxy", "GPair": "Galaxy pair", "GTrpl": "Galaxy triplet", "GGroup": "Galaxy group",
        "OCl": "Open cluster", "GCl": "Globular cluster", "Cl+N": "Cluster with nebula", "*Ass": "Stellar association",
        "PN": "Planetary nebula", "HII": "Emission nebula", "EmN": "Emission nebula", "Neb": "Nebula", "RfN": "Reflection nebula",
        "SNR": "Supernova remnant", "DrkN": "Dark nebula"
    ]

    /// Well-known names OpenNGC leaves out, by its Name, so they show on the card and the search finds them (v1.0.1: the owner
    /// searched "sombrero" for C43). From Wikipedia's Caldwell catalogue table, and its NGC 7814 article for the Little Sombrero.
    /// OpenNGC's own name wins where it has one.
    /// Sizes OpenNGC gets wrong, in arcminutes (major, minor), where a visibility judgement depends on them (#63).
    /// NGC 7000: OpenNGC has 120 × 30; the nebula is 120′ × 100′ (Wikipedia, North America Nebula).
    static let sizeCorrections: [String: (Double, Double)] = ["NGC7000": (120, 100)]

    /// The Sharpless numbers of objects OpenNGC lists under another name, by its Name, so "Sh2-25" finds the Lagoon Nebula.
    /// SIMBAD's identifications, printed by `scripts/build-sharpless.py` (25 November 2026); OpenNGC's own "SH 2-155"
    /// identifier is read from the file. A nebula that merely lies inside a Sharpless region is in `sharplessByPosition`.
    static let sharplessNumbers: [String: Int] = [
        "NGC6302": 6, "NGC6357": 11, "NGC6523": 25, "NGC6590": 37, "NGC6823": 86, "NGC6842": 95, "NGC6847": 97, "NGC7000": 117,
        "NGC7380": 142, "IC1470": 156, "NGC7538": 158, "NGC7635": 162, "NGC7822": 171, "NGC0281": 184, "IC1805": 190,
        "IC1848": 199, "NGC1491": 206, "NGC1624": 212, "NGC1499": 220, "NGC1579": 222, "IC0417": 234, "NGC1931": 237,
        "NGC1555": 238, "NGC1952": 244, "IC0443": 248, "NGC2175": 252, "IC2162": 255, "NGC2264": 273, "NGC2238": 275,
        "IC0466": 288, "IC2177": 292, "NGC2359": 298, "NGC2467": 311
    ]

    /// Sharpless numbers given by position, where neither SIMBAD nor OpenNGC says which region an object is (owner, 25 November
    /// 2026: "Sh2-281" found nothing, though the Orion Nebula lies inside it). The number goes to the OpenNGC nebula nearest the
    /// region's centre among those inside it; never a planetary or reflection nebula, never a region over 5° wide, and an object keeps
    /// one number. A match, not an identification: in a crowded field it can name the wrong member. From `scripts/build-sharpless.py`.
    static let sharplessByPosition: [String: Int] = [
        "NGC6334": 8, "NGC6559": 29, "NGC6514": 30, "IC4701": 44, "NGC6618": 45, "IC4703": 49, "NGC6857": 100, "NGC6974": 103,
        "NGC6888": 105, "IC5146": 125, "IC1396": 131, "IC0063": 185, "IC0405": 229, "IC0410": 236, "IC0434": 277, "NGC1977": 279,
        "NGC1976": 281
    ]

    static let extraNames: [String: String] = [
        "NGC0188": "Polarissima Cluster", "IC0342": "Hidden Galaxy", "NGC0891": "Silver Sliver Galaxy",
        "NGC7814": "Little Sombrero Galaxy", "NGC7479": "Superman Galaxy", "NGC0246": "Skull Nebula",
        "NGC2362": "Tau Canis Majoris Cluster", "NGC6729": "R CrA Nebula", "NGC0300": "Sculptor Pinwheel Galaxy",
        "NGC0055": "String of Pearls Galaxy", "NGC6752": "Great Peacock Globular", "NGC2516": "Southern Beehive Cluster"
    ]

    static func hours(_ s: String) -> Double? {
        let p = s.split(separator: ":").compactMap { Double($0) }
        guard p.count == 3 else { return nil }
        return p[0] + p[1] / 60 + p[2] / 3600
    }

    static func degrees(_ s: String) -> Double? {
        guard let first = s.first else { return nil }
        let sign: Double = first == "-" ? -1 : 1
        let body = (first == "-" || first == "+") ? String(s.dropFirst()) : s
        let p = body.split(separator: ":").compactMap { Double($0) }
        guard p.count == 3 else { return nil }
        return sign * (p[0] + p[1] / 60 + p[2] / 3600)
    }

    public static func parse(csv: String) throws -> [DeepSkyObject] {
        var lines = csv.split(whereSeparator: \.isNewline).map(String.init)
        guard !lines.isEmpty else { return [] }
        let header = lines.removeFirst().split(separator: ";").map(String.init)
        guard header.count > 28 else { throw CatalogError.badHeader }
        let col = Dictionary(uniqueKeysWithValues: header.enumerated().map { ($1, $0) })
        func field(_ row: [String], _ name: String) -> String {
            guard let i = col[name], i < row.count else { return "" }
            return row[i]
        }
        var out: [DeepSkyObject] = []
        for line in lines {
            let row = line.components(separatedBy: ";")
            let type = field(row, "Type")
            guard let group = groupByType[type],
                  let ra = hours(field(row, "RA")), let dec = degrees(field(row, "Dec")) else { continue }
            let v = Double(field(row, "V-Mag")), b = Double(field(row, "B-Mag"))
            let names = field(row, "Common names")
            let listed = field(row, "Const")   // Sharpless gives no constellation: it is found from the place
            out.append(DeepSkyObject(
                id: field(row, "Name"),
                commonName: names.isEmpty ? extraNames[field(row, "Name")]
                    : names.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) },
                messier: Int(field(row, "M")),
                typeCode: type, group: group, raHours: ra, decDeg: dec,
                majAxisArcmin: sizeCorrections[field(row, "Name")]?.0 ?? Double(field(row, "MajAx")),
                minAxisArcmin: sizeCorrections[field(row, "Name")]?.1 ?? Double(field(row, "MinAx")),
                magnitude: v ?? b, constellation: listed.isEmpty ? Ephemeris.constellation(raHours: ra, decDeg: dec).symbol : listed,
                caldwell: DeepSkyObject.caldwellNumber(identifiers: field(row, "Identifiers")) ?? DeepSkyObject.caldwellNumber(name: field(row, "Name")),
                sharpless: DeepSkyObject.sharplessNumber(identifiers: field(row, "Identifiers")) ?? sharplessNumbers[field(row, "Name")]
                    ?? sharplessByPosition[field(row, "Name")]))
        }
        return out
    }

    /// Every object a search matches, by the Targets grid's own rule, whether or not it is up tonight: for a search tonight's ranked list
    /// cannot answer ("Find the Crescent Nebula" on a night it is below the horizon all through the dark, #72).
    public func objects(matching query: String) -> [DeepSkyObject] {
        guard !query.allSatisfy(\.isWhitespace) else { return [] }
        return objects.filter { o in
            var r = RankedTarget(id: o.id, name: o.displayName, subtitle: L10n.format("\(o.typeCode) in \(o.constellation)"), group: o.group, raHours: o.raHours,
                                 decDeg: o.decDeg, sizeArcmin: o.majAxisArcmin, magnitude: o.magnitude, fit: .fits, peakAltDeg: 0, peakTime: Date(timeIntervalSince1970: 0),
                                 moonSepDeg: 90, moonWashed: false, visibleFraction: 0)
            r.typeName = Catalog.typeNames[o.typeCode] ?? o.typeCode
            return r.matches(query)
        }
    }

    public static func bundled() throws -> Catalog {
        var all: [DeepSkyObject] = []
        for name in ["NGC", "addendum", "sharpless"] {
            guard let url = Bundle.module.url(forResource: name, withExtension: "csv", subdirectory: "Resources/catalog") else {
                throw CatalogError.missingResource(name)
            }
            all += try parse(csv: String(contentsOf: url, encoding: .utf8))
        }
        return Catalog(objects: all)
    }
}

public struct Constellation: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let raHours: Double
    public let decDeg: Double
    /// Stick-figure polylines, each point [raHours, decDeg].
    public let lines: [[[Double]]]
}

public enum Constellations {
    private struct Collection: Decodable { let features: [Feature] }
    private struct Feature: Decodable {
        let id: String
        let properties: [String: AnyCodableValue]?
        let geometry: Geometry
        struct Geometry: Decodable { let type: String; let coordinates: AnyCodableValue }
    }

    /// d3-celestial stores RA in degrees from -180 to 180; convert to hours 0..24.
    static func hours(fromDegrees d: Double) -> Double {
        var h = d / 15
        if h < 0 { h += 24 }
        return h
    }

    public static func bundled() throws -> [Constellation] {
        guard let cUrl = Bundle.module.url(forResource: "constellations", withExtension: "json", subdirectory: "Resources/catalog"),
              let lUrl = Bundle.module.url(forResource: "constellations.lines", withExtension: "json", subdirectory: "Resources/catalog") else {
            throw CatalogError.missingResource("constellations")
        }
        let centres = try JSONDecoder().decode(Collection.self, from: Data(contentsOf: cUrl))
        let figures = try JSONDecoder().decode(Collection.self, from: Data(contentsOf: lUrl))
        // Some ids (e.g. "Ser" for Serpens Caput/Cauda) appear as two features; merge their lines.
        let linesByID: [String: [[[Double]]]] = figures.features.reduce(into: [:]) { dict, f in
            let raw = f.geometry.coordinates.doubleArrays3
            let converted = raw.map { line in line.map { [hours(fromDegrees: $0[0]), $0[1]] } }
            dict[f.id, default: []] += converted
        }

        // Group centre features by id (preserving first-occurrence order) so a
        // split constellation like Serpens Caput/Cauda still yields one Constellation.
        var order: [String] = []
        var groups: [String: [Feature]] = [:]
        for f in centres.features {
            if groups[f.id] == nil { order.append(f.id) }
            groups[f.id, default: []].append(f)
        }

        return order.compactMap { id -> Constellation? in
            let points: [(name: String, raDeg: Double, dec: Double)] = (groups[id] ?? []).compactMap { f in
                guard let pt = f.geometry.coordinates.doubleArray, pt.count == 2 else { return nil }
                return (f.properties?["name"]?.string ?? f.id, pt[0], pt[1])
            }
            guard !points.isEmpty else { return nil }
            let raDeg = points.map(\.raDeg).reduce(0, +) / Double(points.count)
            let dec = points.map(\.dec).reduce(0, +) / Double(points.count)
            let name: String
            if points.count == 2 {
                let word0 = points[0].name.prefix { $0 != " " }
                let word1 = points[1].name.prefix { $0 != " " }
                name = word0 == word1 ? String(word0) : points[0].name
            } else {
                name = points[0].name
            }
            return Constellation(id: id, name: name, raHours: hours(fromDegrees: raDeg), decDeg: dec, lines: linesByID[id] ?? [])
        }
    }
}

/// Minimal JSON value for the loosely typed GeoJSON files.
public enum AnyCodableValue: Decodable, Sendable {
    case string(String), number(Double), bool(Bool), array([AnyCodableValue]), object([String: AnyCodableValue]), null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([AnyCodableValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: AnyCodableValue].self)) }
    }

    var string: String? { if case .string(let s) = self { return s }; return nil }
    var double: Double? { if case .number(let n) = self { return n }; return nil }
    var doubleArray: [Double]? { if case .array(let a) = self { return a.compactMap(\.double) }; return nil }
    var doubleArrays3: [[[Double]]] {
        if case .array(let lines) = self {
            return lines.compactMap { line -> [[Double]]? in
                if case .array(let pts) = line { return pts.compactMap(\.doubleArray) }
                return nil
            }
        }
        return []
    }
}
