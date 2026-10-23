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
  static const _recheck = Duration(minutes: 20);
  static const _agent = 'TripSplit/1.12 (Android app; city header photo)';

  String? city;
  ImageProvider? image;
  bool _started = false;
  bool _busy = false;

  /// Shows the saved photo at once, then checks where the phone is now.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      city = await SharedPreferencesAsync().getString(_cityKey);
      final file = await _file(city);
      if (city != null && await file.exists()) {
        image = ResizeImage(FileImage(file), width: 1400);
        notifyListeners();
      }
    } catch (_) {}
    await check();
  }

  /// Looks again (back in the app, say) if it's been a while, or if there's
  /// no photo yet.
  Future<void> check() async {
    if (!_started || _busy) return;
    _busy = true;
    try {
      final checked = await SharedPreferencesAsync().getInt(_checkedKey) ?? 0;
      if (image == null || DateTime.now().millisecondsSinceEpoch - checked > _recheck.inMilliseconds) {
        await _refresh();
      }
    } catch (_) {
      // Offline, no location: the saved photo (or the brand gradient) stays.
    } finally {
      _busy = false;
    }
  }

  /// One file per city: a new path is a new image, never the old city's
  /// pixels still held by the image cache.
  static Future<File> _file(String? city) async {
    final slug = (city ?? '').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    return File('${(await getApplicationSupportDirectory()).path}/city_photo_$slug.jpg');
  }

  Future<void> _refresh() async {
    final names = await _currentPlaceNames();
    if (names.isEmpty) return;
    final prefs = SharedPreferencesAsync();
    await prefs.setInt(_checkedKey, DateTime.now().millisecondsSinceEpoch);
    if (names.contains(city) && image != null) return;
    // The town, else its district, else its state: whichever has a photo.
    for (final here in names) {
      final url = await _photoUrl(here);
      if (url == null) continue;
      final response = await http
          .get(Uri.parse(url), headers: {'User-Agent': _agent})
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200 || response.bodyBytes.length < 10000) continue;
      final file = await _file(here);
      await file.writeAsBytes(response.bodyBytes, flush: true);
      await prefs.setString(_cityKey, here);
      city = here;
      image = ResizeImage(FileImage(file), width: 1400);
      notifyListeners();
      await _deleteOthers(file);
      return;
    }
  }

  /// Earlier cities' photos (and the old single city_photo.jpg).
  static Future<void> _deleteOthers(File keep) async {
    try {
      await for (final entry in keep.parent.list()) {
        final name = entry.uri.pathSegments.last;
        if (entry is File && name.startsWith('city_photo') && entry.path != keep.path) await entry.delete();
      }
    } catch (_) {}
  }

  /// Where the phone is: town, district, state (no repeats). A fresh coarse
  /// fix (network, quick), else the last known position. Asks for location
  /// once if it never has.
  static Future<List<String>> _currentPlaceNames() async {
    if (!await Geolocator.isLocationServiceEnabled()) return const [];
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return const [];
    Position? position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 15)),
      );
    } catch (_) {
      position = await Geolocator.getLastKnownPosition();
    }
    if (position == null) return const [];
    final places = await Geocoding().placemarkFromCoordinates(position.latitude, position.longitude);
    if (places.isEmpty) return const [];
    final p = places.first;
    final names = <String>[];
    for (final name in [p.locality, p.subAdministrativeArea, p.administrativeArea]) {
      final n = name?.trim() ?? '';
      if (n.isNotEmpty && !names.contains(n)) names.add(n);
    }
    return names;
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
