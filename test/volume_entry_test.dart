import 'package:flutter_test/flutter_test.dart';

import 'package:baby_app/core/format/unit_system.dart';
import 'package:baby_app/core/format/volume_entry.dart';
import 'package:baby_app/core/format/volume_format.dart';

/// Typing an amount in ounces while storage stays millilitres. The risk is
/// not the arithmetic, it is the round trip: a value converted out and back
/// on every edit walks away from what was entered.
void main() {
  group('which unit is offered first', () {
    test('follows the caregiver setting', () {
      expect(VolumeUnit.defaultFor(UnitSystem.metric), VolumeUnit.ml);
      expect(VolumeUnit.defaultFor(UnitSystem.us), VolumeUnit.flOz);
    });
  });

  group('conversion', () {
    test('millilitres pass straight through', () {
      expect(VolumeUnit.ml.toMl(120), 120);
      expect(VolumeUnit.ml.fromMl(120), 120);
    });

    test('ounces convert both ways', () {
      expect(VolumeUnit.flOz.toMl(5), closeTo(147.87, 0.01));
      expect(VolumeUnit.flOz.fromMl(147.87), closeTo(5, 0.001));
    });

    test('a typed amount survives a round trip', () {
      for (final typed in [1.0, 2.5, 4.0, 5.5, 8.0]) {
        final stored = VolumeUnit.flOz.toMl(typed);
        expect(
          VolumeUnit.flOz.fromMl(stored),
          closeTo(typed, 0.0001),
          reason: '$typed fl oz',
        );
      }
    });

    test('agrees with the display formatter', () {
      // Two paths to the same number; if they drift, an amount would read
      // differently on the row it was just typed on.
      final stored = VolumeUnit.flOz.toMl(5);
      expect(formatFlOz(stored), '5');
      expect(VolumeUnit.flOz.fieldText(stored), '5');
    });
  });

  group('what the field opens with', () {
    test('drops a trailing .0 so there is nothing to delete first', () {
      expect(VolumeUnit.ml.fieldText(120), '120');
      expect(VolumeUnit.flOz.fieldText(VolumeUnit.flOz.toMl(4)), '4');
    });

    test('keeps one decimal where it matters', () {
      expect(VolumeUnit.ml.fieldText(62.5), '62.5');
      expect(VolumeUnit.flOz.fieldText(150), '5.1');
    });

    test('rounds rather than truncating', () {
      expect(VolumeUnit.ml.fieldText(120.06), '120.1');
    });
  });

  group('the drift this guards against', () {
    test('re-parsing a display value moves the stored amount', () {
      // What would happen if an untouched field were re-read on every save:
      // 150 ml shows as 5.1 fl oz, and 5.1 fl oz is not 150 ml. Nobody
      // touched the amount, and it changed.
      const stored = 150.0;
      final reparsed = VolumeUnit.flOz.toMl(
        double.parse(VolumeUnit.flOz.fieldText(stored)),
      );
      expect(reparsed, isNot(closeTo(stored, 0.05)));
      expect((reparsed - stored).abs(), greaterThan(0.5));
    });

    test('it lands on the rounding grid and stays, rather than compounding', () {
      // Worth pinning, because the obvious fear is a value walking further on
      // every edit. It does not: one conversion snaps it to a point that
      // survives the next round trip. That makes this a wrong number rather
      // than a runaway one — still wrong, still worth not writing.
      var stored = 150.0;
      final steps = <double>[];
      for (var edit = 0; edit < 5; edit++) {
        stored = VolumeUnit.flOz.toMl(
          double.parse(VolumeUnit.flOz.fieldText(stored)),
        );
        steps.add(stored);
      }
      expect(steps.toSet(), hasLength(1), reason: 'settles after the first');
      expect(steps.first, isNot(closeTo(150, 0.05)));
    });
  });
}
