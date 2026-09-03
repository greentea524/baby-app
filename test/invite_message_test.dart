import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:baby_app/data/models/baby.dart';
import 'package:baby_app/data/models/caregiver_invite.dart';
import 'package:baby_app/features/caregivers/caregivers_screen.dart';
import 'package:baby_app/features/caregivers/invite_message.dart';

void main() {
  group('inviteShareMessage', () {
    test('names the baby and the address to sign in with', () {
      final msg = inviteShareMessage(
        babyName: 'Rosa',
        email: 'gran@example.com',
        appUrl: 'https://baby.example.app',
      );
      expect(msg, contains('Rosa'));
      expect(msg, contains('gran@example.com'));
      expect(msg, contains('https://baby.example.app'));
    });

    test('says the address has to match', () {
      // The silent failure this whole change exists for: a different Google
      // account finds nothing, with no error anywhere.
      final msg = inviteShareMessage(
        babyName: 'Rosa',
        email: 'gran@example.com',
      );
      expect(msg.toLowerCase(), contains('that address'));
    });

    test('drops the link when there is no URL to give', () {
      final msg = inviteShareMessage(
        babyName: 'Rosa',
        email: 'gran@example.com',
      );
      expect(msg, isNot(contains('Open ')));
      expect(msg, contains('Sign in with gran@example.com'));
    });

    test('treats an empty URL as no URL', () {
      final msg = inviteShareMessage(
        babyName: 'Rosa',
        email: 'gran@example.com',
        appUrl: '',
      );
      expect(msg, isNot(contains('Open ')));
    });

    test('never claims anything was sent', () {
      final msg = inviteShareMessage(
        babyName: 'Rosa',
        email: 'gran@example.com',
        appUrl: 'https://baby.example.app',
      ).toLowerCase();
      for (final word in ['sent you', 'emailed', 'invitation email']) {
        expect(msg, isNot(contains(word)));
      }
    });
  });

  group('PendingInviteTile', () {
    const invite = CaregiverInvite(
      babyId: 'b1',
      babyName: 'Rosa',
      email: 'gran@example.com',
      role: CaregiverRole.editor,
      invitedByUid: 'owner-uid',
    );

    Future<void> pumpTile(
      WidgetTester tester, {
      required bool canRevoke,
      VoidCallback? onCopy,
      VoidCallback? onRevoke,
    }) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PendingInviteTile(
            invite: invite,
            canRevoke: canRevoke,
            onCopy: onCopy ?? () {},
            onRevoke: onRevoke ?? () {},
          ),
        ),
      ),
    );

    testWidgets('shows the address and that it is still waiting', (
      tester,
    ) async {
      await pumpTile(tester, canRevoke: true);
      expect(find.text('gran@example.com'), findsOneWidget);
      expect(
        find.textContaining('waiting for them to sign in'),
        findsOneWidget,
      );
      // A mail icon would imply something was posted.
      expect(find.byIcon(Icons.mail_outline), findsNothing);
    });

    testWidgets('copy fires', (tester) async {
      var copied = false;
      await pumpTile(tester, canRevoke: true, onCopy: () => copied = true);
      await tester.tap(find.byIcon(Icons.copy));
      expect(copied, isTrue);
    });

    testWidgets('the owner can revoke', (tester) async {
      var revoked = false;
      await pumpTile(tester, canRevoke: true, onRevoke: () => revoked = true);
      await tester.tap(find.byIcon(Icons.close));
      expect(revoked, isTrue);
    });

    testWidgets('a non-owner gets copy but not revoke', (tester) async {
      // The roster asymmetry: the owner removes people, other members can only
      // remove themselves. Copying repeats an address already on this row, so
      // it stays available to everyone who can see it.
      await pumpTile(tester, canRevoke: false);
      expect(find.byIcon(Icons.copy), findsOneWidget);
      expect(find.byIcon(Icons.close), findsNothing);
    });
  });
}
