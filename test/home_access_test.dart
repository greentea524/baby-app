import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:baby_app/data/models/baby.dart';
import 'package:baby_app/data/models/caregiver_invite.dart';
import 'package:baby_app/features/home/home_access.dart';

/// Who gets which empty Home. The app is invitation-only, so this decides
/// whether someone is offered a household, pointed at an invite, or told no —
/// and getting it wrong turns away the people it was meant to let in.
void main() {
  const invite = CaregiverInvite(
    babyId: 'baby1',
    babyName: 'Robin',
    email: 'bob@example.com',
    role: CaregiverRole.editor,
    invitedByUid: 'alice',
  );

  HomeEmptyState stateOf({
    required AsyncValue<bool> allowed,
    required AsyncValue<List<CaregiverInvite>> invites,
  }) => homeEmptyState(mayStartHousehold: allowed, incomingInvites: invites);

  group('once both answers are in', () {
    test('an allowlisted caregiver is asked to add a baby', () {
      expect(
        stateOf(
          allowed: const AsyncValue.data(true),
          invites: const AsyncValue.data([]),
        ),
        HomeEmptyState.addBaby,
      );
    });

    test('a stranger is told access is by invitation', () {
      expect(
        stateOf(
          allowed: const AsyncValue.data(false),
          invites: const AsyncValue.data([]),
        ),
        HomeEmptyState.locked,
      );
    });

    test('someone with a pending invite is pointed at it, not locked out', () {
      // The whole point of the allowlist is to gate *starting* a household.
      // An invitee is admitted by the owner, not by the list, so locking
      // them out here would block the exact people it was meant to let in.
      expect(
        stateOf(
          allowed: const AsyncValue.data(false),
          invites: const AsyncValue.data([invite]),
        ),
        HomeEmptyState.awaitingInvite,
      );
    });

    test('an allowlisted caregiver who also has an invite still gets the '
        'add-baby prompt', () {
      // Either route works for them; the banner is on screen regardless.
      expect(
        stateOf(
          allowed: const AsyncValue.data(true),
          invites: const AsyncValue.data([invite]),
        ),
        HomeEmptyState.addBaby,
      );
    });
  });

  group('while the answers are still arriving', () {
    test('nobody is accused of anything mid-round-trip', () {
      expect(
        stateOf(
          allowed: const AsyncValue.loading(),
          invites: const AsyncValue.data([]),
        ),
        HomeEmptyState.loading,
      );
      expect(
        stateOf(
          allowed: const AsyncValue.data(false),
          invites: const AsyncValue.loading(),
        ),
        HomeEmptyState.loading,
      );
    });

    test('but a known-good answer does not wait on the other', () {
      expect(
        stateOf(
          allowed: const AsyncValue.data(true),
          invites: const AsyncValue.loading(),
        ),
        HomeEmptyState.addBaby,
      );
      expect(
        stateOf(
          allowed: const AsyncValue.loading(),
          invites: const AsyncValue.data([invite]),
        ),
        HomeEmptyState.awaitingInvite,
      );
    });
  });

  group('when the allowlist read fails', () {
    test('the owner is not locked out of their own app', () {
      // Offline, or a transient Firestore error. Rules are what actually
      // stop a create, so guessing "allowed" here costs nothing and guessing
      // "locked" would greet the owner with a lock screen on a flaky train.
      expect(
        stateOf(
          allowed: AsyncValue.error(Exception('offline'), StackTrace.empty),
          invites: const AsyncValue.data([]),
        ),
        HomeEmptyState.addBaby,
      );
    });
  });
}
