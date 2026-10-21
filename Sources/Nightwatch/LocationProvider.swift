import CoreLocation
import SkyCore

/// @unchecked: created on the main thread, and CoreLocation delivers delegate calls on that thread.
final class LocationProvider: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<Site?, Never>?
    private var request = 0   // numbers each requestOnce, so an earlier request's timeout never ends a later one
    /// A fix that arrives with no `requestOnce` waiting: authorisation granted after the timeout (60 s while asking, 15 s otherwise).
    var onSite: ((Site) -> Void)?

    private var allowed: Bool { [.authorizedAlways, .authorized].contains(manager.authorizationStatus) }
    /// macOS has not asked about this app yet, so the next `requestOnce` brings up its prompt.
    var neverAsked: Bool { manager.authorizationStatus == .notDetermined }
    /// Location Services is switched off for the whole Mac: macOS then shows no prompt, and no app can be allowed.
    var servicesOff: Bool { !CLLocationManager.locationServicesEnabled() }

    /// One fix, or nil when denied, restricted or timed out. Never prompts more than macOS itself does.
    /// When macOS has not asked yet, this asks and waits for the answer (up to a minute, time to read the prompt) before
    /// requesting a fix: a fix requested before the answer fails at once, which showed "not available" while the prompt
    /// was still on screen (v0.6.10).
    @MainActor func requestOnce() async -> Site? {   // on main, with the delegate calls and the timeout
        guard continuation == nil else { return nil }   // one request in flight; a second would leak its continuation
        guard !servicesOff else { return nil }          // nothing to ask: the caller says so at once, not after a minute
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        let asking = manager.authorizationStatus == .notDetermined
        guard allowed || asking else { return nil }
        request += 1
        let this = request
        return await withCheckedContinuation { c in
            continuation = c
            if asking { manager.requestWhenInUseAuthorization() } else { manager.requestLocation() }
            DispatchQueue.main.asyncAfter(deadline: .now() + (asking ? 60 : 15)) { [weak self] in
                if self?.request == this { self?.finish(nil) }
            }
        }
    }

    private func finish(_ site: Site?) {
        continuation?.resume(returning: site)
        continuation = nil
    }

    /// The user answered the prompt (possibly long after `requestOnce` gave up): ask for a fix now, or end a waiting
    /// request at once on Don't Allow.
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if allowed { manager.requestLocation() } else if manager.authorizationStatus != .notDetermined { finish(nil) }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let l = locations.last else { return finish(nil) }
        let site = Site(name: "Current location", latitude: l.coordinate.latitude, longitude: l.coordinate.longitude,
                        elevationM: max(0, l.altitude), timeZoneID: TimeZone.current.identifier, bortle: 5)
        if continuation != nil { finish(site) } else { onSite?(site) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { finish(nil) }
}
