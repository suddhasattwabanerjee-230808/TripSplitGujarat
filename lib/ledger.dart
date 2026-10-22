import 'dart:math';

import 'models.dart';

// The money rules that used to live on the server, now run on the phone.
// Ported from the FastAPI backend (_resolve_shares, get_balances,
// get_settlements) so numbers match what users saw before the move.

/// Rounds to paise. (Python's round() rounds halves to even; this rounds them
/// away from zero, which only differs on exact .xx5 values.)
double round2(double value) => (value * 100).roundToDouble() / 100;

/// Splits [amount] equally; any rounding remainder goes to the last member.
Map<String, double> equalShares(double amount, List<String> memberIds) {
  if (memberIds.isEmpty) throw ArgumentError('A trip needs at least one member');
  final base = round2(amount / memberIds.length);
  final shares = {for (final id in memberIds) id: base};
  final drift = round2(amount - base * memberIds.length);
  if (drift != 0) shares[memberIds.last] = round2(base + drift);
  return shares;
}

/// Who an expense is split between: the [chosen] ids that are on the trip, in
/// [memberIds]' (join) order so the rounding remainder lands on the same
/// person on every phone. Everyone when [chosen] is null or names nobody here.
List<String> splitMembers(List<String> memberIds, Iterable<String>? chosen) {
  if (chosen == null) return memberIds;
  final picked = chosen.toSet();
  final result = [for (final id in memberIds) if (picked.contains(id)) id];
  return result.isEmpty ? memberIds : result;
}

/// The Firestore increments that keep a trip's running totals (`paid.<uid>`,
/// `owed.<uid>`, `totalSpent`) in step when an expense goes from [before] to
/// [after]. Pass null for [before] on create and for [after] on delete.
Map<String, double> moneyDelta(TripExpense? before, TripExpense? after) {
  final delta = <String, double>{};
  void add(String key, double v) => delta[key] = (delta[key] ?? 0) + v;
  void apply(TripExpense e, double sign) {
    add('paid.${e.paidBy}', sign * e.amount);
    for (final s in e.shares) {
      add('owed.${s.userId}', sign * s.shareAmount);
    }
    if (!e.isSettlement) add('totalSpent', sign * e.amount);
  }

  if (before != null) apply(before, -1);
  if (after != null) apply(after, 1);
  delta.removeWhere((_, v) => v.abs() < 0.0001);
  return delta.map((k, v) => MapEntry(k, round2(v)));
}

/// Running totals rebuilt from every expense (the source of truth).
({Map<String, double> paid, Map<String, double> owed, double totalSpent}) totalsFromExpenses(
  List<TripExpense> expenses,
) {
  final paid = <String, double>{};
  final owed = <String, double>{};
  var total = 0.0;
  for (final e in expenses) {
    paid[e.paidBy] = (paid[e.paidBy] ?? 0) + e.amount;
    for (final s in e.shares) {
      owed[s.userId] = (owed[s.userId] ?? 0) + s.shareAmount;
    }
    if (!e.isSettlement) total += e.amount;
  }
  return (
    paid: paid.map((k, v) => MapEntry(k, round2(v))),
    owed: owed.map((k, v) => MapEntry(k, round2(v))),
    totalSpent: round2(total),
  );
}

/// One balance per member, in join order.
List<Balance> balancesFor(List<TripMember> members, Map<String, double> paid, Map<String, double> owed) => [
  for (final m in members)
    Balance(
      userId: m.id,
      name: m.name,
      totalPaid: round2(paid[m.id] ?? 0),
      totalOwed: round2(owed[m.id] ?? 0),
      netBalance: round2((paid[m.id] ?? 0) - (owed[m.id] ?? 0)),
    ),
];

