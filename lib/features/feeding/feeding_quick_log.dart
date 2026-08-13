import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/feeding_event.dart';
import '../../data/repositories/repository_providers.dart';
import '../../core/format/volume_entry.dart';
import '../common/app_sheet.dart';
import '../common/event_time_row.dart';
import '../common/volume_field.dart';
import 'feeding_format.dart';

/// Opens the feeding quick-log sheet. Pass [existing] to edit an entry
/// (KAN-147); omit it to log a new feed (KAN-143/144/145).
Future<void> showFeedingQuickLog(
  BuildContext context, {
  FeedingEvent? existing,
}) {
  return showAppSheet<void>(
    context,
    builder: (_) => _QuickLogSheet(existing: existing),
  );
}

class _QuickLogSheet extends StatefulWidget {
  const _QuickLogSheet({this.existing});

  final FeedingEvent? existing;

  @override
  State<_QuickLogSheet> createState() => _QuickLogSheetState();
}

class _QuickLogSheetState extends State<_QuickLogSheet> {
  late FeedingType? _mode = widget.existing?.type;

  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;
    return switch (_mode) {
      null => _TypeChooser(onSelected: (t) => setState(() => _mode = t)),
      FeedingType.breast => _BreastForm(existing: existing),
      FeedingType.bottle => _BottleForm(existing: existing),
      FeedingType.solids => _SolidsForm(existing: existing),
    };
  }
}

class _TypeChooser extends StatelessWidget {
  const _TypeChooser({required this.onSelected});

  final ValueChanged<FeedingType> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Log a feed', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        for (final type in FeedingType.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                alignment: Alignment.centerLeft,
              ),
              icon: Icon(FeedingFormat.typeIcon(type)),
              label: Text(FeedingFormat.typeLabel(type)),
              onPressed: () => onSelected(type),
            ),
          ),
      ],
    );
  }
}

/// Shared save button + error handling for the three forms.
class _SaveBar extends ConsumerStatefulWidget {
  const _SaveBar({
    required this.isEdit,
    required this.build,
    this.enabled = true,
  });

  final bool isEdit;

  /// False while the form holds something it must not save — a time ahead of
  /// the clock. The form shows the reason; this only stops the write.
  final bool enabled;

  /// Returns the event to persist, or null if the input is invalid (the
  /// form is responsible for showing its own validation state first).
  final FeedingEvent? Function() build;

  @override
  ConsumerState<_SaveBar> createState() => _SaveBarState();
}

class _SaveBarState extends ConsumerState<_SaveBar> {
  bool _busy = false;

  Future<void> _save() async {
    final event = widget.build();
    if (event == null) return;
    final repo = ref.read(feedingRepositoryProvider);
    if (repo == null) {
      _snack('No baby selected.');
      return;
    }
    setState(() => _busy = true);
    try {
      if (widget.isEdit) {
        await repo.update(event);
      } else {
        await repo.add(event);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) _snack('Could not save: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: _busy || !widget.enabled ? null : _save,
      child: _busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(widget.isEdit ? 'Save changes' : 'Save'),
    );
  }
}

// --- Breastfeeding (KAN-143) ------------------------------------------------

class _BreastForm extends StatefulWidget {
  const _BreastForm({this.existing});

  final FeedingEvent? existing;

  @override
  State<_BreastForm> createState() => _BreastFormState();
}

class _BreastFormState extends State<_BreastForm> {
  BreastSide _side = BreastSide.left;
  DateTime _startTime = DateTime.now();
  Duration _elapsed = Duration.zero;
  bool _isSnack = false;

  Timer? _ticker;
  DateTime? _runningSince;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _side = e.side ?? BreastSide.left;
      _startTime = e.startTime;
      _elapsed = Duration(minutes: e.durationMinutes ?? 0);
      _isSnack = e.isSnack;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  bool get _running => _runningSince != null;

  void _toggleTimer() {
    if (_running) {
      _ticker?.cancel();
      setState(() {
        _elapsed += DateTime.now().difference(_runningSince!);
        _runningSince = null;
      });
    } else {
      // First start also sets the feed's start time.
      if (_elapsed == Duration.zero) _startTime = DateTime.now();
      _runningSince = DateTime.now();
      _ticker = Timer.periodic(
        const Duration(seconds: 1),
        (_) => setState(() {}),
      );
      setState(() {});
    }
  }

  Duration get _displayed => _running
      ? _elapsed + DateTime.now().difference(_runningSince!)
      : _elapsed;

  FeedingEvent? _build() {
    final minutes = _displayed.inMinutes;
    return FeedingEvent(
      id: widget.existing?.id ?? '',
      type: FeedingType.breast,
      startTime: _startTime,
      durationMinutes: minutes,
      side: _side,
      isSnack: _isSnack,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Breastfeeding', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        Center(
          child: Text(
            FeedingFormat.stopwatch(_displayed),
            style: Theme.of(context).textTheme.displaySmall,
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: FilledButton.tonalIcon(
            onPressed: _toggleTimer,
            icon: Icon(_running ? Icons.pause : Icons.play_arrow),
            label: Text(_running ? 'Pause' : 'Start'),
          ),
        ),
        const SizedBox(height: 16),
        SegmentedButton<BreastSide>(
          segments: const [
            ButtonSegment(value: BreastSide.left, label: Text('Left')),
            ButtonSegment(value: BreastSide.right, label: Text('Right')),
            ButtonSegment(value: BreastSide.both, label: Text('Both')),
          ],
          selected: {_side},
          onSelectionChanged: (s) => setState(() => _side = s.first),
        ),
        _SnackToggle(
          value: _isSnack,
          onChanged: (v) => setState(() => _isSnack = v),
        ),
        const SizedBox(height: 16),
        _SaveBar(isEdit: widget.existing != null, build: _build),
      ],
    );
  }
}

