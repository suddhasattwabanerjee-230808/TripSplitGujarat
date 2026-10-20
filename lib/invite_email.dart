import 'package:flutter/services.dart';

import 'models.dart';
import 'update_service.dart';

/// Invites someone to a trip by email. There's no mail server: this opens the
/// user's own email app with the invite filled in, and they tap Send. Before
/// that the app leaves a note for the address (ApiClient.inviteByEmail), so
/// signing in with it adds them to the trip: no code anywhere.
class InviteEmail {
  static const _channel = MethodChannel('tripsplit/email');

  static final _address = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  static bool isValidAddress(String text) => _address.hasMatch(text.trim());

  static String subject(Trip trip, String inviter) => '$inviter invited you to “${trip.name}” on TripSplit';

  static String body(Trip trip, String inviter, {required String to}) => '''Hi,

$inviter is splitting the expenses for “${trip.name}” on TripSplit and has added you to the trip.

1. Tap to download the app (Android): ${UpdateService.apkUrl}
2. Open the downloaded file to install it. If your phone asks, allow installs from your browser or Files app. If Google Play Protect warns you, tap “More details” → “Install anyway”.
3. Open TripSplit and sign in with Google using ${to.trim()}

That's it: you'll land straight in “${trip.name}”.

See you on the trip!''';

  /// Opens the email app addressed to [to]. Returns false if there's no email app.
  static Future<bool> compose({
    required String to,
    required Trip trip,
    required String inviter,
  }) async {
    try {
      await _channel.invokeMethod<void>('compose', {
        'to': to.trim(),
        'subject': subject(trip, inviter),
        'body': body(trip, inviter, to: to),
      });
      return true;
    } on PlatformException catch (e) {
      if (e.code == 'no_email_app') return false;
      rethrow;
    }
  }
}
