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
    #expect(DarkSites.spotName(place: "Kielder, Northumberland") == "Dark spot near Kielder")
    #expect(DarkSites.spotName(place: "Newtonmore") == "Dark spot near Newtonmore")
    #expect(DarkSites.spotName(place: " , ") == nil)
    #expect(DarkSites.spotName(place: "") == nil)
    let spot = DarkSite(id: "spot-1", name: "Dark spot 55.230, -2.580", kind: "spot", coordinate: Coordinate(latitude: 55.23, longitude: -2.58),
                        distanceKm: 20, bearingDeg: 300, band: .dark, bortle: nil, source: nil, isComputed: true)
    let named = spot.named("Dark spot near Kielder")
    #expect(named.name == "Dark spot near Kielder")
    #expect(named.id == spot.id && named.coordinate == spot.coordinate && named.band == spot.band && named.isComputed)
}

// Computed spots move to a dark car park (owner's UAT, 29 September 2026).
@Test func computedSpotsMoveToADarkCarPark() {
    #expect(DarkSites.darkEnough(.dark, spot: .veryDark) && DarkSites.darkEnough(.veryDark, spot: .dark))
    #expect(!DarkSites.darkEnough(.rural, spot: .veryDark) && !DarkSites.darkEnough(.bright, spot: .dark))   // a town car park
    #expect(DarkSites.darkEnough(nil, spot: .veryDark) && DarkSites.darkEnough(.bright, spot: nil))
    #expect(DarkSites.carParkName("Hafren Forest Car Park and Toilet Block") == "Hafren Forest Car Park and Toilet Block")
    #expect(DarkSites.carParkName("Car Park") == "Car park" && DarkSites.carParkName("Parking") == "Car park" && DarkSites.carParkName(nil) == "Car park")
    #expect(DarkSites.spotName(place: "Kettlewell, North Yorkshire", lead: DarkSites.genericCarPark) == "Car park near Kettlewell")
    #expect(DarkSites.spotName(place: "Hetton, North Yorkshire", lead: "Euro Car Parks") == "Euro Car Parks near Hetton")
    // Names that already say where they are, or were already renamed, are left alone.
    #expect(DarkSites.spotName(place: "Malham", lead: "Malham National Park car park") == "Malham National Park car park")
    #expect(DarkSites.spotName(place: "Hetton", lead: "Euro Car Parks near Hetton") == "Euro Car Parks near Hetton")
}

/// A computed car park within 1 km of a certified site is dropped; the certified site stays (owner's UAT, 30 September 2026).
@Test func aComputedCarParkBesideACertifiedSiteIsDropped() {
    func site(_ id: String, _ lat: Double, _ lon: Double, computed: Bool) -> DarkSite {
        DarkSite(id: id, name: id, kind: computed ? "spot" : "discovery", coordinate: Coordinate(latitude: lat, longitude: lon),
                 distanceKm: 0, bearingDeg: 0, band: .veryDark, bortle: nil, source: nil, isComputed: computed)
    }
    let certified = site("Malham National Park car park", 54.0610, -2.1520, computed: false)
    let beside = site("Car park near Malham", 54.0615, -2.1530, computed: true)       // about 80 m away
    let apart = site("Euro Car Parks near Kettlewell", 54.1460, -2.0470, computed: true)
    #expect(DarkSites.withoutDuplicates([certified, beside, apart]).map(\.name) == [certified.name, apart.name])
    // Two certified sites close together are both kept: only computed ones are dropped.
    let other = site("Another certified site", 54.0612, -2.1522, computed: false)
    #expect(DarkSites.withoutDuplicates([certified, other]).count == 2)
}
