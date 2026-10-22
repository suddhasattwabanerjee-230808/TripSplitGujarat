import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A typeface the app can be set in. All but Inter (built in) come from
/// Google Fonts (open licences) the first time they're picked, then stay on
/// the phone.
class AppFont {
  const AppFont(this.family, this.kind, this.note);
  final String family;
  final FontKind kind;
  final String note;
}

enum FontKind {
  sans('Sans Serif', 'Clean And Modern'),
  serif('Serif', 'Classic And Elegant'),
  rounded('Rounded', 'Soft And Friendly');

  const FontKind(this.title, this.subtitle);
  final String title, subtitle;
}

const builtInFont = 'Inter';

const appFonts = [
  AppFont('Inter', FontKind.sans, 'Closest To Apple’s San Francisco'),
  AppFont('Geist', FontKind.sans, 'Swiss-Style, Sharp And Modern'),
  AppFont('Manrope', FontKind.sans, 'Geometric, Wide And Calm'),
  AppFont('Plus Jakarta Sans', FontKind.sans, 'Modern Geometric, Soft Curves'),
  AppFont('DM Sans', FontKind.sans, 'Low-Contrast, Clean Geometric'),
  AppFont('Figtree', FontKind.sans, 'Friendly And Very Clear'),
  AppFont('Onest', FontKind.sans, 'Neutral Grotesque'),
  AppFont('Instrument Sans', FontKind.sans, 'Precise, Editorial Sans'),
  AppFont('Albert Sans', FontKind.sans, 'Scandinavian Geometric'),
  AppFont('Hanken Grotesk', FontKind.sans, 'Classic Grotesque'),
  AppFont('Schibsted Grotesk', FontKind.sans, 'Newspaper Grotesque'),
  AppFont('Outfit', FontKind.sans, 'Rounded Geometric'),
  AppFont('Urbanist', FontKind.sans, 'Minimal Geometric'),
  AppFont('Sora', FontKind.sans, 'Wide And Futuristic'),
  AppFont('Lexend', FontKind.sans, 'Built For Easy Reading'),
  AppFont('Poppins', FontKind.sans, 'Popular Geometric'),
  AppFont('Montserrat', FontKind.sans, 'Bold Urban Geometric'),
  AppFont('Jost', FontKind.sans, 'Futura-Style Geometric'),
  AppFont('Work Sans', FontKind.sans, 'Grotesque Made For Screens'),
  AppFont('IBM Plex Sans', FontKind.sans, 'Engineered Corporate Sans'),
  AppFont('Red Hat Display', FontKind.sans, 'Confident Display Sans'),
  AppFont('Space Grotesk', FontKind.sans, 'Quirky Tech Grotesque'),
  AppFont('Raleway', FontKind.sans, 'Elegant Display Sans'),
  AppFont('Josefin Sans', FontKind.sans, 'Vintage Geometric'),
  AppFont('Open Sans', FontKind.sans, 'Humanist Classic'),
  AppFont('Lato', FontKind.sans, 'Warm Humanist'),
  AppFont('Mulish', FontKind.sans, 'Minimalist Sans'),
  AppFont('Nunito Sans', FontKind.sans, 'Balanced Humanist'),
  AppFont('Rubik', FontKind.sans, 'Slightly Rounded Corners'),
  AppFont('Source Serif 4', FontKind.serif, 'Closest To Apple’s New York'),
  AppFont('Playfair Display', FontKind.serif, 'High-Contrast, Luxury Feel'),
  AppFont('Cormorant Garamond', FontKind.serif, 'Refined Garamond Display'),
  AppFont('Bodoni Moda', FontKind.serif, 'Fashion-Magazine Bodoni'),
  AppFont('Fraunces', FontKind.serif, 'Soft Old-Style Display'),
  AppFont('EB Garamond', FontKind.serif, 'Classic Book Garamond'),
  AppFont('Libre Baskerville', FontKind.serif, 'Traditional Baskerville'),
  AppFont('Lora', FontKind.serif, 'Calligraphic Contemporary'),
  AppFont('Crimson Pro', FontKind.serif, 'Elegant Book Serif'),
  AppFont('Newsreader', FontKind.serif, 'Editorial News Serif'),
  AppFont('Spectral', FontKind.serif, 'Screen-First Serif'),
  AppFont('Literata', FontKind.serif, 'Made For Long Reading'),
  AppFont('Merriweather', FontKind.serif, 'Sturdy And Readable'),
  AppFont('Cinzel', FontKind.serif, 'Roman Inscription Capitals'),
  AppFont('Nunito', FontKind.rounded, 'Rounded And Friendly'),
  AppFont('Quicksand', FontKind.rounded, 'Light Rounded Geometric'),
  AppFont('M PLUS Rounded 1c', FontKind.rounded, 'Soft Rounded Gothic'),
];

