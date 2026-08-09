import 'package:baby_app/core/format/unit_system.dart';
import 'package:baby_app/data/models/baby.dart';
import 'package:baby_app/data/models/diaper_event.dart';
import 'package:baby_app/data/models/feeding_event.dart';
import 'package:baby_app/data/models/growth_measurement.dart';
import 'package:baby_app/data/models/pumping_event.dart';
import 'package:baby_app/features/export/export_data.dart';
import 'package:baby_app/features/export/pdf_export.dart';
import 'package:baby_app/features/export/report_summary.dart';
import 'package:flutter_test/flutter_test.dart';

ExportData _sample({UnitSystem units = UnitSystem.us}) => ExportData(
  units: units,
  baby: Baby(
    id: 'b',
    name: 'Ada',
    birthDate: DateTime(2026, 1, 1),
    sex: BabySex.female,
    ownerUid: 'u',
    members: const {'u': CaregiverRole.owner},
  ),
  start: DateTime(2026, 7, 1),
  end: DateTime(2026, 7, 4),
  feedings: [
    FeedingEvent(
      id: 'f1',
      type: FeedingType.bottle,
      startTime: DateTime(2026, 7, 1, 8),
      amountMl: 120,
    ),
    FeedingEvent(
      id: 'f2',
      type: FeedingType.bottle,
      startTime: DateTime(2026, 7, 1, 11),
      amountMl: 100,
    ),
    FeedingEvent(
      id: 'f3',
      type: FeedingType.breast,
      startTime: DateTime(2026, 7, 2, 9),
      durationMinutes: 20,
    ),
  ],
  diapers: [
    DiaperEvent(id: 'd1', type: DiaperType.wet, time: DateTime(2026, 7, 1, 9)),
    DiaperEvent(
      id: 'd2',
      type: DiaperType.dirty,
      time: DateTime(2026, 7, 2, 10),
    ),
  ],
  growth: [
    GrowthMeasurement(id: 'g1', date: DateTime(2026, 7, 1), weightKg: 7.2),
  ],
);

