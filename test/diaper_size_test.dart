import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:baby_app/data/models/diaper_event.dart';
import 'package:baby_app/features/diaper/diaper_format.dart';

/// How big a dirty one was (#20). Optional throughout, and meaningless on a
/// wet-only change — which the model refuses to represent rather than merely
/// discourage.
void main() {
  final at = DateTime(2026, 8, 10, 9, 30);

  DiaperEvent change(DiaperType type, {DiaperSize? size, String? notes}) =>
      DiaperEvent(id: 'd', type: type, time: at, size: size, notes: notes);

  group('a wet change cannot carry a size', () {
    test('the constructor drops it', () {
      final wet = change(DiaperType.wet, size: DiaperSize.large);
      expect(wet.size, isNull);
      expect(wet.hasStool, isFalse);
    });

    test('so a record already stored that way reads clean', () {
      // Not hypothetical: a size picked, then the type switched to wet, then
      // saved by a build without the clearing logic would land exactly here.
      expect(change(DiaperType.wet, size: DiaperSize.small).toMap()['size'],
          isNull);
    });

    test('but a dirty one keeps it', () {
      expect(change(DiaperType.dirty, size: DiaperSize.medium).size,
          DiaperSize.medium);
      expect(change(DiaperType.both, size: DiaperSize.large).size,
          DiaperSize.large);
    });

    test('wet + dirty counts as having stool', () {
      expect(change(DiaperType.both).hasStool, isTrue);
      expect(change(DiaperType.dirty).hasStool, isTrue);
      expect(change(DiaperType.wet).hasStool, isFalse);
    });
  });

  group('staying optional', () {
    test('no size is a normal state, not a gap', () {
      final plain = change(DiaperType.dirty);
      expect(plain.size, isNull);
      expect(plain.toMap()['size'], isNull);
    });

    test('a change logged before sizes existed still reads', () {
      expect(DiaperSize.fromName(null), isNull);
    });

    test('a size this build does not know reads as none', () {
      // A value removed in a later version should not throw on an older one.
      expect(DiaperSize.fromName('enormous'), isNull);
    });

    test('every known name round-trips', () {
      for (final size in DiaperSize.values) {
        expect(DiaperSize.fromName(size.name), size);
      }
    });
  });

  group('how it reads on a row', () {
    test('size and notes join as one line', () {
      expect(
        DiaperFormat.details(
          change(DiaperType.dirty, size: DiaperSize.large, notes: 'green'),
        ),
        'Large · green',
      );
    });

    test('either alone stands on its own', () {
      expect(
        DiaperFormat.details(change(DiaperType.dirty, size: DiaperSize.small)),
        'Small',
      );
      expect(
        DiaperFormat.details(change(DiaperType.dirty, notes: 'runny')),
        'runny',
      );
    });

    test('neither leaves the row empty rather than dangling a separator', () {
      expect(DiaperFormat.details(change(DiaperType.wet)), '');
    });

    test('whitespace-only notes do not earn a separator', () {
      expect(
        DiaperFormat.details(
          change(DiaperType.dirty, size: DiaperSize.medium, notes: '   '),
        ),
        'Medium',
      );
    });
  });

  group('the labels', () {
    test('read as words, not enum names', () {
      expect(DiaperSize.small.label, 'Small');
      expect(DiaperSize.medium.label, 'Medium');
      expect(DiaperSize.large.label, 'Large');
    });

    test('run smallest to largest, which is the order they are offered in', () {
      expect(
        DiaperSize.values.map((s) => s.label),
        ['Small', 'Medium', 'Large'],
      );
    });
  });

  testWidgets('the icon still comes from the type, not the size', (
    tester,
  ) async {
    // Guards against the size quietly taking over the row's icon.
    expect(DiaperFormat.typeIcon(DiaperType.dirty), Icons.eco);
    expect(DiaperFormat.typeIcon(DiaperType.wet), Icons.water_drop);
  });
}
