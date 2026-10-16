import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:baby_app/core/auth/auth_providers.dart';
import 'package:baby_app/core/theme/theme_mode_provider.dart';
import 'package:baby_app/data/models/diaper_event.dart';
import 'package:baby_app/data/repositories/repository_providers.dart';
import 'package:baby_app/features/home/home_status_card.dart';
import 'package:baby_app/features/insights/diaper_mix_bar.dart';

/// Today's wet and dirty counts on Home's diaper row: one short line
/// beside the clock time, where the row had room to spare.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 10, 16, 15);

  /// One count on the line — "3 wet" — which is part of a single run of
  /// text, held together by non-breaking spaces.
  Finder count(String text) =>
      find.textContaining(text.replaceAll(' ', '\u00a0'), findRichText: true);
  DiaperEvent change(String id, DiaperType type, Duration ago) =>
      DiaperEvent(id: id, type: type, time: now.subtract(ago));

  Future<void> pumpCard(WidgetTester tester, List<DiaperEvent> diapers) async {
    SharedPreferences.setMockInitialValues({'unit_system': 'metric'});
    final stored = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(stored),
          authStateProvider.overrideWith((ref) => Stream.value(null)),
          recentFeedingsProvider.overrideWith((ref) => Stream.value([])),
          recentDiapersProvider.overrideWith((ref) => Stream.value(diapers)),
          recentPumpingProvider.overrideWith((ref) => Stream.value([])),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: HomeStatusCard(now: now)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('counts today\'s wet and dirty, a both in each', (tester) async {
    await pumpCard(tester, [
      change('a', DiaperType.wet, const Duration(hours: 1)),
      change('b', DiaperType.both, const Duration(hours: 3)),
      change('c', DiaperType.wet, const Duration(hours: 5)),
      change('d', DiaperType.dirty, const Duration(hours: 7)),
      // Yesterday: not today's.
      change('e', DiaperType.dirty, const Duration(hours: 20)),
    ]);
    expect(count('3 wet'), findsOneWidget);
    expect(count('2 dirty'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('Today: 3 wet, 2 dirty')),
      findsOneWidget,
    );
  });

  testWidgets('keeps a nought, which is the count that matters', (
    tester,
  ) async {
    await pumpCard(tester, [
      change('a', DiaperType.wet, const Duration(hours: 1)),
      change('b', DiaperType.dirty, const Duration(hours: 20)),
    ]);
    expect(count('1 wet'), findsOneWidget);
    expect(count('0 dirty'), findsOneWidget);
  });

  testWidgets('sits beside the clock time rather than below the row', (
    tester,
  ) async {
    await pumpCard(tester, [
      change('a', DiaperType.wet, const Duration(hours: 1)),
    ]);
    // On the test's default 800-wide screen: the test font's glyphs are
    // wider than any real one's, and at a phone's width the times stack.
    final counts = tester.getRect(count('1 wet'));
    final clock = tester.getRect(find.text('2:00 PM'));
    expect((counts.center.dy - clock.center.dy).abs(), lessThan(4));
    // No bar: the Insights one is three lines of height.
    expect(find.byType(DiaperMixBar), findsNothing);
  });

  testWidgets('and is not there before the first change ever', (tester) async {
    await pumpCard(tester, const []);
    expect(find.text('No changes yet'), findsOneWidget);
    expect(count(' wet'), findsNothing);
  });
}
