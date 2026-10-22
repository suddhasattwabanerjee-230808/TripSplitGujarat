import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:trip_split_gujarat/models.dart';
import 'package:trip_split_gujarat/screens/trip_people.dart';

const trip = Trip(
  id: 't1',
  name: 'Gujarat Trip',
  destination: 'Ahmedabad',
  inviteCode: 'HVHKBJ',
  members: [
    TripMember(id: 'a', name: 'Aarav Mehta', upiId: 'aarav@okaxis'),
    TripMember(id: 'b', name: 'Priya Shah'),
    TripMember(id: 'c', name: 'Kabir Rao'),
  ],
);

TripExpense _e(String id, String paidBy, double amount, Map<String, double> shares, {String category = 'Food'}) =>
    TripExpense(
      id: id,
      tripId: 't1',
      description: id,
      amount: amount,
      paidBy: paidBy,
      paidByName: paidBy,
      category: category,
      date: '2026-10-19T19:42:00',
      location: 'Manek Chowk, Ahmedabad',
      shares: [for (final s in shares.entries) ExpenseShare(userId: s.key, shareAmount: s.value)],
    );

// A paid 1,800 for all three; B paid 600 for B and C.
final expenses = [
  _e('Dinner at Manek Chowk', 'a', 1800, {'a': 600, 'b': 600, 'c': 600}),
  _e('Cab to Adalaj', 'b', 600, {'b': 300, 'c': 300}, category: 'Transport'),
];

void main() {
  setUp(() => SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty());

  testWidgets('trip details lists paid, share and balance for everyone', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TripDetailsView(trip: trip, expenses: expenses))));

    expect(find.text('₹2,400'), findsOneWidget); // total spent
    // Aarav: paid 1,800, share 600, gets back 1,200.
    expect(find.text('+₹1,200'), findsOneWidget);
    // Priya: paid 600, share 900, owes 300. Kabir: share 900, owes 900.
    expect(find.text('-₹300'), findsOneWidget);
    expect(find.text('-₹900'), findsOneWidget);
    expect(find.text('Kabir Pays Aarav'), findsOneWidget);
    // Each person is a tappable row (it opens their live page, which needs Firebase).
    expect(find.ancestor(of: find.text('Priya'), matching: find.byType(InkWell)), findsOneWidget);
  });

  testWidgets('a person page shows their totals, settle-ups and expenses', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: MemberView(trip: trip, expenses: expenses, memberId: 'a'))));

    expect(find.text('Aarav Mehta'), findsOneWidget);
    expect(find.text('aarav@okaxis'), findsOneWidget);
    expect(find.text('Gets Back'), findsOneWidget);
    expect(find.text('₹1,200'), findsWidgets);
    expect(find.text('Expenses (1)'), findsOneWidget); // Aarav isn't on the cab
    expect(find.text('Paid ₹1,800'), findsOneWidget);
  });
}
