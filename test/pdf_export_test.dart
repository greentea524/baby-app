import 'package:baby_app/data/models/baby.dart';
import 'package:baby_app/data/models/diaper_event.dart';
import 'package:baby_app/data/models/feeding_event.dart';
import 'package:baby_app/data/models/growth_measurement.dart';
import 'package:baby_app/features/export/export_data.dart';
import 'package:baby_app/features/export/pdf_export.dart';
import 'package:baby_app/features/export/report_summary.dart';
import 'package:flutter_test/flutter_test.dart';

ExportData _sample() => ExportData(
  baby: Baby(
    id: 'b',
    name: 'Ada',
    birthDate: DateTime(2026, 1, 1),
    sex: BabySex.female,
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

    test('handles an empty window', () {
      final empty = ExportData(
        baby: Baby(id: 'b', name: 'Ada', birthDate: DateTime(2026, 1, 1)),
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
        baby: Baby(id: 'b', name: 'Ada', birthDate: DateTime(2026, 1, 1)),
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
}
