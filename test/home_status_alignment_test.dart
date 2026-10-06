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
import 'package:baby_app/features/home/home_status_card.dart';

/// How a Home status row is laid out: what happened on the left, when on
/// the right, and what is coming across the full width underneath.
///
/// Read in passes down the card's edges, so the edges are what is pinned:
/// every row's elapsed time ends on the same line, the headline it answers
/// sits level with it, and a row that cannot fit the two side by side moves
/// its time underneath — as every other row on the card does, so they still
/// read alike.
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

  /// A feed two hours back and a change forty minutes back: two rows whose
  /// elapsed times differ in width, so lining them up means something.
  Future<void> pumpHome(
    WidgetTester tester, {
    double textScale = 1.0,
    // Wider than a phone because the test font is: its glyphs are a full
    // em square, so a time takes more room than in any real font, and at a
    // phone's width every row would already have stacked.
    Size size = const Size(600, 900),
  }) async {
    SharedPreferences.setMockInitialValues({
      'reminder_mode': 'fixedInterval',
      'unit_system': 'metric',
    });
    final stored = await SharedPreferences.getInstance();

    tester.view.physicalSize = size;
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
          home: Builder(
            // copyWith, not a fresh MediaQueryData: building one from scratch
            // throws away `size`, and anything that lays out from the screen
            // width then sees zero.
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: const HomeScreen(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Finders kept to the status card: the activity list under it repeats
  /// some of the same words.
  final card = (
    text: (String t) => find.descendant(
      of: find.byType(HomeStatusCard),
      matching: find.text(t),
    ),
    textContaining: (String t) => find.descendant(
      of: find.byType(HomeStatusCard),
      matching: find.textContaining(t),
    ),
    chip: find.descendant(
      of: find.byType(HomeStatusCard),
      matching: find.byType(DueChip),
    ),
    icon: find
        .descendant(
          of: find.byType(HomeStatusCard),
          matching: find.byType(IconButton),
        )
        .first,
  );

  testWidgets('the two rows agree on where the time ends', (tester) async {
    await pumpHome(tester);

    final fed = tester.getRect(card.text('2h ago'));
    final changed = tester.getRect(card.text('40m ago'));

    expect(changed.right, moreOrLessEquals(fed.right, epsilon: 0.5));
  });

  testWidgets('what happened sits level with when', (tester) async {
    await pumpHome(tester);

    // The amount held to its unit, so it never breaks between the two.
    final what = tester.getRect(card.text('Bottle · 150\u00a0ml'));
    final when = tester.getRect(card.text('2h ago'));
    expect(when.top, moreOrLessEquals(what.top, epsilon: 0.5));
    expect(when.left, greaterThan(what.right));

    expect(
      tester.getRect(card.text('40m ago')).top,
      moreOrLessEquals(tester.getRect(card.text('Wet')).top, epsilon: 0.5),
    );
  });

  testWidgets('the label is above the headline, level with the icon', (
    tester,
  ) async {
    await pumpHome(tester);

    final label = tester.getRect(card.text('FEED'));
    final what = tester.getRect(card.text('Bottle · 150\u00a0ml'));
    expect(label.bottom, lessThanOrEqualTo(what.top));
    expect(label.left, moreOrLessEquals(what.left, epsilon: 0.5));

    final icon = tester.getRect(card.icon);
    expect(icon.top, moreOrLessEquals(label.top, epsilon: 4));
  });

  testWidgets('the clock time is under the elapsed time, on its edge', (
    tester,
  ) async {
    await pumpHome(tester);

    final ago = tester.getRect(card.text('2h ago'));
    final clock = TimeOfDay.fromDateTime(
      now.subtract(const Duration(hours: 2)),
    );
    final element = tester.element(card.text('2h ago'));
    final at = tester.getRect(card.text(clock.format(element)));
    expect(at.top, greaterThanOrEqualTo(ago.bottom));
    expect(at.right, moreOrLessEquals(ago.right, epsilon: 0.5));
  });

  testWidgets('the next-feed chip runs the width of the text', (tester) async {
    await pumpHome(tester);

    final chip = tester.getRect(card.chip);
    expect(
      chip.left,
      moreOrLessEquals(
        tester.getRect(card.text('Bottle · 150\u00a0ml')).left,
        epsilon: 0.5,
      ),
    );
    expect(
      chip.right,
      moreOrLessEquals(tester.getRect(card.text('2h ago')).right, epsilon: 0.5),
    );
  });

  testWidgets('and keeps the columns on a wide screen', (tester) async {
    await pumpHome(tester, size: const Size(1200, 900));

    final what = tester.getRect(card.text('Bottle · 150\u00a0ml'));
    final when = tester.getRect(card.text('2h ago'));
    expect(when.top, moreOrLessEquals(what.top, epsilon: 0.5));
    expect(
      tester.getRect(card.chip).right,
      moreOrLessEquals(when.right, epsilon: 0.5),
    );
  });

  testWidgets('at 200% text every row moves its time underneath', (
    tester,
  ) async {
    // The feed's "2h ago" is narrower than the diaper's "40m ago" would
    // be at its widest; decided row by row, one would keep its column and
    // the other not. Measured against the same widest time, both move.
    await pumpHome(tester, textScale: 2.0);
    expect(tester.takeException(), isNull);

    final what = tester.getRect(card.text('Bottle · 150\u00a0ml'));
    final fed = tester.getRect(card.textContaining('2h ago · '));
    final changed = tester.getRect(card.textContaining('40m ago · '));
    expect(fed.top, greaterThanOrEqualTo(what.bottom));
    expect(fed.left, moreOrLessEquals(what.left, epsilon: 0.5));
    expect(changed.left, moreOrLessEquals(fed.left, epsilon: 0.5));
  });
}
