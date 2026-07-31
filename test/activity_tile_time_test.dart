import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:baby_app/core/theme/theme_mode_provider.dart';
import 'package:baby_app/data/models/activity_entry.dart';
import 'package:baby_app/data/models/feeding_event.dart';
import 'package:baby_app/features/activity/activity_tile.dart';

/// How each surface labels time: Home shows a timestamp, the Timeline shows a
/// bare clock time because its nav bar already names the day.
void main() {
  // 2:30 PM on the 30th, read at 4:30 PM the same day.
  final now = DateTime(2026, 7, 30, 16, 30);
  final today = DateTime(2026, 7, 30, 14, 30);
  final yesterday = DateTime(2026, 7, 29, 21, 15);

  FeedingEntry entryAt(DateTime at) => FeedingEntry(
    FeedingEvent(id: 'f1', type: FeedingType.bottle, startTime: at),
  );

  Future<void> pumpTile(
    WidgetTester tester, {
    required DateTime at,
    required ActivityTimeDisplay display,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          home: Scaffold(
            body: ActivityTile(
              entry: entryAt(at),
              now: now,
              timeDisplay: display,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('Home shows a timestamp, not "x ago"', (tester) async {
    await pumpTile(tester, at: today, display: ActivityTimeDisplay.stamp);
    expect(find.textContaining('ago'), findsNothing);
    expect(find.textContaining('2:30'), findsOneWidget);
  });

  testWidgets('a row from an earlier day carries its date', (tester) async {
    // The recent list spans days, so a bare "9:15 PM" could be any night.
    await pumpTile(tester, at: yesterday, display: ActivityTimeDisplay.stamp);
    expect(find.textContaining('Jul 29'), findsOneWidget);
    expect(find.textContaining('ago'), findsNothing);
  });

  testWidgets('the timeline keeps a bare clock time', (tester) async {
    // Its nav bar already names the day, so a date on every row is noise.
    await pumpTile(tester, at: yesterday, display: ActivityTimeDisplay.clock);
    expect(find.textContaining('Jul 29'), findsNothing);
    expect(find.textContaining('9:15'), findsOneWidget);
  });

  testWidgets('relative mode still pairs "x ago" with the stamp', (
    tester,
  ) async {
    await pumpTile(tester, at: today, display: ActivityTimeDisplay.relative);
    expect(find.textContaining('2 hr ago'), findsOneWidget);
    expect(find.textContaining('2:30'), findsOneWidget);
  });
}
