import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:baby_app/core/auth/auth_providers.dart';
import 'package:baby_app/core/theme/theme_mode_provider.dart';
import 'package:baby_app/data/models/baby.dart';
import 'package:baby_app/data/models/diaper_event.dart';
import 'package:baby_app/data/models/feeding_event.dart';
import 'package:baby_app/data/repositories/repository_providers.dart';
import 'package:baby_app/features/home/home_screen.dart';

/// Where the "x ago" sits on the Home status rows.
///
/// It is meant to be hard right, matching the activity list below. It was
/// not: the `Wrap` that paired label and time shrink-wrapped to its children,
/// so `WrapAlignment.spaceBetween` had no free space to distribute and the
/// time simply trailed the label. Rows disagreed with each other — the short
/// "Last fed" left its time short of the edge, and the long "Last diaper
/// changed" pushed its own onto a second line against the *left* margin.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime.now();
  final baby = Baby(
    id: 'baby1',
    name: 'Ada',
    birthDate: DateTime(2026, 2, 1),
    ownerUid: 'alice',
    members: const {'alice': CaregiverRole.owner},
  );

  /// A feed two hours back and a change forty minutes back, which is the case
  /// that matters: "2 hr ago" fits beside its short label and "40 min ago"
  /// cannot fit beside the longest one, so the two rows exercise both
  /// branches at once.
  Future<void> pumpHome(WidgetTester tester, {double textScale = 1.0}) async {
    SharedPreferences.setMockInitialValues({'reminder_mode': 'fixedInterval'});
    final stored = await SharedPreferences.getInstance();

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(stored),
          authStateProvider.overrideWith((ref) => Stream.value(null)),
          babiesStreamProvider.overrideWith((ref) => Stream.value([baby])),
          recentFeedingsProvider.overrideWith(
            (ref) => Stream.value([
              FeedingEvent(
                id: 'f1',
                type: FeedingType.bottle,
                startTime: now.subtract(const Duration(hours: 2)),
                amountMl: 150,
              ),
            ]),
          ),
          recentDiapersProvider.overrideWith(
            (ref) => Stream.value([
              DiaperEvent(
                id: 'd1',
                type: DiaperType.wet,
                time: now.subtract(const Duration(minutes: 40)),
              ),
            ]),
          ),
        ],
        child: MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: const HomeScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the two rows agree on where the time ends', (tester) async {
    await pumpHome(tester);

    final fed = tester.getRect(find.text('2 hr ago'));
    final changed = tester.getRect(find.text('40 min ago'));

    expect(changed.right, moreOrLessEquals(fed.right, epsilon: 0.5));
  });

  testWidgets('and that is the edge the detail line reaches', (tester) async {
    // Anchored on a full-width line in the same card rather than a hard
    // number, so the assertion survives a change of margin.
    await pumpHome(tester);

    final detail = tester.getRect(find.textContaining('· Bottle ·'));
    expect(
      tester.getRect(find.text('2 hr ago')).right,
      moreOrLessEquals(detail.right, epsilon: 0.5),
    );
    expect(
      tester.getRect(find.text('40 min ago')).right,
      moreOrLessEquals(detail.right, epsilon: 0.5),
    );
  });

  testWidgets('a time that fits still shares its label\'s line', (tester) async {
    // The pairing is the reason the row is three lines and not four; pushing
    // every time onto its own line would align them and lose that.
    await pumpHome(tester);

    final label = tester.getRect(find.text('Last fed'));
    final value = tester.getRect(find.text('2 hr ago'));
    expect(value.top, lessThan(label.bottom));
    expect(value.left, greaterThan(label.right));
  });

  testWidgets('a time that does not fit drops below its label', (tester) async {
    await pumpHome(tester);

    final label = tester.getRect(find.text('Last diaper changed'));
    expect(tester.getRect(find.text('40 min ago')).top, greaterThanOrEqualTo(label.bottom));
  });

  testWidgets('stays right-aligned at 200% text', (tester) async {
    // At this size nothing pairs, so both rows take the stacked branch — the
    // one a Wrap could not right-align, since it puts a lone child at the
    // start of its run.
    await pumpHome(tester, textScale: 2.0);
    expect(tester.takeException(), isNull);

    final fed = tester.getRect(find.text('2 hr ago'));
    final changed = tester.getRect(find.text('40 min ago'));
    expect(changed.right, moreOrLessEquals(fed.right, epsilon: 0.5));
  });
}
