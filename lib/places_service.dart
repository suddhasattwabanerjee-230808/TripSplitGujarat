import 'dart:convert';

import 'package:http/http.dart' as http;

import 'env.dart';

/// Thin client for Google's Places API (New) REST endpoints
/// (places.googleapis.com/v1), called directly instead of through a native
/// SDK plugin. The X-Android-Package/X-Android-Cert headers are what let an
/// Android-app-restricted API key work over plain REST — Google checks them
/// against the key's restriction instead of requiring the native SDK.
const _androidPackageName = 'com.example.trip_split_gujarat';
const _androidCertSha1 = '89FF0CCFFCE83A87EF315F28ACB3DAB12F6F8696';

Map<String, String> get _headers => {
  'Content-Type': 'application/json',
  'X-Goog-Api-Key': googleMapsApiKey,
  'X-Android-Package': _androidPackageName,
  'X-Android-Cert': _androidCertSha1,
};

class PlaceSuggestion {
  const PlaceSuggestion({
    required this.placeId,
    required this.mainText,
    required this.secondaryText,
  });
  final String placeId;
  final String mainText;
  final String secondaryText;
}

class PlaceLocation {
  const PlaceLocation({
    required this.latitude,
    required this.longitude,
    required this.label,
  });
  final double latitude;
  final double longitude;
  final String label;
}

/// Autocomplete suggestions for [query], biased towards [originLat]/[originLng]
/// if given. Returns an empty list on any failure.
Future<List<PlaceSuggestion>> autocompletePlaces(
  String query, {
  double? originLat,
  double? originLng,
}) async {
  try {
    final response = await http
        .post(
          Uri.https('places.googleapis.com', '/v1/places:autocomplete'),
          headers: _headers,
          body: jsonEncode({
            'input': query,
            if (originLat != null && originLng != null)
              'locationBias': {
                'circle': {
                  'center': {'latitude': originLat, 'longitude': originLng},
                  'radius': 50000.0,
                },
              },
          }),
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return [];
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final suggestions = body['suggestions'] as List<dynamic>? ?? [];
    return suggestions
        .map((item) => (item as Map<String, dynamic>)['placePrediction'] as Map<String, dynamic>?)
        .whereType<Map<String, dynamic>>()
        .map((prediction) {
          final structured = prediction['structuredFormat'] as Map<String, dynamic>?;
          final mainText = (structured?['mainText'] as Map<String, dynamic>?)?['text'] as String?;
          final secondaryText = (structured?['secondaryText'] as Map<String, dynamic>?)?['text'] as String?;
          final fullText = (prediction['text'] as Map<String, dynamic>?)?['text'] as String?;
          return PlaceSuggestion(
            placeId: prediction['placeId'] as String,
            mainText: mainText ?? fullText ?? '',
            secondaryText: secondaryText ?? '',
          );
        })
        .toList();
  } catch (_) {
    return [];
  }
}

/// Fetches a place's coordinates and builds a short "name, city" label.
/// Returns null on any failure.
Future<PlaceLocation?> fetchPlaceLocation(String placeId) async {
  try {
    final response = await http
        .get(
          Uri.https('places.googleapis.com', '/v1/places/$placeId'),
          headers: {
            ..._headers,
            'X-Goog-FieldMask': 'location,formattedAddress,displayName,addressComponents',
          },
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return null;
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final location = body['location'] as Map<String, dynamic>?;
    if (location == null) return null;

    final name = (body['displayName'] as Map<String, dynamic>?)?['text'] as String?;
    final address = body['formattedAddress'] as String?;
    final city = _cityFromAddressComponents(body['addressComponents'] as List<dynamic>?);

    String label;
    if (name != null && city != null && name != city) {
      label = '$name, $city';
    } else {
      label = name ?? city ?? address ?? 'Unknown location';
    }

    return PlaceLocation(
      latitude: (location['latitude'] as num).toDouble(),
      longitude: (location['longitude'] as num).toDouble(),
      label: label,
    );
  } catch (_) {
    return null;
  }
}

/// Picks out the city from a Places (New) `addressComponents` list, in
/// order of specificity (locality is the usual "city" level; the others are
/// fallbacks for places Google doesn't tag with a locality).
String? _cityFromAddressComponents(List<dynamic>? components) {
  if (components == null) return null;
  const preferredTypes = ['locality', 'postal_town', 'administrative_area_level_2', 'administrative_area_level_1'];
  for (final type in preferredTypes) {
    for (final component in components) {
      final map = component as Map<String, dynamic>;
      final types = (map['types'] as List<dynamic>?)?.cast<String>() ?? [];
      if (types.contains(type)) return map['longText'] as String?;
    }
  }
  return null;
}
