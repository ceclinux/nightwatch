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

    /// Resumes the continuation with whichever of the answer and the timeout comes first.
    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<String?, Error>?
        init(_ c: CheckedContinuation<String?, Error>) { continuation = c }
        func finish(_ result: Result<String?, Error>) {
            lock.lock(); let c = continuation; continuation = nil; lock.unlock()
            c?.resume(with: result)
        }
    }
}
