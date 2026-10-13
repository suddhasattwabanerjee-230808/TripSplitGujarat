import 'package:flutter/material.dart';

class AppUser {
  const AppUser({required this.id, required this.name, required this.phone});
  final int id;
  final String name;
  final String phone;

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
    id: json['id'] as int,
    name: json['name'] as String,
    phone: json['phone'] as String,
  );

  Map<String, Object> toJson() => {'id': id, 'name': name, 'phone': phone};
}

class TripMember {
  const TripMember({required this.id, required this.name});
  final int id;
  final String name;

  factory TripMember.fromJson(Map<String, dynamic> json) =>
      TripMember(id: json['id'] as int, name: json['name'] as String);
}

class Trip {
  const Trip({
    required this.id,
    required this.name,
    required this.destination,
    required this.inviteCode,
    required this.memberCount,
    this.members = const [],
  });
  final int id;
  final String name;
  final String? destination;
  final String inviteCode;
  final int memberCount;
  final List<TripMember> members;

  factory Trip.fromJson(Map<String, dynamic> json) => Trip(
    id: json['id'] as int,
    name: json['name'] as String,
    destination: json['destination'] as String?,
    inviteCode: json['invite_code'] as String,
    memberCount: json['member_count'] as int,
    members: (json['members'] as List<dynamic>? ?? [])
        .map((item) => TripMember.fromJson(item as Map<String, dynamic>))
        .toList(),
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

  DateTime get dateTime => DateTime.tryParse(date) ?? DateTime.now();

  IconData get icon => switch (category) {
    'Food' => Icons.restaurant_rounded,
    'Stay' => Icons.hotel_rounded,
    'Transport' => Icons.local_taxi_rounded,
    'Activities' => Icons.local_activity_rounded,
    _ => Icons.more_horiz_rounded,
  };

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
  });
  final String fromUser;
  final String toUser;
  final double amount;

  factory Settlement.fromJson(Map<String, dynamic> json) => Settlement(
    fromUser: json['from_user'] as String,
    toUser: json['to_user'] as String,
    amount: (json['amount'] as num).toDouble(),
  );
}
