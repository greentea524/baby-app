import 'package:baby_app/core/format/unit_system.dart';
import 'package:baby_app/data/models/baby.dart';
import 'package:baby_app/data/models/diaper_event.dart';
import 'package:baby_app/data/models/feeding_event.dart';
import 'package:baby_app/data/models/growth_measurement.dart';
import 'package:baby_app/features/export/csv_export.dart';
import 'package:baby_app/features/export/export_data.dart';
import 'package:flutter_test/flutter_test.dart';

ExportData _data({
  List<FeedingEvent> feedings = const [],
  List<DiaperEvent> diapers = const [],
  List<GrowthMeasurement> growth = const [],
  UnitSystem units = UnitSystem.us,
}) => ExportData(
  units: units,
  baby: Baby(
    id: 'b',
    name: 'Ada',
    birthDate: DateTime(2026, 1, 1),
    ownerUid: 'u',
    members: const {'u': CaregiverRole.owner},
  ),
  start: DateTime(2026, 7, 1),
  end: DateTime(2026, 7, 25),
  feedings: feedings,
  diapers: diapers,
  growth: growth,
);

void main() {
  group('escapeCsv', () {
    test('leaves plain values untouched', () {
      expect(escapeCsv('bottle'), 'bottle');
    });

    test('quotes and doubles embedded quotes, commas, newlines', () {
      expect(escapeCsv('a,b'), '"a,b"');
      expect(escapeCsv('say "hi"'), '"say ""hi"""');
      expect(escapeCsv('line1\nline2'), '"line1\nline2"');
    });
  });

  group('buildCsv', () {
    test('writes a header row', () {
      final csv = buildCsv(_data());
      expect(csv.split('\n').first, startsWith('Type,Date,Time,Subtype'));
    });

    test('emits one row per entry, sorted by time across types', () {
      final csv = buildCsv(
        _data(
          feedings: [
            FeedingEvent(
              id: 'f',
              type: FeedingType.bottle,
              startTime: DateTime(2026, 7, 2, 9, 30),
              amountMl: 120,
            ),
          ],
          diapers: [
            DiaperEvent(
              id: 'd',
              type: DiaperType.wet,
              time: DateTime(2026, 7, 1, 8),
            ),
          ],
          growth: [
            GrowthMeasurement(
              id: 'g',
              date: DateTime(2026, 7, 3),
              weightKg: 7.5,
            ),
          ],
        ),
      );
      final lines = csv.trim().split('\n');
      expect(lines.length, 4); // header + 3 entries
      expect(lines[1], startsWith('Diaper,2026-07-01,08:00,wet'));
      expect(lines[2], contains('Feeding,2026-07-02,09:30,bottle'));
      expect(lines[2], contains('120'));
      expect(lines[3], startsWith('Growth,2026-07-03'));
      // 7.5 kg -> 16 lb 9 oz.
      expect(lines[3], contains('16 lb 9 oz'));
    });

    test('escapes notes containing commas', () {
      final csv = buildCsv(
        _data(
          diapers: [
            DiaperEvent(
              id: 'd',
              type: DiaperType.dirty,
              time: DateTime(2026, 7, 1, 8),
              notes: 'green, seedy',
            ),
          ],
        ),
      );
      expect(csv, contains('"green, seedy"'));
    });
  });

  test('csvFilename sanitises the baby name', () {
    final name = csvFilename(_data());
    expect(name, 'Ada-log-2026-07-01-to-2026-07-25');
  });

  group('units', () {
    // One of each row type, so every branch of the row builder is exercised.
    ExportData sample(UnitSystem units) => _data(
      units: units,
      feedings: [
        FeedingEvent(
          id: 'f',
          type: FeedingType.bottle,
          startTime: DateTime(2026, 7, 2, 9, 30),
          amountMl: 120,
        ),
      ],
      diapers: [
        DiaperEvent(
          id: 'd',
          type: DiaperType.wet,
          time: DateTime(2026, 7, 1, 8),
        ),
      ],
      growth: [
        GrowthMeasurement(
          id: 'g',
          date: DateTime(2026, 7, 3),
          weightKg: 7.5,
          heightCm: 62.5,
          headCm: 41,
        ),
      ],
    );

    for (final units in UnitSystem.values) {
      test(
        'every row has exactly as many cells as headers (${units.name})',
        () {
          // The fl oz column is conditional, and each row type repeats that
          // condition — a mismatch would silently shift every later column.
          final lines = buildCsv(sample(units)).trim().split('\n');
          final headerCount = lines.first.split(',').length;
          expect(lines.length, 4);
          for (final line in lines.skip(1)) {
            expect(line.split(','), hasLength(headerCount), reason: line);
          }
        },
      );

      test('growth values land under their own headers (${units.name})', () {
        final lines = buildCsv(sample(units)).trim().split('\n');
        final header = lines.first.split(',');
        final growth = lines
            .firstWhere((l) => l.startsWith('Growth'))
            .split(',');
        final metric = units.isMetric;
        expect(
          growth[header.indexOf(metric ? 'Weight (kg)' : 'Weight (lb oz)')],
          metric ? '7.5 kg' : '16 lb 9 oz',
        );
        expect(
          growth[header.indexOf(metric ? 'Height (cm)' : 'Height (in)')],
          metric ? '62.5 cm' : '24.6 in',
        );
        expect(
          growth[header.indexOf(metric ? 'Head (cm)' : 'Head (in)')],
          metric ? '41 cm' : '16.1 in',
        );
      });
    }

    test('metric omits the fluid-ounce column entirely', () {
      final metricHeader = buildCsv(
        sample(UnitSystem.metric),
      ).split('\n').first;
      final usHeader = buildCsv(sample(UnitSystem.us)).split('\n').first;
      expect(metricHeader, isNot(contains('fl oz')));
      expect(usHeader, contains('Amount (fl oz)'));
      // One column narrower, not merely blanked out.
      expect(metricHeader.split(',').length, usHeader.split(',').length - 1);
    });

    test('the ml amount survives in both systems', () {
      for (final units in UnitSystem.values) {
        final feed = buildCsv(
          sample(units),
        ).split('\n').firstWhere((l) => l.startsWith('Feeding'));
        expect(feed, contains('120'), reason: units.name);
      }
    });
  });
}
