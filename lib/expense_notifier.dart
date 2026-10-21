import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:workmanager/workmanager.dart';

import 'env.dart';
import 'models.dart';
import 'theme.dart';

/// Instant pushes (from push-worker/worker.js) while the app is in the
/// background or closed, even with the phone locked: shown like the rest.
@pragma('vm:entry-point')
Future<void> expensePushHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) await Firebase.initializeApp();
    await ExpenseNotifier.fromPush(message.data);
  } catch (_) {}
}

/// Where a tapped notification leads: an expense, or (for a settle-up
/// reminder) the balance with another member.
typedef NotificationTarget = ({bool settle, String tripId, String id});

/// Runs the periodic background check (see [ExpenseNotifier.schedule]) in
/// its own isolate while the app is closed.
@pragma('vm:entry-point')
void expenseCheckDispatcher() {
  Workmanager().executeTask((task, input) async {
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
      await ExpenseNotifier.init();
      await ExpenseNotifier.checkNow();
    } catch (_) {
      // Nothing to report from here; the next run tries again.
    }
    return true;
  });
}

/// Android notifications when someone on your trips adds an expense: their
/// photo, the amount, what for, the category, trip, place, time and your
/// share. Tapping one opens that expense (read-only).
///
/// They come three ways, and each records what it showed so nothing is
/// announced twice: an instant FCM push sent by the payer's phone through the
/// push relay ([tellTripmates] → [fromPush]), the app's live listeners while
/// it's running ([fromLive]), and a WorkManager check about every 15 minutes
/// as a backstop ([checkNow]).
abstract final class ExpenseNotifier {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static const _channel = AndroidNotificationChannel(
    'trip_expenses',
    'Trip expenses',
    description: 'When someone on your trips adds an expense',
    importance: Importance.high,
  );
  static const _reminders = AndroidNotificationChannel(
    'settle_reminders',
    'Settle-up reminders',
    description: 'Reminders you set to settle a balance',
    importance: Importance.high,
  );
  static const _task = 'trip_split.check_expenses';
  static const _sinceKey = 'trip_split.notify_since.v1';
  static const _shownKey = 'trip_split.notified_expenses.v1';
  static final _prefs = SharedPreferencesAsync();

  /// Opens an expense when a notification is tapped while the app is running.
  static void Function(String tripId, String expenseId)? onOpen;

  /// Opens the settle-up page for a balance when its reminder is tapped.
  static void Function(String tripId, String otherId)? onSettle;

  /// Kept up to date by the app: no system notification while it's on screen
  /// (the bell shows new expenses then).
  static bool appVisible = false;

  static Future<void>? _ready;

  static Future<void> init() => _ready ??= _init();

