import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'theme.dart';

// Firestore layout (see firestore.rules):
//   users/{uid}                      AppUser
//   trips/{tripId}                   Trip (members copied in, running totals)
//   trips/{tripId}/expenses/{id}     TripExpense
//   invites/{code}                   {tripId}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  final first = parts.first[0];
  return (parts.length > 1 ? first + parts.last[0] : first).toUpperCase();
}

DateTime? _time(Object? value) => switch (value) {
  Timestamp t => t.toDate(),
  String s => DateTime.tryParse(s)?.toLocal(),
  _ => null,
};

Map<String, double> _amounts(Object? value) => {
  for (final e in (value as Map<String, dynamic>? ?? const {}).entries) e.key: (e.value as num).toDouble(),
};

class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    this.phone,
    this.email,
    this.photoUrl,
    this.upiId,
  });
  final String id;
  final String name;

  /// Only set on accounts first created with the old phone + OTP login.
  final String? phone;
  final String? email;
  final String? photoUrl;

  /// Where tripmates pay this person from "Pay now" (e.g. name@okhdfc).
  final String? upiId;

  bool get hasGoogle => email != null;

  String get initials => _initials(name);

  factory AppUser.fromMap(String id, Map<String, dynamic> data) => AppUser(
    id: id,
    name: data['name'] as String? ?? '',
    phone: data['phone'] as String?,
    email: data['email'] as String?,
    photoUrl: data['photoUrl'] as String?,
    upiId: data['upiId'] as String?,
  );

  /// The copy kept on each trip, so faces and "Pay" need no extra reads.
  Map<String, Object?> get memberEntry => {'name': name, 'photoUrl': photoUrl, 'upiId': upiId};
}

class TripMember {
  const TripMember({required this.id, required this.name, this.photoUrl, this.upiId});
  final String id;
  final String name;
  final String? photoUrl;
  final String? upiId;

  String get initials => _initials(name);

  factory TripMember.fromMap(String id, Map<String, dynamic>? data) => TripMember(
    id: id,
    name: data?['name'] as String? ?? 'Someone',
    photoUrl: data?['photoUrl'] as String?,
    upiId: data?['upiId'] as String?,
  );
}

class Trip {
  const Trip({
    required this.id,
    required this.name,
    required this.destination,
    required this.inviteCode,
    this.members = const [],
    this.kind,
    this.startDate,
    this.createdAt,
    this.totalSpent = 0,
    this.paid = const {},
    this.owed = const {},
  });
  final String id;
  final String name;
  final String? destination;
  final String inviteCode;

  /// In the order people joined.
  final List<TripMember> members;

  /// One of [tripKinds]' ids; null for trips made before kinds existed.
  final String? kind;
  final String? startDate;
  final DateTime? createdAt;

  /// Running totals kept up to date with every expense write (see moneyDelta):
  /// money spent (not counting settle-up payments), and per member what they
  /// paid and what their shares add up to.
  final double totalSpent;
  final Map<String, double> paid;
  final Map<String, double> owed;

  int get memberCount => members.length;

  TripKind get tripKind => tripKindFor(kind);

  /// The trip's start date if it has one, otherwise when it was made.
  DateTime? get date => DateTime.tryParse(startDate ?? '') ?? createdAt;

  TripMember? member(String userId) {
    for (final m in members) {
      if (m.id == userId) return m;
    }
    return null;
  }

  factory Trip.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final memberData = data['members'] as Map<String, dynamic>? ?? const {};
    final ids = (data['memberIds'] as List<dynamic>? ?? const []).cast<String>();
    return Trip(
      id: doc.id,
      name: data['name'] as String? ?? '',
      destination: data['destination'] as String?,
      inviteCode: data['inviteCode'] as String? ?? '',
      members: [for (final id in ids) TripMember.fromMap(id, memberData[id] as Map<String, dynamic>?)],
      kind: data['kind'] as String?,
      startDate: data['startDate'] as String?,
      createdAt: _time(data['createdAt']),
      totalSpent: (data['totalSpent'] as num?)?.toDouble() ?? 0,
      paid: _amounts(data['paid']),
      owed: _amounts(data['owed']),
    );
  }
}

class ExpenseShare {
  const ExpenseShare({required this.userId, required this.shareAmount});
  final String userId;
  final double shareAmount;
}

class TripExpense {
  const TripExpense({
    required this.id,
    required this.tripId,
    required this.description,
    required this.amount,
    required this.paidBy,
    required this.paidByName,
    required this.category,
    required this.date,
    required this.location,
    required this.shares,
    this.splitType = 'equal',
    this.createdAt,
  });
  final String id;
  final String tripId;
  final String description;
  final double amount;
  final String paidBy;
  final String paidByName;
  final String? category;

  /// Local ISO-8601 date-time of the purchase.
  final String date;
  final String? location;
  final List<ExpenseShare> shares;
  final String splitType;

  /// When it was added (server time); drives the notification feed.
  final DateTime? createdAt;

  DateTime get dateTime => DateTime.tryParse(date) ?? DateTime.now();

  IconData get icon => iconForCategory(category);

  bool get isSettlement => category == settlementCategory;

  double shareOf(String userId) {
    for (final s in shares) {
      if (s.userId == userId) return s.shareAmount;
    }
    return 0;
  }

  factory TripExpense.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return TripExpense(
      id: doc.id,
      tripId: data['tripId'] as String? ?? doc.reference.parent.parent?.id ?? '',
      description: data['description'] as String? ?? '',
      amount: (data['amount'] as num?)?.toDouble() ?? 0,
      paidBy: data['paidBy'] as String? ?? '',
      paidByName: data['paidByName'] as String? ?? 'Someone',
      category: data['category'] as String?,
      date: data['date'] as String? ?? DateTime.now().toIso8601String(),
      location: data['location'] as String?,
      splitType: data['splitType'] as String? ?? 'equal',
      shares: [
        for (final e in _amounts(data['shares']).entries) ExpenseShare(userId: e.key, shareAmount: e.value),
      ],
      // Pending local writes have no server time yet; treat them as "now".
      createdAt: _time(data['createdAt']) ?? DateTime.now(),
    );
  }
}

class Balance {
  const Balance({
    required this.userId,
    required this.name,
    required this.totalPaid,
    required this.totalOwed,
    required this.netBalance,
  });
  final String userId;
  final String name;
  final double totalPaid;
  final double totalOwed;
  final double netBalance;
}

class Settlement {
  const Settlement({
    required this.fromUser,
    required this.toUser,
    required this.amount,
    this.fromUserId,
    this.toUserId,
  });
  final String fromUser;
  final String toUser;
  final double amount;
  final String? fromUserId;
  final String? toUserId;
}

/// One expense in the notification feed (any trip the user is in).
class ActivityItem {
  const ActivityItem({
    required this.expenseId,
    required this.tripId,
    required this.tripName,
    required this.description,
    required this.amount,
    required this.category,
    required this.paidBy,
    required this.paidByName,
    required this.createdAt,
    required this.myShare,
  });
  final String expenseId;
  final String tripId;
  final String tripName;
  final String description;
  final double amount;
  final String? category;
  final String paidBy;
  final String paidByName;
  final DateTime createdAt;
  final double myShare;

  factory ActivityItem.of(TripExpense e, String tripName, String me) => ActivityItem(
    expenseId: e.id,
    tripId: e.tripId,
    tripName: tripName,
    description: e.description,
    amount: e.amount,
    category: e.category,
    paidBy: e.paidBy,
    paidByName: e.paidByName,
    createdAt: e.createdAt ?? DateTime.now(),
    myShare: e.shareOf(me),
  );
}
