import 'package:flutter_test/flutter_test.dart';

import 'package:baby_app/features/notifications/push_service.dart';

/// The reminder switches in Settings are gated on this. Getting it wrong in
/// either direction is a silent failure: hidden when it should work, or
/// offered when nothing can arrive.
void main() {
  test('tracks whether the build carries a VAPID key', () {
    // The contract, true of any build. Run the suite with
    // `--dart-define=VAPID_KEY=x` and this still holds, with both sides true.
    expect(backgroundRemindersAvailable, kWebPushVapidKey.isNotEmpty);
  });

  test(
    'an ordinary build has no key, so the switches stay hidden',
    () {
      // No --dart-define here, which is also what `flutter build web` does
      // unless someone passes the key deliberately.
      expect(kWebPushVapidKey, isEmpty);
      expect(backgroundRemindersAvailable, isFalse);
    },
    // Skipped rather than failed under `--dart-define=VAPID_KEY=...`: that is
    // a legitimate way to run the suite, and the invariant above already
    // covers it.
    skip: kWebPushVapidKey.isNotEmpty
        ? 'built with a VAPID key, so the switches are meant to show'
        : null,
  );
}
