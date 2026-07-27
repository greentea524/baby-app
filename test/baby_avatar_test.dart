import 'package:baby_app/data/models/baby.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Baby sample({BabyAvatar avatar = BabyAvatar.baby}) => Baby(
    id: 'b',
    name: 'Ada',
    birthDate: DateTime(2026, 1, 1),
    avatar: avatar,
    ownerUid: 'u',
    members: const {'u': CaregiverRole.owner},
  );

  group('BabyAvatar.fromName', () {
    test('resolves a stored name', () {
      expect(BabyAvatar.fromName('fox'), BabyAvatar.fox);
      expect(BabyAvatar.fromName('panda'), BabyAvatar.panda);
    });

    test('falls back for profiles saved before avatars existed', () {
      expect(BabyAvatar.fromName(null), BabyAvatar.baby);
    });

    test('falls back for a value this build does not know', () {
      // A newer client could write an avatar this build has never heard of;
      // that must not break the profile.
      expect(BabyAvatar.fromName('dinosaur'), BabyAvatar.baby);
    });

    test('every avatar has a glyph and a readable label', () {
      for (final a in BabyAvatar.values) {
        expect(a.emoji, isNotEmpty, reason: '${a.name} needs an emoji');
        expect(a.label, isNotEmpty, reason: '${a.name} needs a label');
      }
    });
  });

  group('Baby profile serialization', () {
    test('writes the avatar by name, not by glyph', () {
      final map = sample(avatar: BabyAvatar.koala).toProfileMap();
      expect(map['avatar'], 'koala');
    });

    test('defaults to the baby avatar when unset', () {
      expect(sample().avatar, BabyAvatar.baby);
    });

    test('copyWith swaps the avatar and leaves the rest alone', () {
      final updated = sample(
        avatar: BabyAvatar.fox,
      ).copyWith(avatar: BabyAvatar.lion);
      expect(updated.avatar, BabyAvatar.lion);
      expect(updated.name, 'Ada');
      expect(updated.ownerUid, 'u');
      expect(updated.members, {'u': CaregiverRole.owner});
    });

    test('copyWith keeps the existing avatar when none is passed', () {
      final updated = sample(avatar: BabyAvatar.bunny).copyWith(name: 'Bea');
      expect(updated.avatar, BabyAvatar.bunny);
      expect(updated.name, 'Bea');
    });
  });
}
