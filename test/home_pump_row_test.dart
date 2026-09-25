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
import 'package:baby_app/features/home/home_prefs.dart';
import 'package:baby_app/features/home/home_status_card.dart';

/// The "Last pumped" row on the Home status card, and its countdown.
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

    expect(find.text('Last pumped'), findsOneWidget);
    expect(find.text('25 min ago'), findsOneWidget);
    // The newer session, not the 60 ml one five hours back.
    expect(find.textContaining('15 min · 90 ml'), findsOneWidget);
  });

  testWidgets('stays away until something has been pumped', (tester) async {
    // A household that never pumps would otherwise carry a permanently empty
    // row, the same clutter the solids row avoids.
    await pumpCard(tester);

    expect(find.text('Last pumped'), findsNothing);
    expect(find.text('Last fed'), findsOneWidget);
    expect(find.text('Last diaper changed'), findsOneWidget);
  });

  testWidgets('and goes away when pumping is switched off', (tester) async {
    // Turning the pumping action off says pumping is not part of this
    // household's day. Leaving its history on Home would contradict that.
    await pumpCard(
      tester,
      pumping: pumps,
      prefs: {'show_pumping_action': false},
    );

    expect(find.text('Last pumped'), findsNothing);
  });

  testWidgets('leads to the fridge', (tester) async {
    // The question a pumping household asks straight after "when did I last
    // pump", answered from where they are already looking.
    await pumpCard(tester, pumping: pumps);

    expect(
      find.descendant(
        of: find.ancestor(
          of: find.text('Last pumped'),
          matching: find.byType(InkWell),
        ),
        matching: find.byIcon(Icons.chevron_right),
      ),
      findsOneWidget,
    );
  });

  testWidgets('and the rows that lead nowhere say so by having no chevron', (
    tester,
  ) async {
    // A row that looks tappable and is not is worse than one that plainly
    // only reports.
    await pumpCard(tester, pumping: pumps);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
  });

  testWidgets('gets its own card in the separate layout', (tester) async {
    await pumpCard(
      tester,
      pumping: pumps,
      prefs: {'home_layout': HomeLayout.separate.name},
    );

    expect(find.byType(Card), findsNWidgets(3));
    expect(find.text('Last pumped'), findsOneWidget);
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

    /// Every background painted behind the pump row. Comparing the whole set
    /// sidesteps having to identify which box is ours among the ones
    /// Material paints.
    List<Color> backdrops(WidgetTester tester) => tester
        .widgetList<ColoredBox>(
          find.ancestor(
            of: find.text('Last pumped'),
            matching: find.byType(ColoredBox),
          ),
        )
        .map((b) => b.color)
        .toList();

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

      expect(find.text('Last pumped'), findsOneWidget);
      expect(find.textContaining('pump in'), findsNothing);
      expect(find.textContaining('Pump'), findsNothing);
      // The feeding row's own chip is still there — this is about the pump
      // row not having grown one, not about the card going quiet.
      expect(find.byType(DueChip), findsOneWidget);
    });

    testWidgets('and colours the row as it comes due', (tester) async {
      await pumpCard(
        tester,
        pumping: pumpedAt(30),
        prefs: {'pump_interval_minutes': 120},
      );
      final upcoming = backdrops(tester);

      // pumpCard reuses the ProviderScope, which updates in place rather
      // than re-resolving the overridden streams.
      await tester.pumpWidget(const SizedBox());
      await pumpCard(
        tester,
        pumping: pumpedAt(150),
        prefs: {'pump_interval_minutes': 120},
      );

      expect(backdrops(tester), isNot(upcoming));
    });

    testWidgets('leaving the row calm with no cadence', (tester) async {
      // The other half of the escalation: an uncoloured row is the promise
      // that nothing on it is asking for anything.
      await pumpCard(tester, pumping: pumpedAt(150));
      final noCadence = backdrops(tester);

      await tester.pumpWidget(const SizedBox());
      await pumpCard(tester, pumping: pumpedAt(30));

      expect(backdrops(tester), noCadence);
    });

    testWidgets('and the feeding row stays out of it', (tester) async {
      // The two rows carry their own clocks. A pump falling overdue must not
      // tint the row above it.
      await pumpCard(
        tester,
        pumping: pumpedAt(30),
        prefs: {'pump_interval_minutes': 120},
      );
      final calm = tester
          .widgetList<ColoredBox>(
            find.ancestor(
              of: find.text('Last fed'),
              matching: find.byType(ColoredBox),
            ),
          )
          .map((b) => b.color)
          .toList();

      await tester.pumpWidget(const SizedBox());
      await pumpCard(
        tester,
        pumping: pumpedAt(150),
        prefs: {'pump_interval_minutes': 120},
      );

      expect(
        tester
            .widgetList<ColoredBox>(
              find.ancestor(
                of: find.text('Last fed'),
                matching: find.byType(ColoredBox),
              ),
            )
            .map((b) => b.color)
            .toList(),
        calm,
      );
    });
  });
}
