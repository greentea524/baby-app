import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:baby_app/core/theme/theme_mode_provider.dart';
import 'package:baby_app/data/models/pumping_event.dart';
import 'package:baby_app/data/repositories/repository_providers.dart';
import 'package:baby_app/features/pumping/pump_schedule.dart';

/// The pumping cadence, and the due time the Home row counts down to.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 9, 19, 14, 0);

  Future<ProviderContainer> containerWith(
    Map<String, Object> values, {
    List<PumpingEvent> pumps = const [],
  }) async {
    SharedPreferences.setMockInitialValues(values);
    final stored = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(stored),
        recentPumpingProvider.overrideWith((ref) => Stream.value(pumps)),
      ],
    );
    addTearDown(container.dispose);
    // The stream provider is auto-dispose: a bare read would build and tear
    // down again before it ever emits.
    container.listen(recentPumpingProvider, (_, _) {});
    await container.read(recentPumpingProvider.future);
    return container;
  }

  group('the stored interval', () {
    test('is off until it is set', () async {
      // The feed reminder defaults to a 3-hour gap; this deliberately does
      // not. A pumping schedule is the caregiver's, not something the app
      // can read out of the log, so there is nothing to default to.
      final container = await containerWith({});
      expect(container.read(pumpIntervalProvider), 0);
    });

    test('is read back from preferences', () async {
      final container = await containerWith({'pump_interval_minutes': 120});
      expect(container.read(pumpIntervalProvider), 120);
    });

    test('survives a round trip through the notifier', () async {
      final container = await containerWith({});
      await container.read(pumpIntervalProvider.notifier).setMinutes(180);

      expect(container.read(pumpIntervalProvider), 180);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('pump_interval_minutes'), 180);
    });

    test('every offered option is a real choice', () async {
      expect(pumpIntervalOptions, contains(0), reason: 'Off has to be one');
      expect(
        pumpIntervalOptions.toSet(),
        hasLength(pumpIntervalOptions.length),
        reason: 'a duplicate would break the dropdown',
      );
      expect(
        pumpIntervalOptions,
        orderedEquals([...pumpIntervalOptions]..sort()),
        reason: 'the menu should read in order',
      );
    });
  });

  group('when the next pump is due', () {
    final lastPump = PumpingEvent(
      id: 'p1',
      time: now.subtract(const Duration(minutes: 30)),
      amountMl: 90,
    );

    test('is the last session plus the interval', () async {
      final container = await containerWith(
        {'pump_interval_minutes': 120},
        pumps: [lastPump],
      );

      expect(
        container.read(nextPumpDueProvider),
        now.add(const Duration(minutes: 90)),
      );
    });

    test('moves with the last session rather than a fixed clock', () async {
      // Pumping late pushes the next one out. Anchored to a wall-clock
      // schedule it would instead read as already overdue the moment it was
      // logged, which is a countdown that punishes the caregiver for using
      // it.
      final late = PumpingEvent(id: 'p2', time: now, amountMl: 90);
      final container = await containerWith(
        {'pump_interval_minutes': 120},
        pumps: [late],
      );

      expect(
        container.read(nextPumpDueProvider),
        now.add(const Duration(minutes: 120)),
      );
    });

    test('is nothing at all without an interval', () async {
      final container = await containerWith({}, pumps: [lastPump]);
      expect(container.read(nextPumpDueProvider), isNull);
    });

    test('and nothing without a session to measure from', () async {
      final container = await containerWith({'pump_interval_minutes': 120});
      expect(container.read(nextPumpDueProvider), isNull);
    });

    test('a stored zero reads as off, not as due immediately', () async {
      // 0 is what the dropdown's Off writes, and `last + 0 minutes` would be
      // a due time in the past — a row permanently red for a caregiver who
      // asked for no countdown.
      final container = await containerWith(
        {'pump_interval_minutes': 0},
        pumps: [lastPump],
      );

      expect(container.read(nextPumpDueProvider), isNull);
    });
  });
}
