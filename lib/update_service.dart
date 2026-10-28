import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Metadata for a release: latest.json in the public TripSplit-releases repo.
class UpdateInfo {
  UpdateInfo({required this.versionCode, required this.versionName, required this.notes});

  factory UpdateInfo.fromJson(Map<String, dynamic> json) => UpdateInfo(
    versionCode: json['versionCode'] as int,
    versionName: json['versionName'] as String,
    notes: (json['notes'] as String?) ?? '',
  );

  final int versionCode;
  final String versionName;
  final String notes;
}

/// Checks for a newer APK build and installs it in-place, without going
/// through the Play Store or the system's "Install?" screen (see
/// AppUpdater.kt). Releases are published by CI to a public GitHub repo
/// that holds nothing but the APK and its latest.json.
class UpdateService {
  UpdateService._();

  static const _releases = 'https://github.com/suddhasattwabanerjee-230808/TripSplit-releases/releases/latest/download';

  /// Always the newest APK; also the link invite emails send people to.
  static const apkUrl = '$_releases/TripSplit.apk';

  // On a mobile connection a transfer can silently stall (no error, no more
  // bytes) instead of failing outright. Without a watchdog that looks
  // exactly like the app "hanging" at some percentage.
  static const _stallTimeout = Duration(seconds: 12);
  static const _maxAttempts = 5;

  static const _channel = MethodChannel('tripsplit/updater');

  // Shares of the single progress bar: the download dominates; handing the
  // APK to the installer is quick; then Android installs with no progress
  // reporting, so the bar creeps through the rest until the app restarts.
  static const _downloadShare = 0.85;
  static const _stagingShare = 0.08;

  /// Downloads the latest APK and installs it, reporting one combined
  /// progress value in [0, 1] and whether the install phase has begun.
  /// Resumes a partial download (via HTTP Range) and retries through
  /// stalls/drops instead of restarting from zero each time. On success
  /// Android replaces the running app and the new version opens, so this
  /// only ever returns by throwing.
  static Future<void> downloadAndInstall(
    UpdateInfo info,
    void Function(double progress, bool installing) onProgress, {
    void Function(int bytes)? onSize,
  }) async {
    final dir = await getTemporaryDirectory();
    // Keyed by version so a partial download from a prior attempt at the
    // same release can be resumed, but a stale file from a different
    // release never gets mistaken for one.
    final file = File('${dir.path}/trip_split_update_${info.versionCode}.apk');

    Object? lastError;
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        await _downloadOnce(file, (p) => onProgress(p * _downloadShare, false), onSize);
        lastError = null;
        break;
      } catch (e) {
        lastError = e;
        if (attempt < _maxAttempts) {
          await Future.delayed(Duration(seconds: attempt * 2));
        }
      }
    }
    if (lastError != null) throw lastError;

    var progress = _downloadShare;
    onProgress(progress, true);
    Timer? creep;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'installProgress') return;
      final staged = (call.arguments as num).toDouble();
      progress = _downloadShare + staged * _stagingShare;
      onProgress(progress, true);
      if (staged >= 1) {
        // Approach, never reach, 100% while Android installs.
        creep ??= Timer.periodic(const Duration(milliseconds: 250), (_) {
          progress += (0.99 - progress) * 0.04;
          onProgress(progress, true);
        });
      }
    });
    try {
      await _channel.invokeMethod<void>('install', {'path': file.path});
    } on PlatformException catch (e) {
      throw Exception(e.message ?? e.code);
    } finally {
      creep?.cancel();
      _channel.setMethodCallHandler(null);
    }
  }

  /// One attempt: resumes [file] from its current length if it's non-empty,
  /// aborts (to be retried) if no bytes arrive for [_stallTimeout].
  static Future<void> _downloadOnce(
    File file,
    void Function(double progress) onProgress,
    void Function(int bytes)? onSize,
  ) async {
    final existing = await file.exists() ? await file.length() : 0;

    final request = http.Request('GET', Uri.parse(apkUrl));
    if (existing > 0) {
      request.headers['Range'] = 'bytes=$existing-';
    }

    final client = http.Client();
    try {
      final streamed = await client.send(request);

      int received;
      int total;
      final bool resumed = streamed.statusCode == 206;
      if (resumed) {
        received = existing;
        final range = streamed.headers['content-range'];
        total = int.tryParse(range?.split('/').last ?? '') ??
            (existing + (streamed.contentLength ?? 0));
      } else if (streamed.statusCode == 416 && existing > 0) {
        // Nothing left to send: the file is already complete (e.g. a retry
        // after a cancelled install) — unless the server's copy changed size.
        await streamed.stream.drain<void>();
        final size = int.tryParse(streamed.headers['content-range']?.split('/').last ?? '');
        if (size == existing) {
          onProgress(1);
          return;
        }
        await file.delete();
        throw Exception('Stale partial download discarded');
      } else if (streamed.statusCode == 200) {
        // Server didn't honor the Range request (or this is the first
        // attempt) — start over from scratch rather than appending onto
        // data that no longer lines up.
        received = 0;
        total = streamed.contentLength ?? 0;
      } else {
        throw Exception('Download failed (${streamed.statusCode})');
      }

      if (total > 0) onSize?.call(total);
      final sink = file.openWrite(mode: resumed ? FileMode.append : FileMode.write);
      final completer = Completer<void>();
      Timer? stallTimer;
      StreamSubscription<List<int>>? sub;

      void armStallTimer() {
        stallTimer?.cancel();
        stallTimer = Timer(_stallTimeout, () {
          sub?.cancel();
          if (!completer.isCompleted) {
            completer.completeError(
              TimeoutException('Download stalled — no data for ${_stallTimeout.inSeconds}s'),
            );
          }
        });
      }

      armStallTimer();
      sub = streamed.stream.listen(
        (chunk) {
          armStallTimer();
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) onProgress(received / total);
        },
        onDone: () {
          stallTimer?.cancel();
          if (!completer.isCompleted) completer.complete();
        },
        onError: (Object e) {
          stallTimer?.cancel();
          if (!completer.isCompleted) completer.completeError(e);
        },
        cancelOnError: true,
      );

      try {
        await completer.future;
      } finally {
        stallTimer?.cancel();
        await sink.close();
      }

      if (total > 0 && received < total) {
        throw Exception('Download incomplete ($received of $total bytes)');
      }
    } finally {
      client.close();
    }
  }
}

