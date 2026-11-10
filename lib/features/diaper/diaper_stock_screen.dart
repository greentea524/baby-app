import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../data/models/diaper_stock_entry.dart';
import '../../data/repositories/repository_providers.dart';
import '../common/app_sheet.dart';
import '../common/number_input.dart';
import '../common/save_and_close.dart';
import '../feeding/feeding_format.dart';
import '../home/home_status_card.dart' show dueColors;
import '../reminders/feed_prediction.dart' show DueState;
import 'diaper_stock.dart';

/// How many diapers are left, and the packs and counts behind it.
///
/// The count goes down by itself as changes are logged; this is where packs
/// are added, the pile is counted when the sums need putting right, and how
/// low counts as running low is set.
class DiaperStockScreen extends ConsumerWidget {
  const DiaperStockScreen({super.key, this.now});

  /// A fixed clock, for tests.
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clock = now ?? DateTime.now();
    final stock = ref.watch(diaperStockProvider);
    final entries = ref.watch(diaperStockEntriesProvider).value ?? const [];

    return Scaffold(
      appBar: AppBar(title: const Text('Diaper stock')),
      body: stock == null
          ? const _NothingYet()
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                _Summary(stock: stock, now: clock),
                const SizedBox(height: 16),
                const _Actions(),
                const SizedBox(height: 8),
                const _LowAt(),
                const Divider(height: 32),
                Text('History', style: Theme.of(context).textTheme.titleMedium),
                for (final e in entries) _EntryTile(entry: e, now: clock),
              ],
            ),
    );
  }
}

/// Before anything is recorded: what this does, and the two ways to start.
class _NothingYet extends StatelessWidget {
  const _NothingYet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              DiaperStockBadge.icon,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'No diapers counted yet',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Count what you have, or add a pack. Every change you log '
              'then comes off it, so you can see when it is time for more.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            const _Actions(),
          ],
        ),
      ),
    );
  }
}

/// How many are left, how long that lasts, and what it is counted from.
class _Summary extends StatelessWidget {
  const _Summary({required this.stock, required this.now});

  final DiaperStock stock;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final left = stock.left < 0 ? 0 : stock.left;
    final warning = switch (stock.level) {
      StockLevel.out => dueColors(context, DueState.overdue),
      StockLevel.low => dueColors(context, DueState.soon),
      StockLevel.ok => null,
    };
    final days = stock.daysLeft;
    final pace = stock.perDay;

    return Card(
      margin: EdgeInsets.zero,
      color: warning?.background,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '$left',
                  key: const ValueKey('stock-left'),
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: warning?.foreground,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    left == 1 ? 'diaper left' : 'diapers left',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: warning?.foreground,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              switch (stock.level) {
                StockLevel.out => 'Out: time for a new pack',
                StockLevel.low => [
                  'Running low',
                  if (days != null) 'about ${_days(days)} left',
                ].join(' · '),
                StockLevel.ok =>
                  days == null
                      ? 'Plenty for now'
                      : 'About ${_days(days)} at '
                            '${pace!.round()} a day',
              },
              style: theme.textTheme.bodyLarge?.copyWith(
                color: warning?.foreground,
                fontWeight: warning == null ? null : FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Counted from ${FeedingFormat.clockStamp(context, stock.since, now: now)}'
              ' · ${stock.used} used since',
              style: theme.textTheme.bodySmall?.copyWith(
                color: warning?.foreground ?? scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _days(int n) => n == 1 ? '1 day' : '$n days';
}

/// Add a pack; count the pile.
class _Actions extends StatelessWidget {
  const _Actions();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        FilledButton.icon(
          onPressed: () => showStockSheet(context, StockAction.added),
          icon: const Icon(Icons.add),
          label: const Text('Add a pack'),
        ),
        OutlinedButton.icon(
          onPressed: () => showStockSheet(context, StockAction.counted),
          icon: const Icon(Icons.fact_check_outlined),
          label: const Text('Count them'),
        ),
      ],
    );
  }
}