/// The fewest payments that settle everyone: biggest debtor pays biggest
/// creditor, repeat.
List<Settlement> settlementsFor(List<Balance> balances) {
  final creditors = [
    for (final b in balances)
      if (b.netBalance > 0.01) [b, b.netBalance],
  ]..sort((a, b) => (b[1] as double).compareTo(a[1] as double));
  final debtors = [
    for (final b in balances)
      if (b.netBalance < -0.01) [b, b.netBalance],
  ]..sort((a, b) => (a[1] as double).compareTo(b[1] as double));

  final result = <Settlement>[];
  var i = 0, j = 0;
  while (i < debtors.length && j < creditors.length) {
    final debtor = debtors[i][0] as Balance;
    final creditor = creditors[j][0] as Balance;
    final amount = round2(min(-(debtors[i][1] as double), creditors[j][1] as double));
    if (amount > 0.01) {
      result.add(
        Settlement(
          fromUser: debtor.name,
          toUser: creditor.name,
          amount: amount,
          fromUserId: debtor.userId,
          toUserId: creditor.userId,
        ),
      );
    }
    debtors[i][1] = round2((debtors[i][1] as double) + amount);
    creditors[j][1] = round2((creditors[j][1] as double) - amount);
    if ((debtors[i][1] as double).abs() < 0.01) i++;
    if ((creditors[j][1] as double).abs() < 0.01) j++;
  }
  return result;
}

/// What's still open between someone and their trip: positive = owed to
/// them, negative = they owe, 0 = settled (to the paisa, as settlementsFor).
double unsettledAmount(double paid, double owed) {
  final net = round2(paid - owed);
  return net.abs() < 0.01 ? 0 : net;
}

// --- Invite codes & UPI IDs --------------------------------------------------

/// Letters and digits without the look-alikes 0/O/1/I.
const inviteAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

String newInviteCode([Random? random]) {
  final r = random ?? Random.secure();
  return List.generate(6, (_) => inviteAlphabet[r.nextInt(inviteAlphabet.length)]).join();
}

final upiIdPattern = RegExp(r'^[A-Za-z0-9._-]{2,64}@[A-Za-z][A-Za-z0-9.-]{1,32}$');

/// One settle-up payment between two people.
class PairPayment {
  const PairPayment({required this.fromMe, required this.amount, required this.date});

  /// True when the user paid the other person; false when they paid the user.
  final bool fromMe;
  final double amount;
  final DateTime date;
}

/// The balance between the user ([me]) and one other person ([other]) on a
/// trip, from the expenses alone: what each paid towards the other's share,
/// and the settle-up payments (part ones included) between just the two.
class PairBalance {
  const PairBalance({
    required this.paidForThem,
    required this.paidForMe,
    required this.payments,
  });

  /// The other person's shares of expenses the user paid.
  final double paidForThem;

  /// The user's shares of expenses the other person paid.
  final double paidForMe;

  /// Settle-ups between the two, oldest first.
  final List<PairPayment> payments;

  double get paidByMe => round2(payments.where((p) => p.fromMe).fold(0.0, (s, p) => s + p.amount));
  double get paidByThem => round2(payments.where((p) => !p.fromMe).fold(0.0, (s, p) => s + p.amount));

  /// Before any settle-ups: positive when they owe the user.
  double get fromExpenses => round2(paidForThem - paidForMe);

  /// Now, after the settle-ups: positive when they owe the user, negative
  /// when the user owes them.
  double get net => round2(fromExpenses + paidByMe - paidByThem);
}

PairBalance pairBalance(List<TripExpense> expenses, String me, String other) {
  var paidForThem = 0.0, paidForMe = 0.0;
  final payments = <PairPayment>[];
  for (final e in expenses) {
    if (e.isSettlement) {
      // A settle-up is stored as the payer paying the whole amount for the
      // one person paid.
      if (e.paidBy == me && e.shareOf(other) > 0) {
        payments.add(PairPayment(fromMe: true, amount: e.shareOf(other), date: e.dateTime));
      } else if (e.paidBy == other && e.shareOf(me) > 0) {
        payments.add(PairPayment(fromMe: false, amount: e.shareOf(me), date: e.dateTime));
      }
    } else if (e.paidBy == me) {
      paidForThem += e.shareOf(other);
    } else if (e.paidBy == other) {
      paidForMe += e.shareOf(me);
    }
  }
  payments.sort((a, b) => a.date.compareTo(b.date));
  return PairBalance(paidForThem: round2(paidForThem), paidForMe: round2(paidForMe), payments: payments);
}
