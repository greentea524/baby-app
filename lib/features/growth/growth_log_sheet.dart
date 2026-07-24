import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/growth_measurement.dart';
import '../../data/repositories/repository_providers.dart';

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
  final _weight = TextEditingController();
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
    if (e?.weightKg != null) _weight.text = _fmt(e!.weightKg!);
    if (e?.heightCm != null) _height.text = _fmt(e!.heightCm!);
    if (e?.headCm != null) _head.text = _fmt(e!.headCm!);
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  void dispose() {
    _weight.dispose();
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
    final w = _parse(_weight);
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
      heightCm: h,
      headCm: hc,
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
            _numberField(_weight, 'Weight', 'kg'),
            const SizedBox(height: 12),
            _numberField(_height, 'Height', 'cm'),
            const SizedBox(height: 12),
            _numberField(_head, 'Head circumference', 'cm'),
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
