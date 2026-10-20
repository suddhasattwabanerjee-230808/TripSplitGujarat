import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_split_gujarat/invite_email.dart';
import 'package:trip_split_gujarat/models.dart';
import 'package:trip_split_gujarat/screens/trips_ui.dart';
import 'package:trip_split_gujarat/update_service.dart';

const _trip = Trip(id: 't1', name: 'Gir & Somnath', destination: null, inviteCode: 'HVHKBJ');

void main() {
  test('accepts real addresses and rejects junk', () {
    expect(InviteEmail.isValidAddress('friend@gmail.com'), isTrue);
    expect(InviteEmail.isValidAddress('  first.last+trip@example.co.in '), isTrue);
    expect(InviteEmail.isValidAddress(''), isFalse);
    expect(InviteEmail.isValidAddress('friend'), isFalse);
    expect(InviteEmail.isValidAddress('friend@gmail'), isFalse);
    expect(InviteEmail.isValidAddress('a b@gmail.com'), isFalse);
  });

  test('the email carries the download link, the code and the inviter', () {
    final body = InviteEmail.body(_trip, 'Bittu', to: 'friend@gmail.com');
    expect(body, contains('sign in with Google using this address: friend@gmail.com'));
    expect(InviteEmail.body(_trip, 'Bittu', to: 'friend@gmail.com', autoJoin: false), isNot(contains('this address')));
    expect(body, contains(UpdateService.apkUrl));
    expect(body, contains('HVHKBJ'));
    expect(body, contains('Bittu'));
    expect(body, contains('Gir & Somnath'));
    expect(InviteEmail.subject(_trip, 'Bittu'), contains('Gir & Somnath'));
    expect(UpdateService.apkUrl, endsWith('/releases/latest/download/TripSplit.apk'));
  });

  testWidgets('invite sheet fits a phone and checks the address', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 1080 / 393;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(onPressed: () => showInviteSheet(context, _trip), child: const Text('open')),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Invite to Gir & Somnath'), findsOneWidget);
    expect(find.text('HVHKBJ'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'not-an-email');
    await tester.tap(find.text('Send invite'));
    await tester.pump();
    expect(find.textContaining('Enter an email address'), findsOneWidget);
  });
}
