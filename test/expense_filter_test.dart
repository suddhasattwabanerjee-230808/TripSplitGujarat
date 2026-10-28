import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_split_gujarat/models.dart';
import 'package:trip_split_gujarat/screens/expenses_screen.dart';
import 'package:trip_split_gujarat/theme.dart';

TripExpense _e(String desc, String date, {double amount = 100, String category = 'Food', String? location, String paidBy = 'a'}) =>
    TripExpense(
      id: desc,
      tripId: 't1',
      description: desc,
      amount: amount,
      paidBy: paidBy,
      paidByName: paidBy,
      category: category,
      date: date,
      location: location,
      shares: const [ExpenseShare(userId: 'a', shareAmount: 50), ExpenseShare(userId: 'b', shareAmount: 50)],
    );

final dinner = _e('Dinner', '2026-10-20T21:30:00', amount: 2600, location: 'Manek Chowk, Ahmedabad');
final chai = _e('Late-night chai', '2026-10-21T00:40:00', amount: 240, location: 'Bhuj', paidBy: 'b');
final cab = _e('Cab', '2026-10-21T09:15:00', amount: 900, category: 'Transport');
final settle = _e('Settle up', '2026-10-21T20:00:00', category: settlementCategory, paidBy: 'b');
final all = [dinner, chai, cab, settle];

List<String> _match(ExpenseFilter f) => [for (final e in all) if (f.matches(e)) e.description];

void main() {
  test('no filter keeps everything', () {
    expect(_match(ExpenseFilter()), hasLength(4));
    expect(ExpenseFilter().active, 0);
  });

  test('a date range is whole days, ends included', () {
    final f = ExpenseFilter(dates: DateTimeRange(start: DateTime(2026, 10, 21), end: DateTime(2026, 10, 21)));
    expect(_match(f), ['Late-night chai', 'Cab', 'Settle up']);
  });

  test('a time window past midnight wraps, and combines with dates', () {
    final f = ExpenseFilter(timeFrom: const TimeOfDay(hour: 21, minute: 0), timeTo: const TimeOfDay(hour: 1, minute: 0));
    expect(_match(f), ['Dinner', 'Late-night chai']);
    f.dates = DateTimeRange(start: DateTime(2026, 10, 20), end: DateTime(2026, 10, 20));
    expect(_match(f), ['Dinner']);
    expect(f.active, 2);
  });

  test('parts of the day, categories, places, payers and amounts', () {
    expect(_match(ExpenseFilter(dayParts: {0})), ['Cab']); // morning
    expect(_match(ExpenseFilter(categories: {'Transport'})), ['Cab']);
    expect(_match(ExpenseFilter(places: {'Ahmedabad'})), ['Dinner']);
    expect(_match(ExpenseFilter(places: {ExpenseFilter.noPlace})), ['Cab', 'Settle up']);
    expect(_match(ExpenseFilter(payers: {'b'})), ['Late-night chai', 'Settle up']);
    expect(_match(ExpenseFilter(minAmount: 500, maxAmount: 1000)), ['Cab']);
  });

  test('settle-ups can be hidden', () {
    expect(_match(ExpenseFilter(settlements: false)), isNot(contains('Settle up')));
  });

  test('paid for matches anyone with a share, and combines with paid by', () {
    const forB = [ExpenseShare(userId: 'b', shareAmount: 300)];
    const onlyB = TripExpense(
      id: 'gift', tripId: 't1', description: 'Gift for B', amount: 300, paidBy: 'a', paidByName: 'a',
      category: 'Shopping', date: '2026-10-21T11:00:00', location: null, shares: forB,
    );
    const onlyA = TripExpense(
      id: 'tea', tripId: 't1', description: 'My tea', amount: 20, paidBy: 'a', paidByName: 'a',
      category: 'Food', date: '2026-10-21T11:05:00', location: null,
      shares: [ExpenseShare(userId: 'a', shareAmount: 20)],
    );
    List<String> run(ExpenseFilter f) => [for (final e in [...all, onlyB, onlyA]) if (f.matches(e)) e.description];
    expect(run(ExpenseFilter(paidFor: {'a'})), ['Dinner', 'Late-night chai', 'Cab', 'Settle up', 'My tea']);
    expect(run(ExpenseFilter(paidFor: {'b'}, payers: {'a'})), ['Dinner', 'Cab', 'Gift for B']);
    expect(run(ExpenseFilter(paidFor: {'a'}, payers: {'a'}, settlements: false)), ['Dinner', 'Cab', 'My tea']);
    expect(ExpenseFilter(paidFor: {'a'}).active, 1);
  });

  test('search looks at description, place, category, payer and amount', () {
    bool q(TripExpense e, String s) => expenseMatchesQuery(e, s, null);
    expect(q(dinner, 'manek'), isTrue);
    expect(q(cab, 'transport'), isTrue);
    expect(q(chai, '240'), isTrue);
    expect(q(chai, 'b'), isTrue); // paid by "b"
    expect(q(cab, 'hotel'), isFalse);
  });
}
