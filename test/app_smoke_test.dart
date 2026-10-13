import 'package:flutter_test/flutter_test.dart';
import 'package:trip_split_gujarat/main.dart';

void main() {
  testWidgets('app builds without throwing', (tester) async {
    await tester.pumpWidget(const TripSplitApp());
    await tester.pump();
    expect(find.byType(TripSplitApp), findsOneWidget);
  });
}
