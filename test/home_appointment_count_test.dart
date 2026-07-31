import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:baby_app/core/theme/theme_mode_provider.dart';
import 'package:baby_app/features/home/home_prefs.dart';

Future<ProviderContainer> containerWith(Map<String, Object> stored) async {
  SharedPreferences.setMockInitialValues(stored);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('homeAppointmentCountProvider', () {
    test('defaults to two', () async {
      final c = await containerWith({});
      expect(c.read(homeAppointmentCountProvider), 2);
      expect(defaultHomeAppointmentCount, 2);
    });

    test('reads a stored count', () async {
      final c = await containerWith({'home_appointment_count': 3});
      expect(c.read(homeAppointmentCountProvider), 3);
    });

    test('falls back for a count outside the offered options', () async {
      // A value from a newer build, or a stale one, must not render a row
      // count the settings picker has no segment to undo.
      for (final bad in [0, -1, 99]) {
        final c = await containerWith({'home_appointment_count': bad});
        expect(c.read(homeAppointmentCountProvider), 2, reason: 'stored $bad');
      }
    });

    test('set persists and updates', () async {
      final c = await containerWith({});
      await c.read(homeAppointmentCountProvider.notifier).set(3);
      expect(c.read(homeAppointmentCountProvider), 3);

      final reloaded = await containerWith({'home_appointment_count': 3});
      expect(reloaded.read(homeAppointmentCountProvider), 3);
    });

    test('set ignores a value with no segment behind it', () async {
      final c = await containerWith({});
      await c.read(homeAppointmentCountProvider.notifier).set(10);
      expect(c.read(homeAppointmentCountProvider), 2);
    });

    test('every option is reachable from the picker', () async {
      for (final n in appointmentCountOptions) {
        final c = await containerWith({});
        await c.read(homeAppointmentCountProvider.notifier).set(n);
        expect(c.read(homeAppointmentCountProvider), n);
      }
    });

    test('the default is one of the options', () {
      // Otherwise the picker would open with nothing selected.
      expect(appointmentCountOptions, contains(defaultHomeAppointmentCount));
    });
  });
}
