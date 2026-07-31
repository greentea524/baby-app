import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../data/models/appointment.dart';
import '../../data/repositories/repository_providers.dart';
import '../timeline/timeline_format.dart';
import 'appointment_format.dart';

/// The next appointment, in the app bar's top-right corner.
///
/// Shows the day and what the visit is — "Tomorrow · Jabs", "Aug 6 · Checkup"
/// — because a bare countdown tells you something is coming without telling
/// you what to prepare for. Tapping opens the Appointments screen, which is
/// where the rest of them live.
///
/// Renders nothing when there is no upcoming visit, so the corner stays empty
/// for anyone not using appointments rather than showing a dead button.
class NextAppointmentButton extends ConsumerWidget {
  const NextAppointmentButton({super.key, this.now});

  /// Injectable clock, for deterministic day labels in tests.
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(appointmentsProvider).value ?? const [];
    final upcoming = splitAppointments(all, now ?? DateTime.now()).upcoming;
    if (upcoming.isEmpty) return const SizedBox.shrink();

    return NextAppointmentLabel(
      appt: upcoming.first,
      now: now ?? DateTime.now(),
      onTap: () => context.push(AppRoutes.appointments),
    );
  }
}

/// The button itself, without the data lookup — so it can be tested without a
/// signed-in Firebase session.
class NextAppointmentLabel extends StatelessWidget {
  const NextAppointmentLabel({
    super.key,
    required this.appt,
    required this.now,
    required this.onTap,
  });

  final Appointment appt;
  final DateTime now;
  final VoidCallback onTap;

  /// Keeps the button from crowding out the baby switcher in the title. The
  /// label ellipsizes inside this rather than the app bar overflowing.
  static const maxWidth = 190.0;

  /// "Today" / "Tomorrow" / "Aug 6".
  ///
  /// Deliberately shorter than [TimelineFormat.dayLabel], which would spend
  /// the corner's width on a weekday ("Mon, Aug 6") that tells you less than
  /// the appointment's name does.
  static String dayLabel(DateTime at, {required DateTime now}) {
    final days = AppointmentFormat.daysUntil(at, now: now);
    return switch (days) {
      0 => 'Today',
      1 => 'Tomorrow',
      _ => TimelineFormat.shortDate(at),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final imminent = AppointmentFormat.daysUntil(appt.at, now: now) <= 1;
    final label =
        '${dayLabel(appt.at, now: now)} · ${AppointmentFormat.title(appt)}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: maxWidth),
        child: TextButton.icon(
          onPressed: onTap,
          icon: Icon(AppointmentFormat.kindIcon(appt.kind), size: 18),
          label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          style: TextButton.styleFrom(
            // A visit today or tomorrow is the one worth catching your eye;
            // anything further out sits in the ordinary app bar colour.
            foregroundColor: imminent
                ? theme.colorScheme.tertiary
                : theme.colorScheme.onSurfaceVariant,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            visualDensity: VisualDensity.compact,
          ),
        ),
      ),
    );
  }
}
