import 'package:flutter_test/flutter_test.dart';
import 'package:trip_split_gujarat/ledger.dart';
import 'package:trip_split_gujarat/models.dart';

TripExpense expense(
  String id,
  String paidBy,
  double amount,
  Map<String, double> shares, {
  String category = 'Food',
}) => TripExpense(
  id: id,
  tripId: 't',
  description: id,
  amount: amount,
  paidBy: paidBy,
  paidByName: paidBy,
  category: category,
  date: '2026-10-19T12:00:00',
  location: null,
  shares: [for (final e in shares.entries) ExpenseShare(userId: e.key, shareAmount: e.value)],
);

const members = [
  TripMember(id: 'a', name: 'A'),
  TripMember(id: 'b', name: 'B'),
  TripMember(id: 'c', name: 'C'),
];

void main() {
  test('equal split puts the rounding remainder on the last member (as the server did)', () {
    expect(equalShares(100, ['a', 'b', 'c']), {'a': 33.33, 'b': 33.33, 'c': 33.34});
    expect(equalShares(300, ['a', 'b']), {'a': 150, 'b': 150});
    expect(equalShares(1, ['a', 'b', 'c']), {'a': 0.33, 'b': 0.33, 'c': 0.34});
  });

  test('matches the old server: A pays 300 for A+B, B pays A back 100 → B owes A 50', () {
    final expenses = [
      expense('groceries', 'a', 300, {'a': 150, 'b': 150}, category: 'Groceries'),
      expense('payback', 'b', 100, {'a': 100}, category: 'Settlement'),
    ];
    final t = totalsFromExpenses(expenses);
    expect(t.totalSpent, 300, reason: 'settle-up payments are not spending');
    final balances = balancesFor(members.take(2).toList(), t.paid, t.owed);
    expect([for (final b in balances) b.netBalance], [50, -50]);
    final s = settlementsFor(balances);
    expect(s, hasLength(1));
    expect((s.single.fromUserId, s.single.toUserId, s.single.amount), ('b', 'a', 50.0));
  });

  test('fewest payments: biggest debtor pays biggest creditor first', () {
    final balances = [
      const Balance(userId: 'a', name: 'A', totalPaid: 0, totalOwed: 0, netBalance: 70),
      const Balance(userId: 'b', name: 'B', totalPaid: 0, totalOwed: 0, netBalance: -50),
      const Balance(userId: 'c', name: 'C', totalPaid: 0, totalOwed: 0, netBalance: -20),
    ];
    final s = settlementsFor(balances);
    expect([for (final x in s) '${x.fromUserId}->${x.toUserId}:${x.amount}'], ['b->a:50.0', 'c->a:20.0']);
    expect(settlementsFor([
      const Balance(userId: 'a', name: 'A', totalPaid: 5, totalOwed: 5, netBalance: 0),
    ]), isEmpty);
  });

  test('moneyDelta keeps running totals equal to a full recount through create, edit and delete', () {
    final first = expense('dinner', 'a', 90, equalShares(90, ['a', 'b', 'c']));
    final edited = expense('dinner', 'a', 120, equalShares(120, ['a', 'b', 'c']));
    final pay = expense('pay', 'b', 30, {'a': 30}, category: 'Settlement');

    final running = <String, double>{};
    void apply(Map<String, double> delta) => delta.forEach((k, v) => running[k] = round2((running[k] ?? 0) + v));

    apply(moneyDelta(null, first));
    apply(moneyDelta(first, edited));
    apply(moneyDelta(null, pay));
    var t = totalsFromExpenses([edited, pay]);
    expect(running['totalSpent'], t.totalSpent);
    for (final m in members) {
      expect(running['paid.${m.id}'] ?? 0, t.paid[m.id] ?? 0);
      expect(running['owed.${m.id}'] ?? 0, t.owed[m.id] ?? 0);
    }

    apply(moneyDelta(edited, null));
    t = totalsFromExpenses([pay]);
    expect(running['totalSpent'] ?? 0, 0);
    expect(running['paid.a'] ?? 0, t.paid['a'] ?? 0);
    expect(running['owed.a'] ?? 0, t.owed['a'] ?? 0);
  });

  test('invite codes avoid look-alike characters; UPI IDs are validated like the server', () {
    for (var i = 0; i < 200; i++) {
      final code = newInviteCode();
      expect(code, matches(RegExp(r'^[A-HJ-NP-Z2-9]{6}$')));
    }
    expect(upiIdPattern.hasMatch('aarav@okhdfc'), isTrue);
    expect(upiIdPattern.hasMatch('9876543210@ybl'), isTrue);
    expect(upiIdPattern.hasMatch('nope'), isFalse);
    expect(upiIdPattern.hasMatch('a@b'), isFalse);
  });
}
