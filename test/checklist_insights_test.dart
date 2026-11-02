import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:baby_app/data/models/baby.dart';
import 'package:baby_app/data/models/daily_check.dart';
import 'package:baby_app/data/repositories/repository_providers.dart';
import 'package:baby_app/features/checklist/checklist_insights.dart';
import 'package:baby_app/features/checklist/checklist_logic.dart';

/// The daily checklist in Insights: days done over the range, the average
/// day, and the current and best streaks.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 11, 2, 15);
  const vitamin = ChecklistItem(id: 'vitamin-d', label: 'Vitamin D');
  const tummy = ChecklistItem(
    id: 'tummy-time',
    label: 'Tummy time',
    minutes: 30,
  );

  DailyCheck on(String item, int daysAgo, {int? minutes, int hour = 9}) =>
      DailyCheck(
        id: '$item-$daysAgo-$hour',
        itemId: item,
        time: DateTime(2026, 11, 2 - daysAgo, hour),
        minutes: minutes,
      );

  group('the numbers', () {
    test('the best streak is the longest run, wherever it was', () {
      final checks = [
        for (final d in [0, 1, 2]) on('vitamin-d', d),
        for (final d in [10, 11, 12, 13, 14]) on('vitamin-d', d),
        on('vitamin-d', 20),
      ];
      expect(bestStreak(checks, vitamin), 5);
      expect(streak(checks, vitamin, now), 3);
      expect(bestStreak(const [], vitamin), 0);
    });

    test('a range counts its days done and its average day', () {
      final checks = [
        on('tummy-time', 0, minutes: 30),
        on('tummy-time', 1, minutes: 10),
        on('tummy-time', 1, minutes: 25, hour: 15),
        on('tummy-time', 3, minutes: 5),
        // Outside the week.
        on('tummy-time', 8, minutes: 60),
      ];
      final week = rangeSummary(checks, tummy, now, count: 7);
      expect(week.doneDays, 2);
      expect(week.perDay, closeTo(70 / 7, 1e-9));
    });
  });

  Future<void> pump(
    WidgetTester tester, {
    required int days,
    required List<DailyCheck> checks,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentBabyProvider.overrideWithValue(
            Baby(
              id: 'b',
              name: 'Ada',
              birthDate: DateTime(2026, 7, 1),
              ownerUid: 'a',
              members: const {'a': CaregiverRole.owner},
              checklist: const [vitamin, tummy],
            ),
          ),
          checksSinceProvider.overrideWith(
            (ref, start) => Stream.value(checks),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ChecklistInsights(days: days, now: now),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  String text(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(ValueKey(key))).data!;

  testWidgets('a week: days done, the average, and the streaks', (
    tester,
  ) async {
    await pump(
      tester,
      days: 7,
      checks: [
        for (final d in [0, 1, 2, 4]) on('vitamin-d', d),
        for (final d in [9, 10, 11, 12, 13]) on('vitamin-d', d),
        on('tummy-time', 0, minutes: 30),
        on('tummy-time', 1, minutes: 12),
      ],
    );

    // Once a day: done or not, so no average.
    expect(text(tester, 'insight-vitamin-d'), 'Done 4 of 7 days');
    expect(text(tester, 'streaks-vitamin-d'), 'Streak 3 days · best 5 days');
    expect(
      text(tester, 'insight-tummy-time'),
      'Done 1 of 7 days · 6 min a day on average',
    );
    expect(text(tester, 'streaks-tummy-time'), 'Streak 1 day · best 1 day');
    expect(find.bySemanticsLabel('Done 4 of the last 7 days'), findsOneWidget);
  });

  testWidgets('a day: how far today has got', (tester) async {
    await pump(
      tester,
      days: 1,
      checks: [on('tummy-time', 0, minutes: 15), on('vitamin-d', 1)],
    );
    expect(text(tester, 'insight-vitamin-d'), 'Not done yet today');
    expect(text(tester, 'streaks-vitamin-d'), 'Streak 1 day · best 1 day');
    expect(text(tester, 'insight-tummy-time'), '15 min of 30 min today');
    expect(text(tester, 'streaks-tummy-time'), 'No streak now');
  });
}
