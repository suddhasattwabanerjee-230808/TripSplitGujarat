import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'ledger.dart';
import 'models.dart';

/// A debt between the signed-in user and someone else on one trip.
class Debt {
  const Debt({required this.trip, required this.settlement, required this.iOwe});
  final Trip trip;
  final Settlement settlement;

  /// True when the user pays; false when they get paid.
  final bool iOwe;

  String? get otherId => iOwe ? settlement.toUserId : settlement.fromUserId;
  String get otherName => iOwe ? settlement.toUser : settlement.fromUser;
  TripMember? get other => otherId == null ? null : trip.member(otherId!);
  double get amount => settlement.amount;
}

/// Trips, balances, settlements and the activity feed, shared by the tabs.
/// Kept live by Firestore listeners: a tripmate's expense shows up without a
/// refresh, and everything still reads from the local cache when offline.
class TripStore extends ChangeNotifier {
  TripStore._();
  static final TripStore instance = TripStore._();

  static const _seenKey = 'trip_split.activity_seen_at.v1';

  List<Trip>? trips;
  String? error;
  final Map<String, List<TripExpense>> expenses = {};
  List<ActivityItem> activity = [];
  List<TripExpense> _activityRaw = [];
  DateTime? _activitySeenAt;

  StreamSubscription<List<Trip>>? _tripsSub;
  StreamSubscription<List<TripExpense>>? _activitySub;
  Completer<void>? _firstTrips;

  /// The trip the Trip tab shows; the app opens on it.
  String? currentTripId;

  /// Bumped on every trips update, so open screens can react.
  int revision = 0;

  Trip? get currentTrip => trips?.where((t) => t.id == currentTripId).firstOrNull;

  /// Shows [tripId] on the Trip tab (the shell switches to that tab).
  void selectTrip(String tripId) {
    currentTripId = tripId;
    ApiClient.instance.rememberTrip(tripId);
    notifyListeners();
  }

  String? get _me => ApiClient.instance.currentUser?.id;

  /// Starts the live listeners (once) and waits for the first trips list.
  /// Calling it again just waits for that first load.
  Future<void> refresh() {
    if (_tripsSub == null) {
      _firstTrips = Completer<void>();
      error = null;
      try {
        _tripsSub = ApiClient.instance.watchTrips().listen(_onTrips, onError: _onError);
        _activitySub = ApiClient.instance.watchActivity().listen(_onActivity, onError: (_) {});
        SharedPreferences.getInstance().then((p) {
          _activitySeenAt ??= DateTime.tryParse(p.getString(_seenKey) ?? '');
          notifyListeners();
        });
      } on ApiException catch (e) {
        _onError(e);
      }
    }
    return _firstTrips!.future;
  }

  Future<void> _onTrips(List<Trip> list) async {
    if (!list.any((t) => t.id == currentTripId)) {
      final last = await ApiClient.instance.lastTripId();
      currentTripId = list.any((t) => t.id == last) ? last : list.firstOrNull?.id;
    }
    trips = list;
    error = null;
    revision++;
    _buildActivity();
    if (!(_firstTrips?.isCompleted ?? true)) _firstTrips!.complete();
    notifyListeners();
  }

  void _onError(Object e) {
    error = e is ApiException ? e.message : 'Couldn’t load your trips. Check your connection.';
    if (!(_firstTrips?.isCompleted ?? true)) _firstTrips!.complete();
    notifyListeners();
  }

  void _onActivity(List<TripExpense> list) {
    _activityRaw = list;
    _buildActivity();
    notifyListeners();
  }

  void _buildActivity() {
    final names = {for (final t in trips ?? const <Trip>[]) t.id: t.name};
    final me = _me ?? '';
    activity = [for (final e in _activityRaw) ActivityItem.of(e, names[e.tripId] ?? 'A trip', me)];
  }

  /// Every trip's expenses, for the statistics tab.
  Future<void> loadAllExpenses() async {
    final list = trips ?? const <Trip>[];
    await Future.wait([
      for (final t in list)
        ApiClient.instance
            .listExpenses(t.id)
            .then((e) => expenses[t.id] = e)
            .catchError((Object _) => expenses[t.id] ?? <TripExpense>[]),
    ]);
    notifyListeners();
  }

  List<Balance> balancesOf(Trip trip) => balancesFor(trip.members, trip.paid, trip.owed);

  List<Settlement> settlementsOf(Trip trip) => settlementsFor(balancesOf(trip));

  /// The user's net balance on a trip: positive = owed, negative = owes.
  double? myNet(String tripId) {
    final trip = trips?.where((t) => t.id == tripId).firstOrNull;
    final me = _me;
    if (trip == null || me == null) return null;
    return round2((trip.paid[me] ?? 0) - (trip.owed[me] ?? 0));
  }

  /// Sum over every trip.
  ({double owed, double owing}) get totals {
    var owed = 0.0, owing = 0.0;
    for (final t in trips ?? const <Trip>[]) {
      final net = myNet(t.id) ?? 0;
      if (net > 0) owed += net;
      if (net < 0) owing -= net;
    }
    return (owed: owed, owing: owing);
  }

  /// Settle-up payments involving the user, across all trips.
  List<Debt> get debts {
    final me = _me;
    if (me == null) return [];
    final result = <Debt>[];
    for (final t in trips ?? const <Trip>[]) {
      for (final s in settlementsOf(t)) {
        if (s.fromUserId == me || s.toUserId == me) {
          result.add(Debt(trip: t, settlement: s, iOwe: s.fromUserId == me));
        }
      }
    }
    result.sort((a, b) => b.amount.compareTo(a.amount));
    return result;
  }

  // --- Notifications ----------------------------------------------------------

  /// Other people's expenses added since the feed was last opened.
  int get unreadCount => activity.where(isUnread).length;

  bool isUnread(ActivityItem item) =>
      item.paidBy != _me && (_activitySeenAt == null || item.createdAt.isAfter(_activitySeenAt!));

  Future<void> markActivitySeen() async {
    final newest = activity.isEmpty ? DateTime.now() : activity.first.createdAt;
    _activitySeenAt = newest;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setString(_seenKey, newest.toIso8601String());
  }

  /// Stops listening and forgets everything (on sign-out).
  void clear() {
    _tripsSub?.cancel();
    _activitySub?.cancel();
    _tripsSub = null;
    _activitySub = null;
    trips = null;
    error = null;
    expenses.clear();
    activity = [];
    _activityRaw = [];
    currentTripId = null;
    notifyListeners();
  }
}
