import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

/// Fetches the device's current GPS position and reverse-geocodes it down
/// to a short "area, city" label. Returns null if location is unavailable,
/// permission was refused, or anything along the way fails — callers should
/// treat that as "no location for this expense" rather than an error.
Future<String?> fetchLocationLabel() async {
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

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: Duration(seconds: 12),
      ),
    );

    final placemarks = await Geocoding().placemarkFromCoordinates(
      position.latitude,
      position.longitude,
    );
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

String? _firstNonEmpty(List<String?> values) {
  for (final value in values) {
    if (value != null && value.trim().isNotEmpty) return value.trim();
  }
  return null;
}
