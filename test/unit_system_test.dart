import 'package:baby_app/core/format/unit_system.dart';
import 'package:baby_app/core/format/volume_format.dart';
import 'package:baby_app/features/growth/growth_metric.dart';
import 'package:baby_app/features/growth/growth_units.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UnitSystem.fromName', () {
    test('resolves a stored name', () {
      expect(UnitSystem.fromName('metric'), UnitSystem.metric);
      expect(UnitSystem.fromName('us'), UnitSystem.us);
    });

    test('defaults to US, which is what the app showed before the setting', () {
      // An existing caregiver must not find their units silently swapped by
      // an update.
      expect(UnitSystem.fromName(null), UnitSystem.us);
      expect(UnitSystem.fromName('imperial'), UnitSystem.us);
    });
  });

  group('formatVolume', () {
    test('US shows millilitres with the fluid-ounce equivalent', () {
      expect(formatVolume(120, UnitSystem.us), '4.1 fl oz (120 ml)');
    });

    test('metric shows millilitres alone', () {
      expect(formatVolume(120, UnitSystem.metric), '120 ml');
    });

    test('both keep the ml figure, since that is what was typed in', () {
      for (final u in UnitSystem.values) {
        expect(formatVolume(90, u), contains('90 ml'));
      }
    });
  });

  group('formatWeight', () {
    test('metric reports kilograms', () {
      expect(formatWeight(6.4, UnitSystem.metric), '6.4 kg');
      expect(formatWeight(7, UnitSystem.metric), '7 kg');
    });

    test('US reports pounds and ounces', () {
      expect(formatWeight(7.5, UnitSystem.us), '16 lb 9 oz');
    });
  });

  group('formatLength', () {
    test('metric reports centimetres', () {
      expect(formatLength(62.5, UnitSystem.metric), '62.5 cm');
    });

    test('US reports inches', () {
      expect(formatLength(62.5, UnitSystem.us), '24.6 in');
    });
  });

  group('GrowthMetric display', () {
    test('axis units follow the setting', () {
      expect(GrowthMetric.weight.displayUnit(UnitSystem.metric), 'kg');
      expect(GrowthMetric.weight.displayUnit(UnitSystem.us), 'lb');
      expect(GrowthMetric.height.displayUnit(UnitSystem.metric), 'cm');
      expect(GrowthMetric.head.displayUnit(UnitSystem.us), 'in');
    });

    test('metric conversion is a no-op, since storage is already metric', () {
      expect(GrowthMetric.weight.toDisplay(6.4, UnitSystem.metric), 6.4);
      expect(GrowthMetric.height.toDisplay(62.5, UnitSystem.metric), 62.5);
    });

    test('US converts weight to pounds and lengths to inches', () {
      expect(
        GrowthMetric.weight.toDisplay(1, UnitSystem.us),
        closeTo(2.2046, 0.001),
      );
      expect(
        GrowthMetric.height.toDisplay(2.54, UnitSystem.us),
        closeTo(1, 0.001),
      );
    });
  });

  group('round trip', () {
    test('entering in US and storing metric preserves the value', () {
      // The growth sheet converts on save; this is the arithmetic behind it.
      final kg = lbOzToKg(16, 9);
      expect(formatWeight(kg, UnitSystem.us), '16 lb 9 oz');
    });

    test('inches survive the trip through centimetres', () {
      final cm = inToCm(24.6);
      expect(formatLength(cm, UnitSystem.us), '24.6 in');
    });
  });
}
