import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_providers.dart';
import '../../core/theme/theme_mode_provider.dart';
import '../../data/models/daily_check.dart';
import '../../data/repositories/repository_providers.dart';
import '../common/app_sheet.dart';
import '../feeding/feeding_format.dart';
import 'checklist_logic.dart';

const _timersKey = 'checklist_timers';

/// The timers running for timed checklist items on this phone: when each
/// was started, by `babyId/itemId`.
///
/// Kept in this phone's storage rather than only in memory, so a timer
/// survives the sheet closing, the phone locking, and the app being shut —
/// tummy time goes on whatever the screen is doing. Not shared with the
/// other caregiver's phone: the session is saved for everyone when it is
/// stopped.
final checklistTimersProvider =
    NotifierProvider<ChecklistTimersNotifier, Map<String, DateTime>>(
      ChecklistTimersNotifier.new,
    );

class ChecklistTimersNotifier extends Notifier<Map<String, DateTime>> {
  @override
  Map<String, DateTime> build() {
    final raw = ref.read(sharedPreferencesProvider).getString(_timersKey);
    if (raw == null) return const {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final e in map.entries)
          e.key: DateTime.fromMillisecondsSinceEpoch(e.value as int),
      };
    } catch (_) {
      return const {};
    }
  }

  static String key(String babyId, String itemId) => '$babyId/$itemId';

  void start(String key, DateTime at) => _write({...state, key: at});

  void stop(String key) => _write({...state}..remove(key));

  void _write(Map<String, DateTime> next) {
    state = next;
    unawaited(
      ref
          .read(sharedPreferencesProvider)
          .setString(
            _timersKey,
            jsonEncode({
              for (final e in next.entries)
                e.key: e.value.millisecondsSinceEpoch,
            }),
          ),
    );
  }
}

/// When [item]'s timer was started on this phone, or null when it is not
/// running.
DateTime? watchTimerStart(WidgetRef ref, ChecklistItem item) {
  final baby = ref.watch(currentBabyProvider);
  if (baby == null) return null;
  return ref.watch(checklistTimersProvider)[ChecklistTimersNotifier.key(
    baby.id,
    item.id,
  )];
}

/// Minutes a timer run of [elapsed] counts for: to the nearest minute, at
/// least one, at most [ChecklistItem.maxMinutes]. Null for a run too short
/// to have been a session — a start tapped by mistake.
int? sessionMinutes(Duration elapsed) {
  if (elapsed < const Duration(seconds: 20)) return null;
  final m = (elapsed.inSeconds / 60).round();
  return m.clamp(1, ChecklistItem.maxMinutes);
}

