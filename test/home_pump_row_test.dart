import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:baby_app/core/auth/auth_providers.dart';
import 'package:baby_app/core/theme/theme_mode_provider.dart';
import 'package:baby_app/data/models/diaper_event.dart';
import 'package:baby_app/data/models/feeding_event.dart';
import 'package:baby_app/data/models/pumping_event.dart';
import 'package:baby_app/data/repositories/repository_providers.dart';
import 'package:baby_app/features/common/banded_track.dart';
import 'package:baby_app/features/fridge/fridge_button.dart';
import 'package:baby_app/features/home/home_prefs.dart';
import 'package:baby_app/features/home/home_status_card.dart';

/// The pump row on the Home status card, and its countdown.
///
/// Opt-in, like the solids row above it, and that is the part worth pinning:
/// a household that has never pumped should not carry an empty row for it,
/// and one that has switched pumping off has already said it does not want
/// the subject on Home at all.
///
/// The countdown is opt-in again on top of that, and the two are separate
/// switches: the row shows history with no cadence set, and only starts
/// counting — and colouring — once one is.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime.now();

  final feeds = [
    FeedingEvent(
      id: 'f1',
      type: FeedingType.bottle,
      startTime: now.subtract(const Duration(hours: 2)),
      amountMl: 150,
    ),
  ];
  final diapers = [
    DiaperEvent(
      id: 'd1',
      type: DiaperType.wet,
      time: now.subtract(const Duration(minutes: 40)),
    ),
  ];
  final pumps = [
    PumpingEvent(
      id: 'p1',
      time: now.subtract(const Duration(minutes: 25)),
      durationMinutes: 15,
      amountMl: 90,
    ),
    PumpingEvent(
      id: 'p2',
      time: now.subtract(const Duration(hours: 5)),
      amountMl: 60,
    ),
  ];

  Future<void> pumpCard(
    WidgetTester tester, {
    List<PumpingEvent> pumping = const [],
    Map<String, Object> prefs = const {},
  }) async {
    SharedPreferences.setMockInitialValues({
      'reminder_mode': 'fixedInterval',
      'unit_system': 'metric',
      ...prefs,
    });
    final stored = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(stored),
          // Signed out: every repository provider is null, so the only data
          // in play is what is overridden below.
          authStateProvider.overrideWith((ref) => Stream.value(null)),
          recentFeedingsProvider.overrideWith((ref) => Stream.value(feeds)),
          recentDiapersProvider.overrideWith((ref) => Stream.value(diapers)),
          recentPumpingProvider.overrideWith((ref) => Stream.value(pumping)),
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

  testWidgets('shows the most recent session', (tester) async {
    await pumpCard(tester, pumping: pumps);

    expect(find.text('PUMP'), findsOneWidget);
    expect(find.text('25m ago'), findsOneWidget);
    // The newer session, not the 60 ml one five hours back: the amount in
    // the headline, the time it took underneath.
    expect(find.text('90\u00a0ml'), findsOneWidget);
    expect(find.text('15 min'), findsOneWidget);
  });

  testWidgets('is there before the first session, to log it from', (
    tester,
  ) async {
    // It used to stay away until something had been pumped. With the log
    // buttons gone, its icon is the way to log that first session.
    await pumpCard(tester);

    expect(find.text('PUMP'), findsOneWidget);
    expect(find.text('No sessions yet'), findsOneWidget);
    expect(find.byTooltip('Log pump'), findsOneWidget);
  });

  testWidgets('and goes away when pumping is switched off', (tester) async {
    // Turning the pumping action off says pumping is not part of this
    // household's day. Leaving its history on Home would contradict that.
    await pumpCard(
      tester,
      pumping: pumps,
      prefs: {'show_pumping_action': false},
    );

    expect(find.text('PUMP'), findsNothing);
  });

  testWidgets('leaves the way into the fridge to a row of its own', (
    tester,
  ) async {
    // It used to sit on this row. The fridge is not only pumped milk, and
    // now has its own row underneath — see home_fridge_row_test.
    await pumpCard(tester, pumping: pumps);

    final button = tester.getRect(find.byType(FridgeButton));
    final pumped = tester.getRect(find.text('PUMP'));
    final fridge = tester.getRect(find.text('FRIDGE'));
    expect(button.top, greaterThan(pumped.bottom));
    expect(button.top, lessThan(fridge.bottom + 40));
  });

  testWidgets('and no other row has one, or a chevron', (tester) async {
    // Feeding and diapers only report. A row that looks like it goes
    // somewhere and does not is worse than one that plainly does not.
    await pumpCard(tester, pumping: pumps);

    expect(find.byType(FridgeButton), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
  });

  testWidgets('gets its own card in the separate layout', (tester) async {
    await pumpCard(
      tester,
      pumping: pumps,
      prefs: {'home_layout': HomeLayout.separate.name},
    );

    // Feeding, diapers, pumping and the fridge.
    expect(find.byType(Card), findsNWidgets(4));
    expect(find.text('PUMP'), findsOneWidget);
  });

  group('the countdown', () {
    /// A single session [minutesAgo] back, so the due time is arithmetic
    /// rather than a guess about which of several sessions anchors it.
    List<PumpingEvent> pumpedAt(int minutesAgo) => [
      PumpingEvent(
        id: 'p1',
        time: now.subtract(Duration(minutes: minutesAgo)),
        amountMl: 90,
      ),
    ];

    /// The colour of the dot beside [label], or null when there is none.
    Color? dot(WidgetTester tester, String label) {
      final found = find.descendant(
        of: find
            .ancestor(of: find.text(label), matching: find.byType(Row))
            .first,
        matching: find.byKey(const ValueKey('alert-dot')),
      );
      if (found.evaluate().isEmpty) return null;
      final box = tester.widget<Container>(found).decoration! as BoxDecoration;
      return box.color;
    }

    testWidgets('says when the next one is due', (tester) async {
      await pumpCard(
        tester,
        pumping: pumpedAt(30),
        prefs: {'pump_interval_minutes': 120},
      );

      expect(find.textContaining('Next pump in 1h 30m'), findsOneWidget);
    });

    testWidgets('and flips its wording once it has slipped', (tester) async {
      // "Next pump 30m overdue" reads as a contradiction, so the feed chip's
      // wording flip applies here too.
      await pumpCard(
        tester,
        pumping: pumpedAt(150),
        prefs: {'pump_interval_minutes': 120},
      );

      expect(find.textContaining('Pump 30m overdue'), findsOneWidget);
      expect(find.textContaining('Next pump'), findsNothing);
    });

    testWidgets('stays away until a cadence is set', (tester) async {
      // The row still does its original job — this is the default, and the
      // default must not invent a schedule nobody asked for.
      await pumpCard(tester, pumping: pumpedAt(30));

      expect(find.text('PUMP'), findsOneWidget);
      expect(find.textContaining('pump in'), findsNothing);
      expect(find.textContaining('Pump'), findsNothing);
      // The feeding row's own chip is still there — this is about the pump
      // row not having grown one, not about the card going quiet.
      expect(find.byType(DueChip), findsOneWidget);
    });

    testWidgets('and marks the row as it comes due', (tester) async {
      await pumpCard(
        tester,
        pumping: pumpedAt(30),
        prefs: {'pump_interval_minutes': 120},
      );
      expect(dot(tester, 'PUMP'), isNull);

      // pumpCard reuses the ProviderScope, which updates in place rather
      // than re-resolving the overridden streams.
      await tester.pumpWidget(const SizedBox());
      await pumpCard(
        tester,
        pumping: pumpedAt(150),
        prefs: {'pump_interval_minutes': 120},
      );

      final context = tester.element(find.text('PUMP'));
      expect(dot(tester, 'PUMP'), warningInks(context).overdue);
    });

    testWidgets('leaving the row calm with no cadence', (tester) async {
      // The other half of the escalation: an unmarked row is the promise
      // that nothing on it is asking for anything.
      await pumpCard(tester, pumping: pumpedAt(150));
      expect(dot(tester, 'PUMP'), isNull);
    });

    testWidgets('and the feeding row stays out of it', (tester) async {
      // The two rows carry their own clocks. A pump falling overdue must not
      // mark the row above it.
      await pumpCard(
        tester,
        pumping: pumpedAt(30),
        prefs: {'pump_interval_minutes': 120},
      );
      final calm = dot(tester, 'FEED');

      await tester.pumpWidget(const SizedBox());
      await pumpCard(
        tester,
        pumping: pumpedAt(150),
        prefs: {'pump_interval_minutes': 120},
      );

      expect(dot(tester, 'FEED'), calm);
    });
  });
}
