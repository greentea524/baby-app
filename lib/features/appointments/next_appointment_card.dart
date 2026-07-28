import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../data/repositories/repository_providers.dart';
import 'appointment_format.dart';

/// Home preview of the next scheduled visit (KAN-177), matching the shape of
/// the next-feed card above it. Tapping it opens the Visits tab.
///
/// Renders nothing when there is no upcoming appointment: Home is already
/// dense, and an empty "no appointments" card would be permanent clutter for
/// anyone not using the feature.
class NextAppointmentCard extends ConsumerWidget {
  const NextAppointmentCard({super.key, required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(appointmentsProvider).value ?? const [];
    final upcoming = splitAppointments(all, now).upcoming;
    if (upcoming.isEmpty) return const SizedBox.shrink();

    final next = upcoming.first;
    final theme = Theme.of(context);
    // Today or tomorrow gets a tinted card — the whole point of the preview
    // is that an imminent visit is hard to miss.
    final imminent = AppointmentFormat.daysUntil(next.at, now: now) <= 1;
    final detail = AppointmentFormat.details(next);

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      color: imminent ? theme.colorScheme.tertiaryContainer : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.go(AppRoutes.appointments),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                AppointmentFormat.kindIcon(next.kind),
                color: imminent
                    ? theme.colorScheme.onTertiaryContainer
                    : theme.colorScheme.primary,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Next appointment',
                      style: theme.textTheme.labelMedium,
                    ),
                    Text(
                      '${AppointmentFormat.countdown(next.at, now: now)} · '
                      '${TimeOfDay.fromDateTime(next.at).format(context)}',
                      style: theme.textTheme.titleMedium,
                    ),
                    Text(
                      detail.isEmpty
                          ? AppointmentFormat.title(next)
                          : '${AppointmentFormat.title(next)} · $detail',
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
