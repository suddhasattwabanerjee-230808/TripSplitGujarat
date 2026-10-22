import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'expense_notifier.dart';
import 'theme.dart';

/// "UPI payment alerts": bank SMS debit alerts turned into "add to trip"
/// notifications (UpiSmsReceiver). One switch, shown on the profile and as a
/// quick action on the trip page; listen to it for the current state. Also
/// says whether SMS access is there at all, which settle-up payment
/// detection needs too.
class UpiAlerts extends ChangeNotifier with WidgetsBindingObserver {
  UpiAlerts._() {
    WidgetsBinding.instance.addObserver(this);
    refresh();
  }
  static final instance = UpiAlerts._();
  static const _settings = MethodChannel('tripsplit/upi_settings');

  bool smsGranted = true;
  bool enabled = true; // the switch itself, kept natively for the receiver
  bool notificationsOn = true; // the profile's "All notifications"

  bool get on => smsGranted && enabled && notificationsOn;

  // Back from the Settings app, where SMS access may have just been allowed.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  Future<void> refresh() async {
    smsGranted = await Permission.sms.isGranted.catchError((Object _) => false);
    try {
      enabled = await _settings.invokeMethod<bool>('isEnabled') ?? true;
    } on Exception {
      enabled = true;
    }
    notificationsOn = await ExpenseNotifier.enabled();
    notifyListeners();
  }

  /// Switching on without SMS access runs the set-up (asking, then the
  /// restricted-settings steps if Android refused); the state reads on only
  /// once access is granted. Switching off keeps the permission and just
  /// silences the alerts in the native receiver.
  Future<void> set(BuildContext context, bool value) async {
    if (value && !notificationsOn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notifications are off. Turn on All Notifications in your profile first.')),
      );
      return;
    }
    enabled = value;
    notifyListeners();
    try {
      await _settings.invokeMethod<void>('setEnabled', value);
    } on Exception {
      // Stays as it was; the next refresh re-syncs.
    }
    if (value && !smsGranted && context.mounted) await askForSms(context);
    await refresh();
  }

  /// Asks for SMS access; when Android refuses it, spells out how to allow it.
  Future<void> askForSms(BuildContext context) async {
    final result = await [Permission.sms, Permission.notification].request();
    final sms = result[Permission.sms] ?? PermissionStatus.denied;
    // On a build installed from outside the Play Store, Play Protect treats SMS
    // as a restricted permission and auto-denies the request — the toggle in
    // Settings stays greyed out until the user turns on "Allow restricted
    // settings" first. A plain openAppSettings() drops them there with no clue
    // how to proceed, so when SMS didn't get granted we spell the steps out.
    if (!sms.isGranted && context.mounted) await _showSmsHelpDialog(context);
    await refresh();
  }

  Future<void> _showSmsHelpDialog(BuildContext context) => showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: paper,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        'Allow SMS Access',
        style: TextStyle(color: ink, fontWeight: FontWeight.w800, fontSize: 18),
      ),
      content: Text(
        'Because TripSplit is installed outside the Play Store, Android keeps '
        'SMS access switched off and greys out the toggle. Turn it on by hand:\n\n'
        '1.  Tap “Open settings” below.\n'
        '2.  On the App info screen, tap ⋮ in the top-right corner.\n'
        '3.  Choose “Allow restricted settings”.\n'
        '4.  Open Permissions → SMS → Allow.\n\n'
        'Then come back here — it switches on by itself once access is allowed.',
        style: TextStyle(color: ink, fontSize: 13.5, height: 1.45),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text('Not Now', style: TextStyle(color: muted)),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(ctx);
            openAppSettings();
          },
          style: FilledButton.styleFrom(
            backgroundColor: ink,
            foregroundColor: paper,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('Open Settings'),
        ),
      ],
    ),
  );
}
