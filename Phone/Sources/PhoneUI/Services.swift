import Foundation
import CoreLocation
import MapKit
import Network
import SkyCore
import PhoneCore

/// One-shot "where am I": asked only when the user presses the button. Builds a site named "Current location".
@MainActor
public final class LocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    public override init() { super.init(); manager.delegate = self }

    public func currentSite() async throws -> Site {
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        let fix: CLLocation = try await withCheckedThrowingContinuation { c in
            continuation = c
            manager.requestLocation()
        }
        return Site(name: "Current location", latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude,
                    elevationM: max(0, fix.altitude), timeZoneID: TimeZone.current.identifier, bortle: 5)
    }

    public nonisolated func locationManager(_ m: CLLocationManager, didUpdateLocations l: [CLLocation]) {
        Task { @MainActor in if let f = l.last { continuation?.resume(returning: f); continuation = nil } }
    }
    public nonisolated func locationManager(_ m: CLLocationManager, didFailWithError e: Error) {
        Task { @MainActor in continuation?.resume(throwing: e); continuation = nil }
    }
}

/// Search-as-you-type for "add a site": Apple's completer, biased to the region around `near` so a UK name is not buried by its
/// namesakes abroad, and showing places and outdoor spots (parks, car parks, camp sites, museums) but not shops or services.
@MainActor
public final class PlaceCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published public private(set) var suggestions: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    public override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
        completer.pointOfInterestFilter = MKPointOfInterestFilter(including: [.park, .nationalPark, .campground, .parking, .beach, .museum, .university, .library, .marina])
    }

    public func update(_ text: String, near site: Site?) {
        let t = text.trimmingCharacters(in: .whitespaces)
        if let site {
            completer.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: site.latitude, longitude: site.longitude),
                                                  span: MKCoordinateSpan(latitudeDelta: 8, longitudeDelta: 8))
        }
        if t.count < 2 { suggestions = []; completer.queryFragment = ""; return }
        completer.queryFragment = t
    }

    public func clear() { suggestions = []; completer.queryFragment = "" }

    public nonisolated func completerDidUpdateResults(_ c: MKLocalSearchCompleter) {
        let r = c.results
        Task { @MainActor in self.suggestions = Array(r.prefix(8)) }
    }
    public nonisolated func completer(_ c: MKLocalSearchCompleter, didFailWithError e: Error) {}

    /// The chosen suggestion as a site, with its real coordinate.
    public static func site(for completion: MKLocalSearchCompletion) async -> Site? {
        guard let item = try? await MKLocalSearch(request: MKLocalSearch.Request(completion: completion)).start().mapItems.first else { return nil }
        let pm = item.placemark
        let loc = pm.location ?? CLLocation(latitude: pm.coordinate.latitude, longitude: pm.coordinate.longitude)
        // MapKit often leaves the time zone out of a result (a park, a car park). Asking the geocoder is better than assuming the place keeps this
        // device's time: a site in another zone would otherwise have its night, its plan and its alerts at the wrong hours.
        let zone: TimeZone? = if let z = pm.timeZone { z } else { await timeZone(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude) }
        return Site(name: item.name ?? completion.title, latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude,
                    elevationM: max(0, loc.altitude), timeZoneID: zone?.identifier ?? TimeZone.current.identifier, bortle: 5)
    }

    /// The time zone at a coordinate, from the geocoder; nil when it cannot say.
    public static func timeZone(latitude: Double, longitude: Double) async -> TimeZone? {
        let found = try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: latitude, longitude: longitude))
        return found?.first?.timeZone
    }
}

/// Watches the network paths and reports them as PhoneCore's `Connectivity` (see `Connectivity.resolve`).
@MainActor
public final class ConnectivityMonitor: ObservableObject {
    @Published public private(set) var current = Connectivity()
    private let monitor = NWPathMonitor()
    private let wifiMonitor = NWPathMonitor(requiredInterfaceType: .wifi)
    private var latestDefault: Connectivity.Path?
    private var latestWifi: Connectivity.Path?

    private nonisolated static func facts(_ p: NWPath) -> Connectivity.Path {
        Connectivity.Path(isOnline: p.status == .satisfied, isExpensive: p.isExpensive, isConstrained: p.isConstrained)
    }

    private func update() {
        guard let d = latestDefault else { return }
        current = Connectivity.resolve(defaultPath: d, wifi: latestWifi)
        NSLog("Nightwatch connection resolved: optional downloads \(current.allowsOptionalDownloads ? "allowed" : "waiting")")
    }

    public init() {
        monitor.pathUpdateHandler = { [weak self] p in
            let kinds = [NWInterface.InterfaceType.wifi, .cellular, .wiredEthernet, .other, .loopback].filter { p.usesInterfaceType($0) }
            NSLog("Nightwatch connection: status=\(p.status) expensive=\(p.isExpensive) constrained=\(p.isConstrained) interfaces=\(kinds)")
            let f = Self.facts(p)
            Task { @MainActor in self?.latestDefault = f; self?.update() }
        }
        wifiMonitor.pathUpdateHandler = { [weak self] p in
            NSLog("Nightwatch Wi-Fi path: status=\(p.status) expensive=\(p.isExpensive) constrained=\(p.isConstrained)")
            let f = Self.facts(p)
            Task { @MainActor in self?.latestWifi = f; self?.update() }
        }
        monitor.start(queue: .global(qos: .utility))
        wifiMonitor.start(queue: .global(qos: .utility))
    }
    deinit { monitor.cancel(); wifiMonitor.cancel() }
}
