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
import 'package:baby_app/features/home/home_prefs.dart';
import 'package:baby_app/features/home/recent_activity_list.dart';
import 'package:baby_app/features/insights/day_timeline_strip.dart';
import 'package:baby_app/features/insights/diaper_mix_bar.dart';
import 'package:baby_app/core/layout/app_bar_room.dart';
import 'package:baby_app/features/common/day_time_label.dart';
import 'package:baby_app/features/home/baby_switcher.dart';
import 'package:baby_app/features/home/home_screen.dart';
import 'package:baby_app/features/home/home_status_card.dart';

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
  final midnight = DateTime(now.year, now.month, now.day);

  /// [hours] before now, pulled forward if that would land before midnight.
  ///
  /// The Today charts drop anything outside the calendar day, so a fixture
  /// built from a flat "two hours ago" draws an empty chart at 1am — and this
  /// test then quietly measures a Home that is not the one it describes.
  /// Spreading what there is of the day keeps the ordering when the day is
  /// younger than the offsets.
  DateTime earlierToday(int hours) {
    final target = now.subtract(Duration(hours: hours));
    if (!target.isBefore(midnight)) return target;
    return midnight.add(now.difference(midnight) ~/ (hours + 1));
  }

  /// A Home with something on every row: a bottle, solids, a diaper and a
  /// pump. The empty state is the small one — this is the tall one, and the
  /// tall one is what has to fit.
  final feeds = [
    FeedingEvent(
      id: 'f1',
      type: FeedingType.bottle,
      startTime: earlierToday(2),
      amountMl: 150,
    ),
    FeedingEvent(
      id: 'f2',
      type: FeedingType.solids,
      startTime: earlierToday(4),
      notes: 'Sweet potato',
    ),
  ];
  final fixtureDiapers = [
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
    List<DiaperEvent>? diapers,
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
            (ref) =>
                Stream.value(diapers ?? (withData ? fixtureDiapers : const [])),
          ),
          recentPumpingProvider.overrideWith(
            (ref) => Stream.value(withData ? pumps : const []),
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
    // Settle rather than pump a fixed number of times. Home subscribes to
    // several streams and they do not all deliver on the same frame — two
    // pumps got the feeds and diapers but left the pumping out, so a test
    // about a full Home was quietly testing most of one.
    await tester.pumpAndSettle();
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
    expect(find.text('Last pumped'), findsOneWidget);
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
    // The primary button is labelled for what it does, and the bottle
    // shortcut is on by default — see the group below, which pins both.
    const logFeed = 'Log bottle';

    double yOf(WidgetTester tester, String text) =>
        tester.getTopLeft(find.text(text)).dy;

    testWidgets('by default, logging comes before reading', (tester) async {
      // Logging a feed is the reason the app gets opened; it used to sit
      // below the status card and today's totals, a third of the way down.
      await pumpHome(tester);
      expect(yOf(tester, logFeed), lessThan(yOf(tester, 'Last fed')));
    });

    testWidgets('and can be put back under the status rows', (tester) async {
      await pumpHome(tester, prefs: {'home_actions': 'belowStatus'});
      expect(yOf(tester, logFeed), greaterThan(yOf(tester, 'Last fed')));
    });

    testWidgets('either way, both are on screen without scrolling', (
      tester,
    ) async {
      for (final placement in HomeActions.values) {
        await pumpHome(tester, prefs: {'home_actions': placement.name});
        expect(find.text(logFeed), findsOneWidget, reason: placement.name);
        expect(find.text('Last fed'), findsOneWidget, reason: placement.name);
      }
    });
  });

  group('the feeding row carries how close the next feed is', () {
    /// Every background painted above [label]. Comparing the whole set
    /// sidesteps having to identify which box is ours among the ones
    /// Material paints.
    List<Color> backdrops(WidgetTester tester, String label) => tester
        .widgetList<ColoredBox>(
          find.ancestor(
            of: find.text(label),
            matching: find.byType(ColoredBox),
          ),
        )
        .map((b) => b.color)
        .toList();

    FeedingEvent feedAt(int minutesAgo) => FeedingEvent(
      id: 'f1',
      type: FeedingType.bottle,
      startTime: DateTime.now().subtract(Duration(minutes: minutesAgo)),
      amountMl: 150,
    );

    testWidgets('so the row says it before it is read', (tester) async {
      // On a card of three rows the colour is what picks out the one asking
      // for something.
      await pumpHome(tester, feedings: [feedAt(15)]);
      final justFed = backdrops(tester, 'Last fed');

      // pumpHome reuses the ProviderScope, which updates in place rather
      // than re-resolving the overridden streams — without this the second
      // pump quietly measures the first feed again.
      await tester.pumpWidget(const SizedBox());
      await pumpHome(tester, feedings: [feedAt(400)]);
      expect(backdrops(tester, 'Last fed'), isNot(justFed));
    });

    testWidgets('and the diaper row stays out of it', (tester) async {
      await pumpHome(tester, feedings: [feedAt(15)]);
      final calm = backdrops(tester, 'Last diaper changed');

      // pumpHome reuses the ProviderScope, which updates in place rather
      // than re-resolving the overridden streams — without this the second
      // pump quietly measures the first feed again.
      await tester.pumpWidget(const SizedBox());
      await pumpHome(tester, feedings: [feedAt(400)]);
      expect(backdrops(tester, 'Last diaper changed'), calm);
    });

    testWidgets('in the separate layout too', (tester) async {
      await pumpHome(
        tester,
        prefs: {'home_layout': 'separate'},
        feedings: [feedAt(15)],
      );
      final justFed = backdrops(tester, 'Last fed');

      // pumpHome reuses the ProviderScope, which updates in place rather
      // than re-resolving the overridden streams — without this the second
      // pump quietly measures the first feed again.
      await tester.pumpWidget(const SizedBox());
      await pumpHome(
        tester,
        prefs: {'home_layout': 'separate'},
        feedings: [feedAt(400)],
      );
      expect(backdrops(tester, 'Last fed'), isNot(justFed));
    });
  });

  group('the next-feed track', () {
    testWidgets('is wired up on Home, and shortens as the feed nears', (
      tester,
    ) async {
      // The chip and the bar are computed from the same due time, so this is
      // really checking the wiring: that Home hands the fraction over at all.
      Future<double> trackWidth(Duration sinceFeed) async {
        await tester.pumpWidget(const SizedBox());
        await pumpHome(
          tester,
          feedings: [
            FeedingEvent(
              id: 'f1',
              type: FeedingType.bottle,
              startTime: DateTime.now().subtract(sinceFeed),
              amountMl: 120,
            ),
          ],
        );
        return tester
            .getSize(
              find.descendant(
                of: find.byType(DueChip),
                matching: find.byType(ColoredBox),
              ),
            )
            .width;
      }

      final justFed = await trackWidth(const Duration(minutes: 10));
      final later = await trackWidth(const Duration(hours: 2));

      expect(justFed, greaterThan(0));
      expect(later, lessThan(justFed));
    });
  });

  group('the diaper row carries how long it has been', () {
    List<Color> backdrops(WidgetTester tester, String label) => tester
        .widgetList<ColoredBox>(
          find.ancestor(
            of: find.text(label),
            matching: find.byType(ColoredBox),
          ),
        )
        .map((b) => b.color)
        .toList();

    Future<List<Color>> at(WidgetTester tester, Duration ago) async {
      await tester.pumpWidget(const SizedBox());
      await pumpHome(
        tester,
        diapers: [
          DiaperEvent(
            id: 'd1',
            type: DiaperType.wet,
            time: DateTime.now().subtract(ago),
          ),
        ],
      );
      return backdrops(tester, 'Last diaper changed');
    }

    testWidgets('calm, then amber at two hours, then red at three', (
      tester,
    ) async {
      final fresh = await at(tester, const Duration(minutes: 30));
      final amber = await at(tester, const Duration(hours: 2, minutes: 30));
      final red = await at(tester, const Duration(hours: 3, minutes: 30));

      expect(amber, isNot(fresh));
      expect(red, isNot(amber));
      expect(red, isNot(fresh));
    });
  });

  group('the bottle shortcut', () {
    testWidgets('is on by default, and says what it will do', (tester) async {
      // A button labelled "Log feed" that opens the bottle form has told you
      // the wrong thing before you reach it.
      await pumpHome(tester);

      expect(find.text('Log bottle'), findsOneWidget);
      expect(find.text('Log feed'), findsNothing);
    });

    testWidgets('opens the bottle form rather than the chooser', (
      tester,
    ) async {
      await pumpHome(tester);
      await tester.tap(find.text('Log bottle'));
      await tester.pumpAndSettle();

      expect(find.text('Bottle'), findsWidgets);
      expect(find.text('Log a feed'), findsNothing);
    });

    testWidgets('with no detour back to the chooser', (tester) async {
      // Deliberately like nursery mode: straight to the form. The setting is
      // the way back to the other kinds, not a link inside the sheet.
      await pumpHome(tester);
      await tester.tap(find.text('Log bottle'));
      await tester.pumpAndSettle();

      expect(find.text('Log a feed'), findsNothing);
      expect(find.text('Log something else'), findsNothing);
    });

    testWidgets('turned off, the button asks which kind again', (tester) async {
      await pumpHome(tester, prefs: {'feed_button_bottle': false});

      expect(find.text('Log feed'), findsOneWidget);
      await tester.tap(find.text('Log feed'));
      await tester.pumpAndSettle();

      expect(find.text('Log a feed'), findsOneWidget);
      // And every kind is on it — the chooser is what this setting buys.
      expect(find.widgetWithText(OutlinedButton, 'Bottle'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Solids'), findsOneWidget);
      expect(
        find.widgetWithText(OutlinedButton, 'Breastfeeding'),
        findsOneWidget,
      );
    });
  });

  group('the full-timeline link', () {
    testWidgets('opens on today, not wherever the day was left', (
      tester,
    ) async {
      // selectedDayProvider is global and sticky, and Insights can now push
      // it weeks back (#32). Home's drill-down is of Home's recent list, so
      // it means today.
      await pumpHome(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(HomeScreen)),
      );
      container.read(selectedDayProvider.notifier).setDay(DateTime(2026, 7, 4));

      await tester.tap(find.byTooltip('Full timeline'));
      await tester.pump();
      // The layout harness has no GoRouter, so the push itself throws. The
      // day is set first, which is the half Home owns.
      tester.takeException();

      final day = container.read(selectedDayProvider);
      final now = DateTime.now();
      expect(day, DateTime(now.year, now.month, now.day));
    });
  });

  group('the pumping action', () {
    testWidgets('is a button, the size of the two above it', (tester) async {
      // It used to be a bare text link under two proper buttons — smaller to
      // hit, and not obviously a thing to press at all.
      await pumpHome(tester);

      final pumping = find.widgetWithText(OutlinedButton, 'Log pumping');
      expect(pumping, findsOneWidget);
      expect(
        tester.getSize(pumping).height,
        tester.getSize(find.widgetWithText(FilledButton, 'Log diaper')).height,
      );
    });

    testWidgets('spans the pair above it, edge to edge', (tester) async {
      await pumpHome(tester);

      final pumping = tester.getRect(
        find.widgetWithText(OutlinedButton, 'Log pumping'),
      );
      final feed = tester.getRect(
        find.widgetWithText(FilledButton, 'Log bottle'),
      );
      final diaper = tester.getRect(
        find.widgetWithText(FilledButton, 'Log diaper'),
      );

      expect(pumping.left, feed.left);
      expect(pumping.right, diaper.right);
      expect(pumping.top, greaterThan(feed.bottom));
    });

    testWidgets('and is still hidden when pumping is switched off', (
      tester,
    ) async {
      await pumpHome(tester, prefs: {'show_pumping_action': false});
      expect(find.text('Log pumping'), findsNothing);
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

  group('what the Today toggle shows', () {
    /// The toggle's own segment. "Today" is also the label on the summary
    /// row above, so a bare text finder matches two widgets.
    Finder segment(String label) => find.descendant(
      of: find.byType(SegmentedButton<HomeActivityScope>),
      matching: find.text(label),
    );

    testWidgets('Recent is the activity list, with its kind filter', (
      tester,
    ) async {
      await pumpHome(tester);
      expect(find.byType(RecentActivityList), findsOneWidget);
      expect(find.byType(ActivityFilterBar), findsOneWidget);
      expect(find.byType(DayTimelineStrip), findsNothing);
    });

    testWidgets('Today is the day charts instead', (tester) async {
      // The same two the Insights day view draws, so a glance at how today
      // has gone does not cost a tab change.
      await pumpHome(tester, prefs: {'home_activity_scope': 'today'});
      expect(find.byType(DayTimelineStrip), findsOneWidget);
      expect(find.byType(DiaperMixBar), findsOneWidget);
      expect(find.byType(RecentActivityList), findsNothing);
      // The charts have nothing to filter by kind.
      expect(find.byType(ActivityFilterBar), findsNothing);
    });

    testWidgets('the toggle swaps one for the other', (tester) async {
      await pumpHome(tester);
      expect(find.byType(RecentActivityList), findsOneWidget);

      await tester.tap(segment('Today'));
      await tester.pump();
      expect(find.byType(DayTimelineStrip), findsOneWidget);
      expect(find.byType(RecentActivityList), findsNothing);

      await tester.tap(segment('Recent'));
      await tester.pump();
      expect(find.byType(RecentActivityList), findsOneWidget);
      expect(find.byType(DayTimelineStrip), findsNothing);
    });

    testWidgets('the charts show what was logged today', (tester) async {
      await pumpHome(tester, prefs: {'home_activity_scope': 'today'});
      // The fixture is a bottle, some solids, a diaper and a pump, all today.
      expect(find.text('2 feeds'), findsOneWidget);
      expect(find.text('1 diaper'), findsOneWidget);
      expect(find.text('1 pump'), findsOneWidget);
    });

    testWidgets('and the counts are not repeated above them', (tester) async {
      // The summary row used to carry the same numbers a centimetre higher.
      // Its volumes stay — no legend carries millilitres.
      await pumpHome(tester, prefs: {'home_activity_scope': 'today'});
      expect(find.text('2 feeds'), findsOneWidget, reason: 'legend only');
      expect(find.text('1 diapers'), findsNothing);
      expect(find.textContaining('fl oz'), findsWidgets);
    });

    testWidgets('but Recent still gets them, having no legend', (tester) async {
      await pumpHome(tester);
      expect(find.text('2 feeds'), findsOneWidget);
      expect(find.text('1 diapers'), findsOneWidget);
    });

    testWidgets('and cope with a day that has not started', (tester) async {
      await pumpHome(
        tester,
        withData: false,
        prefs: {'home_activity_scope': 'today'},
      );
      expect(find.text('Nothing logged on this day.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the choice is remembered', (tester) async {
      await pumpHome(tester);
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

  group('the list controls stay put', () {
    /// Enough entries to scroll well past the header's original position.
    List<FeedingEvent> manyFeeds() => [
      for (var i = 0; i < 30; i++)
        FeedingEvent(
          id: 'f$i',
          type: FeedingType.bottle,
          startTime: now.subtract(Duration(minutes: 30 * (i + 1))),
          amountMl: 100 + i.toDouble(),
        ),
    ];

    testWidgets('the toggle and filters are still there after scrolling', (
      tester,
    ) async {
      // Home is one scroll view, so without pinning these disappear the
      // moment you start reading the list — which is exactly when you want
      // to change what it shows.
      await pumpHome(tester, feedings: manyFeeds(), withData: false);
      final toggle = find.byType(SegmentedButton<HomeActivityScope>);
      final before = tester.getTopLeft(toggle).dy;

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -2000));
      await tester.pumpAndSettle();

      expect(toggle, findsOneWidget, reason: 'the toggle scrolled away');
      expect(find.byType(ActivityFilterBar), findsOneWidget);
      expect(
        tester.getTopLeft(toggle).dy,
        lessThanOrEqualTo(before),
        reason: 'it should have stopped, not kept moving',
      );
    });

    testWidgets('the rows underneath still scroll', (tester) async {
      await pumpHome(tester, feedings: manyFeeds(), withData: false);
      final last = find.text('129 ml (4.4 fl oz)');
      expect(last, findsNothing);

      // Scrolled until it appears rather than dragged a fixed distance. The
      // list is lazy, so whether one particular row has been built depends on
      // the height of everything above it — and a fixed 3000 quietly stopped
      // reaching the bottom row when that height changed.
      await tester.scrollUntilVisible(
        last,
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(last, findsOneWidget);
    });

    testWidgets('the pinned block fits its own height at every text size', (
      tester,
    ) async {
      // The delegate is handed a number before it lays anything out. Too
      // small overflows; too large fails the sliver's geometry check. Both
      // have happened.
      for (final scale in [1.0, 1.3, 1.5, 2.0]) {
        await pumpHome(
          tester,
          feedings: manyFeeds(),
          withData: false,
          textScale: scale,
        );
        expect(tester.takeException(), isNull, reason: 'at ${scale}x');
      }
    });

    testWidgets('Today pins the toggle without a filter bar', (tester) async {
      await pumpHome(tester, prefs: {'home_activity_scope': 'today'});
      expect(find.byType(SegmentedButton<HomeActivityScope>), findsOneWidget);
      expect(find.byType(ActivityFilterBar), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('the clock in the corner', () {
    testWidgets('is in the app bar, where the companion used to be', (
      tester,
    ) async {
      // Wide enough to have room for it — a phone does not, and there is a
      // test for that below.
      await pumpHome(tester, size: const Size(834, 1194));

      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byType(DayTimeLabel),
        ),
        findsOneWidget,
      );
      // Concrete, never "Today" — a clock has no use for that.
      expect(
        find.descendant(
          of: find.byType(DayTimeLabel),
          matching: find.text('Today'),
        ),
        findsNothing,
      );
    });

    testWidgets('gives way on a phone, so the name is readable', (
      tester,
    ) async {
      // What the report showed: three things wanted the bar, only the name
      // was flexible, and it was down to 10pt with "Jonathan" rendering as
      // "J…". The clock goes, and it is the right one to lose — iOS shows
      // the time a few points above the bar anyway.
      await pumpHome(tester, size: const Size(390, 844));

      expect(find.byType(DayTimeLabel), findsNothing);
      expect(
        tester.getRect(find.byType(BabySwitcher)).width,
        greaterThan(AppBarRoom.nameFloor),
      );
    });

    testWidgets('stays inside a bar whose height does not scale', (
      tester,
    ) async {
      // The risk in the move. An AppBar is kToolbarHeight whatever the
      // reader's text size, and this is two lines of text in it — so it is
      // scaled down to fit rather than allowed to overflow.
      for (final scale in [1.0, 1.5, 2.0]) {
        await pumpHome(tester, textScale: scale, size: const Size(834, 1194));
        expect(tester.takeException(), isNull, reason: 'at $scale');

        final bar = tester.getRect(find.byType(AppBar));
        final clock = tester.getRect(find.byType(DayTimeLabel));
        expect(
          clock.height,
          lessThanOrEqualTo(bar.height),
          reason: 'at $scale',
        );
      }
    });

    testWidgets('leaves the baby switcher its room', (tester) async {
      // The leading slot is wider than the 48pt the companion needed, so the
      // title had to be checked rather than assumed.
      await pumpHome(tester, size: const Size(834, 1194));
      expect(find.text('Ada'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
