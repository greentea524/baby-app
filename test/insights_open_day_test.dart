import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:baby_app/core/auth/auth_providers.dart';
import 'package:baby_app/core/theme/theme_mode_provider.dart';
import 'package:baby_app/data/models/baby.dart';
import 'package:baby_app/data/models/feeding_event.dart';
import 'package:baby_app/data/repositories/repository_providers.dart';
import 'package:baby_app/features/insights/insights_providers.dart';
import 'package:baby_app/features/insights/insights_screen.dart';
import 'package:baby_app/features/insights/range_stats.dart';
import 'package:baby_app/features/insights/trend_chart.dart';

/// A spike in a trend leads to the day behind it (#32).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final baby = Baby(
    id: 'baby1',
    name: 'Ada',
    birthDate: DateTime(2026, 2, 1),
    ownerUid: 'alice',
    members: const {'alice': CaregiverRole.owner},
  );

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final feeds = [
    for (var d = 0; d < 7; d++)
      for (var n = 0; n <= d; n++)
        FeedingEvent(
          id: 'f${d}_$n',
          type: FeedingType.bottle,
          startTime: now.subtract(Duration(days: d, hours: 2 + n)),
          amountMl: 120,
        ),
  ];

  InsightsData dataFor(InsightsRange range) => (
    stats: RangeStats.from(
      start: DateTime(now.year, now.month, now.day - range.days + 1),
      end: DateTime(now.year, now.month, now.day + 1),
      feedings: feeds,
      diapers: const [],
    ),
    feedings: feeds,
    diapers: const [],
    pumps: const [],
  );

  Future<ProviderContainer> pumpInsights(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final stored = await SharedPreferences.getInstance();
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(stored),
        authStateProvider.overrideWith((ref) => Stream.value(null)),
        babiesStreamProvider.overrideWith((ref) => Stream.value([baby])),
        for (final range in InsightsRange.values)
          rangeStatsProvider(range).overrideWith((ref) async => dataFor(range)),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: InsightsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  /// Taps a bar of [chart] — which one does not matter, only that the day
  /// opened is the day captioned.
  Future<void> tapABar(WidgetTester tester, Finder chart) async {
    final rect = tester.getRect(chart);
    // Past the y-axis gutter, and inside the plot rather than the caption.
    await tester.tapAt(Offset(rect.left + rect.width * 0.45, rect.top + 80));
    await tester.pumpAndSettle();
  }

  /// The day named by whichever caption is currently showing a value, read
  /// back from its "M/D · value" label.
  DateTime captionedDay(WidgetTester tester) {
    final pattern = RegExp(r'^(\d+)/(\d+) · ');
    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      final match = pattern.firstMatch(text.data ?? '');
      if (match != null) {
        return DateTime(
          now.year,
          int.parse(match.group(1)!),
          int.parse(match.group(2)!),
        );
      }
    }
    fail('no bar is captioned');
  }

  testWidgets('a per-day bar opens the day it captions', (tester) async {
    final container = await pumpInsights(tester);
    expect(container.read(selectedDayProvider), today);

    await tapABar(tester, find.byType(TrendChart).first);
    expect(find.text('Open this day'), findsOneWidget);
    final captioned = captionedDay(tester);
    // A day in the range, not the one the provider already held — otherwise
    // the assertion below would pass on a tap that did nothing.
    expect(captioned, isNot(today));

    await tester.tap(find.text('Open this day'));
    await tester.pump();
    // The harness has no GoRouter, so the push itself throws. Setting the
    // day happens first, and is the half this screen owns.
    tester.takeException();

    expect(container.read(selectedDayProvider), captioned);
  });

  testWidgets('but an hour-of-day bar offers no day to open', (tester) async {
    // "Feeds by hour of day" stacks the whole range into 24 columns. No
    // single day sits behind a bar, so there is nothing to open.
    await pumpInsights(tester);

    final byHour = find.ancestor(
      of: find.text('All 7 days stacked together'),
      matching: find.byType(Column),
    );
    expect(byHour, findsWidgets);

    final chart = find.descendant(
      of: byHour.first,
      matching: find.byType(TrendChart),
    );
    expect(chart, findsOneWidget);
    await tapABar(tester, chart);

    // It captions, as every chart does — it just goes no further.
    expect(find.textContaining(' · '), findsWidgets);
    expect(find.text('Open this day'), findsNothing);
  });
}
