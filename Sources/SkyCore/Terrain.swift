import Foundation

/// The hills around a site, from Open-Meteo's elevation API (Copernicus DEM GLO-90, 90 m) (#108, owner, 1 October 2026):
/// a starting point for a site's horizon. It sees the land only, never trees or buildings, and it only ever raises a
/// direction. Asked for one site at a time, from the Horizon sheet, never in the background: Open-Meteo answers 429 to
/// a quick run of requests (seen on 1 October 2026), so each batch waits a moment and a refusal is retried after a pause.
public enum Terrain {
    /// Three bearings across each of the eight directions, twelve distances out to 20 km.
    static let offsets: [Double] = [-15, 0, 15]
    static let distancesKm: [Double] = [0.25, 0.5, 1, 1.5, 2, 3, 4, 6, 8, 11, 15, 20]
    /// The observer's eye above the ground.
    static let eyeM = 1.5

    /// The site first, then each sample in direction order.
    public static func samplePoints(around site: Site) -> [Coordinate] {
        let c = Coordinate(latitude: site.latitude, longitude: site.longitude)
        return [c] + (0..<8).flatMap { i in offsets.flatMap { o in distancesKm.map { Geo.destination(from: c, bearingDeg: Double(i) * 45 + o, distanceKm: $0) } } }
    }

    /// The highest angle to the land in each direction, from the elevations of `samplePoints` in the same order, allowing
    /// for the Earth's curve; never below 0.
    public static func horizon(elevations e: [Double]) -> [Double]? {
        let per = offsets.count * distancesKm.count
        guard e.count == 1 + 8 * per else { return nil }
        let eye = e[0] + eyeM
        return (0..<8).map { i in
            let angles = offsets.indices.flatMap { o in distancesKm.indices.map { d -> Double in
                let km = distancesKm[d], h = e[1 + i * per + o * distancesKm.count + d]
                return atan2(h - eye, km * 1000) * 180 / .pi - km / (2 * Geo.earthRadiusKm) * 180 / .pi
            } }
            return max(0, angles.max() ?? 0)
        }
    }

    /// Fetches the hills around `site`: batches of 100 points, a pause between them, and up to two retries after `retryWait`.
    public static func fetch(site: Site, fetcher: Fetcher, retryWait: Duration = .seconds(20),
                             pause: Duration = .seconds(1)) async throws -> [Double] {
        let points = samplePoints(around: site)
        var elevations: [Double] = []
        for start in stride(from: 0, to: points.count, by: 100) {
            if start > 0 { try await Task.sleep(for: pause) }
            let chunk = points[start..<min(start + 100, points.count)]
            var c = URLComponents(string: "https://api.open-meteo.com/v1/elevation")!
            c.queryItems = [URLQueryItem(name: "latitude", value: chunk.map { String(format: "%.5f", $0.latitude) }.joined(separator: ",")),
                            URLQueryItem(name: "longitude", value: chunk.map { String(format: "%.5f", $0.longitude) }.joined(separator: ","))]
            var attempt = 0
            while true {
                do {
                    let data = try await fetcher.get(c.url!)
                    struct Reply: Decodable { let elevation: [Double] }
                    let r = try JSONDecoder().decode(Reply.self, from: data)
                    guard r.elevation.count == chunk.count else { throw ForecastError.malformed("elevation count") }
                    elevations += r.elevation
                    break
                } catch {
                    attempt += 1
                    if attempt > 2 || error is CancellationError { throw error }
                    try await Task.sleep(for: retryWait)
                }
            }
        }
        guard let h = horizon(elevations: elevations) else { throw ForecastError.malformed("elevation") }
        return h
    }

    /// The directions where the hills stand above what is set (the site's horizon, else the go rule's height), raised to
    /// clear them: the next 5° up. Empty when the land is lower everywhere.
    public static func raises(terrain: [Double], site: Site, openDeg: Double) -> [Int: Double] {
        guard terrain.count == 8 else { return [:] }
        var out: [Int: Double] = [:]
        for i in 0..<8 {
            let set = max(site.horizon?[i] ?? openDeg, openDeg)
            if terrain[i] > set { out[i] = HorizonPhoto.horizonValue(terrain[i] + 0.01) }
        }
        return out
    }
}
