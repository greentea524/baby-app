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
import 'package:baby_app/features/insights/report_tables.dart';

/// Charts or tables, on the same window (#30).
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
  final feeds = [
    for (var d = 1; d < 6; d++)
      FeedingEvent(
        id: 'f$d',
        type: FeedingType.bottle,
        startTime: now.subtract(Duration(days: d, hours: 2)),
        amountMl: 120,
      ),
  ];

  /// The same value for every range, so a switch cannot be mistaken for a
  /// refetch: if the screen ever spins on toggling, it is recomputing.
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

  Future<void> pumpInsights(
    WidgetTester tester, {
    double textScale = 1.0,
    Size size = const Size(390, 844),
  }) async {
    SharedPreferences.setMockInitialValues({});
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
          for (final range in InsightsRange.values)
            rangeStatsProvider(
              range,
            ).overrideWith((ref) async => dataFor(range)),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: const InsightsScreen(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('opens on the charts, as it always did', (tester) async {
    await pumpInsights(tester);

    expect(find.byType(ReportTables), findsNothing);
    expect(find.byTooltip('Charts'), findsOneWidget);
    expect(find.byTooltip('Table'), findsOneWidget);
  });

  testWidgets('the table icon shows the report', (tester) async {
    await pumpInsights(tester);
    await tester.tap(find.byTooltip('Table'));
    await tester.pumpAndSettle();

    expect(find.byType(ReportTables), findsOneWidget);
    expect(find.text('Total feeds'), findsOneWidget);
  });

  testWidgets('and the chart icon brings them back', (tester) async {
    await pumpInsights(tester);
    await tester.tap(find.byTooltip('Table'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Charts'));
    await tester.pumpAndSettle();

    expect(find.byType(ReportTables), findsNothing);
  });

  testWidgets('switching does not refetch', (tester) async {
    // Both views render from the value already loaded. A spinner here would
    // mean the same numbers were being computed twice.
    await pumpInsights(tester);
    await tester.tap(find.byTooltip('Table'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('the range picker keeps working underneath it', (tester) async {
    await pumpInsights(tester);
    await tester.tap(find.byTooltip('Table'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Month'));
    await tester.pumpAndSettle();

    // Still the table, now for a different window.
    expect(find.byType(ReportTables), findsOneWidget);
  });

  testWidgets('there is no toggle for a single day', (tester) async {
    // A one-row table is not worth a control, and the day range shows a
    // different set of charts anyway.
    await pumpInsights(tester);
    await tester.tap(find.text('Day'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Table'), findsNothing);
    expect(find.byTooltip('Charts'), findsNothing);
  });

  testWidgets('the icons fit beside the range picker at 200% text', (
    tester,
  ) async {
    // The trap this app has hit repeatedly: a control row that fits at the
    // default size and overflows once the text grows.
    await pumpInsights(tester, textScale: 2.0, size: const Size(320, 640));

    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Table'), findsOneWidget);
  });
}
