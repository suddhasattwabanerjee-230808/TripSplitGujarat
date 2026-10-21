import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ledger.dart';
import 'models.dart';
import 'theme.dart';

class ApiException implements Exception {
  ApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// TripSplit's data layer on Firebase: Google sign-in through Firebase Auth,
/// trips and expenses in Firestore. The money rules run here on the phone
/// (ledger.dart); firestore.rules decides who may read and write what.
///
/// Writes go into Firestore's local cache at once and sync when there's a
/// connection, so adding an expense works offline. Write methods return after
/// the server confirms or after a short wait, whichever comes first; a write
/// the server rejects later is reported through [onWriteError].
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  static const _lastTripKey = 'trip_split.last_trip_id.v2';

  final _preferences = SharedPreferencesAsync();
  AppUser? _user;
  StreamSubscription<User?>? _authWatch;

  AppUser? get currentUser => _user;

  /// Called if Firebase signs the user out on its own (e.g. account disabled).
  void Function()? onSessionExpired;

  /// A write that failed after its method had already returned.
  void Function(ApiException error)? onWriteError;

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  String get _uid {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw ApiException('You’re signed out. Sign in again.');
    return user.uid;
  }

  DocumentReference<Map<String, dynamic>> _tripRef(String id) => _db.collection('trips').doc(id);

  CollectionReference<Map<String, dynamic>> _expenses(String tripId) => _tripRef(tripId).collection('expenses');

  // --- Session ------------------------------------------------------------

  Future<bool> restoreSession() async {
    if (Firebase.apps.isEmpty) return false;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    _user = await _loadProfile(user);
    _watchAuth();
    return true;
  }

