import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:trip_split_gujarat/main.dart';

void main() {
  testWidgets('app builds without throwing', (tester) async {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    await tester.pumpWidget(const TripSplitApp());
    await tester.pump();
    expect(find.byType(TripSplitApp), findsOneWidget);
  });
}