  static Future<void> _init() async {
    await _plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('ic_stat_logo')),
      onDidReceiveNotificationResponse: (response) {
        final target = parseTarget(response.payload);
        if (target == null) return;
        target.settle ? onSettle?.call(target.tripId, target.id) : onOpen?.call(target.tripId, target.id);
      },
    );
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(_channel);
    await android?.createNotificationChannel(_reminders);
  }

  /// What the notification that launched the app points to, if one did.
  static Future<NotificationTarget?> launchTarget() async {
    await init();
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp != true) return null;
    return parseTarget(details!.notificationResponse?.payload);
  }

  /// "tripId|expenseId" for an expense, "settle|tripId|otherId" for a reminder.
  static NotificationTarget? parseTarget(String? payload) {
    final parts = payload?.split('|') ?? const [];
    if (parts.length == 3 && parts[0] == 'settle') return (settle: true, tripId: parts[1], id: parts[2]);
    if (parts.length == 2) return (settle: false, tripId: parts[0], id: parts[1]);
    return null;
  }

  static int _reminderId(String tripId, String otherId) => 'settle|$tripId|$otherId'.hashCode & 0x7fffffff;

  /// Sets (or moves) a reminder at [when] to settle the balance with
  /// [other] on [trip]; tapping it opens that balance's settle-up page.
  static Future<void> remindToSettle({
    required Trip trip,
    required TripMember other,
    required double amount,
    required bool iOwe,
    required DateTime when,
  }) async {
    await init();
    tzdata.initializeTimeZones();
    final first = other.name.trim().split(RegExp(r'\s+')).first;
    final title = iOwe ? 'Time to settle up with $first' : 'Remind $first to settle up';
    final body = iOwe
        ? 'You owe $first ${money(amount)} on ${trip.name}. Tap to pay.'
        : '$first owes you ${money(amount)} on ${trip.name}.';
    final avatar = await _avatar(other);
    await _plugin.zonedSchedule(
      id: _reminderId(trip.id, other.id),
      scheduledDate: tz.TZDateTime.from(when.toUtc(), tz.UTC),
      title: title,
      body: body,
      payload: 'settle|${trip.id}|${other.id}',
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _reminders.id,
          _reminders.name,
          channelDescription: _reminders.description,
          importance: Importance.high,
          priority: Priority.high,
          color: const Color(0xFFF08018),
          largeIcon: avatar == null ? null : ByteArrayAndroidBitmap(avatar),
          styleInformation: BigTextStyleInformation(body, contentTitle: title, summaryText: trip.name),
          category: AndroidNotificationCategory.reminder,
        ),
      ),
    );
  }

  /// Asks for permission (Android 13+), registers this phone for instant
  /// pushes, and starts the background check.
  static Future<void> start() async {
    await init();
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _startWatermark();
    await _registerForPush().catchError((Object _) {});
    await Workmanager().initialize(expenseCheckDispatcher);
    await Workmanager().registerPeriodicTask(
      _task,
      _task,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  }

  /// On sign-out: stop checking, and stop pushes to this phone.
  static Future<void> stop() async {
    await Workmanager().cancelByUniqueName(_task).catchError((Object _) {});
    await _prefs.remove(_sinceKey);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      // ignore: deprecated_member_use (see _registerForPush)
      final token = await FirebaseMessaging.instance.getToken();
      if (uid != null && token != null) {
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'fcmTokens': FieldValue.arrayRemove([token]),
        }, SetOptions(merge: true));
      }
      // ignore: deprecated_member_use
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
  }

  static StreamSubscription<RemoteMessage>? _onMessage;
  static StreamSubscription<String>? _onTokenRefresh;

  /// Saves this phone's FCM token on the user's profile, where the push relay
  /// looks for it, and keeps it current.
  static Future<void> _registerForPush() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    Future<void> save(String token) => FirebaseFirestore.instance.collection('users').doc(uid).set({
      'fcmTokens': FieldValue.arrayUnion([token]),
    }, SetOptions(merge: true));
    // FCM registration tokens (deprecated in firebase_messaging 17 in favour of
    // installation IDs, but still what the FCM v1 send API the relay uses takes).
    // ignore: deprecated_member_use
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) await save(token);
    // ignore: deprecated_member_use
    _onTokenRefresh ??= FirebaseMessaging.instance.onTokenRefresh.listen((t) => save(t).catchError((Object _) {}));
    // While the app is open, pushes arrive here instead of the handler.
    _onMessage ??= FirebaseMessaging.onMessage.listen((m) => fromPush(m.data).catchError((Object _) {}));
  }

  /// After adding an expense: asks the push relay to notify everyone else on
  /// the trip straight away. Best effort; the other paths still cover it.
  static Future<void> tellTripmates(String tripId, String expenseId) async {
    if (pushRelayUrl.isEmpty) return;
    try {
      final idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (idToken == null) return;
      await http
          .post(
            Uri.parse(pushRelayUrl),
            headers: {'Authorization': 'Bearer $idToken', 'Content-Type': 'application/json'},
            body: jsonEncode({'tripId': tripId, 'expenseId': expenseId}),
          )
          .timeout(const Duration(seconds: 20));
    } catch (_) {}
  }

  /// A push from the relay: rebuilds the expense from its data and shows it
  /// (once), unless the app is on screen.
  static Future<void> fromPush(Map<String, dynamic> data) async {
    if (data['kind'] != 'expense') return;
    final tripId = data['tripId'] as String?, expenseId = data['expenseId'] as String?;
    final paidBy = data['paidBy'] as String?;
    final me = FirebaseAuth.instance.currentUser?.uid ?? data['to'] as String?;
    if (tripId == null || expenseId == null || paidBy == null || me == null || paidBy == me) return;
    final shares = <ExpenseShare>[];
    try {
      final raw = jsonDecode(data['shares'] as String? ?? '{}') as Map<String, dynamic>;
      raw.forEach((id, v) => shares.add(ExpenseShare(userId: id, shareAmount: (v as num).toDouble())));
    } catch (_) {}
    String? blank(Object? v) => (v is String && v.isNotEmpty) ? v : null;
    await _loadPrivateNames(me);
    final payerName = TripMember.privateNames[paidBy] ?? blank(data['payerName']) ?? 'Someone';
    // Picked photos don't fit in a push: read the payer's from the trip.
    var payerPhoto = blank(data['payerPhoto']);
    if (payerPhoto == null) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('trips')
            .doc(tripId)
            .get()
            .timeout(const Duration(seconds: 5));
        payerPhoto = Trip.fromDoc(snap).member(paidBy)?.photoUrl;
      } catch (_) {}
    }
    final trip = Trip(
      id: tripId,
      name: blank(data['tripName']) ?? 'Your trip',
      destination: null,
      inviteCode: '',
      members: [TripMember(id: paidBy, name: payerName, photoUrl: payerPhoto)],
    );
    final expense = TripExpense(
      id: expenseId,
      tripId: tripId,
      description: blank(data['description']) ?? 'An expense',
      amount: double.tryParse(data['amount'] as String? ?? '') ?? 0,
      paidBy: paidBy,
      paidByName: payerName,
      category: blank(data['category']),
      date: blank(data['date']) ?? DateTime.now().toIso8601String(),
      location: blank(data['location']),
      shares: shares,
      createdAt: DateTime.fromMillisecondsSinceEpoch(int.tryParse(data['createdAt'] as String? ?? '') ?? 0),
    );
    await init();
    final shown = (await _prefs.getStringList(_shownKey) ?? const <String>[]).toList();
    if (shown.contains(expenseId)) return;
    shown.add(expenseId);
    if (shown.length > 300) shown.removeRange(0, shown.length - 300);
    await _prefs.setStringList(_shownKey, shown);
    if (!appVisible) await _show(trip, expense, me);
  }

  /// The first time, only what's added from now on is announced (no flood of
  /// old expenses).
  static Future<int> _startWatermark() async {
    final since = await _prefs.getInt(_sinceKey);
    if (since != null) return since;
    final now = DateTime.now().millisecondsSinceEpoch;
    await _prefs.setInt(_sinceKey, now);
    return now;
  }

  /// From the live listeners: announce [expenses] of [trip] that are new.
  static Future<void> fromLive(Trip trip, List<TripExpense> expenses) async {
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null) return;
    await init();
    await _announce(trip, expenses, me, show: !appVisible);
  }

  /// The background check: every trip's expenses added since the last one.
  static Future<void> checkNow() async {
    final user = FirebaseAuth.instance.currentUser ??
        await FirebaseAuth.instance.authStateChanges().first.timeout(const Duration(seconds: 10), onTimeout: () => null);
    if (user == null) return;
    await _loadPrivateNames(user.uid);
    final since = await _startWatermark();
    var newest = since;
    final db = FirebaseFirestore.instance;
    final trips = await db.collection('trips').where('memberIds', arrayContains: user.uid).get();
    for (final doc in trips.docs) {
      final trip = Trip.fromDoc(doc);
      final recent = await doc.reference
          .collection('expenses')
          .where('createdAt', isGreaterThan: Timestamp.fromMillisecondsSinceEpoch(since))
          .orderBy('createdAt')
          .limit(20)
          .get();
      final expenses = recent.docs.map(TripExpense.fromDoc).toList();
      await _announce(trip, expenses, user.uid, show: true);
      for (final e in expenses) {
        final at = e.createdAt?.millisecondsSinceEpoch ?? 0;
        if (at > newest) newest = at;
      }
    }
    // Next time, only look at what's newer than everything seen now.
    if (newest > since) await _prefs.setInt(_sinceKey, newest);
  }

  /// Shows the ones not shown before (by someone else, added after the
  /// watermark) and remembers them; [show] false just marks them seen.
  static Future<void> _announce(Trip trip, List<TripExpense> expenses, String me, {required bool show}) async {
    final since = await _startWatermark();
    final shown = (await _prefs.getStringList(_shownKey) ?? const <String>[]).toList();
    for (final e in expenses) {
      final at = e.createdAt?.millisecondsSinceEpoch ?? 0;
      if (at <= since || e.paidBy == me || shown.contains(e.id)) continue;
      shown.add(e.id);
      if (show) await _show(trip, e, me);
    }
    if (shown.length > 300) shown.removeRange(0, shown.length - 300);
    await _prefs.setStringList(_shownKey, shown);
  }

  static Future<void> _show(Trip trip, TripExpense e, String me) async {
    final payer = trip.member(e.paidBy) ?? TripMember(id: e.paidBy, name: e.payerName(trip));
    final first = payer.name.trim().split(RegExp(r'\s+')).first;
    final myShare = e.shareOf(me);
    final String title;
    if (e.isSettlement) {
      title = myShare > 0 ? '$first paid you back ${money(e.amount)}' : '$first settled up ${money(e.amount)}';
    } else {
      title = '$first added ${money(e.amount)}';
    }
    final category = e.isSettlement ? 'Settle-up' : (e.category ?? 'Other');
    final lines = <String>[
      '<b>${_html(e.description)}</b>',
      '${_html(category)} · ${_html(trip.name)}',
      if (e.location != null) '📍 ${_html(e.location!)}',
      '🕒 ${formatDateTime(e.dateTime)}',
      if (!e.isSettlement)
        myShare > 0
            ? '<b>Your share ${money(myShare)}</b> (split ${e.shares.length} way${e.shares.length == 1 ? '' : 's'})'
            : 'You’re not part of this one',
    ];
    final avatar = await _avatar(payer);
    await _plugin.show(
      id: e.id.hashCode & 0x7fffffff,
      title: title,
      body: '${e.description} · ${trip.name}',
      payload: '${trip.id}|${e.id}',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          color: const Color(0xFFF08018),
          largeIcon: avatar == null ? null : ByteArrayAndroidBitmap(avatar),
          styleInformation: BigTextStyleInformation(
            lines.join('<br>'),
            htmlFormatBigText: true,
            contentTitle: title,
            summaryText: trip.name,
          ),
          groupKey: 'trip_${trip.id}',
          when: e.createdAt?.millisecondsSinceEpoch,
          showWhen: true,
          category: AndroidNotificationCategory.social,
        ),
      ),
    );
  }

  static bool _namesLoaded = false;

  /// In a background isolate: the user's private names for tripmates, so
  /// notifications use them too (the app's isolate already has them).
  static Future<void> _loadPrivateNames(String uid) async {
    if (_namesLoaded || TripMember.privateNames.isNotEmpty) return;
    _namesLoaded = true;
    try {
      final snap = await FirebaseFirestore.instance.collection('users').doc(uid).get().timeout(const Duration(seconds: 5));
      TripMember.privateNames = {
        for (final e in (snap.data()?['privateNames'] as Map<String, dynamic>? ?? const {}).entries)
          if (e.value is String && (e.value as String).isNotEmpty) e.key: e.value as String,
      };
    } catch (_) {}
  }

  static String _html(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

  /// The payer's photo cropped to a circle, or their initials on their
  /// colour; PNG bytes for the notification's large icon.
  static Future<Uint8List?> _avatar(TripMember m) async {
    const size = 192.0;
    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      const rect = Rect.fromLTWH(0, 0, size, size);
      canvas.clipPath(Path()..addOval(rect));
      ui.Image? photo;
      final url = m.photoUrl;
      if (url != null) {
        try {
          // A picked photo is embedded (data: URI); Google's is fetched.
          final bytes = url.startsWith('data:')
              ? base64Decode(url.substring(url.indexOf(',') + 1))
              : (await http.get(Uri.parse(url)).timeout(const Duration(seconds: 6))).bodyBytes;
          final codec = await ui.instantiateImageCodec(bytes, targetWidth: size.toInt());
          photo = (await codec.getNextFrame()).image;
        } catch (_) {}
      }
      if (photo != null) {
        canvas.drawImageRect(
          photo,
          Rect.fromLTWH(0, 0, photo.width.toDouble(), photo.height.toDouble()),
          rect,
          Paint()..filterQuality = FilterQuality.medium,
        );
      } else {
        canvas.drawRect(rect, Paint()..color = colorForId(m.id));
        final text = TextPainter(
          text: TextSpan(
            text: m.initials,
            style: const TextStyle(color: Colors.white, fontSize: 76, fontWeight: FontWeight.w700),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        text.paint(canvas, Offset((size - text.width) / 2, (size - text.height) / 2));
      }
      final image = await recorder.endRecording().toImage(size.toInt(), size.toInt());
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      return png?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }
}
