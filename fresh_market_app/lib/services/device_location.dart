import 'dart:async';

import 'package:geolocator/geolocator.dart';

/// Why the phone's location could not be read.
enum LocationProblem {
  /// Location (GPS) is switched off on the phone.
  serviceOff,

  /// The shopper said no to the permission prompt.
  denied,

  /// The permission is refused for good; only the app settings can change
  /// it.
  deniedForever,

  /// No fix within [DeviceLocation.timeout].
  timeout,

  /// Anything else (no location hardware, a platform error).
  failed,
}

/// The answer of [DeviceLocation.locate]: a point, or why there is none.
sealed class LocationOutcome {
  const LocationOutcome();
}

final class LocationFix extends LocationOutcome {
  const LocationFix(this.lat, this.lng);

  final double lat;
  final double lng;

  @override
  String toString() => 'LocationFix($lat, $lng)';
}

final class LocationFailure extends LocationOutcome {
  const LocationFailure(this.problem);

  final LocationProblem problem;

  @override
  String toString() => 'LocationFailure($problem)';
}

/// The phone's location, behind an interface so tests can answer with a
/// fixed point or a refusal.
abstract class DeviceLocation {
  const DeviceLocation();

  /// How long [locate] waits for a fix.
  static const Duration timeout = Duration(seconds: 10);

  /// Checks that location is on, asks for permission when needed and reads
  /// one high-accuracy fix. Never throws.
  Future<LocationOutcome> locate();

  /// Opens this app's page in the phone settings (permission refused for
  /// good). True when the settings opened.
  Future<bool> openAppSettings();

  /// Opens the phone's location settings (location switched off).
  Future<bool> openLocationSettings();
}

/// [DeviceLocation] on the phone, through the geolocator plugin.
class GeolocatorDeviceLocation extends DeviceLocation {
  const GeolocatorDeviceLocation();

  @override
  Future<LocationOutcome> locate() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationFailure(LocationProblem.serviceOff);
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      switch (permission) {
        case LocationPermission.denied:
          return const LocationFailure(LocationProblem.denied);
        case LocationPermission.deniedForever:
          return const LocationFailure(LocationProblem.deniedForever);
        case LocationPermission.whileInUse:
        case LocationPermission.always:
        case LocationPermission.unableToDetermine:
          break;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: DeviceLocation.timeout,
        ),
      ).timeout(DeviceLocation.timeout + const Duration(seconds: 2));
      return LocationFix(position.latitude, position.longitude);
    } on TimeoutException {
      return const LocationFailure(LocationProblem.timeout);
    } on LocationServiceDisabledException {
      return const LocationFailure(LocationProblem.serviceOff);
    } on PermissionDeniedException {
      return const LocationFailure(LocationProblem.denied);
    } catch (_) {
      return const LocationFailure(LocationProblem.failed);
    }
  }

  @override
  Future<bool> openAppSettings() async {
    try {
      return await Geolocator.openAppSettings();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> openLocationSettings() async {
    try {
      return await Geolocator.openLocationSettings();
    } catch (_) {
      return false;
    }
  }
}
