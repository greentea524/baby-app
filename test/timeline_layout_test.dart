import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:baby_app/core/auth/auth_providers.dart';
import 'package:baby_app/core/theme/theme_mode_provider.dart';
import 'package:baby_app/data/models/baby.dart';
import 'package:baby_app/data/models/diaper_event.dart';
import 'package:baby_app/data/models/feeding_event.dart';
import 'package:baby_app/data/models/pumping_event.dart';
import 'package:baby_app/data/repositories/repository_providers.dart';
import 'package:baby_app/features/activity/activity_filter.dart';
import 'package:baby_app/features/activity/activity_tile.dart';
import 'package:baby_app/features/timeline/timeline_screen.dart';

/// How much of the timeline screen the list actually gets.
///
/// The stats were fixed above an Expanded list. On a busy day that is seven
/// chips, which wrap to three rows on a phone and take most of the screen —
/// so the day with the most to read was the day you read it through a slot.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final day = DateTime.now();
  DateTime at(int hour, [int minute = 0]) =>
      DateTime(day.year, day.month, day.day, hour, minute);

  final baby = Baby(
    id: 'baby1',
    name: 'Ada',
    birthDate: DateTime(2026, 2, 1),
    ownerUid: 'alice',
    members: const {'alice': CaregiverRole.owner},
  );

  /// A busy day: every stat chip earns its place, so the summary is as tall
  /// as it ever gets. That is the case worth measuring.
  final feeds = [
    for (var h = 1; h < 22; h += 3)
      FeedingEvent(
        id: 'f$h',
        type: h.isEven ? FeedingType.bottle : FeedingType.breast,
        startTime: at(h),
        amountMl: h.isEven ? 150 : null,
        durationMinutes: h.isEven ? null : 20,
      ),
    FeedingEvent(id: 'snack', type: FeedingType.bottle,
        startTime: at(11), amountMl: 40, isSnack: true),
  ];
  final diapers = [
    for (var h = 2; h < 22; h += 3)
      DiaperEvent(
        id: 'd$h',
        type: h.isEven ? DiaperType.wet : DiaperType.dirty,
        time: at(h),
      ),
  ];
  final pumps = [
    PumpingEvent(id: 'p1', time: at(8), amountMl: 90, durationMinutes: 15),
  ];

  Future<void> pumpTimeline(
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
          feedingsForDayProvider.overrideWith((ref) => Stream.value(feeds)),
          diapersForDayProvider.overrideWith((ref) => Stream.value(diapers)),
          pumpingForDayProvider.overrideWith((ref) => Stream.value(pumps)),
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
              child: const TimelineScreen(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Pumps the timeline the way Home reaches it — pushed over another
  /// route — because that is what puts a back button in the app bar.
  Future<void> pushTimeline(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
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
          feedingsForDayProvider.overrideWith((ref) => Stream.value(feeds)),
          diapersForDayProvider.overrideWith((ref) => Stream.value(diapers)),
          pumpingForDayProvider.overrideWith((ref) => Stream.value(pumps)),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const TimelineScreen(),
                    ),
                  ),
                  child: const Text('open timeline'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open timeline'));
    await tester.pumpAndSettle();
  }

  testWidgets('there is a way back out of it', (tester) async {
    // The timeline is pushed over Home, so the app bar's leading slot holds
    // the back button. Taking that slot for the previous-day chevron — which
    // this bar briefly did — left the screen with no exit at all.
    await pushTimeline(tester);
    expect(find.byType(ActivityTile), findsWidgets);

    expect(find.byType(BackButton), findsOneWidget);
  });

  testWidgets('and it actually goes back', (tester) async {
    await pushTimeline(tester);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.text('open timeline'), findsOneWidget);
    expect(find.byType(TimelineScreen), findsNothing);
  });

  testWidgets('with both day controls still reachable', (tester) async {
    // Moved to the actions side rather than dropped.
    await pushTimeline(tester);

    expect(find.byTooltip('Previous day'), findsOneWidget);
    expect(find.byTooltip('Next day'), findsOneWidget);
  });

  testWidgets('the busy-day fixture really is busy', (tester) async {
    // Guards the measurements below: they mean nothing against a day with
    // three chips and four rows.
    await pumpTimeline(tester);
    // The three optional chips, which only a day with all of it earns. Their
    // labels are unique to the summary; "Bottle" and "Diapers" are not, so
    // they make poor guards.
    expect(find.text('Snacks'), findsOneWidget);
    expect(find.text('Pumped'), findsOneWidget);
    expect(find.text('Breast'), findsOneWidget);
    expect(find.text('Avg interval'), findsOneWidget);
  });

  testWidgets('the list starts in the top half of the screen', (tester) async {
    await pumpTimeline(tester);

    final tiles = find.byType(ActivityTile);
    expect(tiles, findsWidgets);
    // Everything above the first row — app bar, summary, filter bar —
    // against the 844 the screen has. It was about 700 of it: a day nav bar
    // of its own, and a summary whose every chip took a row to itself.
    expect(tester.getRect(tiles.first).top, lessThan(844 * 0.55));
  });

  testWidgets('the summary is a couple of rows, not one chip per row', (
    tester,
  ) async {
    // The bug underneath the complaint: the Row inside each chip defaulted
    // to MainAxisSize.max, so every chip filled the Wrap. Seven chips, seven
    // rows, 518pt of summary.
    await pumpTimeline(tester);
    expect(tester.getSize(find.byType(Wrap).first).height, lessThan(320));
  });

  testWidgets('and the summary scrolls away entirely', (tester) async {
    await pumpTimeline(tester);
    expect(find.text('Avg interval'), findsOneWidget);

    await tester.drag(find.byType(ActivityTile).first, const Offset(0, -400));
    await tester.pumpAndSettle();

    expect(find.text('Avg interval'), findsNothing);
  });

  testWidgets('while the filter stays reachable', (tester) async {
    // The one control above the list that has to survive the scroll.
    await pumpTimeline(tester);
    await tester.drag(find.byType(ActivityTile).first, const Offset(0, -400));
    await tester.pumpAndSettle();

    expect(find.byType(ActivityFilterBar), findsOneWidget);
  });

  testWidgets('the day is still named, and still navigable', (tester) async {
    // It moved into the app bar; losing it would be a worse trade than the
    // row it saved.
    await pumpTimeline(tester);
    expect(find.byTooltip('Previous day'), findsOneWidget);
    expect(find.byTooltip('Next day'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
  });

  testWidgets('survives a small screen at 200% text', (tester) async {
    await pumpTimeline(
      tester,
      textScale: 2.0,
      size: const Size(320, 640),
    );
    expect(tester.takeException(), isNull);
  });
}
