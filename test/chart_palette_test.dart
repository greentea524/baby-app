import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:baby_app/core/theme/app_theme.dart';
import 'package:baby_app/features/insights/chart_palette.dart';

/// The day charts' category colours have to be told apart at a glance.
///
/// They were not: two of them were one hue at different opacity, and two more
/// were `primary` and `secondary` from the same seed, which Material puts
/// side by side. These tests pin the separation numerically so the next
/// person to reach for `withValues(alpha:)` has to argue with a failure.
void main() {
  /// How far apart two colours sit on the wheel, in degrees.
  double hueGap(Color a, Color b) {
    final gap = (HSLColor.fromColor(a).hue - HSLColor.fromColor(b).hue).abs();
    return gap > 180 ? 360 - gap : gap;
  }

  /// Distance in RGB. Crude next to a proper perceptual metric, but enough
  /// to catch "these are the same colour, faded".
  double distance(Color a, Color b) {
    final dr = ((a.r - b.r) * 255);
    final dg = ((a.g - b.g) * 255);
    final db = ((a.b - b.b) * 255);
    return math.sqrt(dr * dr + dg * dg + db * db);
  }

  for (final (name, brightness) in [
    ('light', Brightness.light),
    ('dark', Brightness.dark),
  ]) {
    group('in $name', () {
      late DayColours colours;

      setUp(() {
        colours = DayColours.forBrightness(brightness);
      });

      test('every pair is a long way apart', () {
        final all = {
          'feed': colours.feed,
          'diaper': colours.diaper,
          'pump': colours.pump,
          'wet': colours.wet,
        };
        for (final a in all.entries) {
          for (final b in all.entries) {
            if (a.key == b.key) continue;
            expect(
              distance(a.value, b.value),
              greaterThan(100),
              reason: '${a.key} and ${b.key} are too close',
            );
          }
        }
      });

      test('and none is another one faded', () {
        // The specific failure being guarded: the old palette made its
        // categories by dropping the opacity of one it already had, so two
        // of them were a single hue twice. Requiring real hue separation
        // says that cannot be how the next one is made either.
        final all = [colours.feed, colours.diaper, colours.pump, colours.wet];
        for (var i = 0; i < all.length; i++) {
          for (var j = i + 1; j < all.length; j++) {
            expect(
              hueGap(all[i], all[j]),
              greaterThan(25),
              reason: 'pair $i/$j is the same hue twice',
            );
          }
        }
      });

      test('all of them are opaque', () {
        // Opacity was how the old palette made its variants, and a
        // translucent category takes its colour from whatever is behind it.
        for (final c in [
          colours.feed,
          colours.diaper,
          colours.pump,
          colours.wet,
        ]) {
          expect(c.a, 1.0);
        }
      });
    });
  }

  testWidgets('the palette follows the theme brightness', (tester) async {
    // Read off the element rather than captured from inside a builder: the
    // first version captured during build, and the second pump reused the
    // Builder without rebuilding, so it compared the light set with itself
    // and passed nothing.
    Future<DayColours> underTheme(ThemeData theme) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const SizedBox(key: Key('probe')),
        ),
      );
      // Settle first: MaterialApp lerps between themes, so reading straight
      // after the pump catches the *old* brightness halfway through the
      // transition — which had this test comparing the light set with
      // itself and passing nothing.
      await tester.pumpAndSettle();
      // By key, not by type: MaterialApp builds SizedBoxes of its own above
      // the Theme.
      return DayColours.of(tester.element(find.byKey(const Key('probe'))));
    }

    final light = await underTheme(AppTheme.light());
    final dark = await underTheme(AppTheme.dark());

    expect(light, isNot(dark));
    // Dark surfaces need the lighter set, or every category goes muddy.
    expect(
      light.feed.computeLuminance(),
      lessThan(dark.feed.computeLuminance()),
    );
  });

  test('"both" is drawn from the two it means, not a third colour', () {
    final colours = DayColours.forBrightness(Brightness.light);
    final gradient = colours.both as LinearGradient;
    expect(gradient.colors.toSet(), {colours.wet, colours.diaper});
    // A hard edge at the midpoint, not a blend — a blend would be a third
    // colour again, and a muddy one.
    expect(gradient.stops, [0, 0.5, 0.5, 1]);
  });
}
