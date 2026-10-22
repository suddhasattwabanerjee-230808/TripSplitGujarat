import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:trip_split_gujarat/models.dart';
import 'package:trip_split_gujarat/screens/trip_home_screen.dart';
import 'package:trip_split_gujarat/trip_store.dart';

const _trip = Trip(
  id: 't1',
  name: 'Gujarat Trip',
  destination: null,
  inviteCode: 'HVHKBJ',
  members: [
    TripMember(id: 'a', name: 'Aarav Mehta'),
    TripMember(id: 'b', name: 'Priya Shah'),
    TripMember(id: 'c', name: 'Kabir Rao'),
  ],
);

bool _selected(WidgetTester tester, String label) =>
    tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label)).selected;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    TripStore.instance.trips = [_trip];
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    // No location in tests.
    messenger.setMockMethodCallHandler(const MethodChannel('flutter.baseflow.com/geolocator'), (_) async => null);
    messenger.setMockMethodCallHandler(const MethodChannel('flutter.baseflow.com/permissions/methods'), (_) async => 0);
  });

  testWidgets('split between some members, and the category follows the description', (tester) async {
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: ExpenseSheet(tripId: 't1')))));
    await tester.pump();

    // Everyone by default.
    expect(find.text('SPLIT BETWEEN'), findsOneWidget);
    expect(find.text('Split equally between everyone.'), findsOneWidget);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Dinner at Manek Chowk');
    await tester.enterText(fields.at(1), '300');
    await tester.pump();
    expect(_selected(tester, 'Food'), isTrue);
    expect(find.textContaining('Each · Everyone'), findsOneWidget);

    // Leave Kabir out: 150 each between two of three.
    await tester.tap(find.widgetWithText(FilterChip, 'Kabir'));
    await tester.pump();
    expect(find.textContaining('150 Each · 2 Of 3 People'), findsOneWidget);
    expect(find.text('Everyone'), findsOneWidget);

    // Only Priya: paying on her behalf.
    await tester.tap(find.widgetWithText(FilterChip, 'Aarav'));
    await tester.pump();
    expect(find.textContaining('Only Priya owes this'), findsOneWidget);
    // The last person can't be removed.
    await tester.tap(find.widgetWithText(FilterChip, 'Priya'));
    await tester.pump();
    expect(find.textContaining('Only Priya owes this'), findsOneWidget);

    // A manual pick sticks until the description clearly says otherwise.
    await tester.tap(find.widgetWithText(ChoiceChip, 'Shopping'));
    await tester.pump();
    await tester.enterText(fields.at(0), 'Dinner at Manek Chowk with mom');
    await tester.pump();
    expect(_selected(tester, 'Food'), isTrue); // "dinner" is still clear
    await tester.tap(find.widgetWithText(ChoiceChip, 'Shopping'));
    await tester.enterText(fields.at(0), 'Gift for mom');
    await tester.pump();
    expect(_selected(tester, 'Shopping'), isTrue);
    await tester.enterText(fields.at(0), 'Taxi to Adalaj');
    await tester.pump();
    expect(_selected(tester, 'Transport'), isTrue);

  });
}
