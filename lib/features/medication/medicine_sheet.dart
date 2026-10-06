import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_providers.dart';
import '../../data/models/medication_event.dart';
import '../../data/repositories/repository_providers.dart';
import '../common/app_sheet.dart';
import '../common/banded_track.dart';
import '../feeding/feeding_format.dart';
import '../home/home_prefs.dart';
import '../home/home_status_card.dart';
import '../reminders/feed_prediction.dart';
import 'med_spacing.dart';
import 'medication_format.dart';
import 'medication_quick_log.dart';

/// Opens the medicine summary: each medicine given lately, its last dose,
/// and how long until the next is allowed.
///
/// For nursery mode, which has no medicine card of its own. Pass [now] to
/// fix the clock, for tests.
Future<void> showMedicineSheet(BuildContext context, {DateTime? now}) {
  return showAppSheet<void>(
    context,
    builder: (_) => MedicineSheet(
      now: now,
      // From the caller's context, which outlives this sheet: the log sheet
      // opens as this one closes.
      onLog: () => showMedicationQuickLog(context),
    ),
  );
}

/// The medicines in [doses], each as its latest dose, most recently given
/// first.
List<MedicationEvent> latestPerMedicine(List<MedicationEvent> doses) =>
    recentMedicines(doses, limit: doses.length);

/// Every medicine given lately, one line each.
///
/// The question at the cot is "can I give this yet?", asked of one medicine
/// at a time, so it is laid out by medicine rather than as a list of doses:
/// what was given and when, who gave it, how many in the last day, and the
/// countdown while the wait set on it is still running.
class MedicineSheet extends ConsumerWidget {
  const MedicineSheet({super.key, this.now, this.onLog});

  final DateTime? now;

  /// Opens the log sheet. Null hides the button.
  final VoidCallback? onLog;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final clock = now ?? DateTime.now();
    final doses = ref.watch(recentMedsProvider).value ?? const [];
    final me = ref.watch(authStateProvider).value?.uid;
    final medicines = latestPerMedicine(doses);
    final waits = {
      for (final w in activeWaits(doses, clock)) medicineKey(w.last.name): w,
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Medicine', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        if (medicines.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'No medicine logged yet.',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        for (final (i, last) in medicines.indexed) ...[
          if (i > 0) const Divider(height: 1),
          _MedicineEntry(
            last: last,
            now: clock,
            by: MedicationFormat.givenBy(last, me),
            inLastDay: dosesInLast24h(doses, last.name, clock),
            wait: waits[medicineKey(last.name)],
          ),
        ],
        const SizedBox(height: 8),
        // Said once, plainly, as on the log sheet: this is a record, not
        // advice — a wait running out is not a prompt to give another.
        Text(
          'A record of what was given. Follow the label or your doctor for '
          'how much and how often.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (onLog case final log?) ...[
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Log medicine'),
            onPressed: () {
              // The log sheet in place of this one, rather than on top of
              // it: two sheets deep is one too many to back out of while
              // holding a baby.
              Navigator.pop(context);
              log();
            },
          ),
        ],
      ],
    );
  }
}

class _MedicineEntry extends StatelessWidget {
  const _MedicineEntry({
    required this.last,
    required this.now,
    required this.by,
    required this.inLastDay,
    required this.wait,
  });

  final MedicationEvent last;
  final DateTime now;
  final String? by;
  final int inLastDay;
  final MedWait? wait;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final dose = MedicationFormat.dose(last);
    final w = wait;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  [last.name.trim(), ?dose].join(' · '),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                FeedingFormat.shortAgo(last.time, now: now),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          Text(
            [
              FeedingFormat.clockStamp(context, last.time, now: now),
              if (by != null) 'by $by',
              '$inLastDay in the last 24 hr',
            ].join(' · '),
            style: muted,
          ),
          if (w != null)
            DueChip(
              state: DueState.soon,
              icon: Icons.hourglass_bottom,
              remaining: waitRemaining(w, now),
              text:
                  'Next ${last.name.trim()} '
                  '${countdownLabel(w.allowedAt, now: now)} · '
                  '${TimeOfDay.fromDateTime(w.allowedAt).format(context)}',
            ),
        ],
      ),
    );
  }
}

/// Nursery mode's way to the medicine sheet: a button in its header.
///
/// Shown on the terms Home's medicine row is — switched on in Settings, or
/// any dose logged — so a household that has never given medicine is not
/// handed a button for it. Marked with a dot while a wait is running, so
/// "is something too soon to give?" is answered from across the room
/// before the sheet is opened.
class MedicineButton extends ConsumerWidget {
  const MedicineButton({super.key, this.now});

  /// A fixed clock, for tests; passed on to the sheet.
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doses = ref.watch(recentMedsProvider).value ?? const [];
    if (doses.isEmpty && !ref.watch(showMedicationProvider)) {
      return const SizedBox.shrink();
    }
    final waiting = activeWaits(doses, now ?? DateTime.now()).isNotEmpty;

    return IconButton.filledTonal(
      tooltip: 'Medicine',
      onPressed: () => showMedicineSheet(context, now: now),
      icon: Badge(
        key: const ValueKey('medicine-waiting'),
        isLabelVisible: waiting,
        smallSize: 10,
        backgroundColor: warningInks(context).soon,
        child: const Icon(MedicationFormat.icon),
      ),
    );
  }
}