// --- Bottle (KAN-144) -------------------------------------------------------

/// Marks a feed as a small top-up rather than a full feed.
///
/// Offered on breast and bottle only — those are the feeds that drive the
/// next-feed reminder. Solids don't currently affect the clock either way.
class _SnackToggle extends StatelessWidget {
  const _SnackToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      contentPadding: EdgeInsets.zero,
      title: const Text('Snack / top-up'),
      subtitle: const Text("Won't reset the next-feed reminder"),
    );
  }
}

class _BottleForm extends ConsumerStatefulWidget {
  const _BottleForm({this.existing});

  final FeedingEvent? existing;

  @override
  ConsumerState<_BottleForm> createState() => _BottleFormState();
}

class _BottleFormState extends ConsumerState<_BottleForm> {
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  late DateTime _time;
  late VolumeUnit _unit;
  String? _amountError;
  bool _isSnack = false;

  /// What was stored, and whether the field has actually been typed in.
  ///
  /// Editing an entry without touching the amount must store the amount
  /// unchanged. Re-parsing the field would round-trip it through the display
  /// unit — 150 ml shown as 5.1 fl oz, saved back as 150.8 — so correcting a
  /// note would quietly rewrite a number nobody touched. It settles there
  /// rather than walking further on each edit, which makes it a wrong value
  /// rather than a runaway one; still not ours to write.
  double? _storedMl;
  bool _amountEdited = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _time = e?.startTime ?? DateTime.now();
    _isSnack = e?.isSnack ?? false;
    _unit = VolumeUnit.initial;
    _storedMl = e?.amountMl;
    if (e?.amountMl != null) {
      _amountController.text = _unit.fieldText(e!.amountMl!);
    }
    if (e?.notes != null) _notesController.text = e!.notes!;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  FeedingEvent? _build() {
    final typed = double.tryParse(_amountController.text.trim());
    if (typed == null || typed <= 0) {
      setState(() => _amountError = 'Enter an amount in ${_unit.label}');
      return null;
    }
    // Only re-derive what was actually retyped; see [_storedMl].
    final millilitres = _amountEdited || _storedMl == null
        ? _unit.toMl(typed)
        : _storedMl!;
    return FeedingEvent(
      id: widget.existing?.id ?? '',
      type: FeedingType.bottle,
      startTime: _time,
      amountMl: millilitres,
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
      isSnack: _isSnack,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Bottle', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        VolumeField(
          controller: _amountController,
          unit: _unit,
          autofocus: widget.existing == null,
          errorText: _amountError,
          onUnitChanged: (unit, text) => setState(() {
            _unit = unit;
            _amountController.text = text;
          }),
          onChanged: (_) {
            _amountEdited = true;
            if (_amountError != null) setState(() => _amountError = null);
          },
        ),
        const SizedBox(height: 12),
        EventTimeRow(time: _time, onChanged: (t) => setState(() => _time = t)),
        const SizedBox(height: 12),
        TextField(
          controller: _notesController,
          decoration: const InputDecoration(
            labelText: 'Notes (optional)',
            border: OutlineInputBorder(),
          ),
        ),
        _SnackToggle(
          value: _isSnack,
          onChanged: (v) => setState(() => _isSnack = v),
        ),
        const SizedBox(height: 16),
        _SaveBar(
          isEdit: widget.existing != null,
          build: _build,
          enabled: !isFutureLogTime(_time),
        ),
      ],
    );
  }
}

// --- Solids (KAN-145) -------------------------------------------------------

class _SolidsForm extends StatefulWidget {
  const _SolidsForm({this.existing});

  final FeedingEvent? existing;

  @override
  State<_SolidsForm> createState() => _SolidsFormState();
}

class _SolidsFormState extends State<_SolidsForm> {
  final _notesController = TextEditingController();
  late DateTime _time;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _time = e?.startTime ?? DateTime.now();
    if (e?.notes != null) _notesController.text = e!.notes!;
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  FeedingEvent? _build() {
    return FeedingEvent(
      id: widget.existing?.id ?? '',
      type: FeedingType.solids,
      startTime: _time,
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Solids', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        TextField(
          controller: _notesController,
          autofocus: widget.existing == null,
          decoration: const InputDecoration(
            labelText: 'Food (e.g. banana, rice cereal)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        EventTimeRow(time: _time, onChanged: (t) => setState(() => _time = t)),
        const SizedBox(height: 16),
        _SaveBar(
          isEdit: widget.existing != null,
          build: _build,
          enabled: !isFutureLogTime(_time),
        ),
      ],
    );
  }
}
