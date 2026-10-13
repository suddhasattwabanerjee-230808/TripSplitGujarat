import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

/// Fetches the device's current GPS position. Returns null if location
/// services are off, permission is refused, or the fix times out — callers
/// should treat that as "no location available" rather than an error.
Future<Position?> fetchCurrentPosition() async {
  try {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }

    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: Duration(seconds: 12),
      ),
    );
  } catch (_) {
    return null;
  }
}

/// Reverse-geocodes coordinates down to a short "area, city" label. Returns
/// null if nothing resolvable was found.
Future<String?> labelForCoordinates(double latitude, double longitude) async {
  try {
    final placemarks = await Geocoding().placemarkFromCoordinates(latitude, longitude);
    if (placemarks.isEmpty) return null;

    final place = placemarks.first;
    final city = _firstNonEmpty([place.locality, place.subAdministrativeArea, place.administrativeArea]);
    final area = _firstNonEmpty([place.subLocality, place.thoroughfare]);

    if (area != null && city != null && area != city) return '$area, $city';
    return city ?? area;
  } catch (_) {
    return null;
  }
}

/// Fetches the device's current position and reverse-geocodes it in one go.
Future<String?> fetchLocationLabel() async {
  final position = await fetchCurrentPosition();
  if (position == null) return null;
  return labelForCoordinates(position.latitude, position.longitude);
}

String? _firstNonEmpty(List<String?> values) {
  for (final value in values) {
    if (value != null && value.trim().isNotEmpty) return value.trim();
  }
  return null;
}
