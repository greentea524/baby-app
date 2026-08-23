import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:baby_app/core/theme/theme_mode_provider.dart';
import 'package:baby_app/data/models/feeding_event.dart';
import 'package:baby_app/data/models/notification_prefs.dart';
import 'package:baby_app/data/repositories/repository_providers.dart';
import 'package:baby_app/features/home/companion_art.dart';
import 'package:baby_app/features/home/feed_companion.dart';
import 'package:baby_app/features/reminders/feed_prediction.dart';
import 'package:baby_app/features/reminders/reminder_providers.dart';

/// The plane is a second read of the next-feed chip, so the two must never
/// disagree — and the take-off has to fire on a real feed and nothing else.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 8, 9, 12, 0);

  FeedingEvent feed(
    String id, {
    bool snack = false,
    FeedingType type = FeedingType.bottle,
  }) => FeedingEvent(
    id: id,
    type: type,
    startTime: now.subtract(const Duration(hours: 1)),
    isSnack: snack,
  );

  /// Pumps the plane with [due] as the next feed and [last] as the most
  /// recent clock feed. Returns the container so the test can move them.
  Future<ProviderContainer> pumpCompanion(
    WidgetTester tester, {
    DateTime? due,
    FeedingEvent? last,
    Map<String, Object> prefs = const {},
    bool disableAnimations = false,
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    final stored = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(stored),
        nextFeedDueProvider.overrideWithValue(due),
        lastClockFeedProvider.overrideWithValue(last),
        // The plane reads the heads-up from reminderSettingsProvider, which
        // now also watches the account's copy of the interval (#27) — and
        // that reaches Firebase auth. Stubbed out rather than stubbing
        // Firebase: this test is about the pose, not about syncing.
        hasAccountPrefsProvider.overrideWithValue(false),
        notificationPrefsProvider.overrideWith(
          (ref) => const Stream<NotificationPrefs>.empty(),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: disableAnimations),
            child: Scaffold(body: FeedCompanion(now: now)),
          ),
        ),
      ),
    );
    await tester.pump();
    return container;
  }

  /// The companion's own painter. Scaffold and Material insert CustomPaints of
  /// their own, so byType alone matches Flutter's internals too.
  final companion = find.descendant(
    of: find.byType(FeedCompanion),
    matching: find.byType(CustomPaint),
  );

  String? label(WidgetTester tester) {
    final found = find.byType(FeedCompanion);
    if (tester.widgetList(find.byType(SizedBox)).isEmpty) return null;
    final semantics = tester.getSemantics(found);
    return semantics.label.isEmpty ? null : semantics.label;
  }

  group('resting state follows the chip', () {
    test('maps every due state to a pose', () {
      expect(phaseFor(FeedDueState.upcoming), CompanionPhase.easy);
      expect(phaseFor(FeedDueState.soon), CompanionPhase.soon);
      expect(phaseFor(FeedDueState.overdue), CompanionPhase.due);
    });
  });

  group('when it shows at all', () {
    testWidgets('hidden with reminders off, since there is no due time', (
      tester,
    ) async {
      await pumpCompanion(tester, due: null, last: feed('a'));
      expect(companion, findsNothing);
    });

    testWidgets('hidden when the caregiver turns it off', (tester) async {
      await pumpCompanion(
        tester,
        due: now.add(const Duration(hours: 2)),
        last: feed('a'),
        prefs: {'home_companion_style': 'off'},
      );
      expect(companion, findsNothing);
    });

    testWidgets('shown by default', (tester) async {
      await pumpCompanion(
        tester,
        due: now.add(const Duration(hours: 2)),
        last: feed('a'),
      );
      expect(companion, findsOneWidget);
      expect(label(tester), 'Next feed is a while off');
    });
  });

  group('the pose reads the clock', () {
    testWidgets('amber window puts it on approach', (tester) async {
      await pumpCompanion(
        tester,
        due: now.add(const Duration(minutes: 10)),
        last: feed('a'),
      );
      expect(label(tester), 'Next feed is due soon');
    });

    testWidgets('overdue puts it on the ground', (tester) async {
      await pumpCompanion(
        tester,
        due: now.subtract(const Duration(minutes: 5)),
        last: feed('a'),
      );
      expect(label(tester), 'Feed is due');
    });

    testWidgets('a wider heads-up brings it in earlier', (tester) async {
      await pumpCompanion(
        tester,
        due: now.add(const Duration(minutes: 25)),
        last: feed('a'),
        prefs: {'reminder_heads_up_minutes': 30},
      );
      expect(label(tester), 'Next feed is due soon');
    });
  });

  group('take-off', () {
    testWidgets('fires when a new feed lands', (tester) async {
      final container = await pumpCompanion(
        tester,
        due: now.subtract(const Duration(minutes: 5)),
        last: feed('first'),
      );
      expect(label(tester), 'Feed is due');

      container.updateOverrides([
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
        nextFeedDueProvider.overrideWithValue(
          now.add(const Duration(hours: 3)),
        ),
        lastClockFeedProvider.overrideWithValue(feed('second')),
        hasAccountPrefsProvider.overrideWithValue(false),
        notificationPrefsProvider.overrideWith(
          (ref) => const Stream<NotificationPrefs>.empty(),
        ),
      ]);
      await tester.pump();

      expect(label(tester), 'Feed logged');

      // And it hands back rather than staying airborne.
      await tester.pump(
        FeedCompanion.celebrateDuration + const Duration(seconds: 1),
      );
      await tester.pump();
      expect(label(tester), 'Next feed is a while off');
    });

    testWidgets('does not fire on the first load', (tester) async {
      // The stream arriving is not a feed being logged; otherwise every cold
      // start would launch the plane.
      final container = await pumpCompanion(
        tester,
        due: now.add(const Duration(hours: 2)),
        last: null,
      );
      container.updateOverrides([
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
        nextFeedDueProvider.overrideWithValue(
          now.add(const Duration(hours: 2)),
        ),
        lastClockFeedProvider.overrideWithValue(feed('first')),
        hasAccountPrefsProvider.overrideWithValue(false),
        notificationPrefsProvider.overrideWith(
          (ref) => const Stream<NotificationPrefs>.empty(),
        ),
      ]);
      await tester.pump();

      expect(label(tester), 'Next feed is a while off');
    });

    testWidgets('does not fire when the same feed is edited', (tester) async {
      final container = await pumpCompanion(
        tester,
        due: now.add(const Duration(hours: 2)),
        last: feed('same'),
      );
      container.updateOverrides([
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
        nextFeedDueProvider.overrideWithValue(
          now.add(const Duration(hours: 2)),
        ),
        // Same id, different content — an edit, not a new feed.
        lastClockFeedProvider.overrideWithValue(
          FeedingEvent(
            id: 'same',
            type: FeedingType.bottle,
            startTime: now.subtract(const Duration(minutes: 30)),
            amountMl: 150,
          ),
        ),
        hasAccountPrefsProvider.overrideWithValue(false),
        notificationPrefsProvider.overrideWith(
          (ref) => const Stream<NotificationPrefs>.empty(),
        ),
      ]);
      await tester.pump();

      expect(label(tester), 'Next feed is a while off');
    });
  });

  group('nothing loops between feeds', () {
    // The reported crash: Home stays open for hours, and the plane was the
    // one style repainting the whole time. A scheduled frame with nothing
    // happening means something is animating that should not be.
    final restingStates = {
      'a while off': now.add(const Duration(hours: 2)),
      'due soon': now.add(const Duration(minutes: 10)),
      'overdue': now.subtract(const Duration(minutes: 5)),
    };

    for (final style in ['plane', 'bottle', 'hourglass', 'battery']) {
      for (final state in restingStates.entries) {
        testWidgets('$style stands still when the feed is ${state.key}', (
          tester,
        ) async {
          await pumpCompanion(
            tester,
            due: state.value,
            last: feed('a'),
            prefs: {'home_companion_style': style},
          );
          expect(companion, findsOneWidget);
          expect(
            tester.binding.hasScheduledFrame,
            isFalse,
            reason: '$style is still animating',
          );

          // And is still idle an hour of app-bar time later.
          await tester.pump(const Duration(hours: 1));
          expect(tester.binding.hasScheduledFrame, isFalse);
        });
      }
    }

    testWidgets('the celebration is the one thing that runs, and it ends', (
      tester,
    ) async {
      final container = await pumpCompanion(
        tester,
        due: now.subtract(const Duration(minutes: 5)),
        last: feed('first'),
      );
      container.updateOverrides([
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
        nextFeedDueProvider.overrideWithValue(
          now.add(const Duration(hours: 3)),
        ),
        lastClockFeedProvider.overrideWithValue(feed('second')),
        hasAccountPrefsProvider.overrideWithValue(false),
        notificationPrefsProvider.overrideWith(
          (ref) => const Stream<NotificationPrefs>.empty(),
        ),
      ]);
      await tester.pump();

      expect(
        tester.binding.hasScheduledFrame,
        isTrue,
        reason: 'the take-off should actually animate',
      );

      await tester.pumpAndSettle();
      expect(
        tester.binding.hasScheduledFrame,
        isFalse,
        reason: 'and hand back to a still pose',
      );
    });
  });

  group('reduced motion', () {
    testWidgets('still poses for the state, just does not move', (
      tester,
    ) async {
      await pumpCompanion(
        tester,
        due: now.subtract(const Duration(minutes: 5)),
        last: feed('a'),
        disableAnimations: true,
      );
      expect(companion, findsOneWidget);
      expect(label(tester), 'Feed is due');
      // No frames scheduled means nothing is looping.
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });
}
