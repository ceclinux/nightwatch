import MapKit
import SkyCore

/// The nearest town or village to a point, from Apple Maps: "Kielder, Northumberland". Nil when Apple Maps has no town or
/// village there; throws when the lookup fails or takes longer than `timeout`, so the caller can try again later.
enum PlaceNames {
    static func nearest(to c: Coordinate, timeout: TimeInterval = 5) async throws -> String? {
        let location = CLLocation(latitude: c.latitude, longitude: c.longitude)
        return try await withCheckedThrowingContinuation { continuation in
            let once = Once(continuation)
            let cancel: () -> Void
            if #available(macOS 26, *) {
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
            // The timeout answers itself rather than relying on cancel() to call back.
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { cancel(); once.finish(.failure(URLError(.timedOut))) }
        }
    }

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

/// A public place for a computed dark spot (owner's UAT, 29 September 2026: a pin in the middle of a moor raised whether the
/// spot was public, or condoning trespass). The nearest car park Apple Maps knows within `radiusKm` that the light-pollution
/// data still shows as dark; nil when there is none. Throws when the search fails or times out, so it is tried again later.
enum PublicPlaces {
    struct Place: Codable, Equatable, Sendable {
        var latitude: Double
        var longitude: Double
        /// The car park's own name, or "Car park" when Apple Maps only calls it that (the town is added later).
        var name: String
    }

    static func nearest(to c: Coordinate, band: DarknessBand?, grids: [LPGrid], radiusKm: Double = 8, timeout: TimeInterval = 8) async throws -> Place? {
        let here = CLLocation(latitude: c.latitude, longitude: c.longitude)
        let request = MKLocalSearch.Request()
        // A text search: the points-of-interest request found nothing on Dartmoor or the Dales even at 10 km, where this
        // finds car parks within 1 to 7 km (tried 29 September 2026).
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
        let places = items.compactMap { item -> (Place, Double)? in
            let at: CLLocation
            if #available(macOS 26, *) { at = item.location } else { at = CLLocation(latitude: item.placemark.coordinate.latitude, longitude: item.placemark.coordinate.longitude) }
            let d = at.distance(from: here)
            let spot = Coordinate(latitude: at.coordinate.latitude, longitude: at.coordinate.longitude)
            guard d <= radiusKm * 1000,
                  DarkSites.darkEnough(LPGrids.radiance(at: spot, in: grids).map(DarknessBand.from), spot: band) else { return nil }
            return (Place(latitude: spot.latitude, longitude: spot.longitude, name: DarkSites.carParkName(item.name)), d)
        }
        return places.min { $0.1 < $1.1 }?.0
    }
}
