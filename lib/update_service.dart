import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// Metadata for a release published on the backend's /releases endpoints.
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

/// Checks the TripSplit backend for a newer APK build and installs it
/// in-place, without going through the Play Store. The backend is the same
/// server the app's API already talks to (see api_client.dart) — it just
/// also serves whatever APK was last pushed to its /releases/publish
/// endpoint.
class UpdateService {
  UpdateService._();

  static const _baseUrl = 'https://nav-server.tail85596c.ts.net';

  // Over a Tailscale Funnel on a mobile connection, a transfer can silently
  // stall (no error, no more bytes) instead of failing outright. Without a
  // watchdog that looks exactly like the app "hanging" at some percentage.
  static const _stallTimeout = Duration(seconds: 12);
  static const _maxAttempts = 5;

  /// Returns update info if the server has a build newer than the one
  /// currently installed, or null if up to date / unreachable.
  static Future<UpdateInfo?> checkForUpdate() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/releases/latest'))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;

      final info = UpdateInfo.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
      final current = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(current.buildNumber) ?? 0;
      return info.versionCode > currentBuild ? info : null;
    } catch (_) {
      return null;
    }
  }

  /// Downloads the latest APK, reporting progress in [0, 1], then opens it
  /// so the system installer takes over. Resumes a partial download (via
  /// HTTP Range) and retries through stalls/drops instead of restarting
  /// from zero each time. Throws on failure after exhausting retries.
  static Future<void> downloadAndInstall(
    UpdateInfo info,
    void Function(double progress) onProgress,
  ) async {
    final dir = await getTemporaryDirectory();
    // Keyed by version so a partial download from a prior attempt at the
    // same release can be resumed, but a stale file from a different
    // release never gets mistaken for one.
    final file = File('${dir.path}/trip_split_update_${info.versionCode}.apk');

    Object? lastError;
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        await _downloadOnce(file, onProgress);
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

    final result = await OpenFilex.open(file.path);
    if (result.type != ResultType.done) {
      throw Exception(result.message);
    }
  }

  /// One attempt: resumes [file] from its current length if it's non-empty,
  /// aborts (to be retried) if no bytes arrive for [_stallTimeout].
  static Future<void> _downloadOnce(
    File file,
    void Function(double progress) onProgress,
  ) async {
    final existing = await file.exists() ? await file.length() : 0;

    final request = http.Request('GET', Uri.parse('$_baseUrl/releases/download'));
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
      } else if (streamed.statusCode == 200) {
        // Server didn't honor the Range request (or this is the first
        // attempt) — start over from scratch rather than appending onto
        // data that no longer lines up.
        received = 0;
        total = streamed.contentLength ?? 0;
      } else {
        throw Exception('Download failed (${streamed.statusCode})');
      }

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
