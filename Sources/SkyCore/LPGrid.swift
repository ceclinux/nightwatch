import Foundation

public enum DarknessBand: String, Codable, CaseIterable, Sendable {
    case veryDark, dark, rural, suburban, bright
    public var displayName: String {
        switch self {
        case .veryDark: "Very dark"
        case .dark: "Dark"
        case .rural: "Rural"
        case .suburban: "Suburban"
        case .bright: "Bright"
        }
    }
    /// The Bortle class a band most resembles, for a site whose darkness is only known from the grid.
    public var bortle: Int {
        switch self {
        case .veryDark: 2
        case .dark: 3
        case .rural: 4
        case .suburban: 6
        case .bright: 8
        }
    }
    /// Heuristic bands on VIIRS upward radiance (nW/cm²/sr). Not a Bortle class; the About window says so.
    public static func from(radiance r: Double) -> DarknessBand {
        switch r {
        case ..<0.25: .veryDark
        case ..<1: .dark
        case ..<5: .rural
        case ..<20: .suburban
        default: .bright
        }
    }
}

public struct DarkSpot: Equatable, Sendable {
    public let coordinate: Coordinate
    public let radiance: Double
    public let band: DarknessBand

    public init(coordinate: Coordinate, radiance: Double, band: DarknessBand) {
        self.coordinate = coordinate; self.radiance = radiance; self.band = band
    }
}

public enum LPGridError: Error { case badMagic, truncated }

/// Row 0 is the southernmost row; column 0 the westernmost. Cell (r, c) covers
/// [south + r·cell, south + (r+1)·cell) × [west + c·cell, west + (c+1)·cell).
public struct LPGrid: Sendable {
    public let south: Double
    public let west: Double
    public let cellDeg: Double
    public let rows: Int
    public let cols: Int
    /// The cells as radiance, for a grid stored as floats (LPG1: the British grid). Empty for a compact grid.
    public let values: [Float]
    /// The cells of a compact grid (LPG2: the world grid, #138), one byte each on a log scale, header included. Kept as the
    /// file's memory map, so of its 20 MB only the pages near the places asked about are ever loaded.
    let compact: Data?

    public init(south: Double, west: Double, cellDeg: Double, rows: Int, cols: Int, values: [Float]) {
        self.init(south: south, west: west, cellDeg: cellDeg, rows: rows, cols: cols, values: values, compact: nil)
    }

    private init(south: Double, west: Double, cellDeg: Double, rows: Int, cols: Int, values: [Float], compact: Data?) {
        self.south = south; self.west = west; self.cellDeg = cellDeg; self.rows = rows; self.cols = cols; self.values = values
        self.compact = compact
    }

    /// The compact grid's scale: byte q is (2^(q/32) − 1) / 8 nW/cm²/sr, and 255 is no data (scripts/build-lp-grid.py).
    static let scale: [Float] = (0..<256).map { $0 == 255 ? .nan : Float((pow(2, Double($0) / 32) - 1) / 8) }

    /// Radiance in cell `i` (row × cols + col); NaN where there is no data.
    func value(_ i: Int) -> Float {
        guard let compact else { return values[i] }
        return Self.scale[Int(compact[compact.startIndex + 20 + i])]
    }

