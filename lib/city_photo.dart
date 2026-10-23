import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme.dart';

/// Photos of the city the phone is in (landmarks from its Wikivoyage and
/// Wikipedia articles), behind the profile header and the trip card. A new
/// photo of the same city every half hour; a new city when the phone moves.
class CityPhoto extends ChangeNotifier {
  CityPhoto._();
  static final instance = CityPhoto._();

  static const _cityKey = 'trip_split.city_photo.city.v1';
  static const _urlsKey = 'trip_split.city_photo.urls.v1';
  static const _indexKey = 'trip_split.city_photo.index.v1';
  static const _shownKey = 'trip_split.city_photo.shown.v1';
  static const _every = Duration(minutes: 30);
  static const _agent = 'TripSplit/1.12 (Android app; city header photo)';

  String? city;
  ImageProvider? image;
  bool _started = false;
  bool _busy = false;
  bool _askedLocation = false;
  DateTime? _lastTry;

  /// Shows the saved photo at once, then checks where the phone is now, and
  /// every minute after that while TripSplit is on screen.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      final prefs = SharedPreferencesAsync();
      city = await prefs.getString(_cityKey);
      final file = await _file(city, await prefs.getInt(_indexKey) ?? 0);
      if (city != null && await file.exists()) {
        image = ResizeImage(FileImage(file), width: 1400);
        notifyListeners();
      }
    } catch (_) {}
    Timer.periodic(const Duration(minutes: 1), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) check();
    });
    await check();
  }

  /// The next photo, if the current one has been up half an hour (or there
  /// is none yet). Cheap when nothing's due.
  Future<void> check() async {
    if (!_started || _busy) return;
    // Offline or no location: don't retry more than every few minutes.
    final last = _lastTry;
    if (last != null && DateTime.now().difference(last) < const Duration(minutes: 5)) return;
    _busy = true;
    try {
      final shown = await SharedPreferencesAsync().getInt(_shownKey) ?? 0;
      if (image == null || DateTime.now().millisecondsSinceEpoch - shown >= _every.inMilliseconds) {
        _lastTry = DateTime.now();
        await _refresh();
      }
    } catch (_) {
      // The saved photo (or the brand gradient) stays.
    } finally {
      _busy = false;
    }
  }

  /// One file per city and photo: a new path is a new image, never the old
  /// pixels still held by the image cache.
  static Future<File> _file(String? city, int index) async {
    final slug = (city ?? '').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    return File('${(await getApplicationSupportDirectory()).path}/city_photo_${slug}_$index.jpg');
  }

  Future<void> _refresh() async {
    final names = await _currentPlaceNames().catchError((Object _) => <String>[]);
    final current = city;
    // Same city (or location unknown): its next photo.
    if (current != null && (names.isEmpty || names.contains(current))) {
      final prefs = SharedPreferencesAsync();
      final saved = jsonDecode(await prefs.getString(_urlsKey) ?? '{}') as Map;
      var urls = saved['city'] == current ? (saved['urls'] as List).cast<String>() : <String>[];
      if (urls.isEmpty) urls = await _photoUrls(current);
      if (urls.isEmpty) return;
      final index = await prefs.getInt(_indexKey) ?? 0;
      await _show(current, urls, image == null ? index : index + 1);
      return;
    }
    // A new city: the town, else its district, else its state.
    for (final here in names) {
      final urls = await _photoUrls(here);
      if (urls.isNotEmpty && await _show(here, urls, 0)) return;
    }
  }

  /// Downloads photo [from] of [urls] (or the next one that works) and puts
  /// it up.
  Future<bool> _show(String here, List<String> urls, int from) async {
    for (var i = 0; i < urls.length; i++) {
      final index = (from + i) % urls.length;
      try {
        final response = await http
            .get(Uri.parse(urls[index]), headers: {'User-Agent': _agent})
            .timeout(const Duration(seconds: 30));
        if (response.statusCode != 200 || response.bodyBytes.length < 10000) continue;
        final file = await _file(here, index);
        await file.writeAsBytes(response.bodyBytes, flush: true);
        final prefs = SharedPreferencesAsync();
        await prefs.setString(_cityKey, here);
        await prefs.setString(_urlsKey, jsonEncode({'city': here, 'urls': urls}));
        await prefs.setInt(_indexKey, index);
        await prefs.setInt(_shownKey, DateTime.now().millisecondsSinceEpoch);
        city = here;
        image = ResizeImage(FileImage(file), width: 1400);
        notifyListeners();
        await _deleteOthers(file);
        return true;
      } catch (_) {
        // Try the next photo.
      }
    }
    return false;
  }

  /// Earlier photos (and the old single city_photo.jpg).
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
  /// once per launch at most.
  Future<List<String>> _currentPlaceNames() async {
    if (!await Geolocator.isLocationServiceEnabled()) return const [];
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied && !_askedLocation) {
      _askedLocation = true;
      permission = await Geolocator.requestPermission();
    }
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

  /// [city]'s photos: the lead photos of its travel guide (Wikivoyage) and
  /// encyclopedia article first, then the other photos in them. Only wide,
  /// sharp JPEGs that aren't maps or collages; at most 12.
  static Future<List<String>> _photoUrls(String city) async {
    final lead = <String, String>{};
    final rest = <String, String>{};
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
          final name = (page['pageimage'] as String? ?? '').toLowerCase().replaceAll(' ', '_');
          final w = (original?['width'] as num?)?.toDouble() ?? 0;
          final h = (original?['height'] as num?)?.toDouble() ?? 1;
          if (thumb == null || w < 1000 || w / h < 1.15) continue;
          if (_notAPhoto.hasMatch(name)) continue;
          lead.putIfAbsent(name, () => thumb);
        }
      } catch (_) {
        // Try the next source.
      }
      try {
        final uri = Uri.https(host, '/w/api.php', {
          'action': 'query',
          'format': 'json',
          'redirects': '1',
          'generator': 'images',
          'gimlimit': '50',
          'prop': 'imageinfo',
          'iiprop': 'url|size|mime',
          'iiurlwidth': '1600',
          'titles': city,
        });
        final response = await http.get(uri, headers: {'User-Agent': _agent}).timeout(const Duration(seconds: 15));
        if (response.statusCode != 200) continue;
        final pages = (jsonDecode(response.body)['query']?['pages'] as Map?)?.values ?? const [];
        for (final page in pages.cast<Map<String, dynamic>>()) {
          final info = (page['imageinfo'] as List?)?.firstOrNull as Map?;
          final name = (page['title'] as String? ?? '').replaceFirst('File:', '').toLowerCase().replaceAll(' ', '_');
          final url = (info?['thumburl'] ?? info?['url']) as String?;
          final w = (info?['width'] as num?)?.toDouble() ?? 0;
          final h = (info?['height'] as num?)?.toDouble() ?? 1;
          if (url == null || info?['mime'] != 'image/jpeg' || w < 1000 || w / h < 1.15) continue;
          if (_notAPhoto.hasMatch(name)) continue;
          rest.putIfAbsent(name, () => url);
        }
      } catch (_) {
        // Try the next source.
      }
    }
    for (final name in lead.keys) {
      rest.remove(name);
    }
    return [...lead.values, ...rest.values].take(12).toList();
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
