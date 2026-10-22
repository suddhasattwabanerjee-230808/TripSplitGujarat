import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'app_resume.dart';
import 'expense_notifier.dart';
import 'theme.dart';

/// "UPI payment alerts": UPI payments made, turned into "add to trip"
/// notifications. They're spotted on GPay's and PhonePe's own success screen
/// (UpiScreenWatcher, an accessibility service: the one that doesn't depend
/// on anything being sent), in the bank's debit SMS (UpiSmsReceiver) or in
/// the notification GPay or PhonePe posts (UpiNotificationListener); any one
/// access is enough. One
/// switch, shown in App Settings and as a quick action on the trip page;
/// listen to it for the current state. Settle-up payment detection needs one
/// of the two accesses too.
class UpiAlerts extends ChangeNotifier with WidgetsBindingObserver {
  UpiAlerts._() {
    WidgetsBinding.instance.addObserver(this);
    refresh();
  }
  static final instance = UpiAlerts._();
  static const _settings = MethodChannel('tripsplit/upi_settings');

  bool smsGranted = true;
  bool listenerOn = false; // reading GPay's and PhonePe's notifications
  bool screensOn = false; // reading GPay's and PhonePe's success screens
  bool enabled = true; // the switch itself, kept natively for the receiver
  bool notificationsOn = true; // the profile's "All notifications"

  /// Payments can be spotted at all: screen, SMS or notification access.
  bool get canSpot => screensOn || smsGranted || listenerOn;

  bool get on => canSpot && enabled && notificationsOn;

  // Back from the Settings app, where access may have just been allowed.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  Future<void> refresh() async {
    smsGranted = await Permission.sms.isGranted.catchError((Object _) => false);
    try {
      enabled = await _settings.invokeMethod<bool>('isEnabled') ?? true;
      listenerOn = await _settings.invokeMethod<bool>('listenerOn') ?? false;
      screensOn = await _settings.invokeMethod<bool>('screensOn') ?? false;
    } on Exception {
      enabled = true;
    }
    notificationsOn = await ExpenseNotifier.enabled();
    notifyListeners();
  }

  /// Switching on without any access runs the set-up (payment screens or bank
  /// SMS, then the restricted-settings steps if Android refuses);
  /// the state reads on only once access is granted. Switching off keeps the permission and just
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
    if (value && !canSpot && context.mounted) await _chooseAccess(context);
    await refresh();
  }

  /// GPay's and PhonePe's success screens (works without any SMS or
  /// notification), or the bank's SMS.
  Future<void> _chooseAccess(BuildContext context) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: paper,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Spot Your UPI Payments',
          style: TextStyle(color: ink, fontWeight: FontWeight.w800, fontSize: 18),
        ),
        content: Text(
          'TripSplit can spot a payment on the “Payment successful” screen in GPay or '
          'PhonePe, so it works even when no SMS or notification comes. Or it can '
          'read your bank’s SMS.',
          style: TextStyle(color: ink, fontSize: 13.5, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'sms'),
            child: Text('Bank SMS', style: TextStyle(color: ink, fontWeight: FontWeight.w700)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'screens'),
            style: FilledButton.styleFrom(
              backgroundColor: ink,
              foregroundColor: paper,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Payment Screens'),
          ),
        ],
      ),
    );
    if (!context.mounted) return;
    if (choice == 'sms') {
      await askForSms(context);
    } else if (choice == 'screens') {
      await askForScreens(context);
    }
  }

  /// Accessibility access, limited to GPay and PhonePe, so their success
  /// screen can be read. Android has no prompt for it: the steps, then its
  /// Settings page.
  Future<void> askForScreens(BuildContext context) async {
    await Permission.notification.request();
    if (!context.mounted) return;
    await _showHelpDialog(
      context,
      title: 'Spot Payments On Screen',
      body:
          'TripSplit reads only GPay and PhonePe, and only to spot the “Payment '
          'successful” screen after you pay. Nothing it reads leaves your phone.\n\n'
          '1.  Tap “Open Settings” below.\n'
          '2.  Open “TripSplit Payment Detection” (it may be under Downloaded or '
          'Installed apps) and switch it on.\n'
          '3.  If Android says “Restricted setting”, open App Info for TripSplit, '
          'tap ⋮ in the top-right corner, choose “Allow restricted settings”, '
          'then try step 2 again.\n\n'
          'Then come back here — it switches on by itself once it’s allowed.',
      open: () => _settings.invokeMethod<bool>('openScreenSettings').catchError((Object _) => false),
      secondary: ('App Info', openAppSettings),
    );
    await refresh();
  }

  /// Notification access, so GPay's and PhonePe's "paid" notifications can be
  /// read. Android has no prompt for it: the steps, then its Settings page.
  Future<void> askForAppNotifications(BuildContext context) async {
    await Permission.notification.request();
    if (!context.mounted) return;
    await _showHelpDialog(
      context,
      title: 'Read GPay & PhonePe Alerts',
      body:
          'TripSplit only looks at notifications from GPay and PhonePe (and Paytm '
          'and BHIM), for the payments you make.\n\n'
          '1.  Tap “Open Settings” below and switch TripSplit on.\n'
          '2.  If Android says “Restricted setting”, open App Info for TripSplit, '
          'tap ⋮ in the top-right corner, choose “Allow restricted settings”, '
          'then try step 1 again.\n\n'
          'Then come back here — it switches on by itself once access is allowed.',
      open: () => _settings.invokeMethod<bool>('openListenerSettings').catchError((Object _) => false),
      secondary: ('App Info', openAppSettings),
    );
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
    if (!sms.isGranted && context.mounted) {
      await _showHelpDialog(
        context,
        title: 'Allow SMS Access',
        body:
            'Because TripSplit is installed outside the Play Store, Android keeps '
            'SMS access switched off and greys out the toggle. Turn it on by hand:\n\n'
            '1.  Tap “Open settings” below.\n'
            '2.  On the App info screen, tap ⋮ in the top-right corner.\n'
            '3.  Choose “Allow restricted settings”.\n'
            '4.  Open Permissions → SMS → Allow.\n\n'
            'Then come back here — it switches on by itself once access is allowed.',
        open: openAppSettings,
      );
    }
    await refresh();
  }

  Future<void> _showHelpDialog(
    BuildContext context, {
    required String title,
    required String body,
    required Future<Object?> Function() open,
    (String, Future<Object?> Function())? secondary,
  }) => showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: paper,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        title,
        style: TextStyle(color: ink, fontWeight: FontWeight.w800, fontSize: 18),
      ),
      content: Text(
        body,
        style: TextStyle(color: ink, fontSize: 13.5, height: 1.45),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text('Not Now', style: TextStyle(color: muted)),
        ),
        if (secondary != null)
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              AppResume.sendingOut();
              secondary.$2();
            },
            child: Text(secondary.$1, style: TextStyle(color: ink, fontWeight: FontWeight.w700)),
          ),
        FilledButton(
          onPressed: () {
            Navigator.pop(ctx);
            AppResume.sendingOut();
            open();
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
