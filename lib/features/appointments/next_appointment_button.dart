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
/// Shows when the visit is and what it is — "Tomorrow, 2:00 PM · Jabs" —
/// because a bare countdown says something is coming without saying what to
/// prepare for or when to be there. Tapping opens the Appointments screen,
/// which is where the rest of them live.
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
  ///
  /// Stacking day/time over the name keeps this narrow enough to sit beside
  /// the baby switcher on a phone, which a single line could not.
  static const maxWidth = 220.0;

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
    final scheme = theme.colorScheme;
    final imminent = AppointmentFormat.daysUntil(appt.at, now: now) <= 1;

    // Day and time lead: that is what you cannot infer. The visit's name sits
    // under them rather than beside them, which halves the width the pill
    // needs — on one line the two together crowded out the baby switcher.
    final when =
        '${dayLabel(appt.at, now: now)}, '
        '${TimeOfDay.fromDateTime(appt.at).format(context)}';

    // A visit today or tomorrow is the one worth catching your eye; anything
    // further out sits in the quieter container. Mirrors the next-feed chip on
    // Home, which uses the same tinted-pill treatment.
    final background = imminent
        ? scheme.tertiaryContainer
        : scheme.secondaryContainer;
    final foreground = imminent
        ? scheme.onTertiaryContainer
        : scheme.onSecondaryContainer;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: maxWidth),
        // A filled pill with a chevron, rather than bare text: in an app bar a
        // plain label reads as a heading, and nothing about it invites a tap.
        child: Material(
          color: background,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    AppointmentFormat.kindIcon(appt.kind),
                    size: 16,
                    color: foreground,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          when,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: foreground,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          AppointmentFormat.title(appt),
                          style: theme.textTheme.labelSmall?.copyWith(
                            // Softened against the container so the line you
                            // scan for stays on top.
                            color: foreground.withValues(alpha: 0.8),
                            height: 1.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(Icons.chevron_right, size: 16, color: foreground),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
