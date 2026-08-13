import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/unit_system.dart';
import '../../data/models/growth_measurement.dart';
import '../../data/repositories/repository_providers.dart';
import '../common/app_sheet.dart';
import '../common/save_and_close.dart';
import 'growth_units.dart';

/// Opens the growth measurement sheet. Pass [existing] to edit.
Future<void> showGrowthLog(
  BuildContext context, {
  GrowthMeasurement? existing,
}) {
  return showAppSheet<void>(
    context,
    builder: (_) => _GrowthSheet(existing: existing),
  );
}

class _GrowthSheet extends ConsumerStatefulWidget {
  const _GrowthSheet({this.existing});

  final GrowthMeasurement? existing;

  @override
  ConsumerState<_GrowthSheet> createState() => _GrowthSheetState();
}

class _GrowthSheetState extends ConsumerState<_GrowthSheet> {
  /// In metric this holds kilograms; in US it holds whole pounds and [_oz]
  /// carries the remainder.
  final _weight = TextEditingController();
  final _oz = TextEditingController();
  final _height = TextEditingController();
  final _head = TextEditingController();

  /// Captured in initState so the fields can't be reinterpreted mid-edit if
  /// the setting changes in another tab.
  late final UnitSystem _units;
  late DateTime _date;
  String? _error;

  /// Guards against a second tap landing while the sheet is closing. There
  /// is no spinner any more — the sheet goes immediately (#21) — so this is
  /// all that stands between an impatient double-tap and two records.
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _units = ref.read(unitSystemProvider);
    final e = widget.existing;
    _date = e?.date ?? DateTime.now();
    if (e?.weightKg != null) {
      if (_units.isMetric) {
        _weight.text = _fmt(e!.weightKg!);
      } else {
        final w = kgToLbOz(e!.weightKg!);
        _weight.text = w.lb.toString();
        if (w.oz != 0) _oz.text = w.oz.toString();
      }
    }
    if (e?.heightCm != null) {
      _height.text = _fmt(
        _units.isMetric ? e!.heightCm! : cmToIn(e!.heightCm!),
      );
    }
    if (e?.headCm != null) {
      _head.text = _fmt(_units.isMetric ? e!.headCm! : cmToIn(e!.headCm!));
    }
  }

  /// Formats a number for an editable field: one decimal place, trailing
  /// ".0" stripped.
  static String _fmt(double v) {
    final r = (v * 10).round() / 10;
    return r == r.roundToDouble() ? r.toStringAsFixed(0) : r.toString();
  }

  @override
  void dispose() {
    _weight.dispose();
    _oz.dispose();
    _height.dispose();
    _head.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2015),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = picked);
  }

  double? _parse(TextEditingController c) {
    final t = c.text.trim();
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  String get _lengthUnit => _units.isMetric ? 'cm' : 'in';

  /// A typed length in the caregiver's units, as centimetres for storage.
  double? _toCm(double? entered) {
    if (entered == null) return null;
    return _units.isMetric ? entered : inToCm(entered);
  }

  void _save() {
    if (_saving) return;
    // Whatever was typed, what gets stored is always kg and cm.
    final weight = _parse(_weight);
    final oz = _parse(_oz);
    final double? w;
    if (_units.isMetric) {
      w = weight;
    } else {
      w = (weight == null && oz == null)
          ? null
          : lbOzToKg(weight?.toInt() ?? 0, oz ?? 0);
    }
    final h = _toCm(_parse(_height));
    final hc = _toCm(_parse(_head));
    if (w == null && h == null && hc == null) {
      setState(() => _error = 'Enter at least one measurement.');
      return;
    }
    final repo = ref.read(growthRepositoryProvider);
    if (repo == null) {
      setState(() => _error = 'No baby selected.');
      return;
    }
    final m = GrowthMeasurement(
      id: widget.existing?.id ?? '',
      date: _date,
      weightKg: w,
      heightCm: h,
      headCm: hc,
    );
    _saving = true;
    saveAndClose(
      context,
      () => widget.existing != null ? repo.update(m) : repo.add(m),
      failure: 'Could not save the measurement',
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          isEdit ? 'Edit measurement' : 'Log measurement',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Icon(Icons.event, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text('${_date.month}/${_date.day}/${_date.year}')),
            TextButton(onPressed: _pickDate, child: const Text('Change')),
          ],
        ),
        const SizedBox(height: 8),
        // Metric weighs in a single decimal field; US splits into whole
        // pounds plus ounces, which is how scales and paediatricians
        // report it.
        if (_units.isMetric)
          _numberField(_weight, 'Weight', 'kg')
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _numberField(_weight, 'Weight', 'lb')),
              const SizedBox(width: 12),
              Expanded(child: _numberField(_oz, 'Ounces', 'oz')),
            ],
          ),
        const SizedBox(height: 12),
        _numberField(_height, 'Height', _lengthUnit),
        const SizedBox(height: 12),
        _numberField(_head, 'Head circumference', _lengthUnit),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _save,
          child: Text(isEdit ? 'Save changes' : 'Save'),
        ),
      ],
    );
  }

  Widget _numberField(TextEditingController c, String label, String unit) {
    return TextField(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        suffixText: unit,
        border: const OutlineInputBorder(),
      ),
      onChanged: (_) {
        if (_error != null) setState(() => _error = null);
      },
    );
  }
}
