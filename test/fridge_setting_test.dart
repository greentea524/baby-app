import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:baby_app/core/theme/theme_mode_provider.dart';
import 'package:baby_app/features/home/home_prefs.dart';

/// The Settings switch that hides the fridge.
void main() {
  Future<ProviderContainer> containerWith(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('is on to begin with, which is how anyone finds the fridge', () async {
    final container = await containerWith({});
    expect(container.read(showFridgeProvider), isTrue);
  });

  test('is remembered once turned off', () async {
    final container = await containerWith({});
    await container.read(showFridgeProvider.notifier).set(false);
    expect(container.read(showFridgeProvider), isFalse);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('show_fridge'), isFalse);
  });
}
