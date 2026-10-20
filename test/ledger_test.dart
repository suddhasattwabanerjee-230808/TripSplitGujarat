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

  test('split between some members: only the chosen people owe, in join order', () {
    final all = ['a', 'b', 'c'];
    expect(splitMembers(all, null), all);
    expect(splitMembers(all, ['c', 'a']), ['a', 'c']); // join order, not tap order
    expect(splitMembers(all, ['b']), ['b']);
    expect(splitMembers(all, ['x']), all); // nobody on the trip → everyone
    expect(splitMembers(all, []), all);

    // A pays 300 for A and C only: C owes A 150, B is untouched.
    final shares = equalShares(300, splitMembers(all, ['a', 'c']));
    expect(shares, {'a': 150, 'c': 150});
    final t = totalsFromExpenses([expense('dinner', 'a', 300, shares)]);
    final balances = balancesFor(members, t.paid, t.owed);
    expect([for (final b in balances) b.netBalance], [150, 0, -150]);
    final settle = settlementsFor(balances);
    expect(settle.single.fromUserId, 'c');
    expect(settle.single.toUserId, 'a');
    expect(settle.single.amount, 150);
  });

  test('paying on behalf of one person: they owe the whole amount', () {
    final t = totalsFromExpenses([expense('cab', 'a', 240, equalShares(240, splitMembers(['a', 'b', 'c'], ['b'])))]);
    expect([for (final b in balancesFor(members, t.paid, t.owed)) b.netBalance], [240, -240, 0]);
    expect(t.totalSpent, 240);
  });

  test('editing who an expense is split between moves the running totals exactly', () {
    final before = expense('dinner', 'a', 300, {'a': 100, 'b': 100, 'c': 100});
    final after = expense('dinner', 'a', 300, {'a': 150, 'c': 150});
    expect(moneyDelta(before, after), {'owed.a': 50, 'owed.b': -100, 'owed.c': 50});
  });
}
