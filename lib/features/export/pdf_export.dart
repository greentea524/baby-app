import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/format/volume_format.dart';
import '../growth/growth_metric.dart';
import '../growth/growth_units.dart';
import '../timeline/timeline_format.dart';
import 'export_data.dart';
import 'report_summary.dart';

/// Builds a printable summary report to share with a pediatrician
/// (KAN-165): header, overall figures, a per-day table, and growth history.
Future<Uint8List> buildPdfReport(ExportData data) async {
  final summary = ReportSummary.from(data);
  final doc = pw.Document();

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (context) => [
        _header(data),
        pw.SizedBox(height: 16),
        _overview(summary),
        pw.SizedBox(height: 20),
        if (summary.daily.isNotEmpty) ...[
          _sectionTitle('Daily breakdown'),
          pw.SizedBox(height: 6),
          _dailyTable(summary),
          pw.SizedBox(height: 20),
        ],
        if (data.growth.isNotEmpty) ...[
          _sectionTitle('Growth measurements'),
          pw.SizedBox(height: 6),
          _growthTable(data),
        ],
        if (data.isEmpty)
          pw.Text(ascii('No entries were logged in this period.')),
      ],
    ),
  );

  return doc.save();
}

pw.Widget _header(ExportData data) {
  final sex = data.baby.sex?.name;
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        ascii('${data.baby.name} - activity summary'),
        style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 4),
      pw.Text(
        ascii(
          'Born ${_date(data.baby.birthDate)}'
          '${sex == null ? '' : ' ($sex)'}',
        ),
      ),
      pw.Text('Period ${_date(data.start)} to ${_date(data.endInclusive)}'),
      pw.Text(
        'Generated ${_date(DateTime.now())}',
        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
      ),
    ],
  );
}

pw.Widget _overview(ReportSummary s) {
  final cells = <List<String>>[
    ['Total feeds', '${s.totalFeeds}'],
    ['Feeds per day (avg)', s.feedsPerDay.toStringAsFixed(1)],
    [
      'Avg interval between feeds',
      TimelineFormat.interval(s.avgFeedIntervalMinutes),
    ],
    [
      'Bottle total',
      '${_num(s.totalBottleMl)} ml (${formatFlOz(s.totalBottleMl)} fl oz)',
    ],
    ['Breastfeeding total', '${s.totalBreastMinutes} min'],
    ['Total diaper changes', '${s.totalDiapers}'],
    ['Days with activity', '${s.daily.length}'],
  ];
  return pw.Table(
    border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
    columnWidths: const {0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(2)},
    children: [
      for (final row in cells)
        pw.TableRow(children: [_cell(row[0]), _cell(row[1], bold: true)]),
    ],
  );
}

pw.Widget _dailyTable(ReportSummary s) {
  return pw.Table(
    border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
    children: [
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
        children: [
          _cell('Date', bold: true),
          _cell('Feeds', bold: true),
          _cell('Bottle (ml)', bold: true),
          _cell('Bottle (fl oz)', bold: true),
          _cell('Breast (min)', bold: true),
          _cell('Diapers', bold: true),
        ],
      ),
      for (final row in s.daily)
        pw.TableRow(
          children: [
            _cell(_date(row.day)),
            _cell('${row.stats.feedCount}'),
            _cell(_num(row.stats.bottleMl)),
            _cell(
              row.stats.bottleMl == 0 ? '' : formatFlOz(row.stats.bottleMl),
            ),
            _cell('${row.stats.breastMinutes}'),
            _cell('${row.stats.diaperCount}'),
          ],
        ),
    ],
  );
}

pw.Widget _growthTable(ExportData data) {
  return pw.Table(
    border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
    children: [
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
        children: [
          _cell('Date', bold: true),
          _cell('Age (mo)', bold: true),
          _cell('Weight (lb oz)', bold: true),
          _cell('Height (in)', bold: true),
          _cell('Head (in)', bold: true),
        ],
      ),
      for (final m in data.growth)
        pw.TableRow(
          children: [
            _cell(_date(m.date)),
            _cell(ageInMonths(data.baby.birthDate, m.date).toStringAsFixed(1)),
            _cell(m.weightKg == null ? '' : formatLbOz(m.weightKg!)),
            _cell(_inches(m.heightCm)),
            _cell(_inches(m.headCm)),
          ],
        ),
    ],
  );
}

pw.Widget _sectionTitle(String text) => pw.Text(
  ascii(text),
  style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
);

pw.Widget _cell(String text, {bool bold = false}) => pw.Padding(
  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
  child: pw.Text(
    ascii(text),
    style: pw.TextStyle(
      fontSize: 10,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    ),
  ),
);

/// The PDF package's built-in Helvetica only covers WinAnsi, so typographic
/// dashes and similar would silently drop out of the report. Fold them to
/// ASCII equivalents before drawing.
String ascii(String text) => text
    .replaceAll('—', '-') // em dash
    .replaceAll('–', '-') // en dash
    .replaceAll('•', '-') // bullet
    .replaceAll('‘', "'")
    .replaceAll('’', "'")
    .replaceAll('“', '"')
    .replaceAll('”', '"');

String _date(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

String _num(double? v) {
  if (v == null || v == 0) return v == 0 ? '0' : '';
  return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}

/// A stored (cm) length rendered in inches to one decimal, blank if null.
String _inches(double? cm) => cm == null ? '' : cmToIn(cm).toStringAsFixed(1);

extension on ExportData {
  /// The last day actually covered (end is exclusive).
  DateTime get endInclusive => end.subtract(const Duration(days: 1));
}