/// The app's typeface, bold text and text size, remembered on the phone.
/// Changing either redraws every screen in place (see main.dart).
class AppFonts extends ChangeNotifier {
  AppFonts._();
  static final instance = AppFonts._();

  static const _familyKey = 'trip_split.font_family.v1';
  static const _boldKey = 'trip_split.bold_text.v1';
  static const _scaleKey = 'trip_split.text_scale.v1';
  static const minScale = 0.85, maxScale = 1.3;
  static const _weights = [400, 500, 600, 700, 800];

  String family = builtInFont;
  bool bold = false;

  /// Text size, on top of the phone's own: 1 is as the phone has it.
  double scale = 1;

  /// Families on the phone (downloaded, or built in).
  final downloaded = <String>{builtInFont};

  /// The family being downloaded, and how far along (0..1).
  String? downloading;
  double progress = 0;

  final _loaded = <String>{builtInFont};

  /// Before the first frame: the saved choice, from the files on the phone.
  /// Falls back to Inter if they're gone.
  Future<void> load() async {
    try {
      final prefs = SharedPreferencesAsync();
      bold = await prefs.getBool(_boldKey) ?? false;
      scale = (await prefs.getDouble(_scaleKey) ?? 1).clamp(minScale, maxScale);
      final saved = await prefs.getString(_familyKey) ?? builtInFont;
      for (final font in appFonts) {
        if (await File('${(await _dir(font.family)).path}/400.ttf').exists()) downloaded.add(font.family);
      }
      if (saved != builtInFont && downloaded.contains(saved)) {
        await _register(saved);
        family = saved;
      }
    } catch (_) {
      family = builtInFont;
    }
  }

  Future<void> setScale(double value) async {
    final v = (value * 20).round() / 20; // steps of 5%
    if (v == scale) return;
    scale = v;
    notifyListeners();
    await SharedPreferencesAsync().setDouble(_scaleKey, v).catchError((Object _) {});
  }

  Future<void> setBold(bool on) async {
    bold = on;
    notifyListeners();
    await SharedPreferencesAsync().setBool(_boldKey, on).catchError((Object _) {});
  }

  /// Sets the app in [name], downloading it first if needed. Throws if the
  /// download fails (offline).
  Future<void> select(String name) async {
    if (downloading != null) return;
    if (!downloaded.contains(name)) {
      downloading = name;
      progress = 0;
      notifyListeners();
      try {
        await _download(name);
        downloaded.add(name);
      } finally {
        downloading = null;
        notifyListeners();
      }
    }
    await _register(name);
    family = name;
    notifyListeners();
    await SharedPreferencesAsync().setString(_familyKey, name).catchError((Object _) {});
  }

  static String _slug(String family) => family.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');

  Future<Directory> _dir(String name) async =>
      Directory('${(await getApplicationSupportDirectory()).path}/fonts/${_slug(name)}');

  /// Each weight the family has, as a static TTF (Google serves those to
  /// clients that don't ask for WOFF2); weights it doesn't have are skipped.
  Future<void> _download(String name) async {
    final dir = await _dir(name);
    await dir.create(recursive: true);
    final client = http.Client();
    var got = 0;
    try {
      for (final (i, w) in _weights.indexed) {
        final css = await client
            .get(Uri.parse('https://fonts.googleapis.com/css2?family=${Uri.encodeQueryComponent(name)}:wght@$w'))
            .timeout(const Duration(seconds: 20));
        final url = RegExp(r'url\((https://[^)]+\.ttf)\)').firstMatch(css.body)?.group(1);
        if (css.statusCode == 200 && url != null) {
          final font = await client.get(Uri.parse(url)).timeout(const Duration(seconds: 60));
          if (font.statusCode == 200) {
            await File('${dir.path}/$w.ttf').writeAsBytes(font.bodyBytes, flush: true);
            got++;
          }
        }
        progress = (i + 1) / _weights.length;
        notifyListeners();
      }
    } finally {
      client.close();
    }
    if (got == 0 || !await File('${dir.path}/400.ttf').exists()) {
      await dir.delete(recursive: true).catchError((Object _) => dir);
      throw const HttpException('Couldn’t download that font. Is the phone online?');
    }
  }

  /// Registers every font on the phone, so the picker can show each in its own face.
  Future<void> registerAll() async {
    for (final name in downloaded.toList()) {
      await _register(name).catchError((Object _) {});
    }
    notifyListeners();
  }

  /// Makes the family's files usable under its name (once per launch).
  Future<void> _register(String name) async {
    if (_loaded.contains(name)) return;
    final dir = await _dir(name);
    final loader = FontLoader(name);
    for (final w in _weights) {
      final file = File('${dir.path}/$w.ttf');
      if (await file.exists()) loader.addFont(file.readAsBytes().then(ByteData.sublistView));
    }
    await loader.load();
    _loaded.add(name);
  }
}
