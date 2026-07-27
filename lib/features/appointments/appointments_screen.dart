import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/appointment.dart';
import '../../data/repositories/repository_providers.dart';
import '../common/event_tile.dart';
import '../feeding/feeding_format.dart';
import 'appointment_format.dart';
import 'appointment_sheet.dart';

/// Upcoming and past visits (KAN-176). This is the app's only forward-looking
/// screen — everything else reviews what already happened.
class AppointmentsScreen extends ConsumerWidget {
  const AppointmentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final baby = ref.watch(currentBabyProvider);
    final appointmentsAsync = ref.watch(appointmentsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Appointments')),
      floatingActionButton: baby == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => showAppointmentSheet(context),
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            ),
      body: baby == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Add a baby on the Home tab to track visits.'),
              ),
            )
          : appointmentsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Could not load: $e')),
              data: (all) {
                // Split on every build so an appointment that comes due while
                // the app is open moves across on its own.
                final split = splitAppointments(all, DateTime.now());
                if (all.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No appointments yet.\nAdd the next checkup so it '
                        'does not sneak up on you.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                return ListView(
                  padding: const EdgeInsets.only(bottom: 88),
                  children: [
                    if (split.upcoming.isNotEmpty) ...[
                      const _SectionHeader('Upcoming'),
                      for (final a in split.upcoming)
                        _AppointmentTile(appointment: a, upcoming: true),
                    ],
                    if (split.past.isNotEmpty) ...[
                      const _SectionHeader('Past'),
                      for (final a in split.past)
                        _AppointmentTile(appointment: a, upcoming: false),
                    ],
                  ],
                );
              },
            ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(label, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}

class _AppointmentTile extends ConsumerWidget {
  const _AppointmentTile({required this.appointment, required this.upcoming});

  final Appointment appointment;
  final bool upcoming;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    // Upcoming rows lead with how far off it is, which is what you scan for;
    // past rows lead with the date, since "12 days ago" is less useful than
    // knowing which day it was.
    final trailing = upcoming
        ? AppointmentFormat.countdown(appointment.at, now: now)
        : AppointmentFormat.dayLabel(appointment.at, now: now);
    final trailingDetail = FeedingFormat.clockStamp(
      context,
      appointment.at,
      now: now,
    );

    return EventTile(
      key: ValueKey('appointment_${appointment.id}'),
      icon: AppointmentFormat.kindIcon(appointment.kind),
      title: AppointmentFormat.title(appointment),
      subtitle: AppointmentFormat.details(appointment),
      trailing: trailing,
      trailingDetail: trailingDetail,
      confirmTitle: 'Delete appointment?',
      deletedMessage: 'Appointment deleted',
      onTap: () => showAppointmentSheet(context, existing: appointment),
      onDelete: () async =>
          ref.read(appointmentsRepositoryProvider)?.delete(appointment.id),
    );
  }
}
