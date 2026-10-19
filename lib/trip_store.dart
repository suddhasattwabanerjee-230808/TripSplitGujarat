import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'models.dart';

/// A debt between the signed-in user and someone else on one trip.
class Debt {
  const Debt({required this.trip, required this.settlement, required this.iOwe});
  final Trip trip;
  final Settlement settlement;

  /// True when the user pays; false when they get paid.
  final bool iOwe;

  int? get otherId => iOwe ? settlement.toUserId : settlement.fromUserId;
  String get otherName => iOwe ? settlement.toUser : settlement.fromUser;
  TripMember? get other => otherId == null ? null : trip.member(otherId!);
  double get amount => settlement.amount;
}

/// Trips, balances, settlements and the activity feed, shared by the home
/// tabs so each one doesn't refetch the same data.
class TripStore extends ChangeNotifier {
  TripStore._();
  static final TripStore instance = TripStore._();

  static const _seenKey = 'trip_split.activity_seen_at.v1';

  List<Trip>? trips;
  String? error;
  final Map<int, List<Balance>> balances = {};
  final Map<int, List<Settlement>> settlements = {};
  final Map<int, List<TripExpense>> expenses = {};
  List<ActivityItem> activity = [];
  DateTime? _activitySeenAt;

  /// The trip the Trip tab shows; the app opens on it.
  int? currentTripId;

  /// Bumped after every refresh, so open screens know to reload their own data.
  int revision = 0;

  Trip? get currentTrip => trips?.where((t) => t.id == currentTripId).firstOrNull;

  /// Shows [tripId] on the Trip tab (the shell switches to that tab).
  void selectTrip(int tripId) {
    currentTripId = tripId;
    ApiClient.instance.rememberTrip(tripId);
    notifyListeners();
  }

  /// Keeps [currentTripId] pointing at a trip the user is still in: the last
  /// one opened, else the newest.
  Future<void> _pickCurrentTrip(List<Trip> list) async {
    if (list.any((t) => t.id == currentTripId)) return;
    final last = await ApiClient.instance.lastTripId();
    currentTripId = list.any((t) => t.id == last) ? last : list.firstOrNull?.id;
  }

  int? get _me => ApiClient.instance.currentUser?.id;

  Future<void> refresh() async {
    error = null;
    try {
      final list = await ApiClient.instance.listTrips();
      await _pickCurrentTrip(list);
      trips = list;
      notifyListeners();
      await Future.wait([
        for (final t in list) _loadMoney(t.id),
        _loadActivity(),
      ]);
    } on ApiException catch (e) {
      error = e.message;
    }
    revision++;
    notifyListeners();
  }

  Future<void> _loadMoney(int tripId) async {
    try {
      final results = await Future.wait([
        ApiClient.instance.getBalances(tripId),
        ApiClient.instance.getSettlements(tripId),
      ]);
      balances[tripId] = results[0] as List<Balance>;
      settlements[tripId] = results[1] as List<Settlement>;
    } on ApiException {
      // That trip's numbers stay unknown; the rest still show.
    }
  }

  /// Every trip's expenses, for the statistics tab.
  Future<void> loadAllExpenses() async {
    final list = trips ?? const <Trip>[];
    await Future.wait([
      for (final t in list)
        ApiClient.instance.listExpenses(t.id).then((e) => expenses[t.id] = e).catchError((_) => <TripExpense>[]),
    ]);
    notifyListeners();
  }

  /// The user's net balance on a trip: positive = owed, negative = owes,
  /// null while unknown.
  double? myNet(int tripId) {
    final list = balances[tripId];
    if (list == null) return null;
    for (final b in list) {
      if (b.userId == _me) return b.netBalance;
    }
    return 0;
  }

  /// Sum over every trip whose balance is known.
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
    final me = ApiClient.instance.currentUser;
    if (me == null) return [];
    final result = <Debt>[];
    for (final t in trips ?? const <Trip>[]) {
      for (final s in settlements[t.id] ?? const <Settlement>[]) {
        // Older servers only send names; fall back to matching on those.
        final fromMe = s.fromUserId != null ? s.fromUserId == me.id : s.fromUser == me.name;
        final toMe = s.toUserId != null ? s.toUserId == me.id : s.toUser == me.name;
        if (fromMe || toMe) result.add(Debt(trip: t, settlement: s, iOwe: fromMe));
      }
    }
    result.sort((a, b) => b.amount.compareTo(a.amount));
    return result;
  }

  // --- Notifications ----------------------------------------------------------

  Future<void> _loadActivity() async {
    try {
      _activitySeenAt ??= DateTime.tryParse((await SharedPreferences.getInstance()).getString(_seenKey) ?? '');
      activity = await ApiClient.instance.activity();
    } on ApiException {
      // Older server without /activity: the bell just stays empty.
    }
  }

  /// Other people's expenses added since the feed was last opened.
  int get unreadCount => activity
      .where((a) => a.paidBy != _me && (_activitySeenAt == null || a.createdAt.isAfter(_activitySeenAt!)))
      .length;

  bool isUnread(ActivityItem item) =>
      item.paidBy != _me && (_activitySeenAt == null || item.createdAt.isAfter(_activitySeenAt!));

  Future<void> markActivitySeen() async {
    final newest = activity.isEmpty ? DateTime.now() : activity.first.createdAt;
    _activitySeenAt = newest;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setString(_seenKey, newest.toIso8601String());
  }

  void clear() {
    trips = null;
    error = null;
    balances.clear();
    settlements.clear();
    expenses.clear();
    activity = [];
    currentTripId = null;
    notifyListeners();
  }
}