  void _watchAuth() {
    _authWatch ??= FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null && _user != null) {
        _user = null;
        onSessionExpired?.call();
      }
    });
  }

  /// Signs in to Firebase with the Google ID token from Credential Manager.
  /// Accounts moved from the old server keep their uid, so their trips are there.
  Future<AppUser> signInWithGoogle(String idToken) async {
    try {
      final result = await FirebaseAuth.instance.signInWithCredential(GoogleAuthProvider.credential(idToken: idToken));
      _user = await _loadProfile(result.user!);
      _watchAuth();
      return _user!;
    } on FirebaseAuthException catch (e) {
      throw ApiException(e.message ?? 'Google sign-in failed (${e.code}).');
    }
  }

  /// The user's profile doc, created from their Google account the first time.
  /// Keeps a name they chose; refreshes email and photo from Google.
  Future<AppUser> _loadProfile(User account) async {
    final ref = _db.collection('users').doc(account.uid);
    final fallback = AppUser(
      id: account.uid,
      name: account.displayName ?? account.email?.split('@').first ?? 'You',
      email: account.email,
      photoUrl: account.photoURL,
    );
    try {
      final snap = await ref.get();
      if (!snap.exists) {
        await ref.set({
          'name': fallback.name,
          'email': fallback.email,
          'photoUrl': fallback.photoUrl,
          'createdAt': FieldValue.serverTimestamp(),
        });
        return fallback;
      }
      final user = AppUser.fromMap(account.uid, snap.data()!);
      if (account.photoURL != null && (user.photoUrl != account.photoURL || user.email != account.email)) {
        final updated = AppUser(
          id: user.id,
          name: user.name,
          phone: user.phone,
          email: account.email ?? user.email,
          photoUrl: account.photoURL,
          upiId: user.upiId,
          nicknameSet: user.nicknameSet,
        );
        unawaited(_saveProfile(updated, {'email': updated.email, 'photoUrl': updated.photoUrl}).catchError((_) {}));
        return updated;
      }
      return user;
    } on FirebaseException {
      return fallback; // offline on first launch: show what Google gave us
    }
  }

  Future<AppUser> refreshMe() async {
    final account = FirebaseAuth.instance.currentUser;
    if (account == null) throw ApiException('You’re signed out.');
    return _user = await _loadProfile(account);
  }

  /// Sets the nickname shown to tripmates everywhere (also on every trip the
  /// user is in). Photo and email keep coming from Google.
  Future<AppUser> updateName(String name) {
    final user = _user!;
    final updated = AppUser(
      id: user.id,
      name: name,
      phone: user.phone,
      email: user.email,
      photoUrl: user.photoUrl,
      upiId: user.upiId,
      nicknameSet: true,
    );
    return _saveProfile(updated, {'name': name, 'nicknameSet': true}).then((_) => _user = updated);
  }

  /// An empty [upiId] removes it.
  Future<AppUser> updateUpiId(String upiId) {
    final value = upiId.trim().isEmpty ? null : upiId.trim();
    if (value != null && !upiIdPattern.hasMatch(value)) {
      throw ApiException('That doesn’t look like a UPI ID (it should be like name@bank).');
    }
    final user = _user!;
    final updated = AppUser(
      id: user.id,
      name: user.name,
      phone: user.phone,
      email: user.email,
      photoUrl: user.photoUrl,
      upiId: value,
      nicknameSet: user.nicknameSet,
    );
    return _saveProfile(updated, {'upiId': value}).then((_) => _user = updated);
  }

  /// Writes the profile and its copy on every trip the user is in, together.
  Future<void> _saveProfile(AppUser user, Map<String, Object?> fields) async {
    final batch = _db.batch()..set(_db.collection('users').doc(user.id), fields, SetOptions(merge: true));
    final trips = await _db.collection('trips').where('memberIds', arrayContains: user.id).get();
    for (final t in trips.docs) {
      batch.update(t.reference, {'members.${user.id}': user.memberEntry});
    }
    await _commit(batch);
  }

  /// Deletes the signed-in user's TripSplit account. [googleIdToken] is a
  /// fresh Google sign-in for the same account: Firebase only deletes
  /// accounts that signed in recently.
  ///
  /// Personal data goes: the profile, invites to or from them, and their
  /// name, photo and UPI ID on every trip. Their expenses stay so tripmates'
  /// balances still add up, shown as [deletedUserName]. The Firebase login is
  /// deleted last, once everything it's needed for is done.
  Future<void> deleteAccount(String googleIdToken) => _guard(() async {
    final account = FirebaseAuth.instance.currentUser;
    final me = _user;
    if (account == null || me == null) throw ApiException('You’re signed out.');
    try {
      await account.reauthenticateWithCredential(GoogleAuthProvider.credential(idToken: googleIdToken));
    } on FirebaseAuthException catch (e) {
      throw ApiException(
        e.code == 'user-mismatch'
            ? 'That’s a different Google account. Pick ${me.email ?? 'the one you signed in with'}.'
            : (e.message ?? 'Google couldn’t confirm it’s you (${e.code}).'),
      );
    }

    // Never leave tripmates with a debt nobody can settle: checked again here
    // against the server's latest totals (Profile checks before asking).
    final trips = await _db.collection('trips').where('memberIds', arrayContains: me.id).get(
      const GetOptions(source: Source.server),
    );
    final unsettled = [
      for (final t in trips.docs.map(Trip.fromDoc))
        if (unsettledAmount(t.paid[me.id] ?? 0, t.owed[me.id] ?? 0) != 0) t.name,
    ];
    if (unsettled.isNotEmpty) {
      throw ApiException('Settle up on ${unsettled.join(', ')} first: your account can’t be deleted while money is owed.');
    }

    const gone = {'name': deletedUserName, 'photoUrl': null, 'upiId': null};
    var batch = _db.batch();
    var writes = 0;
    Future<void> add(void Function(WriteBatch b) write) async {
      write(batch);
      if (++writes == 400) {
        await batch.commit(); // a batch holds at most 500 writes
        batch = _db.batch();
        writes = 0;
      }
    }

    for (final trip in trips.docs) {
      await add((b) => b.update(trip.reference, {'members.${me.id}': gone}));
      final mine = await _expenses(trip.id).where('paidBy', isEqualTo: me.id).get();
      for (final e in mine.docs) {
        await add((b) => b.update(e.reference, {'paidByName': deletedUserName}));
      }
    }
    // No personal data left in the profile (set without merge replaces it all).
    await add((b) => b.set(_db.collection('users').doc(me.id), {'deleted': true}));
    await batch.commit();

    // Invites to or from them. Best effort: these need the email-invite rules.
    final email = account.email?.toLowerCase();
    for (final query in [
      if (email != null) _emailInvites.where('email', isEqualTo: email),
      _emailInvites.where('invitedBy', isEqualTo: me.id),
    ]) {
      try {
        for (final doc in (await query.get()).docs) {
          await doc.reference.delete();
        }
      } on FirebaseException {
        // Without those rules there are no invites to clean up anyway.
      }
    }

    await account.delete();
    _user = null;
    await _preferences.remove(_lastTripKey);
  });

  Future<void> logOut() async {
    _user = null;
    if (Firebase.apps.isNotEmpty) await FirebaseAuth.instance.signOut();
  }

  Future<void> rememberTrip(String tripId) => _preferences.setString(_lastTripKey, tripId);

  Future<String?> lastTripId() => _preferences.getString(_lastTripKey);

  // --- Live data --------------------------------------------------------------

  /// Every trip the user is in, newest first.
  Stream<List<Trip>> watchTrips() => _db
      .collection('trips')
      .where('memberIds', arrayContains: _uid)
      .snapshots()
      .map((s) => s.docs.map(Trip.fromDoc).toList()
        ..sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0))));

  Stream<QuerySnapshot<Map<String, dynamic>>> watchExpenseSnapshots(String tripId) =>
      _expenses(tripId).orderBy('date', descending: true).snapshots(includeMetadataChanges: true);

  /// The 50 newest expenses across all the user's trips (the bell's feed).
  /// One trip's newest expenses, for the bell. Listened to per trip rather
  /// than with one collection-group query, which silently needed a composite
  /// index and left the feed empty without it; this needs none.
  Stream<List<TripExpense>> watchRecentExpenses(String tripId) => _expenses(tripId)
      .orderBy('createdAt', descending: true)
      .limit(30)
      .snapshots()
      .map((s) => s.docs.map(TripExpense.fromDoc).toList());

  // --- Trips ------------------------------------------------------------------

  Future<List<Trip>> listTrips() => _guard(() async {
    final snap = await _db.collection('trips').where('memberIds', arrayContains: _uid).get();
    return snap.docs.map(Trip.fromDoc).toList();
  });

  Future<Trip> getTrip(String tripId) => _guard(() async {
    final snap = await _tripRef(tripId).get();
    if (!snap.exists) throw ApiException('That trip no longer exists.');
    return Trip.fromDoc(snap);
  });

  /// Needs a connection: the invite code must be checked as unused.
  Future<Trip> createTrip({
    required String name,
    String? destination,
    String? startDate,
    String? endDate,
    String? kind,
  }) => _guard(() async {
    final me = _user!;
    String? code;
    for (var i = 0; i < 10 && code == null; i++) {
      final candidate = newInviteCode();
      final taken = await _db.collection('invites').doc(candidate).get(const GetOptions(source: Source.server));
      if (!taken.exists) code = candidate;
    }
    if (code == null) throw ApiException('Couldn’t make an invite code. Try again.');
    final ref = _db.collection('trips').doc();
    final batch = _db.batch()
      ..set(ref, {
        'name': name,
        'destination': destination,
        'startDate': startDate,
        'endDate': endDate,
        'kind': kind,
        'inviteCode': code,
        'createdBy': me.id,
        'createdAt': FieldValue.serverTimestamp(),
        'memberIds': [me.id],
        'members': {me.id: me.memberEntry},
        'totalSpent': 0,
        'paid': <String, double>{},
        'owed': <String, double>{},
      })
      ..set(_db.collection('invites').doc(code), {'tripId': ref.id});
    await batch.commit();
    return Trip(
      id: ref.id,
      name: name,
      destination: destination,
      inviteCode: code,
      members: [TripMember(id: me.id, name: me.name, photoUrl: me.photoUrl, upiId: me.upiId)],
      kind: kind,
      startDate: startDate,
      createdAt: DateTime.now(),
    );
  });

  /// Needs a connection. Adding yourself is the only change a non-member may
  /// make to a trip (firestore.rules).
  Future<Trip> joinTrip(String inviteCode) => _guard(() async {
    final code = inviteCode.trim().toUpperCase();
    final invite = await _db.collection('invites').doc(code).get(const GetOptions(source: Source.server));
    final tripId = invite.data()?['tripId'] as String?;
    if (tripId == null) throw ApiException('No trip has that invite code. Check it and try again.');
    final me = _user!;
    await _tripRef(tripId).update({
      'memberIds': FieldValue.arrayUnion([me.id]),
      'members.${me.id}': me.memberEntry,
    });
    return getTrip(tripId);
  });

  // --- Invite by email ------------------------------------------------------

  CollectionReference<Map<String, dynamic>> get _emailInvites => _db.collection('emailInvites');

  /// Leaves a note that [email] is invited to [trip]. When they sign in with
  /// that Google account, [acceptEmailInvites] joins them: no code to type.
  Future<void> inviteByEmail(Trip trip, String email) => _guard(() async {
    final me = _user!;
    final address = email.trim().toLowerCase();
    await _commit(
      _db.batch()..set(_emailInvites.doc('${trip.id}_$address'), {
        'email': address,
        'tripId': trip.id,
        'tripName': trip.name,
        'inviteCode': trip.inviteCode,
        'invitedBy': me.id,
        'invitedByName': me.name,
        'createdAt': FieldValue.serverTimestamp(),
      }),
    );
  });

  /// Joins every trip this Google account's email was invited to, then clears
  /// those invites. Returns the trips newly joined. Never throws: on failure
  /// the code in the email still works.
  Future<List<({Trip trip, String invitedBy})>> acceptEmailInvites() async {
    final joined = <({Trip trip, String invitedBy})>[];
    try {
      final email = FirebaseAuth.instance.currentUser?.email?.toLowerCase();
      if (email == null || _user == null) return joined;
      final invites = await _emailInvites.where('email', isEqualTo: email).get(const GetOptions(source: Source.server));
      for (final doc in invites.docs) {
        final data = doc.data();
        try {
          if (!await _isMemberOf(data['tripId'] as String? ?? '')) {
            final trip = await joinTrip(data['inviteCode'] as String? ?? '');
            joined.add((trip: trip, invitedBy: data['invitedByName'] as String? ?? 'a friend'));
          }
        } on ApiException {
          // The trip or its code is gone; the invite is useless either way.
        }
        await doc.reference.delete().catchError((_) {});
      }
    } catch (_) {}
    return joined;
  }

  /// Non-members can't read a trip, so a refused read means "not a member".
  Future<bool> _isMemberOf(String tripId) async {
    if (tripId.isEmpty) return false;
    try {
      final snap = await _tripRef(tripId).get(const GetOptions(source: Source.server));
      return ((snap.data()?['memberIds'] as List<dynamic>?) ?? const []).contains(_user?.id);
    } on FirebaseException {
      return false;
    }
  }

  // --- Expenses -----------------------------------------------------------------

  Future<List<TripExpense>> listExpenses(String tripId) => _guard(() async {
    final snap = await _expenses(tripId).orderBy('date', descending: true).get();
    return snap.docs.map(TripExpense.fromDoc).toList();
  });

  /// Split equally across [splitWith] (member ids), or everyone on [trip]
  /// when null. [trip] is fetched when not passed, e.g. from the UPI pop-up.
  Future<TripExpense> createExpense({
    required String tripId,
    Trip? trip,
    required String description,
    required double amount,
    String? category,
    required String date,
    String? location,
    List<String>? splitWith,
  }) async {
    trip ??= await getTrip(tripId);
    final shares = equalShares(amount, splitMembers([for (final m in trip.members) m.id], splitWith));
    return _addExpense(trip, description, amount, category, date, location, shares, 'equal');
  }

  /// Records that the user paid [toUserId] back: an expense they paid with the
  /// whole amount as [toUserId]'s share, which cancels that much of the debt.
  Future<TripExpense> recordPayment({
    required String tripId,
    Trip? trip,
    required String toUserId,
    required double amount,
    String method = 'UPI',
  }) async {
    trip ??= await getTrip(tripId);
    return _addExpense(
      trip,
      'Paid back via $method',
      amount,
      settlementCategory,
      DateTime.now().toIso8601String(),
      null,
      {toUserId: amount},
      'custom',
    );
  }

  Future<TripExpense> _addExpense(
    Trip trip,
    String description,
    double amount,
    String? category,
    String date,
    String? location,
    Map<String, double> shares,
    String splitType,
  ) => _guard(() async {
    final me = _user!;
    final ref = _expenses(trip.id).doc();
    final expense = TripExpense(
      id: ref.id,
      tripId: trip.id,
      description: description,
      amount: amount,
      paidBy: me.id,
      paidByName: me.name,
      category: category,
      date: date,
      location: location,
      splitType: splitType,
      shares: [for (final e in shares.entries) ExpenseShare(userId: e.key, shareAmount: e.value)],
    );
    final batch = _db.batch()
      ..set(ref, {
        ..._expenseFields(expense, trip),
        'paidBy': me.id,
        'createdAt': FieldValue.serverTimestamp(),
      })
      ..update(_tripRef(trip.id), _increments(moneyDelta(null, expense)));
    await _commit(batch);
    return expense;
  });

  /// Edits keep the payer. A normal expense is re-split equally across
  /// [splitWith], or the people it was already split between when null; a
  /// settle-up payment keeps its single recipient.
  Future<TripExpense> updateExpense({
    required TripExpense existing,
    Trip? trip,
    required String description,
    required double amount,
    String? category,
    required String date,
    String? location,
    List<String>? splitWith,
  }) => _guard(() async {
    trip ??= await getTrip(existing.tripId);
    final shares = existing.isSettlement && existing.shares.isNotEmpty
        ? {existing.shares.first.userId: amount}
        : equalShares(
            amount,
            splitMembers([for (final m in trip!.members) m.id], splitWith ?? [for (final s in existing.shares) s.userId]),
          );
    final after = TripExpense(
      id: existing.id,
      tripId: existing.tripId,
      description: description,
      amount: amount,
      paidBy: existing.paidBy,
      paidByName: existing.paidByName,
      category: category,
      date: date,
      location: location,
      splitType: existing.splitType,
      shares: [for (final e in shares.entries) ExpenseShare(userId: e.key, shareAmount: e.value)],
      createdAt: existing.createdAt,
    );
    final batch = _db.batch()
      ..update(_expenses(existing.tripId).doc(existing.id), _expenseFields(after, trip!))
      ..update(_tripRef(existing.tripId), _increments(moneyDelta(existing, after)));
    await _commit(batch);
    return after;
  });

  Future<void> deleteExpense(TripExpense expense) => _guard(() async {
    final batch = _db.batch()
      ..delete(_expenses(expense.tripId).doc(expense.id))
      ..update(_tripRef(expense.tripId), _increments(moneyDelta(expense, null)));
    await _commit(batch);
  });

  /// Rewrites a trip's running totals from its expenses if they've drifted
  /// (e.g. two phones editing at once). Any member may.
  Future<void> repairTotals(Trip trip, List<TripExpense> expenses) async {
    final t = totalsFromExpenses(expenses);
    bool same(Map<String, double> a, Map<String, double> b) =>
        {...a.keys, ...b.keys}.every((k) => ((a[k] ?? 0) - (b[k] ?? 0)).abs() < 0.01);
    if ((trip.totalSpent - t.totalSpent).abs() < 0.01 && same(trip.paid, t.paid) && same(trip.owed, t.owed)) return;
    await _commit(_db.batch()..update(_tripRef(trip.id), {'paid': t.paid, 'owed': t.owed, 'totalSpent': t.totalSpent}));
  }

  Map<String, Object?> _expenseFields(TripExpense e, Trip trip) => {
    'tripId': e.tripId,
    'description': e.description,
    'amount': e.amount,
    'paidByName': e.paidByName,
    'category': e.category,
    'date': e.date,
    'location': e.location,
    'splitType': e.splitType,
    'shares': {for (final s in e.shares) s.userId: s.shareAmount},
    // Lets the bell's collection-group query (and its rule) find it.
    'memberIds': [for (final m in trip.members) m.id],
  };

  Map<String, Object> _increments(Map<String, double> delta) => {
    for (final e in delta.entries) e.key: FieldValue.increment(e.value),
  };

  // --- Plumbing -------------------------------------------------------------------

  /// Returns once the server confirms or after 1.5 s (the write is already in
  /// the local cache and syncs later); later failures go to [onWriteError].
  Future<void> _commit(WriteBatch batch) {
    final done = Completer<void>();
    batch.commit().then(
      (_) {
        if (!done.isCompleted) done.complete();
      },
      onError: (Object e) {
        final error = _friendly(e);
        if (!done.isCompleted) {
          done.completeError(error);
        } else {
          onWriteError?.call(error);
        }
      },
    );
    Timer(const Duration(milliseconds: 1500), () {
      if (!done.isCompleted) done.complete();
    });
    return done.future;
  }

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on ApiException {
      rethrow;
    } catch (e) {
      throw _friendly(e);
    }
  }

  ApiException _friendly(Object e) {
    if (e is ApiException) return e;
    if (e is FirebaseException) {
      return ApiException(switch (e.code) {
        'permission-denied' => 'You don’t have permission to do that.',
        'unavailable' => 'You’re offline. Connect to the internet and try again.',
        'not-found' => 'That no longer exists.',
        _ => e.message ?? 'Something went wrong (${e.code}).',
      });
    }
    return ApiException(e.toString());
  }
}
