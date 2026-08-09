import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:baby_app/core/theme/theme_mode_provider.dart';
import 'package:baby_app/data/models/feeding_event.dart';
import 'package:baby_app/data/repositories/repository_providers.dart';
import 'package:baby_app/features/home/feed_plane.dart';
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
  Future<ProviderContainer> pumpPlane(
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
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: disableAnimations),
            child: Scaffold(body: FeedPlane(now: now)),
          ),
        ),
      ),
    );
    await tester.pump();
    return container;
  }

  /// The plane's own painter. Scaffold and Material insert CustomPaints of
  /// their own, so byType alone matches Flutter's internals too.
  final plane = find.descendant(
    of: find.byType(FeedPlane),
    matching: find.byType(CustomPaint),
  );

  String? label(WidgetTester tester) {
    final found = find.byType(FeedPlane);
    if (tester.widgetList(find.byType(SizedBox)).isEmpty) return null;
    final semantics = tester.getSemantics(found);
    return semantics.label.isEmpty ? null : semantics.label;
  }

  group('resting state follows the chip', () {
    test('maps every due state to a pose', () {
      expect(planeStateFor(FeedDueState.upcoming), PlaneState.cruising);
      expect(planeStateFor(FeedDueState.soon), PlaneState.approach);
      expect(planeStateFor(FeedDueState.overdue), PlaneState.landed);
    });
  });

  group('when it shows at all', () {
    testWidgets('hidden with reminders off, since there is no due time', (
      tester,
    ) async {
      await pumpPlane(tester, due: null, last: feed('a'));
      expect(plane, findsNothing);
    });

    testWidgets('hidden when the caregiver turns it off', (tester) async {
      await pumpPlane(
        tester,
        due: now.add(const Duration(hours: 2)),
        last: feed('a'),
        prefs: {'show_feed_plane': false},
      );
      expect(plane, findsNothing);
    });

    testWidgets('shown by default', (tester) async {
      await pumpPlane(
        tester,
        due: now.add(const Duration(hours: 2)),
        last: feed('a'),
      );
      expect(plane, findsOneWidget);
      expect(label(tester), 'Next feed is a while off');
    });
  });

  group('the pose reads the clock', () {
    testWidgets('amber window puts it on approach', (tester) async {
      await pumpPlane(
        tester,
        due: now.add(const Duration(minutes: 10)),
        last: feed('a'),
      );
      expect(label(tester), 'Next feed is due soon');
    });

    testWidgets('overdue puts it on the ground', (tester) async {
      await pumpPlane(
        tester,
        due: now.subtract(const Duration(minutes: 5)),
        last: feed('a'),
      );
      expect(label(tester), 'Feed is due');
    });

    testWidgets('a wider heads-up brings it in earlier', (tester) async {
      await pumpPlane(
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
      final container = await pumpPlane(
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
      ]);
      await tester.pump();

      expect(label(tester), 'Feed logged');

      // And it hands back rather than staying airborne.
      await tester.pump(FeedPlane.takeoffDuration + const Duration(seconds: 1));
      await tester.pump();
      expect(label(tester), 'Next feed is a while off');
    });

    testWidgets('does not fire on the first load', (tester) async {
      // The stream arriving is not a feed being logged; otherwise every cold
      // start would launch the plane.
      final container = await pumpPlane(
        tester,
        due: now.add(const Duration(hours: 2)),
        last: null,
      );
      container.updateOverrides([
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
        nextFeedDueProvider.overrideWithValue(now.add(const Duration(hours: 2))),
        lastClockFeedProvider.overrideWithValue(feed('first')),
      ]);
      await tester.pump();

      expect(label(tester), 'Next feed is a while off');
    });

    testWidgets('does not fire when the same feed is edited', (tester) async {
      final container = await pumpPlane(
        tester,
        due: now.add(const Duration(hours: 2)),
        last: feed('same'),
      );
      container.updateOverrides([
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
        nextFeedDueProvider.overrideWithValue(now.add(const Duration(hours: 2))),
        // Same id, different content — an edit, not a new feed.
        lastClockFeedProvider.overrideWithValue(
          FeedingEvent(
            id: 'same',
            type: FeedingType.bottle,
            startTime: now.subtract(const Duration(minutes: 30)),
            amountMl: 150,
          ),
        ),
      ]);
      await tester.pump();

      expect(label(tester), 'Next feed is a while off');
    });
  });

  group('reduced motion', () {
    testWidgets('still poses for the state, just does not move', (
      tester,
    ) async {
      await pumpPlane(
        tester,
        due: now.subtract(const Duration(minutes: 5)),
        last: feed('a'),
        disableAnimations: true,
      );
      expect(plane, findsOneWidget);
      expect(label(tester), 'Feed is due');
      // No frames scheduled means nothing is looping.
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });
}
