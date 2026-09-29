import MapKit
import SkyCore

/// The nearest town or village to a point, from Apple Maps: "Blubberhouses, North Yorkshire". Nil when offline or when
/// Apple Maps knows no place there.
enum PlaceNames {
    static func nearest(to c: Coordinate) async -> String? {
        let location = CLLocation(latitude: c.latitude, longitude: c.longitude)
        if #available(macOS 26, *) {
            guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
            return try? await request.mapItems.first?.addressRepresentations?.cityName
        }
        guard let place = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return nil }
        return place.locality ?? place.subAdministrativeArea
    }
}
