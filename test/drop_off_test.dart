import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:baby_app/core/auth/auth_providers.dart';
import 'package:baby_app/core/theme/theme_mode_provider.dart';
import 'package:baby_app/data/models/baby.dart';
import 'package:baby_app/data/models/care_stay.dart';
import 'package:baby_app/data/models/diaper_event.dart';
import 'package:baby_app/data/models/feeding_event.dart';
import 'package:baby_app/data/models/milk_kind.dart';
import 'package:baby_app/data/repositories/repository_providers.dart';
import 'package:baby_app/features/common/banded_track.dart';
import 'package:baby_app/features/home/home_screen.dart';
import 'package:baby_app/features/home/home_status_card.dart';
import 'package:baby_app/features/home/nursery_screen.dart';

/// Dropping the baby off with someone else, and picking them up.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime.now();
  DateTime ago(int h, [int m = 0]) =>
      now.subtract(Duration(hours: h, minutes: m));

  final baby = Baby(
    id: 'baby1',
    name: 'Ada',
    birthDate: DateTime(2026, 2, 1),
    ownerUid: 'alice',
    members: const {'alice': CaregiverRole.owner},
  );

  CareStay stay({DateTime? pickedUp, bool auto = true}) => CareStay(
    id: 's1',
    droppedAt: ago(6),
    pickedUpAt: pickedUp,
    carer: 'Grandparents',
    autoFeed: auto,
    amountMl: 120,
    milk: MilkKind.expressed,
    intervalMinutes: 180,
  );

  Future<void> pumpHome(
    WidgetTester tester, {
    List<CareStay> stays = const [],
    List<FeedingEvent>? feeds,
    List<DiaperEvent>? diapers,
    Widget? home,
    Size size = const Size(390, 2400),
  }) async {
    SharedPreferences.setMockInitialValues({
      'reminder_mode': 'fixedInterval',
      'unit_system': 'metric',
      'display_mode': home is NurseryScreen ? 'nursery' : 'normal',
    });
    final stored = await SharedPreferences.getInstance();
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(stored),
          authStateProvider.overrideWith((ref) => Stream.value(null)),
          babiesStreamProvider.overrideWith((ref) => Stream.value([baby])),
          recentFeedingsProvider.overrideWith(
            (ref) => Stream.value(
              feeds ??
                  [
                    FeedingEvent(
                      id: 'f1',
                      type: FeedingType.bottle,
                      startTime: ago(4),
                      amountMl: 150,
                      milk: MilkKind.formula,
                    ),
                  ],
            ),
          ),
          recentDiapersProvider.overrideWith(
            (ref) => Stream.value(
              diapers ??
                  [DiaperEvent(id: 'd1', type: DiaperType.wet, time: ago(5))],
            ),
          ),
          recentStaysProvider.overrideWith((ref) => Stream.value(stays)),
        ],
        child: MaterialApp(home: home ?? const HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The colour of the dot beside a Home row's label, or null.
  Color? dot(WidgetTester tester, String label) {
    final found = find.descendant(
      of: find
          .ancestor(
            of: find.textContaining(RegExp('^$label( #\\d+)?\$')),
            matching: find.byType(Row),
          )
          .first,
      matching: find.byKey(const ValueKey('alert-dot')),
    );
    if (found.evaluate().isEmpty) return null;
    return (tester.widget<Container>(found).decoration! as BoxDecoration).color;
  }

  group('at home', () {
    testWidgets('the header has a drop-off, and there is no banner', (
      tester,
    ) async {
      await pumpHome(tester);
      expect(find.byKey(const ValueKey('drop-off')), findsOneWidget);
      expect(find.text('Drop off'), findsOneWidget);
      expect(find.byKey(const ValueKey('away-banner')), findsNothing);
    });

    testWidgets('the drop-off form starts from the usual bottle', (
      tester,
    ) async {
      await pumpHome(tester);
      await tester.tap(find.byKey(const ValueKey('drop-off')));
      await tester.pumpAndSettle();

      expect(find.text('Who has the baby'), findsOneWidget);
      for (final who in ['Grandparents', 'Sitter', 'Daycare']) {
        expect(find.widgetWithText(ChoiceChip, who), findsOneWidget);
      }
      expect(find.text('Log feeds automatically'), findsOneWidget);
      // The last bottle was 150 ml of formula.
      expect(find.widgetWithText(TextField, '150'), findsOneWidget);
      final milk = tester.widget<SegmentedButton<MilkKind>>(
        find.byType(SegmentedButton<MilkKind>),
      );
      expect(milk.selected, {MilkKind.formula});
    });

    testWidgets('and the amount goes with automatic feeds turned off', (
      tester,
    ) async {
      await pumpHome(tester);
      await tester.tap(find.byKey(const ValueKey('drop-off')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Log feeds automatically'));
      await tester.pumpAndSettle();
      expect(find.byType(SegmentedButton<MilkKind>), findsNothing);
    });
  });

  group('while away', () {
    testWidgets('a banner says who has the baby, with the pick-up', (
      tester,
    ) async {
      await pumpHome(tester, stays: [stay()]);
      final banner = find.byKey(const ValueKey('away-banner'));
      expect(banner, findsOneWidget);
      expect(
        find.descendant(
          of: banner,
          matching: find.textContaining('With Grandparents since'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: banner,
          matching: find.textContaining('Feeds logged automatically'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('picked-up')), findsOneWidget);
      // The drop-off has done its job.
      expect(find.byKey(const ValueKey('drop-off')), findsNothing);
    });

    testWidgets('the diaper row stops warning about a change nobody can make', (
      tester,
    ) async {
      // Five hours since the last change: purple at home.
      await pumpHome(tester);
      expect(dot(tester, 'DIAPER'), isNotNull);

      await tester.pumpWidget(const SizedBox());
      await pumpHome(tester, stays: [stay()]);
      expect(dot(tester, 'DIAPER'), isNull);
      // And nothing coloured behind it.
      final label = find.textContaining(RegExp('^DIAPER')).evaluate().single;
      expect(label.findAncestorWidgetOfExactType<AlertRowMark>(), isNull);
    });

    testWidgets('the feed row counts to the next automatic feed, calmly', (
      tester,
    ) async {
      // An automatic feed an hour ago: the next is in two hours.
      await pumpHome(
        tester,
        stays: [stay()],
        feeds: [
          FeedingEvent(
            id: 'auto-s1-1',
            type: FeedingType.bottle,
            startTime: ago(1),
            amountMl: 120,
          ),
        ],
      );
      expect(find.textContaining('Next auto feed in'), findsOneWidget);
    });

    testWidgets('and past its time, says it is being logged, not overdue', (
      tester,
    ) async {
      // Four hours since the last feed on a three-hour gap, with no device
      // online to log it yet: overdue at home, not while away.
      await pumpHome(tester, stays: [stay()]);
      expect(find.textContaining('Auto feed logging\u00a0now'), findsOneWidget);
      expect(find.textContaining('overdue'), findsNothing);
      expect(
        dot(tester, 'FEED'),
        isNot(warningInks(tester.element(find.text('Ada').first)).overdue),
      );
    });

    testWidgets('and the nursery shows the banner too', (tester) async {
      await pumpHome(
        tester,
        stays: [stay()],
        home: NurseryScreen(now: now),
        size: const Size(834, 1194),
      );
      expect(find.byKey(const ValueKey('away-banner')), findsOneWidget);
      expect(find.byKey(const ValueKey('picked-up')), findsOneWidget);
    });
  });

  group('the activity list', () {
    testWidgets('has the drop-off and the pick-up', (tester) async {
      await pumpHome(tester, stays: [stay(pickedUp: ago(1))]);
      expect(find.text('Dropped off'), findsOneWidget);
      expect(find.text('Picked up'), findsOneWidget);
      expect(find.textContaining('away 5h'), findsOneWidget);
      // Picked up: no banner, and the drop-off is back.
      expect(find.byKey(const ValueKey('away-banner')), findsNothing);
      expect(find.byKey(const ValueKey('drop-off')), findsOneWidget);
    });

    testWidgets('marks a feed the app logged by itself', (tester) async {
      await pumpHome(
        tester,
        stays: [stay()],
        feeds: [
          FeedingEvent(
            id: 'auto-s1-1',
            type: FeedingType.bottle,
            startTime: ago(1),
            amountMl: 120,
            notes: 'Auto-logged · with Grandparents',
          ),
        ],
      );
      expect(
        find.textContaining('Auto-logged · with Grandparents'),
        findsWidgets,
      );
    });
  });
}
