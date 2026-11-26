import 'package:flutter_test/flutter_test.dart';

import 'package:baby_app/data/models/baby.dart';
import 'package:baby_app/data/repositories/repository_providers.dart';

/// Caregivers are shown by name, not by a slice of their account id (#44).
void main() {
  final baby = Baby(
    id: 'b',
    name: 'Ada',
    birthDate: DateTime(2026, 2, 1),
    ownerUid: 'alice',
    members: const {
      'alice': CaregiverRole.owner,
      'bob': CaregiverRole.editor,
      'carol': CaregiverRole.editor,
    },
    memberNames: const {'alice': 'Alice', 'bob': '  '},
  );

  test('a caregiver goes by the name their app saved', () {
    expect(baby.memberName('alice'), 'Alice');
  });

  test('and by "Caregiver" until it has, never their account id', () {
    // "User a1b2c3" told nobody who it was.
    expect(baby.memberName('carol'), 'Caregiver');
    expect(baby.memberName('bob'), 'Caregiver');
  });

  test('the name saved is the display name, else the email', () {
    expect(caregiverNameOf('Bob Smith', 'bob@example.com'), 'Bob Smith');
    expect(caregiverNameOf('  ', 'bob@example.com'), 'bob@example.com');
    expect(caregiverNameOf(null, null), isNull);
    // The rules cap a name at 100.
    expect(caregiverNameOf('x' * 300, null), hasLength(100));
  });

  test('a profile edit keeps the names', () {
    expect(baby.copyWith(name: 'Ada B').memberNames, baby.memberNames);
  });
}