/// "4:05", "1:02:30": a running timer.
String timerLabel(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(h > 0 ? 2 : 1, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

/// "25 min", "1 hr 10 min".
String minutesLabel(int minutes) {
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '$h hr' : '$h hr $m min';
}

/// The minutes a session can be added as, after the fact.
const quickMinutes = [5, 10, 15];

/// Opens the sheet for a timed item: how far today has got, the timer, and
/// minutes to add by hand.
Future<void> showTimedItemSheet(
  BuildContext context, {
  required ChecklistItem item,
  DateTime Function()? clock,
}) => showAppSheet<void>(
  context,
  builder: (_) => TimedItemSheet(item: item, clock: clock ?? DateTime.now),
);

/// A timed item's day: minutes so far against the goal, a timer to start
/// and stop, minutes to add for a session that was not timed, and each
/// session so far with the way to take the last one back.
class TimedItemSheet extends ConsumerStatefulWidget {
  const TimedItemSheet({super.key, required this.item, required this.clock});

  final ChecklistItem item;

  /// The time now. A function rather than a value, since the timer reads
  /// it every second.
  final DateTime Function() clock;

  @override
  ConsumerState<TimedItemSheet> createState() => _TimedItemSheetState();
}

class _TimedItemSheetState extends ConsumerState<TimedItemSheet> {
  Timer? _ticker;

  ChecklistItem get item => widget.item;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// Ticks once a second while a timer runs, so the display keeps up.
  void _tick(bool running) {
    if (running && _ticker == null) {
      _ticker = Timer.periodic(
        const Duration(seconds: 1),
        (_) => setState(() {}),
      );
    } else if (!running && _ticker != null) {
      _ticker!.cancel();
      _ticker = null;
    }
  }

  String? _myName() {
    final user = ref.read(authStateProvider).value;
    final name = user?.displayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return user?.email?.split('@').first;
  }

  /// Saves a session of [minutes] at [at], without waiting on the write.
  void _save(int minutes, DateTime at) {
    final repo = ref.read(checksRepositoryProvider);
    if (repo == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      unawaited(
        repo
            .addNow(
              DailyCheck(
                id: '',
                itemId: item.id,
                time: at,
                label: item.label,
                minutes: minutes,
                byName: _myName(),
              ),
            )
            .written
            .catchError((Object e) {
              messenger.showSnackBar(
                SnackBar(content: Text('Could not save ${item.label}: $e')),
              );
            }),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not save ${item.label}: $e')),
      );
    }
  }

  void _start(String key) =>
      ref.read(checklistTimersProvider.notifier).start(key, widget.clock());

  void _stop(String key, DateTime started) {
    ref.read(checklistTimersProvider.notifier).stop(key);
    final minutes = sessionMinutes(widget.clock().difference(started));
    if (minutes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Too short to count — not saved')),
      );
      return;
    }
    // Dated from when it started, so it sits in the day where it happened.
    _save(minutes, started);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final baby = ref.watch(currentBabyProvider);
    final now = widget.clock();
    final today = dayOf(now);
    final checks = ref.watch(checksSinceProvider(today)).value ?? const [];
    final sessions = ticksOf(checks, item.id, today)
      ..sort((a, b) => a.time.compareTo(b.time));
    final done = sessions.fold<int>(0, (sum, c) => sum + amountOf(item, c));
    final goal = item.goal;
    final me = ref.watch(authStateProvider).value?.uid;

    final key = baby == null
        ? null
        : ChecklistTimersNotifier.key(baby.id, item.id);
    final started = key == null
        ? null
        : ref.watch(checklistTimersProvider)[key];
    _tick(started != null);
    final running = started == null ? null : now.difference(started);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              done >= goal ? Icons.check_circle : checklistIcon(item.icon),
              color: scheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(item.label, style: theme.textTheme.titleLarge),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          done >= goal
              ? '${minutesLabel(done)} today — done'
              : '${minutesLabel(done)} of ${minutesLabel(goal)} today',
          key: const ValueKey('timed-progress'),
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (done / goal).clamp(0.0, 1.0),
            minHeight: 8,
            backgroundColor: scheme.surfaceContainerHighest,
          ),
        ),
        const SizedBox(height: 20),
        // The timer: big enough to read from the floor beside the baby.
        Center(
          child: Text(
            timerLabel(running ?? Duration.zero),
            key: const ValueKey('timer'),
            style: theme.textTheme.displayMedium?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
              color: running == null ? scheme.onSurfaceVariant : null,
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (key != null)
          FilledButton.icon(
            icon: Icon(running == null ? Icons.play_arrow : Icons.stop),
            label: Text(running == null ? 'Start timer' : 'Stop and save'),
            onPressed: () =>
                started == null ? _start(key) : _stop(key, started),
          ),
        if (running != null) ...[
          const SizedBox(height: 4),
          Text(
            'Keeps running if you close this or lock the phone.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          TextButton(
            onPressed: () =>
                ref.read(checklistTimersProvider.notifier).stop(key!),
            child: const Text('Cancel the timer'),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          'Or add a session that was not timed',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in quickMinutes)
              ActionChip(
                key: ValueKey('add-$m'),
                avatar: const Icon(Icons.add),
                label: Text('$m min'),
                onPressed: () {
                  _save(m, widget.clock());
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('$m min of ${item.label} added')),
                  );
                },
              ),
          ],
        ),
        if (sessions.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Today', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          for (final c in sessions)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(
                [
                  FeedingFormat.clockStamp(context, c.time, now: now),
                  minutesLabel(c.minutes ?? 0),
                  if (_by(c, me) case final by?) 'by $by',
                ].join(' · '),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.undo),
            label: const Text('Take the last one back'),
            onPressed: () {
              final repo = ref.read(checksRepositoryProvider);
              if (repo == null) return;
              unawaited(
                Future.sync(
                  () => repo.delete(sessions.last.id),
                ).catchError((_) {}),
              );
            },
          ),
        ],
      ],
    );
  }
}

String? _by(DailyCheck tick, String? me) {
  if (tick.createdBy != null && tick.createdBy == me) return 'you';
  final name = tick.byName?.trim();
  return name == null || name.isEmpty ? null : name;
}
