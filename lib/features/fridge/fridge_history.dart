import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/unit_system.dart';
import '../../core/format/volume_format.dart';
import '../../data/models/fridge_log_entry.dart';
import '../../data/models/pumping_event.dart';
import '../../data/repositories/repository_providers.dart';
import '../feeding/feeding_format.dart';
import '../home/home_prefs.dart';
import '../pumping/pumping_format.dart';
import '../timeline/timeline_format.dart';
import 'bottle_sheet.dart';
import 'fridge_order.dart';

/// What happened in the fridge, newest first: bottles added, fed, removed,
/// split, combined and put back, and the week's pump sessions among them.
///
/// Under the shelf on the fridge screen, as slivers of its scroll: what is
/// there and what happened to it, on one page. Not in the activity log. The
/// log is what happened to the baby; this is the shelf's own bookkeeping.
///
/// A removed bottle can be put back from here, as it was: the answer to a
/// tap on the wrong bottle, without a confirmation every time one is taken
/// out. Nothing at all while there is nothing to say.
class FridgeHistory extends ConsumerWidget {
  const FridgeHistory({super.key, this.now});

  /// A fixed clock, for tests.
  final DateTime? now;

  /// How far back pump sessions are shown: a week, a little more than the
  /// longest anything keeps in a fridge.
  static const pumpDays = 7;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final clock = now ?? DateTime.now();
    final log = ref.watch(fridgeLogProvider);
    final shelfBottles = ref.watch(fridgeShelfProvider);
    final shelf = {for (final b in shelfBottles) b.id};
    // Only for a household that pumps, as on Home.
    final recentPumps = ref.watch(showPumpingActionProvider)
        ? ref.watch(recentPumpingProvider).value ?? const <PumpingEvent>[]
        : const <PumpingEvent>[];
    final pumps = [
      for (final p in recentPumps)
        if (clock.difference(p.time) < const Duration(days: pumpDays)) p,
    ];

    // Loading or failed, there is nothing to say yet, and the shelf above
    // is the page's point either way.
    final entries = log.value ?? const <FridgeLogEntry>[];
    if (entries.isEmpty && pumps.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
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

    // A session is in a bottle once one says so, now or ever — or,
    // for bottles from before they said, once one was filled in its
    // window.
    final linked = {
      for (final b in shelfBottles) ?b.pumpId,
      for (final e in entries) ?e.pumpId,
    };
    final byId = {for (final p in recentPumps) p.id: p};
    bool bottled(PumpingEvent p, DateTime? next) =>
        linked.contains(p.id) ||
        isBottled(p.time, shelfBottles, nextPumpAt: next);

    // The two lists, newest first, as one.
    final items = <({DateTime at, Object item})>[
      for (final e in entries) (at: e.at, item: e),
      for (final p in pumps) (at: p.time, item: p),
    ]..sort((a, b) => b.at.compareTo(a.at));

    final rows = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Text('History', style: theme.textTheme.titleMedium),
      ),
    ];
    DateTime? day;
    for (final it in items) {
      final d = DateTime(it.at.year, it.at.month, it.at.day);
      if (d != day) {
        day = d;
        rows.add(_DayHeader(day: d, now: clock));
      }
      switch (it.item) {
        case final FridgeLogEntry e:
          rows.add(
            _EntryTile(
              entry: e,
              now: clock,
              from: byId[e.pumpId],
              onPutBack: canPutBack.contains(e.id)
                  ? () => _putBack(context, ref, e)
                  : null,
            ),
          );
        case final PumpingEvent p:
          // The next session along, newest first being the order.
          final i = recentPumps.indexOf(p);
          final next = i > 0 ? recentPumps[i - 1].time : null;
          final inBottle = bottled(p, next);
          final canAdd =
              (p.amountMl ?? 0) > 0 &&
              clock.difference(p.time) < const Duration(days: 3) &&
              !inBottle;
          rows.add(
            _PumpTile(
              session: p,
              inBottle: inBottle,
              onAdd: canAdd
                  ? () => showBottleSheet(
                      context,
                      prefillFrom: p,
                      pumps: linkablePumps(recentPumps, clock),
                    )
                  : null,
            ),
          );
      }
    }
    return SliverList(delegate: SliverChildListDelegate(rows));
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
  const _EntryTile({
    required this.entry,
    required this.now,
    this.from,
    this.onPutBack,
  });

  final FridgeLogEntry entry;
  final DateTime now;

  /// The pump session the bottle is from, when it says and it is recent.
  final PumpingEvent? from;

  /// Puts a removed bottle back. Null where it cannot come back: it is on
  /// the shelf again, or something has happened to it since.
  final VoidCallback? onPutBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final units = ref.watch(unitSystemProvider);
    String vol(double ml) => formatVolume(ml, units);
    final e = entry;
    final milk = e.kind.label.toLowerCase();
    // The session, when it is known, says when the milk is from. The
    // bottle's own time too only where it says something else: a bottle
    // put in the fridge just after pumping would say the same time twice.
    final pump = from;
    final sameTime =
        pump != null &&
        e.filledAt.difference(pump.time).abs() <= const Duration(minutes: 30);
    final age = [
      if (!sameTime)
        '${e.kind.filledLabel.toLowerCase()} '
            '${FeedingFormat.clockStamp(context, e.filledAt, now: now)}',
      if (pump != null)
        'from the ${FeedingFormat.clockStamp(context, pump.time, now: now)} '
            'pump',
    ].join(' · ');

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

/// A pump session, among the fridge's goings-on: how much, and whether its
/// milk has gone in a bottle yet — with the way to put it in one if not.
class _PumpTile extends ConsumerWidget {
  const _PumpTile({required this.session, required this.inBottle, this.onAdd});

  final PumpingEvent session;

  /// Whether its milk has gone into a bottle.
  final bool inBottle;

  /// Opens a new bottle from this session. Null once its milk is in a
  /// bottle, or with none to bottle.
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final units = ref.watch(unitSystemProvider);
    final p = session;
    final at = TimeOfDay.fromDateTime(p.time).format(context);
    return ListTile(
      key: ValueKey('fridge-pump-${p.id}'),
      leading: const Icon(PumpingFormat.icon),
      title: Text(
        p.amountMl == null
            ? 'Pumped'
            : 'Pumped ${formatVolume(p.amountMl!, units)}',
      ),
      subtitle: Text(
        [
          if (onAdd != null) at,
          if (p.durationMinutes case final m?) '$m min',
          if (p.side case final side?) FeedingFormat.sideLabel(side),
          if (inBottle) 'In a bottle',
        ].join(' · '),
      ),
      trailing: onAdd != null
          ? TextButton(onPressed: onAdd, child: const Text('Add to fridge'))
          : Text(at, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}
