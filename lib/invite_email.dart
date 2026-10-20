import 'package:flutter/services.dart';

import 'models.dart';
import 'update_service.dart';

/// Invites someone to a trip by email. There's no mail server: this opens the
/// user's own email app with the invite filled in, and they tap Send. The app
/// also leaves a note for the address (ApiClient.inviteByEmail), so signing in
/// with it joins the trip straight away; the code is the fallback.
class InviteEmail {
  static const _channel = MethodChannel('tripsplit/email');

  static final _address = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  static bool isValidAddress(String text) => _address.hasMatch(text.trim());

  static String subject(Trip trip, String inviter) => '$inviter invited you to “${trip.name}” on TripSplit';

  /// With [autoJoin] (the note for [to] was saved), signing in with [to] is
  /// all it takes; otherwise they type the code.
  static String body(Trip trip, String inviter, {required String to, bool autoJoin = true}) {
    final steps = autoJoin
        ? '''3. Open TripSplit and sign in with Google using this address: ${to.trim()}
   You'll be taken straight into “${trip.name}”. Nothing to type.

Using a different Google account? Tap “Join trip” and enter this invite code instead: ${trip.inviteCode}'''
        : '''3. Open TripSplit and sign in with your Google (Gmail) account.
4. Tap “Join trip” and enter this invite code: ${trip.inviteCode}''';
    return '''Hi,

$inviter is splitting the expenses for “${trip.name}” on TripSplit and has invited you to join.

1. Download the app (Android): ${UpdateService.apkUrl}
2. Open the downloaded file to install it. If your phone asks, allow installs from your browser or Files app. If Google Play Protect warns you, tap “More details” → “Install anyway”.
$steps

See you on the trip!''';
  }

  /// Opens the email app addressed to [to]. Returns false if there's no email app.
  static Future<bool> compose({
    required String to,
    required Trip trip,
    required String inviter,
    bool autoJoin = true,
  }) async {
    try {
      await _channel.invokeMethod<void>('compose', {
        'to': to.trim(),
        'subject': subject(trip, inviter),
        'body': body(trip, inviter, to: to, autoJoin: autoJoin),
      });
      return true;
    } on PlatformException catch (e) {
      if (e.code == 'no_email_app') return false;
      rethrow;
    }
  }
}
