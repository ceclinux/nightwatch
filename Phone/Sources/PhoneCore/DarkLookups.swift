import Foundation
import MapKit
import SkyCore

/// A public place for a computed dark spot: the nearest car park Apple Maps knows that the light-pollution data still shows as dark.
public struct PublicPlace: Codable, Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double
    /// The car park's own name, or "Car park" when Apple Maps only calls it that (the town is added later).
    public var name: String
    public init(latitude: Double, longitude: Double, name: String) { self.latitude = latitude; self.longitude = longitude; self.name = name }
}

/// The two Apple Maps lookups dark sites need, behind closures so the core can be tested without a network. Both throw when the
/// search fails or times out, so the caller tries again later, and answer nil when Apple Maps has nothing there.
public struct DarkLookups: Sendable {
    /// The nearest town or village to a point: "Kielder".
    public var placeName: @Sendable (Coordinate) async throws -> String?
    public var publicPlace: @Sendable (Coordinate, DarknessBand?, [LPGrid]) async throws -> PublicPlace?

    public init(placeName: @escaping @Sendable (Coordinate) async throws -> String?,
                publicPlace: @escaping @Sendable (Coordinate, DarknessBand?, [LPGrid]) async throws -> PublicPlace?) {
        self.placeName = placeName; self.publicPlace = publicPlace
    }

    public static let live = DarkLookups(placeName: { try await AppleMaps.townNear($0) },
                                         publicPlace: { try await AppleMaps.carPark(near: $0, band: $1, grids: $2) })
}

/// Resumes the continuation with whichever of the answer and the timeout comes first.
private final class Once<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    init(_ c: CheckedContinuation<T, Error>) { continuation = c }
    func finish(_ result: Result<T, Error>) {
        lock.lock(); let c = continuation; continuation = nil; lock.unlock()
        c?.resume(with: result)
    }
}

enum AppleMaps {
    /// "Kielder" for a point near it: the town alone, since a county would mislead. Nil where Apple Maps has none.
    static func townNear(_ c: Coordinate, timeout: TimeInterval = 5) async throws -> String? {
        let location = CLLocation(latitude: c.latitude, longitude: c.longitude)
        return try await withCheckedThrowingContinuation { continuation in
            let once = Once(continuation)
            let cancel: () -> Void
            // iOS 26's reverse geocoder names the city where the older one often has no locality (the Mac uses it too).
            if #available(iOS 26, macOS 26, *) {
                guard let request = MKReverseGeocodingRequest(location: location) else { once.finish(.success(nil)); return }
                request.getMapItems { items, error in
                    if let error, (error as? MKError)?.code != .placemarkNotFound { once.finish(.failure(error)); return }
                    once.finish(.success(items?.first?.addressRepresentations?.cityName))
                }
                cancel = request.cancel
            } else {
                let geocoder = CLGeocoder()
                geocoder.reverseGeocodeLocation(location) { places, error in
                    if let error, (error as? CLError)?.code != .geocodeFoundNoResult { once.finish(.failure(error)); return }
                    once.finish(.success(places?.first?.locality))   // the town only: a county would mislead
                }
                cancel = geocoder.cancelGeocode
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { cancel(); once.finish(.failure(URLError(.timedOut))) }
        }
    }

    /// The nearest car park within `radiusKm` that is still about as dark as the spot. A text search: the points-of-interest request
    /// found nothing on Dartmoor or in the Dales even at 10 km, where this finds car parks within 1 to 7 km (the Mac's finding).
    static func carPark(near c: Coordinate, band: DarknessBand?, grids: [LPGrid], radiusKm: Double = 8, timeout: TimeInterval = 8) async throws -> PublicPlace? {
        let here = CLLocation(latitude: c.latitude, longitude: c.longitude)
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "car park"
        request.region = MKCoordinateRegion(center: here.coordinate, latitudinalMeters: radiusKm * 2000, longitudinalMeters: radiusKm * 2000)
        request.resultTypes = .pointOfInterest
        let items: [MKMapItem] = try await withCheckedThrowingContinuation { continuation in
            let once = Once(continuation), search = MKLocalSearch(request: request)
            search.start { response, error in
                if let error, (error as? MKError)?.code != .placemarkNotFound { once.finish(.failure(error)); return }
                once.finish(.success(response?.mapItems ?? []))
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { search.cancel(); once.finish(.failure(URLError(.timedOut))) }
        }
        let places = items.compactMap { item -> (PublicPlace, Double)? in
            let at = CLLocation(latitude: item.placemark.coordinate.latitude, longitude: item.placemark.coordinate.longitude)
            let d = at.distance(from: here)
            let spot = Coordinate(latitude: at.coordinate.latitude, longitude: at.coordinate.longitude)
            guard d <= radiusKm * 1000, DarkSites.darkEnough(LPGrids.radiance(at: spot, in: grids).map(DarknessBand.from), spot: band) else { return nil }
            return (PublicPlace(latitude: spot.latitude, longitude: spot.longitude, name: DarkSites.carParkName(item.name)), d)
        }
        return places.min { $0.1 < $1.1 }?.0
    }
}