void main() {
  group('ReportSummary', () {
    test('aggregates totals and per-day rows', () {
      final s = ReportSummary.from(_sample());
      expect(s.totalFeeds, 3);
      expect(s.totalDiapers, 2);
      expect(s.totalBottleMl, 220);
      expect(s.totalBreastMinutes, 20);
      expect(s.daily.length, 2); // Jul 1 and Jul 2
      expect(s.feedsPerDay, closeTo(1.5, 0.001));
      // Only Jul 1 has 2+ feeds: interval 8:00 -> 11:00 = 180 min.
      expect(s.avgFeedIntervalMinutes, 180);
    });

    test('counts top-ups apart from feeds', () {
      // A pediatrician reading "feeds per day" should not have 10 ml top-ups
      // folded into it — but the volume should still include them.
      final base = _sample();
      final withSnack = ExportData(
        units: base.units,
        baby: base.baby,
        start: base.start,
        end: base.end,
        feedings: [
          ...base.feedings,
          FeedingEvent(
            id: 'snack',
            type: FeedingType.bottle,
            startTime: DateTime(2026, 7, 1, 9),
            amountMl: 10,
            isSnack: true,
          ),
        ],
        diapers: base.diapers,
        growth: base.growth,
      );

      final s = ReportSummary.from(withSnack);
      expect(s.totalFeeds, 3, reason: 'unchanged by the top-up');
      expect(s.totalSnacks, 1);
      expect(s.totalBottleMl, 230, reason: 'the baby still drank it');
      expect(s.feedsPerDay, closeTo(1.5, 0.001));
    });

    group('pumping', () {
      ExportData withPumps(List<PumpingEvent> pumps) {
        final base = _sample();
        return ExportData(
          units: base.units,
          baby: base.baby,
          start: base.start,
          end: base.end,
          feedings: base.feedings,
          diapers: base.diapers,
          growth: base.growth,
          pumps: pumps,
        );
      }

      PumpingEvent pump(String id, DateTime at, double ml) =>
          PumpingEvent(id: id, time: at, amountMl: ml);

      test('totals sessions and volume', () {
        final s = ReportSummary.from(
          withPumps([
            pump('p1', DateTime(2026, 7, 1, 7), 90),
            pump('p2', DateTime(2026, 7, 2, 7), 110),
          ]),
        );
        expect(s.totalPumps, 2);
        expect(s.totalPumpedMl, 200);
      });

      test('pumped milk never lands in the bottle total', () {
        // The same milk usually comes back as a bottle that is already
        // counted; adding both would report it twice to a pediatrician.
        final s = ReportSummary.from(
          withPumps([pump('p1', DateTime(2026, 7, 1, 7), 90)]),
        );
        expect(s.totalBottleMl, 220, reason: 'the feeds, and only the feeds');
        expect(s.totalPumpedMl, 90);
      });

      test('a day with only pumping still gets a row', () {
        // Jul 3 has no feed and no diaper. The CSV exports the session, so
        // dropping it here would make two exports of one window disagree.
        final s = ReportSummary.from(
          withPumps([pump('p1', DateTime(2026, 7, 3, 7), 60)]),
        );
        expect(s.daily.length, 3);
        final last = s.daily.last;
        expect(last.day, DateTime(2026, 7, 3));
        expect(last.stats.pumpedMl, 60);
        expect(last.stats.feedCount, 0);
      });

      test('stays at zero when nobody pumped', () {
        final s = ReportSummary.from(_sample());
        expect(s.totalPumps, 0);
        expect(s.totalPumpedMl, 0);
      });

      test('a window of nothing but pumping is not empty', () {
        // The report prints "No entries were logged in this period" off this
        // flag, which would have flatly contradicted its own table.
        final base = _sample();
        final onlyPumps = ExportData(
          baby: base.baby,
          start: base.start,
          end: base.end,
          feedings: const [],
          diapers: const [],
          growth: const [],
          pumps: [pump('p1', DateTime(2026, 7, 1, 7), 90)],
        );
        expect(onlyPumps.isEmpty, isFalse);
      });

      test('renders a valid report', () async {
        final bytes = await buildPdfReport(
          withPumps([pump('p1', DateTime(2026, 7, 1, 7), 90)]),
        );
        expect(bytes.lengthInBytes, greaterThan(1000));
        expect(bytes.sublist(0, 4), [0x25, 0x50, 0x44, 0x46]); // %PDF
      });
    });

    test('handles an empty window', () {
      final empty = ExportData(
        baby: Baby(
          id: 'b',
          name: 'Ada',
          birthDate: DateTime(2026, 1, 1),
          ownerUid: 'u',
          members: const {'u': CaregiverRole.owner},
        ),
        start: DateTime(2026, 7, 1),
        end: DateTime(2026, 7, 2),
        feedings: const [],
        diapers: const [],
        growth: const [],
      );
      final s = ReportSummary.from(empty);
      expect(s.daily, isEmpty);
      expect(s.feedsPerDay, 0);
      expect(s.avgFeedIntervalMinutes, isNull);
    });
  });

  group('ascii', () {
    test('folds characters the built-in PDF font cannot draw', () {
      // Helvetica in the pdf package is WinAnsi-only; these would otherwise
      // be silently dropped from the report.
      expect(ascii('a — b'), 'a - b');
      expect(ascii('a – b'), 'a - b');
      expect(ascii('“quoted”'), '"quoted"');
      expect(ascii('it’s'), "it's");
      expect(ascii('plain text'), 'plain text');
    });
  });

  group('buildPdfReport', () {
    test('produces a valid, non-trivial PDF document', () async {
      final bytes = await buildPdfReport(_sample());
      expect(bytes.length, greaterThan(1000));
      // PDF files start with the %PDF- magic header.
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('still renders when there is nothing logged', () async {
      final empty = ExportData(
        baby: Baby(
          id: 'b',
          name: 'Ada',
          birthDate: DateTime(2026, 1, 1),
          ownerUid: 'u',
          members: const {'u': CaregiverRole.owner},
        ),
        start: DateTime(2026, 7, 1),
        end: DateTime(2026, 7, 2),
        feedings: const [],
        diapers: const [],
        growth: const [],
      );
      final bytes = await buildPdfReport(empty);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });
  });

  group('units', () {
    // The daily table drops a column in metric, so the header and body rows
    // have to agree — a mismatch throws inside the pdf table builder.
    for (final units in UnitSystem.values) {
      test('renders a valid report in ${units.name}', () async {
        final bytes = await buildPdfReport(_sample(units: units));
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
        expect(bytes.length, greaterThan(1000));
      });
    }
  });
}
