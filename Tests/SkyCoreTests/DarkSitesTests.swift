import Testing
import Foundation
@testable import SkyCore

@Test func certifiedListLoadsAndHasSources() throws {
    let all = try DarkSites.bundledCertified()
    #expect(all.count >= 40)
    #expect(all.allSatisfy { $0.source.hasPrefix("http") })
    #expect(all.allSatisfy { $0.country == nil || ($0.country!.count == 2 && $0.country! == $0.country!.uppercased()) })
    #expect(Set(all.map(\.id)).count == all.count)
    #expect(all.contains { $0.id == "gb-northumberland" })
}

@Test func sitesNearSheffieldWithinRadius() throws {
    let all = try DarkSites.bundledCertified()
    let home = Coordinate(latitude: 53.381, longitude: -1.470)
    let near = DarkSites.sites(near: home, radiusKm: 120, certified: all, grids: [], maxSpots: 0)
    #expect(near.allSatisfy { $0.distanceKm <= 120 })
    #expect(near.contains { $0.id == "gb-yorkshire-dales" })
    #expect(!near.contains { $0.id == "gb-northumberland" })     // 220 km away
    #expect(near == near.sorted { $0.distanceKm < $1.distanceKm })
}

@Test func computedSpotsAreMergedAndNamed() {
    let values: [Float] = [5, 3, 0.1, 20, .nan, 0.5, 0.2, 8, 40]
    let g = LPGrid(south: 53.0, west: -2.0, cellDeg: 0.1, rows: 3, cols: 3, values: values)
    let home = Coordinate(latitude: 53.15, longitude: -1.85)
    let sites = DarkSites.sites(near: home, radiusKm: 30, certified: [], grids: [g], maxSpots: 2)
    #expect(sites.count == 2)
    #expect(sites.allSatisfy { $0.isComputed })
    #expect(sites.allSatisfy { $0.kind == "spot" })
    #expect(sites.allSatisfy { $0.band != nil })
    #expect(sites.allSatisfy { $0.bortle == nil })
    #expect(sites.allSatisfy { $0.name == String(format: "Dark spot %.3f, %.3f", $0.coordinate.latitude, $0.coordinate.longitude) })
    #expect(sites.allSatisfy { !$0.name.contains("km") })
    #expect(sites[0].id.hasPrefix("spot-"))
}

@Test func toSiteCarriesCoordinatesAndName() throws {
    let s = DarkSite(id: "x", name: "Elan Valley", kind: "park", coordinate: Coordinate(latitude: 52.27, longitude: -3.6),
                     distanceKm: 100, bearingDeg: 250, band: nil, bortle: 2, source: nil, isComputed: false)
    let site = DarkSites.toSite(s, timeZoneID: "Europe/London")
    #expect(site.name == "Elan Valley" && site.latitude == 52.27 && site.bortle == 2)
}

@Test func darkSpotNamedAfterNearestTown() {
    #expect(DarkSites.spotName(place: "Blubberhouses, North Yorkshire") == "Dark spot near Blubberhouses")
    #expect(DarkSites.spotName(place: "Newtonmore") == "Dark spot near Newtonmore")
    #expect(DarkSites.spotName(place: " , ") == nil)
    #expect(DarkSites.spotName(place: "") == nil)
    let spot = DarkSite(id: "spot-1", name: "Dark spot 54.000, -1.800", kind: "spot", coordinate: Coordinate(latitude: 54, longitude: -1.8),
                        distanceKm: 20, bearingDeg: 300, band: .dark, bortle: nil, source: nil, isComputed: true)
    let named = spot.named("Dark spot near Blubberhouses")
    #expect(named.name == "Dark spot near Blubberhouses")
    #expect(named.id == spot.id && named.coordinate == spot.coordinate && named.band == spot.band && named.isComputed)
}
