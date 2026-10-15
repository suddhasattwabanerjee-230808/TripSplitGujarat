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
  /// so the system installer takes over. Throws on failure.
  static Future<void> downloadAndInstall(void Function(double progress) onProgress) async {
    final request = http.Request('GET', Uri.parse('$_baseUrl/releases/download'));
    final streamed = await http.Client().send(request);
    if (streamed.statusCode != 200) {
      throw Exception('Download failed (${streamed.statusCode})');
    }

    final total = streamed.contentLength ?? 0;
    var received = 0;
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/trip_split_update.apk');
    final sink = file.openWrite();

    await streamed.stream
        .map((chunk) {
          received += chunk.length;
          if (total > 0) onProgress(received / total);
          return chunk;
        })
        .pipe(sink);
    await sink.close();

    final result = await OpenFilex.open(file.path);
    if (result.type != ResultType.done) {
      throw Exception(result.message);
    }
  }
}
