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
  /// Wide enough for "Tomorrow, 2:00 PM · 4-month jabs" — at 240 the visit's
  /// name was being cut off even on a desktop window.
  static const maxWidth = 300.0;

  /// Below this the app bar cannot hold the day, the time, the visit's name
  /// *and* the baby switcher, so the name is dropped rather than letting the
  /// pill squeeze the switcher down to "Wilhelm…". When it is due is the part
  /// you cannot infer; what it is can be read on the screen this opens.
  static const compactBelowWidth = 480.0;

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

    // Day and time read as one fact, so they sit together; what the visit is
    // follows after the separator, and is the first thing dropped when the
    // bar is too narrow to hold everything.
    final when =
        '${dayLabel(appt.at, now: now)}, '
        '${TimeOfDay.fromDateTime(appt.at).format(context)}';
    final compact = MediaQuery.sizeOf(context).width < compactBelowWidth;
    final label = compact
        ? when
        : '$when · ${AppointmentFormat.title(appt)}';

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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
              padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    AppointmentFormat.kindIcon(appt.kind),
                    size: 16,
                    color: foreground,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: foreground,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
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
