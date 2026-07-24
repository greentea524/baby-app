import 'package:baby_app/data/models/diaper_event.dart';
import 'package:baby_app/features/diaper/diaper_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DiaperFormat', () {
    test('type labels', () {
      expect(DiaperFormat.typeLabel(DiaperType.wet), 'Wet');
      expect(DiaperFormat.typeLabel(DiaperType.dirty), 'Dirty');
      expect(DiaperFormat.typeLabel(DiaperType.both), 'Wet + Dirty');
    });

    test('details returns trimmed notes or empty', () {
      final withNotes = DiaperEvent(
        id: 'a',
        type: DiaperType.dirty,
        time: DateTime(2026, 7, 23),
        notes: '  greenish  ',
      );
      expect(DiaperFormat.details(withNotes), 'greenish');

      final noNotes = DiaperEvent(
        id: 'b',
        type: DiaperType.wet,
        time: DateTime(2026, 7, 23),
      );
      expect(DiaperFormat.details(noNotes), '');
    });
  });
}
