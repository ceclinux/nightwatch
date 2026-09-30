import MapKit
import SkyCore

/// Search for a place by name in Add a site (owner-approved mock-up, 30 September 2026), so a site no longer needs its
/// coordinates typed. Suggestions come from Apple Maps as the name is typed; only the typed text is sent, never where the
/// Mac is.
@MainActor
final class PlaceSearch: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    struct Place: Equatable {
        let name: String
        let coordinate: Coordinate
        let timeZoneID: String?
    }

    @Published var query = "" { didSet { completer.queryFragment = query.trimmingCharacters(in: .whitespaces) } }
    @Published private(set) var results: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    nonisolated func completerDidUpdateResults(_ c: MKLocalSearchCompleter) {
        let found = Array(c.results.prefix(5))
        Task { @MainActor in self.results = self.query.isEmpty ? [] : found }
    }

    nonisolated func completer(_ c: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in self.results = [] }
    }

    /// The chosen suggestion's name, position and time zone; nil when Apple Maps cannot place it.
    func resolve(_ c: MKLocalSearchCompletion) async -> Place? {
        guard let item = try? await MKLocalSearch(request: MKLocalSearch.Request(completion: c)).start().mapItems.first else { return nil }
        let at: CLLocationCoordinate2D
        if #available(macOS 26, *) { at = item.location.coordinate } else { at = item.placemark.coordinate }
        return Place(name: item.name ?? c.title, coordinate: Coordinate(latitude: at.latitude, longitude: at.longitude),
                     timeZoneID: item.timeZone?.identifier)
    }

    func clear() { query = ""; results = [] }
}
