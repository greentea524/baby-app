import 'package:baby_app/data/models/appointment.dart';
import 'package:baby_app/features/appointments/appointment_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Appointment at(DateTime when, {String id = 'a'}) =>
      Appointment(id: id, at: when);

  group('splitAppointments', () {
    final now = DateTime(2026, 7, 27, 12, 0);

    test('puts what is ahead in upcoming, soonest first', () {
      final split = splitAppointments([
        at(DateTime(2026, 9, 1), id: 'far'),
        at(DateTime(2026, 7, 28), id: 'near'),
        at(DateTime(2026, 8, 5), id: 'mid'),
      ], now);
      expect(split.upcoming.map((a) => a.id).toList(), ['near', 'mid', 'far']);
      expect(split.past, isEmpty);
    });

    test('puts what is behind in past, most recent first', () {
      final split = splitAppointments([
        at(DateTime(2026, 1, 5), id: 'old'),
        at(DateTime(2026, 7, 20), id: 'recent'),
        at(DateTime(2026, 4, 2), id: 'mid'),
      ], now);
      expect(split.past.map((a) => a.id).toList(), ['recent', 'mid', 'old']);
      expect(split.upcoming, isEmpty);
    });

    test('an appointment later today is still upcoming', () {
      // The split is by instant, not by calendar day — a 4pm visit is still
      // ahead of you at noon.
      final split = splitAppointments([
        at(DateTime(2026, 7, 27, 16, 0), id: 'afternoon'),
        at(DateTime(2026, 7, 27, 9, 0), id: 'morning'),
      ], now);
      expect(split.upcoming.map((a) => a.id).toList(), ['afternoon']);
      expect(split.past.map((a) => a.id).toList(), ['morning']);
    });

    test('an appointment exactly now counts as upcoming', () {
      final split = splitAppointments([at(now)], now);
      expect(split.upcoming, hasLength(1));
    });

    test('handles an empty list', () {
      final split = splitAppointments(const [], now);
      expect(split.upcoming, isEmpty);
      expect(split.past, isEmpty);
    });
  });

  group('countdown', () {
    final now = DateTime(2026, 7, 27, 12, 0);

    test('counts calendar days, not elapsed hours', () {
      // 11pm tonight is under 12 hours away but still "Today"; 1am tomorrow
      // is closer in hours than 11pm but reads as "Tomorrow".
      expect(
        AppointmentFormat.countdown(DateTime(2026, 7, 27, 23, 0), now: now),
        'Today',
      );
      expect(
        AppointmentFormat.countdown(DateTime(2026, 7, 28, 1, 0), now: now),
        'Tomorrow',
      );
    });

    test('reads ahead in days', () {
      expect(
        AppointmentFormat.countdown(DateTime(2026, 7, 30), now: now),
        'in 3 days',
      );
      expect(
        AppointmentFormat.countdown(DateTime(2026, 8, 26), now: now),
        'in 30 days',
      );
    });

    test('reads backwards for past visits', () {
      expect(
        AppointmentFormat.countdown(DateTime(2026, 7, 26), now: now),
        'Yesterday',
      );
      expect(
        AppointmentFormat.countdown(DateTime(2026, 7, 24), now: now),
        '3 days ago',
      );
    });
  });

  group('title and details', () {
    test('falls back to the kind when no title was given', () {
      final a = Appointment(
        id: 'a',
        at: _fixed,
        kind: AppointmentKind.vaccination,
      );
      expect(AppointmentFormat.title(a), 'Vaccination');
    });

    test('prefers the caregiver wording', () {
      final a = Appointment(
        id: 'a',
        at: _fixed,
        kind: AppointmentKind.checkup,
        title: '6-month well visit',
      );
      expect(AppointmentFormat.title(a), '6-month well visit');
    });

    test('ignores a whitespace-only title', () {
      final a = Appointment(id: 'a', at: _fixed, title: '   ');
      expect(AppointmentFormat.title(a), 'Checkup');
    });

    test('joins the provider, location, and notes', () {
      final a = Appointment(
        id: 'a',
        at: _fixed,
        provider: 'Dr. Chen',
        location: 'Sunrise Pediatrics',
        notes: 'bring the red book',
      );
      expect(
        AppointmentFormat.details(a),
        'Dr. Chen · Sunrise Pediatrics · bring the red book',
      );
    });

    test('omits blank fields entirely', () {
      final a = Appointment(id: 'a', at: _fixed, provider: 'Dr. Chen');
      expect(AppointmentFormat.details(a), 'Dr. Chen');
      expect(AppointmentFormat.details(Appointment(id: 'b', at: _fixed)), '');
    });
  });

  group('model', () {
    test('copyWith can clear a completion, which a plain ?? cannot', () {
      final done = Appointment(
        id: 'a',
        at: _fixed,
        completedAt: DateTime(2026, 7, 20),
      );
      expect(done.isCompleted, isTrue);
      expect(done.copyWith(clearCompletedAt: true).isCompleted, isFalse);
      // Without the flag the existing value survives.
      expect(done.copyWith(title: 'x').isCompleted, isTrue);
    });
  });
}

final _fixed = DateTime(2026, 7, 27, 10, 0);
