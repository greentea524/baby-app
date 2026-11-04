import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/unit_system.dart';
import '../../core/format/volume_format.dart';
import '../../data/models/fridge_log_entry.dart';
import '../../data/repositories/repository_providers.dart';
import '../feeding/feeding_format.dart';
import '../timeline/timeline_format.dart';

/// What happened in the fridge, newest first: bottles added, fed, removed,
/// split, combined and put back.
///
/// Here only, not in the activity log. The log is what happened to the
/// baby; this is the shelf's own bookkeeping.
///
/// A removed bottle can be put back from here, as it was: the answer to a
/// tap on the wrong bottle, without a confirmation every time one is taken
/// out.
class FridgeHistoryScreen extends ConsumerWidget {
  const FridgeHistoryScreen({super.key, this.now});

  /// A fixed clock, for tests.
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final clock = now ?? DateTime.now();
    final log = ref.watch(fridgeLogProvider);
    final shelf = {for (final b in ref.watch(fridgeShelfProvider)) b.id};

    return Scaffold(
      appBar: AppBar(title: const Text('Fridge history')),
      body: log.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load: $e')),
        data: (entries) {
          if (entries.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Nothing yet. Bottles added to the fridge, fed from it or '
                  'taken out will show here.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            );
          }
          // A removed bottle can come back while it is off the shelf and
          // nothing has happened to it since — its latest entry, newest
          // first being the order they come in.
          final latest = <String>{};
          final canPutBack = <String>{};
          for (final e in entries) {
            if (latest.add(e.bottleId) &&
                e.action == FridgeAction.removed &&
                !shelf.contains(e.bottleId)) {
              canPutBack.add(e.id);
            }
          }

          final rows = <Widget>[];
          DateTime? day;
          for (final e in entries) {
            final d = DateTime(e.at.year, e.at.month, e.at.day);
            if (d != day) {
              day = d;
              rows.add(_DayHeader(day: d, now: clock));
            }
            rows.add(
              _EntryTile(
                entry: e,
                now: clock,
                onPutBack: canPutBack.contains(e.id)
                    ? () => _putBack(context, ref, e)
                    : null,
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: rows,
          );
        },
      ),
    );
  }

  /// Puts [removed] back on the shelf. Not waited on, like every write: the
  /// shelf has it from the local cache at once.
  void _putBack(BuildContext context, WidgetRef ref, FridgeLogEntry removed) {
    final repo = ref.read(fridgeRepositoryProvider);
    if (repo == null) return;
    final messenger = ScaffoldMessenger.of(context);
    unawaited(
      Future.sync(() => repo.restore(removed)).catchError((Object e) {
        messenger.showSnackBar(
          SnackBar(content: Text('Could not put the bottle back: $e')),
        );
      }),
    );
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Back in the fridge')));
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day, required this.now});

  final DateTime day;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = DateTime(now.year, now.month, now.day);
    final label = day == today
        ? 'Today'
        : day == DateTime(today.year, today.month, today.day - 1)
        ? 'Yesterday'
        : TimelineFormat.shortDate(day);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _EntryTile extends ConsumerWidget {
  const _EntryTile({required this.entry, required this.now, this.onPutBack});

  final FridgeLogEntry entry;
  final DateTime now;

  /// Puts a removed bottle back. Null where it cannot come back: it is on
  /// the shelf again, or something has happened to it since.
  final VoidCallback? onPutBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final units = ref.watch(unitSystemProvider);
    String vol(double ml) => formatVolume(ml, units);
    final e = entry;
    final milk = e.kind.label.toLowerCase();
    final age =
        '${e.kind.filledLabel.toLowerCase()} '
        '${FeedingFormat.clockStamp(context, e.filledAt, now: now)}';

    final (icon, title, detail) = switch (e.action) {
      FridgeAction.added => (
        Icons.add_circle_outline,
        'Added ${vol(e.amountMl)} $milk',
        age,
      ),
      FridgeAction.fed => (
        Icons.local_drink_outlined,
        'Fed ${vol(e.amountMl)} $milk',
        age,
      ),
      FridgeAction.removed => (
        Icons.delete_outline,
        'Removed ${vol(e.amountMl)} $milk',
        age,
      ),
      FridgeAction.restored => (
        Icons.restore,
        'Put back ${vol(e.amountMl)} $milk',
        age,
      ),
      FridgeAction.split => (
        Icons.call_split,
        'Split ${vol(e.amountMl)} $milk',
        'Into ${vol(e.amountMl - (e.otherMl ?? 0))} and '
            '${vol(e.otherMl ?? 0)} · $age',
      ),
      FridgeAction.combined => (
        Icons.merge_type,
        (e.otherMl ?? e.amountMl) >= e.amountMl
            ? 'Poured all ${vol(e.amountMl)} $milk'
            : 'Poured ${vol(e.otherMl!)} of ${vol(e.amountMl)} $milk',
        'Into another bottle · $age',
      ),
    };

    final at = TimeOfDay.fromDateTime(e.at).format(context);
    return ListTile(
      key: ValueKey('fridge-log-${e.id}'),
      leading: Icon(icon),
      title: Text(title),
      // The button takes the time's place on the right, so the time moves
      // onto the line under it.
      subtitle: Text(onPutBack != null ? '$at · $detail' : detail),
      trailing: onPutBack != null
          ? TextButton(onPressed: onPutBack, child: const Text('Put back'))
          : Text(at, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}
