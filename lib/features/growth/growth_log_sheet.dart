import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/growth_measurement.dart';
import '../../data/repositories/repository_providers.dart';
import 'growth_units.dart';

/// Opens the growth measurement sheet. Pass [existing] to edit.
Future<void> showGrowthLog(
  BuildContext context, {
  GrowthMeasurement? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: _GrowthSheet(existing: existing),
    ),
  );
}

class _GrowthSheet extends ConsumerStatefulWidget {
  const _GrowthSheet({this.existing});

  final GrowthMeasurement? existing;

  @override
  ConsumerState<_GrowthSheet> createState() => _GrowthSheetState();
}

class _GrowthSheetState extends ConsumerState<_GrowthSheet> {
  final _lb = TextEditingController();
  final _oz = TextEditingController();
  final _height = TextEditingController();
  final _head = TextEditingController();
  late DateTime _date;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _date = e?.date ?? DateTime.now();
    if (e?.weightKg != null) {
      final w = kgToLbOz(e!.weightKg!);
      _lb.text = w.lb.toString();
      if (w.oz != 0) _oz.text = w.oz.toString();
    }
    if (e?.heightCm != null) _height.text = _fmt(cmToIn(e!.heightCm!));
    if (e?.headCm != null) _head.text = _fmt(cmToIn(e!.headCm!));
  }

  /// Formats a number for an editable field: one decimal place, trailing
  /// ".0" stripped.
  static String _fmt(double v) {
    final r = (v * 10).round() / 10;
    return r == r.roundToDouble() ? r.toStringAsFixed(0) : r.toString();
  }

  @override
  void dispose() {
    _lb.dispose();
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

  Future<void> _save() async {
    final lb = _parse(_lb);
    final oz = _parse(_oz);
    final w = (lb == null && oz == null)
        ? null
        : lbOzToKg(lb?.toInt() ?? 0, oz ?? 0);
    final h = _parse(_height);
    final hc = _parse(_head);
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
      heightCm: h == null ? null : inToCm(h),
      headCm: hc == null ? null : inToCm(hc),
    );
    setState(() => _busy = true);
    try {
      if (widget.existing != null) {
        await repo.update(m);
      } else {
        await repo.add(m);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not save: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
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
                Expanded(
                  child: Text('${_date.month}/${_date.day}/${_date.year}'),
                ),
                TextButton(onPressed: _pickDate, child: const Text('Change')),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _numberField(_lb, 'Weight', 'lb')),
                const SizedBox(width: 12),
                Expanded(child: _numberField(_oz, 'Ounces', 'oz')),
              ],
            ),
            const SizedBox(height: 12),
            _numberField(_height, 'Height', 'in'),
            const SizedBox(height: 12),
            _numberField(_head, 'Head circumference', 'in'),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(isEdit ? 'Save changes' : 'Save'),
            ),
          ],
        ),
      ),
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
