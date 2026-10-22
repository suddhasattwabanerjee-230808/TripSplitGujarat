import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'theme.dart';
import 'trip_store.dart';
import 'upi_alerts.dart';

/// A settle-up paid in a UPI app (picked, or opened on its QR scanner) is
/// confirmed without asking: the bank's UPI debit SMS for the same amount
/// (caught by UpiSmsReceiver, like the UPI payment alerts) marks it paid, and
/// it's recorded here as soon as the app is back on screen. Without SMS
/// access, or if no SMS comes in time, a snack bar offers "Mark Paid".
class SettleWatch with WidgetsBindingObserver {
  SettleWatch._();
  static final instance = SettleWatch._();

  static const _key = 'trip_split.pending_settle.v1';
  static const _channel = MethodChannel('tripsplit/upi_pay');

  /// Where the results are told (the app's messenger).
  ScaffoldMessengerState? Function()? messenger;

  Timer? _poll;
  bool _busy = false;

  void init(ScaffoldMessengerState? Function() messenger) {
    this.messenger = messenger;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      check();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _poll?.cancel();
    }
  }

  /// Starts waiting for a payment of [amount] (all or part of [debt]).
  Future<void> start(Debt debt, double amount) async {
    await SharedPreferencesAsync().setString(
      _key,
      jsonEncode({
        'tripId': debt.trip.id,
        'toUserId': debt.otherId,
        'name': debt.otherName,
        'amount': amount,
        'sms': UpiAlerts.instance.smsGranted,
      }),
    );
    try {
      await _channel.invokeMethod<void>('expectSettle', {'amount': amount});
    } on PlatformException {
      // Then it times out into "Mark Paid".
    }
  }

  /// Stops waiting (paid some other way, or the app couldn't be opened).
  Future<void> cancel() async {
    _poll?.cancel();
    await SharedPreferencesAsync().remove(_key);
    try {
      await _channel.invokeMethod<void>('cancelSettle');
    } on PlatformException {
      // Nothing to cancel.
    }
  }

  /// Looks for the bank's SMS: records the payment if it came, keeps looking
  /// (every few seconds while on screen) if it may still come, else offers
  /// "Mark Paid".
  Future<void> check({bool firstLook = true}) async {
    if (_busy) return;
    _busy = true;
    try {
      final raw = await SharedPreferencesAsync().getString(_key);
      if (raw == null) return;
      final pending = jsonDecode(raw) as Map<String, dynamic>;
      final amount = (pending['amount'] as num).toDouble();
      final name = pending['name'] as String;
      Map<Object?, Object?> status;
      try {
        status = await _channel.invokeMapMethod<Object?, Object?>('settleStatus') ?? const {};
      } on PlatformException {
        status = const {};
      }
      if (status['paid'] != null) {
        await cancel();
        await _record(pending);
        _tell('Paid ${money(amount)} to $name — confirmed from your bank’s SMS. Balances updated.');
      } else if (pending['sms'] == true && status['waiting'] == true) {
        if (firstLook) _tell('Waiting for your bank’s SMS to confirm ${money(amount)} to $name…');
        _poll?.cancel();
        _poll = Timer(const Duration(seconds: 3), () => check(firstLook: false));
      } else {
        // No SMS access, or none came in time.
        await cancel();
        _tell(
          pending['sms'] == true
              ? 'No bank SMS for ${money(amount)} to $name arrived.'
              : 'Paid ${money(amount)} to $name? Allow SMS access to confirm it by itself.',
          action: SnackBarAction(label: 'Mark Paid', onPressed: () => _markPaid(pending)),
        );
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _markPaid(Map<String, dynamic> pending) async {
    await _record(pending);
    _tell('Paid ${money((pending['amount'] as num).toDouble())} to ${pending['name']} — balances updated.');
  }

  Future<void> _record(Map<String, dynamic> pending) async {
    final tripId = pending['tripId'] as String;
    try {
      await ApiClient.instance.recordPayment(
        tripId: tripId,
        trip: TripStore.instance.trips?.where((t) => t.id == tripId).firstOrNull,
        toUserId: pending['toUserId'] as String,
        amount: (pending['amount'] as num).toDouble(),
      );
      await TripStore.instance.refresh();
    } on ApiException catch (e) {
      _tell(e.message);
    }
  }

  void _tell(String text, {SnackBarAction? action}) {
    final m = messenger?.call();
    if (m == null) return;
    m.hideCurrentSnackBar();
    m.showSnackBar(
      SnackBar(
        content: Text(text),
        action: action,
        duration: Duration(seconds: action == null ? 4 : 10),
      ),
    );
  }
}
