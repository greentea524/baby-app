import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:baby_app/core/auth/auth_providers.dart';
import 'package:baby_app/core/theme/theme_mode_provider.dart';
import 'package:baby_app/data/models/activity_entry.dart';
import 'package:baby_app/data/models/baby.dart';
import 'package:baby_app/data/models/diaper_event.dart';
import 'package:baby_app/data/models/feeding_event.dart';
import 'package:baby_app/data/models/pumping_event.dart';
import 'package:baby_app/data/repositories/repository_providers.dart';
import 'package:baby_app/features/home/home_prefs.dart';
import 'package:baby_app/features/home/recent_activity_list.dart';
import 'package:baby_app/features/home/home_screen.dart';

/// Home has to survive a small screen at a large text size (#—).
///
/// Everything above the recent list used to be fixed height, with the list
/// taking whatever remained. Nothing scrolled at the page level, so once the
/// fixed part grew past the viewport there was nowhere for it to go.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final baby = Baby(
    id: 'baby1',
    name: 'Ada',
    birthDate: DateTime(2026, 2, 1),
    ownerUid: 'alice',
    members: const {'alice': CaregiverRole.owner},
  );

  // Relative to the real clock, because HomeScreen reads DateTime.now()
  // itself. A fixed date drifts into "overdue" the day after it is written,
  // which changes the wording the chip uses.
  final now = DateTime.now();

  /// A Home with something on every row: a bottle, solids, a diaper and a
  /// pump. The empty state is the small one — this is the tall one, and the
  /// tall one is what has to fit.
  final feeds = [
    FeedingEvent(
      id: 'f1',
      type: FeedingType.bottle,
      startTime: now.subtract(const Duration(hours: 2)),
      amountMl: 150,
    ),
    FeedingEvent(
      id: 'f2',
      type: FeedingType.solids,
      startTime: now.subtract(const Duration(hours: 4)),
      notes: 'Sweet potato',
    ),
  ];
  final diapers = [
    DiaperEvent(
      id: 'd1',
      type: DiaperType.dirty,
      time: now,
      poopSize: PoopSize.small,
    ),
  ];
  final pumps = [
    PumpingEvent(id: 'p1', time: now, amountMl: 90, durationMinutes: 15),
  ];

  Future<void> pumpHome(
    WidgetTester tester, {
    double textScale = 1.0,
    Size size = const Size(390, 844),
    Map<String, Object> prefs = const {},
    bool withData = true,
    List<FeedingEvent>? feedings,
  }) async {
    SharedPreferences.setMockInitialValues({
      // Reminders on, so the next-feed chip is drawn. That is the tallest
      // the feeding row ever gets, and height is the point here.
      'reminder_mode': 'fixedInterval',
      ...prefs,
    });
    final stored = await SharedPreferences.getInstance();

    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(stored),
          // Signed out, so every repository provider is null and the streams
          // are empty — this test is about layout, not data.
          authStateProvider.overrideWith((ref) => Stream.value(null)),
          babiesStreamProvider.overrideWith((ref) => Stream.value([baby])),
          recentFeedingsProvider.overrideWith(
            (ref) => Stream.value(feedings ?? (withData ? feeds : const [])),
          ),
          recentDiapersProvider.overrideWith(
            (ref) => Stream.value(withData ? diapers : const []),
          ),
          recentPumpingProvider.overrideWith(
            (ref) => Stream.value(withData ? pumps : const []),
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
    // Two frames: the first builds, the second delivers the streams' initial
    // values. Without it the card renders its empty state and a test about a
    // full Home would be quietly testing an empty one.
    await tester.pump();
    await tester.pump();
  }

  testWidgets('fits a phone at the default text size', (tester) async {
    await pumpHome(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the fixture really is a full Home', (tester) async {
    // Guards the harness, not the app: the streams need a second frame to
    // deliver, and without it every test below would be quietly measuring an
    // empty Home — which is the short one, and not the one that overflows.
    await pumpHome(tester);
    expect(find.text('Last fed'), findsOneWidget);
    expect(find.text('Last ate'), findsOneWidget);
    expect(find.text('Last diaper changed'), findsOneWidget);
    expect(find.textContaining('Next feed'), findsOneWidget);
  });

  testWidgets('does not overflow a small screen at 200% text', (tester) async {
    // The failure this guards: a RenderFlex overflow, because the block above
    // the list grew past the viewport and nothing could scroll.
    await pumpHome(tester, textScale: 2.0, size: const Size(320, 568));
    expect(tester.takeException(), isNull);
  });

  testWidgets('does not overflow at 150% either', (tester) async {
    await pumpHome(tester, textScale: 1.5, size: const Size(360, 640));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the whole page scrolls, not just the activity list', (
    tester,
  ) async {
    // The point of the restructure: on a short screen the status card has to
    // be able to move out of the way, rather than pinning the list into
    // whatever is left over.
    await pumpHome(tester, size: const Size(390, 600));
    final card = find.text('Last fed');
    expect(card, findsOneWidget);
    final before = tester.getTopLeft(card).dy;

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -200));
    await tester.pump();

    expect(
      tester.getTopLeft(card).dy,
      lessThan(before),
      reason: 'the status card should scroll away with everything else',
    );
  });

  group('where the quick actions sit', () {
    double yOf(WidgetTester tester, String text) =>
        tester.getTopLeft(find.text(text)).dy;

    testWidgets('by default, logging comes before reading', (tester) async {
      // Logging a feed is the reason the app gets opened; it used to sit
      // below the status card and today's totals, a third of the way down.
      await pumpHome(tester);
      expect(yOf(tester, 'Log feed'), lessThan(yOf(tester, 'Last fed')));
    });

    testWidgets('and can be put back under the status rows', (tester) async {
      await pumpHome(tester, prefs: {'home_actions': 'belowStatus'});
      expect(yOf(tester, 'Log feed'), greaterThan(yOf(tester, 'Last fed')));
    });

    testWidgets('either way, both are on screen without scrolling', (
      tester,
    ) async {
      for (final placement in HomeActions.values) {
        await pumpHome(tester, prefs: {'home_actions': placement.name});
        expect(find.text('Log feed'), findsOneWidget, reason: placement.name);
        expect(find.text('Last fed'), findsOneWidget, reason: placement.name);
      }
    });
  });

  group('the stored placement', () {
    test('defaults to the top', () {
      expect(HomeActions.fromName(null), HomeActions.top);
    });

    test('reads back what was chosen', () {
      expect(HomeActions.fromName('belowStatus'), HomeActions.belowStatus);
    });

    test('falls back on a value it does not know', () {
      // A placement removed in a later version, or a hand-edited preference.
      expect(HomeActions.fromName('sideways'), HomeActions.top);
    });
  });

  group('what the activity list covers', () {
    /// The toggle's own segment. "Today" is also the label on the summary
    /// row above, so a bare text finder matches two widgets.
    Finder segment(String label) => find.descendant(
      of: find.byType(SegmentedButton<HomeActivityScope>),
      matching: find.text(label),
    );

    // Anchored to real midnight so the two entries are unambiguously on
    // different days whenever the suite happens to run.
    final midnight = DateTime(now.year, now.month, now.day);
    final todayFeed = FeedingEvent(
      id: 'today',
      type: FeedingType.bottle,
      startTime: midnight.add(const Duration(minutes: 1)),
      amountMl: 100,
    );
    final yesterdayFeed = FeedingEvent(
      id: 'yesterday',
      type: FeedingType.bottle,
      startTime: midnight.subtract(const Duration(hours: 1)),
      amountMl: 200,
    );

    testWidgets('Recent reaches back past midnight', (tester) async {
      await pumpHome(
        tester,
        feedings: [todayFeed, yesterdayFeed],
        withData: false,
      );
      expect(find.text('100 ml (3.4 fl oz)'), findsOneWidget);
      expect(find.text('200 ml (6.8 fl oz)'), findsOneWidget);
    });

    testWidgets('Today stops at midnight', (tester) async {
      // A calendar day, not a rolling 24 hours — otherwise last night's
      // 11pm feed would still be on the list this afternoon.
      await pumpHome(
        tester,
        feedings: [todayFeed, yesterdayFeed],
        withData: false,
        prefs: {'home_activity_scope': 'today'},
      );
      expect(find.text('100 ml (3.4 fl oz)'), findsOneWidget);
      expect(find.text('200 ml (6.8 fl oz)'), findsNothing);
    });

    testWidgets('the toggle switches between them', (tester) async {
      await pumpHome(
        tester,
        feedings: [todayFeed, yesterdayFeed],
        withData: false,
      );
      expect(find.text('200 ml (6.8 fl oz)'), findsOneWidget);

      await tester.tap(segment('Today'));
      await tester.pump();
      expect(find.text('200 ml (6.8 fl oz)'), findsNothing);

      await tester.tap(segment('Recent'));
      await tester.pump();
      expect(find.text('200 ml (6.8 fl oz)'), findsOneWidget);
    });

    testWidgets('Today says so when the day has not started', (tester) async {
      await pumpHome(
        tester,
        feedings: [yesterdayFeed],
        withData: false,
        prefs: {'home_activity_scope': 'today'},
      );
      expect(find.text('Nothing logged today yet.'), findsOneWidget);
    });

    testWidgets('the choice is remembered', (tester) async {
      await pumpHome(
        tester,
        feedings: [todayFeed, yesterdayFeed],
        withData: false,
      );
      await tester.tap(segment('Today'));
      await tester.pump();

      final stored = await SharedPreferences.getInstance();
      expect(stored.getString('home_activity_scope'), 'today');
    });
  });

  group('the stored scope', () {
    test('defaults to recent', () {
      expect(HomeActivityScope.fromName(null), HomeActivityScope.recent);
    });

    test('falls back on a value it does not know', () {
      expect(HomeActivityScope.fromName('fortnight'), HomeActivityScope.recent);
    });
  });

  group('drawing the line at midnight', () {
    // The pure rule behind the toggle, tested away from the widget so the
    // boundary cases are readable.
    final noon = DateTime(2026, 8, 20, 12);
    ActivityEntry entry(DateTime t) => FeedingEntry(
      FeedingEvent(id: 't', type: FeedingType.bottle, startTime: t),
    );

    test('keeps the whole calendar day, edge to edge', () {
      final entries = [
        entry(DateTime(2026, 8, 20)),
        entry(DateTime(2026, 8, 20, 23, 59, 59)),
      ];
      expect(onlyToday(entries, now: noon), hasLength(2));
    });

    test('drops a minute before midnight', () {
      final entries = [entry(DateTime(2026, 8, 19, 23, 59))];
      expect(onlyToday(entries, now: noon), isEmpty);
    });

    test('drops tomorrow, in case one was mis-stamped', () {
      final entries = [entry(DateTime(2026, 8, 21))];
      expect(onlyToday(entries, now: noon), isEmpty);
    });

    test('keeps the order it was given', () {
      final entries = [
        entry(DateTime(2026, 8, 20, 18)),
        entry(DateTime(2026, 8, 20, 6)),
      ];
      final kept = onlyToday(entries, now: noon);
      expect(kept.first.time.hour, 18);
      expect(kept.last.time.hour, 6);
    });

    test('an empty list stays empty', () {
      expect(onlyToday(const [], now: noon), isEmpty);
    });
  });
}
