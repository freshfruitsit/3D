import '../delivery/place_search.dart';
import 'device_location.dart';

/// What the delivery location picker may use: the phone's location, the
/// remote address search and the map. The app supplies the real ones;
/// tests pass fakes, no remote search and no map (no network).
class LocationServices {
  const LocationServices({
    this.device = const GeolocatorDeviceLocation(),
    this.search,
    this.showMap = true,
  });

  /// "Use my current location".
  final DeviceLocation device;

  /// Address search through the website's geocoder (Photon). Null: the
  /// picker finds the website's own areas only.
  final PlaceSearch? search;

  /// Shows the OpenStreetMap map with the Express zone (tap or drag to
  /// place the pin).
  final bool showMap;
}