/// The app's updates, for the screens: the check at launch (if switched on),
/// what's available, and the download's progress. Screens listen to it for
/// the "new version" banner, the dot on the profile and the update sheet.
class Updates extends ChangeNotifier {
  Updates._();
  static final instance = Updates._();
  static const _atLaunchKey = 'trip_split.check_updates_at_launch.v1';

  /// The installed version ("1.11.0").
  String current = '';
  UpdateInfo? latest; // set when it's newer than this build
  bool checking = false;
  bool checkFailed = false;
  double? progress; // 0..1 while updating
  bool installing = false;
  int? apkBytes; // the download's size, once known
  String? error;

  /// Check for a new version every time the app opens.
  bool atLaunch = true;

  bool get available => latest != null;

  /// Reads the setting, then checks if it's on.
  ///
  /// APK sideload updates only make sense on Android; on other platforms
  /// `check()` would still report a "newer" build (latest.json is
  /// platform-agnostic) but `downloadAndInstall` would then fail, since it
  /// calls the Android-only `MethodChannel('tripsplit/updater')`.
  Future<void> launchCheck() async {
    if (!Platform.isAndroid) return;
    atLaunch = await SharedPreferencesAsync().getBool(_atLaunchKey).catchError((Object _) => null) ?? true;
    notifyListeners();
    if (atLaunch) await check();
  }

  Future<void> setAtLaunch(bool on) async {
    atLaunch = on;
    notifyListeners();
    await SharedPreferencesAsync().setBool(_atLaunchKey, on).catchError((Object _) {});
  }

  Future<void> check() async {
    if (checking) return;
    checking = true;
    checkFailed = false;
    notifyListeners();
    try {
      current = (await PackageInfo.fromPlatform()).version;
      final response = await http.get(Uri.parse('${UpdateService._releases}/latest.json')).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) throw HttpException('${response.statusCode}');
      final info = UpdateInfo.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
      final build = int.tryParse((await PackageInfo.fromPlatform()).buildNumber) ?? 0;
      latest = info.versionCode > build ? info : null;
    } catch (_) {
      checkFailed = true;
    } finally {
      checking = false;
      notifyListeners();
    }
  }

  /// Downloads and installs [latest]; on success Android replaces the app and
  /// it reopens on the new version, so this only returns on failure.
  Future<void> install() async {
    final info = latest;
    if (info == null || progress != null) return;
    progress = 0;
    installing = false;
    error = null;
    notifyListeners();
    try {
      await UpdateService.downloadAndInstall(
        info,
        (p, installing) {
          progress = p;
          this.installing = installing;
          notifyListeners();
        },
        onSize: (bytes) {
          apkBytes = bytes;
          notifyListeners();
        },
      );
    } catch (e) {
      error = '$e'.replaceFirst('Exception: ', '');
    } finally {
      progress = null;
      installing = false;
      notifyListeners();
    }
  }
}
