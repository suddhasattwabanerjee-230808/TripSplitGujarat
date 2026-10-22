import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme.dart';

/// A photo of the city the phone is in (a landmark from its Wikivoyage or
/// Wikipedia article), behind the profile header and the trip card. Kept on
/// the phone and looked up again only when the city changes.
class CityPhoto extends ChangeNotifier {
  CityPhoto._();
  static final instance = CityPhoto._();

  static const _cityKey = 'trip_split.city_photo.city.v1';
  static const _checkedKey = 'trip_split.city_photo.checked.v1';
  static const _recheck = Duration(hours: 3);
  static const _agent = 'TripSplit/1.12 (Android app; city header photo)';

  String? city;
  ImageProvider? image;
  bool _started = false;

  /// Shows the saved photo at once, then checks where the phone is now.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    final prefs = SharedPreferencesAsync();
    try {
      city = await prefs.getString(_cityKey);
      final file = await _file();
      if (city != null && await file.exists()) {
        image = ResizeImage(FileImage(file), width: 1400);
        notifyListeners();
      }
      final checked = await prefs.getInt(_checkedKey) ?? 0;
      if (image == null || DateTime.now().millisecondsSinceEpoch - checked > _recheck.inMilliseconds) {
        await _refresh();
      }
    } catch (_) {
      // Offline, no location: the brand gradient shows instead.
    }
  }

  Future<File> _file() async => File('${(await getApplicationSupportDirectory()).path}/city_photo.jpg');

  Future<void> _refresh() async {
    final here = await _currentCity();
    if (here == null) return;
    final prefs = SharedPreferencesAsync();
    await prefs.setInt(_checkedKey, DateTime.now().millisecondsSinceEpoch);
    if (here == city && image != null) return;
    final url = await _photoUrl(here);
    if (url == null) return;
    final response = await http
        .get(Uri.parse(url), headers: {'User-Agent': _agent})
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200 || response.bodyBytes.length < 10000) return;
    final file = await _file();
    await file.writeAsBytes(response.bodyBytes, flush: true);
    await prefs.setString(_cityKey, here);
    // A fresh provider: the old one's cached pixels are the old city.
    PaintingBinding.instance.imageCache.clear();
    city = here;
    image = ResizeImage(FileImage(file), width: 1400);
    notifyListeners();
  }

  /// The phone's city, from its last known position if there is one (fast,
  /// no GPS), else a coarse fix. Asks for location once if it never has.
  static Future<String?> _currentCity() async {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return null;
    final position =
        await Geolocator.getLastKnownPosition() ??
        await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 15)),
        );
    final places = await Geocoding().placemarkFromCoordinates(position.latitude, position.longitude);
    if (places.isEmpty) return null;
    final p = places.first;
    for (final name in [p.locality, p.subAdministrativeArea, p.administrativeArea]) {
      if (name != null && name.trim().isNotEmpty) return name.trim();
    }
    return null;
  }

  static final _notAPhoto = RegExp(r'montage|collage|collection|map|flag|seal|emblem|logo|locator|\.svg|\.png$');

  /// The lead photo of [city]'s travel guide (Wikivoyage), else of its
  /// encyclopedia article: wide, sharp enough for a header, not a collage.
  static Future<String?> _photoUrl(String city) async {
    for (final host in ['en.wikivoyage.org', 'en.wikipedia.org']) {
      try {
        final uri = Uri.https(host, '/w/api.php', {
          'action': 'query',
          'format': 'json',
          'redirects': '1',
          'prop': 'pageimages',
          'piprop': 'thumbnail|name|original',
          'pithumbsize': '1600',
          'titles': city,
        });
        final response = await http.get(uri, headers: {'User-Agent': _agent}).timeout(const Duration(seconds: 15));
        if (response.statusCode != 200) continue;
        final pages = (jsonDecode(response.body)['query']?['pages'] as Map?)?.values ?? const [];
        for (final page in pages.cast<Map<String, dynamic>>()) {
          final original = page['original'] as Map?;
          final thumb = page['thumbnail']?['source'] as String?;
          final name = (page['pageimage'] as String? ?? '').toLowerCase();
          final w = (original?['width'] as num?)?.toDouble() ?? 0;
          final h = (original?['height'] as num?)?.toDouble() ?? 1;
          if (thumb == null || w < 1000 || w / h < 1.15) continue;
          if (_notAPhoto.hasMatch(name)) continue;
          return thumb;
        }
      } catch (_) {
        // Try the next source.
      }
    }
    return null;
  }
}

/// The brand gradient with the city photo blended in: the photo washed in
/// wine and the logo's orange, darker where text sits, so it reads as one
/// surface. Without a photo it's the plain gradient. Its own layer, so a
/// scroll moves it without painting it again.
class CityBackdrop extends StatelessWidget {
  const CityBackdrop({super.key, required this.child, this.borderRadius = BorderRadius.zero, this.boxShadow});
  final Widget child;
  final BorderRadius borderRadius;
  final List<BoxShadow>? boxShadow;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: CityPhoto.instance,
    builder: (context, _) {
      final image = CityPhoto.instance.image;
      return RepaintBoundary(
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(gradient: brandGradient, borderRadius: borderRadius, boxShadow: boxShadow),
          child: Stack(
            children: [
              if (image != null) ...[
                Positioned.fill(
                  child: Image(
                    image: image,
                    fit: BoxFit.cover,
                    alignment: const Alignment(0, -.2),
                    gaplessPlayback: true,
                    // Fade the photo in over the gradient.
                    frameBuilder: (context, child, frame, sync) => AnimatedOpacity(
                      opacity: frame == null ? 0 : 1,
                      duration: sync ? Duration.zero : const Duration(milliseconds: 600),
                      curve: Curves.easeOut,
                      child: child,
                    ),
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
                // The brand wash: wine from the top left into the logo's orange.
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          wineDeep.withValues(alpha: .86),
                          wine.withValues(alpha: .52),
                          const Color(0xFFE0691A).withValues(alpha: .32),
                        ],
                        stops: const [0, .55, 1],
                      ),
                    ),
                  ),
                ),
                // Depth: darker towards the bottom, where the figures sit.
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [wineDeep.withValues(alpha: .1), wineDeep.withValues(alpha: .55)],
                      ),
                    ),
                  ),
                ),
              ],
              child,
            ],
          ),
        ),
      );
    },
  );
}