    public init(data source: Data) throws {
        let magic = String(decoding: source.prefix(4), as: UTF8.self)
        guard magic == "LPG1" || magic == "LPG2" else { throw LPGridError.badMagic }
        // Data slices (e.g. a `.prefix(n)`) keep the parent's indices; copy to a
        // fresh, zero-indexed buffer before doing any offset-based access. Not the compact grid: a copy would read the
        // whole memory-mapped file in, and its cells are read through `startIndex`.
        let data = magic == "LPG2" ? source : Data(source)
        guard data.count >= 20 else { throw LPGridError.truncated }
        func f32(_ o: Int) -> Float {
            let bits = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: UInt32.self) }
            return Float(bitPattern: UInt32(littleEndian: bits))
        }
        func u16(_ o: Int) -> Int {
            let bits = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: UInt16.self) }
            return Int(UInt16(littleEndian: bits))
        }
        let s = Double(f32(4))
        let w = Double(f32(8))
        let c = Double(f32(12))
        let r = u16(16)
        let k = u16(18)
        if magic == "LPG2" {
            guard data.count == 20 + r * k else { throw LPGridError.truncated }
            self.init(south: s, west: w, cellDeg: c, rows: r, cols: k, values: [], compact: data)
            return
        }
        guard data.count == 20 + r * k * 4 else { throw LPGridError.truncated }
        var vals = [Float](repeating: .nan, count: r * k)
        for i in 0..<(r * k) { vals[i] = f32(20 + i * 4) }
        self.init(south: s, west: w, cellDeg: c, rows: r, cols: k, values: vals)
    }

    public func encoded() -> Data {
        if let compact { return Data(compact) }
        var d = Data("LPG1".utf8)
        for v in [Float(south), Float(west), Float(cellDeg)] { var le = v.bitPattern.littleEndian; d.append(Data(bytes: &le, count: 4)) }
        for n in [UInt16(rows), UInt16(cols)] { var le = n.littleEndian; d.append(Data(bytes: &le, count: 2)) }
        d.reserveCapacity(d.count + values.count * 4)
        for v in values { var le = v.bitPattern.littleEndian; d.append(Data(bytes: &le, count: 4)) }
        return d
    }

    public var north: Double { south + Double(rows) * cellDeg }
    public var east: Double { west + Double(cols) * cellDeg }

    public func radiance(at c: Coordinate) -> Double? {
        let r = Int(floor((c.latitude - south) / cellDeg)), k = Int(floor((c.longitude - west) / cellDeg))
        guard r >= 0, r < rows, k >= 0, k < cols else { return nil }
        let v = value(r * cols + k)
        return v.isNaN ? nil : Double(v)
    }

    /// True when `c` lies within the grid's bounds, on land or not.
    public func contains(_ c: Coordinate) -> Bool {
        c.latitude >= south && c.latitude < north && c.longitude >= west && c.longitude < east
    }

    func centre(row: Int, col: Int) -> Coordinate {
        Coordinate(latitude: south + (Double(row) + 0.5) * cellDeg, longitude: west + (Double(col) + 0.5) * cellDeg)
    }

    /// Lowest-radiance cells within `radiusKm` (ties to the nearest), greedy from darkest, each at least `minSpacingKm` from the ones already picked.
    public func darkestSpots(center: Coordinate, radiusKm: Double, count: Int, minSpacingKm: Double) -> [DarkSpot] {
        let latSpan = radiusKm / 111.2, lonSpan = radiusKm / (111.2 * max(0.1, cos(center.latitude * .pi / 180)))
        let r0 = max(0, Int(floor((center.latitude - latSpan - south) / cellDeg))), r1 = min(rows - 1, Int(floor((center.latitude + latSpan - south) / cellDeg)))
        let c0 = max(0, Int(floor((center.longitude - lonSpan - west) / cellDeg))), c1 = min(cols - 1, Int(floor((center.longitude + lonSpan - west) / cellDeg)))
        guard r0 <= r1, c0 <= c1 else { return [] }
        var candidates: [(p: Coordinate, v: Double, d: Double)] = []
        for r in r0...r1 { for k in c0...c1 {
            let v = value(r * cols + k)
            guard !v.isNaN else { continue }
            let p = centre(row: r, col: k), d = Geo.distanceKm(center, p)
            if d <= radiusKm { candidates.append((p, Double(v), d)) }
        } }
        // Much of the grid is exactly 0 (VIIRS masks unlit land to 0), so ties are common: the nearest wins.
        candidates.sort { ($0.v, $0.d) < ($1.v, $1.d) }
        var picked: [DarkSpot] = []
        for (p, v, _) in candidates where picked.count < count {
            if picked.allSatisfy({ Geo.distanceKm($0.coordinate, p) >= minSpacingKm }) {
                picked.append(DarkSpot(coordinate: p, radiance: v, band: DarknessBand.from(radiance: v)))
            }
        }
        return picked
    }
}

public enum LPGrids {
    public static func bundled() -> [LPGrid] {
        guard let urls = Bundle.module.urls(forResourcesWithExtension: "lpgrid", subdirectory: "Resources/lightpollution") else { return [] }
        return urls.compactMap { url in (try? Data(contentsOf: url)).flatMap { try? LPGrid(data: $0) } }
    }
    /// A grid file read through a memory map, which is what keeps the 20 MB world grid out of memory.
    public static func load(_ url: URL) -> LPGrid? {
        (try? Data(contentsOf: url, options: .mappedIfSafe)).flatMap { try? LPGrid(data: $0) }
    }

    /// Finest first: where two grids cover a place, the first with a value answers, so the finer British grid is used
    /// in Britain and the world grid everywhere else.
    public static func finestFirst(_ grids: [LPGrid]) -> [LPGrid] { grids.sorted { $0.cellDeg < $1.cellDeg } }

    public static func radiance(at c: Coordinate, in grids: [LPGrid]) -> Double? {
        for g in grids { if let v = g.radiance(at: c) { return v } }
        return nil
    }

    /// The darkest spots around `center`, from the finest grid that covers it: one grid only, or a place covered by two
    /// would get each spot twice.
    public static func darkestSpots(center: Coordinate, radiusKm: Double, count: Int, minSpacingKm: Double, in grids: [LPGrid]) -> [DarkSpot] {
        grids.filter { $0.contains(center) }.min { $0.cellDeg < $1.cellDeg }?
            .darkestSpots(center: center, radiusKm: radiusKm, count: count, minSpacingKm: minSpacingKm) ?? []
    }
}