/// How low counts as running low, in fives.
class _LowAt extends ConsumerWidget {
  const _LowAt();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lowAt = ref.watch(diaperLowAtProvider);
    final notifier = ref.read(diaperLowAtProvider.notifier);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Running low at'),
      subtitle: const Text('Home turns amber at this many'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Fewer',
            onPressed: lowAt <= 0 ? null : () => notifier.set(lowAt - 5),
            icon: const Icon(Icons.remove),
          ),
          Text(
            '$lowAt',
            key: const ValueKey('low-at'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          IconButton(
            tooltip: 'More',
            onPressed: () => notifier.set(lowAt + 5),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}

/// A pack added or a count made, with the way to take it back.
class _EntryTile extends ConsumerWidget {
  const _EntryTile({required this.entry, required this.now});

  final DiaperStockEntry entry;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = entry;
    final notes = e.notes?.trim() ?? '';
    return ListTile(
      key: ValueKey('stock-${e.id}'),
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        e.action == StockAction.added
            ? Icons.add_box_outlined
            : Icons.fact_check_outlined,
      ),
      title: Text(
        e.action == StockAction.added
            ? 'Added ${e.count}'
            : 'Counted ${e.count}',
      ),
      subtitle: Text(
        [
          FeedingFormat.clockStamp(context, e.at, now: now),
          if (notes.isNotEmpty) notes,
        ].join(' · '),
      ),
      trailing: IconButton(
        tooltip: 'Delete',
        icon: const Icon(Icons.delete_outline),
        onPressed: () => _delete(context, ref),
      ),
    );
  }

  /// Takes the line away, with an undo: a pack added twice by mistake is
  /// the usual reason, and a wrong tap should not cost the history.
  void _delete(BuildContext context, WidgetRef ref) {
    final repo = ref.read(diaperStockRepositoryProvider);
    if (repo == null) return;
    final messenger = ScaffoldMessenger.of(context);
    unawaited(
      Future.sync(() => repo.delete(entry.id)).catchError((Object e) {
        messenger.showSnackBar(SnackBar(content: Text('Could not delete: $e')));
      }),
    );
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Deleted'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => unawaited(repo.add(entry)),
          ),
        ),
      );
  }
}

/// Adds a pack, or records a count.
Future<void> showStockSheet(BuildContext context, StockAction action) =>
    showAppSheet<void>(context, builder: (_) => _StockSheet(action: action));

class _StockSheet extends ConsumerStatefulWidget {
  const _StockSheet({required this.action});

  final StockAction action;

  @override
  ConsumerState<_StockSheet> createState() => _StockSheetState();
}

class _StockSheetState extends ConsumerState<_StockSheet> {
  final _count = TextEditingController();
  final _notes = TextEditingController();
  bool _saving = false;

  /// Common pack sizes, one tap each.
  static const packs = [20, 30, 40, 50, 100];

  bool get _adding => widget.action == StockAction.added;

  int? get _value => int.tryParse(_count.text.trim());

  @override
  void dispose() {
    _count.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _save() {
    final n = _value;
    final repo = ref.read(diaperStockRepositoryProvider);
    if (_saving || repo == null || n == null) return;
    if (_adding ? n <= 0 : n < 0) return;
    _saving = true;
    final notes = _notes.text.trim();
    saveAndClose(
      context,
      () => repo.add(
        DiaperStockEntry(
          id: '',
          action: widget.action,
          at: DateTime.now(),
          count: n,
          notes: notes.isEmpty ? null : notes,
        ),
      ),
      failure: _adding ? 'Could not add the pack' : 'Could not save the count',
    );
  }

  @override
  Widget build(BuildContext context) {
    final n = _value;
    final valid = n != null && (_adding ? n > 0 : n >= 0) && n <= 10000;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _adding ? 'Add a pack' : 'Count them',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (!_adding) ...[
          const SizedBox(height: 4),
          Text(
            'How many are there now? Changes logged from here on come off '
            'this.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
        const SizedBox(height: 16),
        TextField(
          controller: _count,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: wholeNumberInput,
          decoration: InputDecoration(
            labelText: _adding ? 'How many in it' : 'How many there are',
            border: const OutlineInputBorder(),
            suffixText: 'diapers',
          ),
          onChanged: (_) => setState(() {}),
        ),
        if (_adding) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final p in packs)
                ActionChip(
                  label: Text('$p'),
                  onPressed: () => setState(() => _count.text = '$p'),
                ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _notes,
          decoration: const InputDecoration(
            labelText: 'Notes (optional)',
            hintText: 'Size 2',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: valid ? _save : null,
          child: Text(_adding ? 'Add' : 'Save count'),
        ),
      ],
    );
  }
}

/// "42 left", on Home's diaper row: how many diapers are left, amber when
/// running low and red when out, and the way into the stock. "Stock" before
/// anything has been counted.
class DiaperStockBadge extends ConsumerWidget {
  const DiaperStockBadge({super.key});

  static const icon = Icons.inventory_2_outlined;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stock = ref.watch(diaperStockProvider);
    final theme = Theme.of(context);
    final colours = switch (stock?.level) {
      StockLevel.out => dueColors(context, DueState.overdue),
      StockLevel.low => dueColors(context, DueState.soon),
      _ => null,
    };
    final background =
        colours?.background ?? theme.colorScheme.secondaryContainer;
    final foreground =
        colours?.foreground ?? theme.colorScheme.onSecondaryContainer;
    final label = switch (stock) {
      null => 'Stock',
      final s when s.left <= 0 => 'None left',
      final s => '${s.left} left',
    };

    return Semantics(
      button: true,
      label: stock == null ? 'Diaper stock' : 'Diaper stock: $label',
      excludeSemantics: true,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          key: const ValueKey('diaper-stock'),
          borderRadius: BorderRadius.circular(14),
          onTap: () => context.push(AppRoutes.diaperStock),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: foreground),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
