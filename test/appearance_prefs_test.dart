import 'package:baby_app/core/theme/app_accent.dart';
import 'package:baby_app/core/theme/app_theme.dart';
import 'package:baby_app/features/home/home_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppAccent', () {
    test('resolves a stored name', () {
      expect(AppAccent.fromName('sage'), AppAccent.sage);
      expect(AppAccent.fromName('lavender'), AppAccent.lavender);
    });

    test('falls back for an unset or unknown value', () {
      // Someone on a newer build could store an accent this one has never
      // heard of; that must not break theming.
      expect(AppAccent.fromName(null), AppAccent.blue);
      expect(AppAccent.fromName('chartreuse'), AppAccent.blue);
    });

    test('the default accent matches the theme default seed', () {
      // Otherwise a fresh install would look different from one that has
      // explicitly picked the default.
      expect(AppAccent.blue.seed, AppTheme.defaultSeed);
    });

    test('every accent has a distinct seed and a label', () {
      final seeds = AppAccent.values.map((a) => a.seed).toSet();
      expect(seeds, hasLength(AppAccent.values.length));
      for (final a in AppAccent.values) {
        expect(a.label, isNotEmpty, reason: '${a.name} needs a label');
      }
    });
  });

  group('AppTheme', () {
    test('derives both brightnesses from the given seed', () {
      final light = AppTheme.light(AppAccent.sage.seed);
      final dark = AppTheme.dark(AppAccent.sage.seed);
      expect(light.colorScheme.brightness, Brightness.light);
      expect(dark.colorScheme.brightness, Brightness.dark);
    });

    test('a different accent produces a different primary', () {
      final blue = AppTheme.light(AppAccent.blue.seed).colorScheme.primary;
      final blush = AppTheme.light(AppAccent.blush.seed).colorScheme.primary;
      expect(blue, isNot(blush));
    });

    test('omitting the seed keeps the original palette', () {
      expect(
        AppTheme.light().colorScheme.primary,
        AppTheme.light(AppTheme.defaultSeed).colorScheme.primary,
      );
    });
  });

  group('HomeLayout', () {
    test('resolves a stored name', () {
      expect(HomeLayout.fromName('separate'), HomeLayout.separate);
      expect(HomeLayout.fromName('combined'), HomeLayout.combined);
    });

    test('defaults to combined', () {
      expect(HomeLayout.fromName(null), HomeLayout.combined);
      expect(HomeLayout.fromName('mosaic'), HomeLayout.combined);
    });

    test('every layout has a label and a description', () {
      for (final l in HomeLayout.values) {
        expect(l.label, isNotEmpty);
        expect(l.description, isNotEmpty);
      }
    });
  });
}
