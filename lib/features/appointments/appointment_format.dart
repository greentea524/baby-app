import 'package:flutter/material.dart';

import '../../data/models/appointment.dart';
import '../timeline/timeline_format.dart';

/// Display helpers for appointments (KAN-176), kept out of widgets so the
/// partitioning and countdown logic stay unit-testable.
abstract final class AppointmentFormat {
  static String kindLabel(AppointmentKind kind) => switch (kind) {
    AppointmentKind.checkup => 'Checkup',
    AppointmentKind.vaccination => 'Vaccination',
    AppointmentKind.specialist => 'Specialist',
    AppointmentKind.dental => 'Dental',
    AppointmentKind.other => 'Appointment',
  };

  static IconData kindIcon(AppointmentKind kind) => switch (kind) {
    AppointmentKind.checkup => Icons.medical_services_outlined,
    AppointmentKind.vaccination => Icons.vaccines_outlined,
    AppointmentKind.specialist => Icons.person_search_outlined,
    AppointmentKind.dental => Icons.sentiment_satisfied_outlined,
    AppointmentKind.other => Icons.event_outlined,
  };

  /// The row title: the caregiver's own wording when they gave one, the kind
  /// otherwise.
  static String title(Appointment a) {
    final custom = a.title?.trim();
    return (custom == null || custom.isEmpty) ? kindLabel(a.kind) : custom;
  }

  /// Provider, location, and notes joined for the row subtitle.
  static String details(Appointment a) {
    final parts = <String>[
      if (a.provider != null && a.provider!.trim().isNotEmpty)
        a.provider!.trim(),
      if (a.location != null && a.location!.trim().isNotEmpty)
        a.location!.trim(),
      if (a.notes != null && a.notes!.trim().isNotEmpty) a.notes!.trim(),
    ];
    return parts.join(' · ');
  }

  /// How far off an appointment is, in calendar days rather than elapsed
  /// hours — "tomorrow" should mean the next calendar day even if it is only
  /// 14 hours away. Past appointments read as "3 days ago".
  static String countdown(DateTime at, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    final today = DateTime(reference.year, reference.month, reference.day);
    final target = DateTime(at.year, at.month, at.day);
    final days = target.difference(today).inDays;

    if (days == 0) return 'Today';
    if (days == 1) return 'Tomorrow';
    if (days == -1) return 'Yesterday';
    if (days > 1) return 'in $days days';
    return '${-days} days ago';
  }

  /// The calendar day for the row's trailing label — "Today", "Tomorrow", or
  /// "Mon, Jul 20".
  static String dayLabel(DateTime at, {DateTime? now}) =>
      TimelineFormat.dayLabel(at, now: now);
}

/// Appointments split around [now]: what's still ahead, and what's behind.
typedef SplitAppointments = ({
  List<Appointment> upcoming,
  List<Appointment> past,
});

/// Splits [all] into upcoming (soonest first) and past (most recent first).
///
/// Ordering differs between the two halves on purpose: for what's ahead you
/// want the nearest thing at the top, and for history you want the latest.
SplitAppointments splitAppointments(List<Appointment> all, DateTime now) {
  final upcoming = <Appointment>[];
  final past = <Appointment>[];
  for (final a in all) {
    if (a.isUpcoming(now)) {
      upcoming.add(a);
    } else {
      past.add(a);
    }
  }
  upcoming.sort((a, b) => a.at.compareTo(b.at));
  past.sort((a, b) => b.at.compareTo(a.at));
  return (upcoming: upcoming, past: past);
}
