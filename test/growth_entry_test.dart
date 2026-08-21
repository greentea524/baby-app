import 'package:flutter_test/flutter_test.dart';

import 'package:baby_app/features/growth/growth_units.dart';

/// Entering a weight in pounds when your scale reads in decimals.
///
/// The sheet offers a pounds field and an ounces field, which is how a
/// paediatrician reports a weight — but plenty of scales, and plenty of
/// notes written down at home, say "7.5 lb". That has to mean seven and a
/// half pounds, not seven.
void main() {
  group('pounds with a fraction', () {
    test('half a pound is eight ounces, not nothing', () {
      // The bug: the pounds field used to be truncated to a whole number
      // before conversion, so this silently dropped 227 grams.
      expect(lbOzToKg(7.5, 0), closeTo(lbOzToKg(7, 8), 1e-9));
    });

    test('a tenth of a pound survives', () {
      expect(kgToLb(lbOzToKg(7.4, 0)), closeTo(7.4, 1e-9));
    });

    test('pounds and ounces still add up', () {
      expect(kgToLb(lbOzToKg(7.5, 4)), closeTo(7.75, 1e-9));
    });

    test('whole pounds are unchanged', () {
      expect(kgToLb(lbOzToKg(13, 4)), closeTo(13.25, 1e-9));
    });
  });

  group('what the fields show it back as', () {
    test('a decimal entry re-reads as pounds and ounces', () {
      // 7.5 lb is exactly 7 lb 8 oz, so nothing is lost showing it that way.
      final split = kgToLbOz(lbOzToKg(7.5, 0));
      expect(split.lb, 7);
      expect(split.oz, 8);
    });

    test('a tenth that is not a whole ounce rounds on display only', () {
      // 7.4 lb is 7 lb 6.4 oz. The field has to show whole ounces, so it
      // shows 6 — which is why an untouched field must not be written back.
      final split = kgToLbOz(lbOzToKg(7.4, 0));
      expect(split.lb, 7);
      expect(split.oz, 6);
      expect(kgToLb(lbOzToKg(7, 6)), closeTo(7.375, 1e-9));
    });
  });

  group('what actually gets stored', () {
    double? store({
      bool metric = false,
      double? stored,
      bool edited = true,
      double? kilograms,
      double? pounds,
      double? ounces,
    }) => weightToStore(
      metric: metric,
      stored: stored,
      edited: edited,
      kilograms: kilograms,
      pounds: pounds,
      ounces: ounces,
    );

    test('a decimal in the pounds field is taken at its word', () {
      expect(kgToLb(store(pounds: 7.5)!), closeTo(7.5, 1e-9));
    });

    test('pounds and ounces are added, not chosen between', () {
      expect(kgToLb(store(pounds: 7.5, ounces: 4)!), closeTo(7.75, 1e-9));
    });

    test('ounces alone still work', () {
      expect(kgToLb(store(ounces: 9)!), closeTo(9 / 16, 1e-9));
    });

    test('both fields empty means no weight', () {
      expect(store(), isNull);
    });

    test('metric reads the kilogram field and ignores the rest', () {
      expect(store(metric: true, kilograms: 6.4, pounds: 6.4), 6.4);
    });

    group('an untouched field', () {
      // The drift this exists to stop: 7.4 lb displays as 7 lb 6 oz, and
      // 7 lb 6 oz is 7.375 lb. Nobody edited it, and it changed.
      final original = lbOzToKg(7.4, 0);

      test('is written back exactly, not re-read from the boxes', () {
        expect(
          store(stored: original, edited: false, pounds: 7, ounces: 6),
          original,
        );
      });

      test('and re-reading it really would have moved it', () {
        // Proves the guard is load-bearing rather than belt and braces.
        final reparsed = store(edited: true, pounds: 7, ounces: 6)!;
        expect(reparsed, isNot(closeTo(original, 1e-6)));
        expect(kgToLb(reparsed), closeTo(7.375, 1e-9));
      });

      test('gives way the moment it is retyped', () {
        expect(
          kgToLb(store(stored: original, edited: true, pounds: 8)!),
          closeTo(8, 1e-9),
        );
      });

      test('metric drifts the same way, and is guarded the same way', () {
        // 6.45 kg shows as "6.5" in a one-decimal field.
        expect(
          store(metric: true, stored: 6.45, edited: false, kilograms: 6.5),
          6.45,
        );
      });
    });
  });
}
