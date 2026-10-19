import 'package:flutter/material.dart';

import 'theme.dart';

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  final first = parts.first[0];
  return (parts.length > 1 ? first + parts.last[0] : first).toUpperCase();
}

/// Server timestamps are UTC "YYYY-MM-DD HH:MM:SS"; read them as UTC, show local.
DateTime? _parseServerTime(String? value) {
  if (value == null) return null;
  final iso = value.contains('T') ? value : value.replaceFirst(' ', 'T');
  final parsed = DateTime.tryParse(iso.endsWith('Z') || iso.contains('+') ? iso : '${iso}Z');
  return parsed?.toLocal();
}

class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    this.phone,
    this.email,
    this.photoUrl,
    this.upiId,
  });
  final int id;
  final String name;

  /// Only set on accounts first created with the old phone + OTP login.
  final String? phone;

  /// Set once the account is signed in with (or linked to) Google.
  final String? email;
  final String? photoUrl;

  /// Where tripmates pay this person from "Pay now" (e.g. name@okhdfc).
  final String? upiId;

  bool get hasGoogle => email != null;

  String get initials => _initials(name);

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
    id: json['id'] as int,
    name: json['name'] as String,
    phone: json['phone'] as String?,
    email: json['email'] as String?,
    photoUrl: json['photo_url'] as String?,
    upiId: json['upi_id'] as String?,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'phone': phone,
    'email': email,
    'photo_url': photoUrl,
    'upi_id': upiId,
  };
}

class TripMember {
  const TripMember({required this.id, required this.name, this.photoUrl, this.upiId});
  final int id;
  final String name;
  final String? photoUrl;
  final String? upiId;

  String get initials => _initials(name);

  factory TripMember.fromJson(Map<String, dynamic> json) => TripMember(
    id: json['id'] as int,
    name: json['name'] as String,
    photoUrl: json['photo_url'] as String?,
    upiId: json['upi_id'] as String?,
  );
}

class Trip {
  const Trip({
    required this.id,
    required this.name,
    required this.destination,
    required this.inviteCode,
    required this.memberCount,
    this.members = const [],
    this.kind,
    this.startDate,
    this.createdAt,
    this.totalSpent = 0,
  });
  final int id;
  final String name;
  final String? destination;
  final String inviteCode;
  final int memberCount;
  final List<TripMember> members;

  /// One of [tripKinds]' ids; null for trips made before kinds existed.
  final String? kind;
  final String? startDate;
  final DateTime? createdAt;

  /// Money spent on the trip, not counting settle-up payments.
  final double totalSpent;

  TripKind get tripKind => tripKindFor(kind);

  /// The trip's start date if it has one, otherwise when it was made.
  DateTime? get date => DateTime.tryParse(startDate ?? '') ?? createdAt;

  TripMember? member(int userId) {
    for (final m in members) {
      if (m.id == userId) return m;
    }
    return null;
  }

  factory Trip.fromJson(Map<String, dynamic> json) => Trip(
    id: json['id'] as int,
    name: json['name'] as String,
    destination: json['destination'] as String?,
    inviteCode: json['invite_code'] as String,
    memberCount: json['member_count'] as int,
    members: (json['members'] as List<dynamic>? ?? [])
        .map((item) => TripMember.fromJson(item as Map<String, dynamic>))
        .toList(),
    kind: json['kind'] as String?,
    startDate: json['start_date'] as String?,
    createdAt: _parseServerTime(json['created_at'] as String?),
    totalSpent: (json['total_spent'] as num?)?.toDouble() ?? 0,
  );
}

class ExpenseShare {
  const ExpenseShare({required this.userId, required this.shareAmount});
  final int userId;
  final double shareAmount;

  factory ExpenseShare.fromJson(Map<String, dynamic> json) => ExpenseShare(
    userId: json['user_id'] as int,
    shareAmount: (json['share_amount'] as num).toDouble(),
  );
}

class TripExpense {
  const TripExpense({
    required this.id,
    required this.description,
    required this.amount,
    required this.paidBy,
    required this.paidByName,
    required this.category,
    required this.date,
    required this.location,
    required this.shares,
    this.createdAt,
  });
  final int id;
  final String description;
  final double amount;
  final int paidBy;
  final String paidByName;
  final String? category;
  final String date;
  final String? location;
  final List<ExpenseShare> shares;
  final DateTime? createdAt;

  DateTime get dateTime => DateTime.tryParse(date) ?? DateTime.now();

  IconData get icon => iconForCategory(category);

  bool get isSettlement => category == settlementCategory;

  double shareOf(int userId) {
    for (final s in shares) {
      if (s.userId == userId) return s.shareAmount;
    }
    return 0;
  }

  factory TripExpense.fromJson(Map<String, dynamic> json) => TripExpense(
    id: json['id'] as int,
    description: json['description'] as String,
    amount: (json['amount'] as num).toDouble(),
    paidBy: json['paid_by'] as int,
    paidByName: json['paid_by_name'] as String,
    category: json['category'] as String?,
    date: json['date'] as String,
    location: json['location'] as String?,
    shares: (json['shares'] as List<dynamic>)
        .map((item) => ExpenseShare.fromJson(item as Map<String, dynamic>))
        .toList(),
    createdAt: _parseServerTime(json['created_at'] as String?),
  );
}

class Balance {
  const Balance({
    required this.userId,
    required this.name,
    required this.totalPaid,
    required this.totalOwed,
    required this.netBalance,
  });
  final int userId;
  final String name;
  final double totalPaid;
  final double totalOwed;
  final double netBalance;

  factory Balance.fromJson(Map<String, dynamic> json) => Balance(
    userId: json['user_id'] as int,
    name: json['name'] as String,
    totalPaid: (json['total_paid'] as num).toDouble(),
    totalOwed: (json['total_owed'] as num).toDouble(),
    netBalance: (json['net_balance'] as num).toDouble(),
  );
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
  final int? fromUserId;
  final int? toUserId;

  factory Settlement.fromJson(Map<String, dynamic> json) => Settlement(
    fromUser: json['from_user'] as String,
    toUser: json['to_user'] as String,
    amount: (json['amount'] as num).toDouble(),
    fromUserId: json['from_user_id'] as int?,
    toUserId: json['to_user_id'] as int?,
  );
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
  final int expenseId;
  final int tripId;
  final String tripName;
  final String description;
  final double amount;
  final String? category;
  final int paidBy;
  final String paidByName;
  final DateTime createdAt;
  final double myShare;

  factory ActivityItem.fromJson(Map<String, dynamic> json) => ActivityItem(
    expenseId: json['expense_id'] as int,
    tripId: json['trip_id'] as int,
    tripName: json['trip_name'] as String,
    description: json['description'] as String,
    amount: (json['amount'] as num).toDouble(),
    category: json['category'] as String?,
    paidBy: json['paid_by'] as int,
    paidByName: json['paid_by_name'] as String,
    createdAt: _parseServerTime(json['created_at'] as String?) ?? DateTime.now(),
    myShare: (json['my_share'] as num).toDouble(),
  );
}
