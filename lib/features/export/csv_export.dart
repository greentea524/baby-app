import '../../core/format/volume_format.dart';
import '../growth/growth_units.dart';
import 'export_data.dart';

/// Builds a flat CSV of every logged record (KAN-164), one row per entry
/// across feeding, diaper, and growth, sorted by time. A single sheet with a
/// Type column is the most useful thing to hand a pediatrician or open in
/// a spreadsheet.
String buildCsv(ExportData data) {
  final units = data.units;
  final metric = units.isMetric;
  final headers = [
    'Type',
    'Date',
    'Time',
    'Subtype',
    'Snack',
    'Duration (min)',
    'Amount (ml)',
    if (!metric) 'Amount (fl oz)',
    'Side',
    metric ? 'Weight (kg)' : 'Weight (lb oz)',
    metric ? 'Height (cm)' : 'Height (in)',
    metric ? 'Head (cm)' : 'Head (in)',
    'Notes',
  ];

  final rows = <({DateTime at, List<String> cells})>[
    for (final f in data.feedings)
      (
        at: f.startTime,
        cells: [
          'Feeding',
          _date(f.startTime),
          _time(f.startTime),
          f.type.name,
          // Blank rather than "no", so filtering on "yes" is one click and the
          // column stays quiet on the many rows it does not apply to.
          f.isSnack ? 'yes' : '',
          f.durationMinutes?.toString() ?? '',
          _num(f.amountMl),
          if (!metric) f.amountMl == null ? '' : formatFlOz(f.amountMl!),
          f.side?.name ?? '',
          '',
          '',
          '',
          f.notes ?? '',
        ],
      ),
    for (final d in data.diapers)
      (
        at: d.time,
        cells: [
          'Diaper',
          _date(d.time),
          _time(d.time),
          d.type.name,
          '',
          '',
          '',
          if (!metric) '',
          '',
          '',
          '',
          '',
          d.notes ?? '',
        ],
      ),
    for (final g in data.growth)
      (
        at: g.date,
        cells: [
          'Growth',
          _date(g.date),
          '',
          '',
          '',
          '',
          '',
          if (!metric) '',
          '',
          g.weightKg == null ? '' : formatWeight(g.weightKg!, units),
          g.heightCm == null ? '' : formatLength(g.heightCm!, units),
          g.headCm == null ? '' : formatLength(g.headCm!, units),
          '',
        ],
      ),
  ]..sort((a, b) => a.at.compareTo(b.at));

  final buffer = StringBuffer()..writeln(headers.map(escapeCsv).join(','));
  for (final row in rows) {
    buffer.writeln(row.cells.map(escapeCsv).join(','));
  }
  return buffer.toString();
}

/// Quotes a CSV field when it contains a comma, quote, or newline, doubling
/// any embedded quotes (RFC 4180).
String escapeCsv(String value) {
  if (!value.contains(RegExp('[",\n\r]'))) return value;
  return '"${value.replaceAll('"', '""')}"';
}

String _date(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

String _time(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

String _num(double? v) {
  if (v == null) return '';
  return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
}

/// Suggested filename, e.g. `Ada-log-2026-07-01-to-2026-07-24.csv`.
String csvFilename(ExportData data) {
  final safeName = data.baby.name.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  return '$safeName-log-${_date(data.start)}-to-${_date(data.end)}';
}
