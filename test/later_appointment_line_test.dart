import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:baby_app/data/models/appointment.dart';
import 'package:baby_app/features/home/home_status_card.dart';

/// Appointments after the next one are compact single lines inside the same
/// card, rather than a full row (and, under the Separate layout, a whole card)
/// each.
void main() {
  final now = DateTime(2026, 7, 30, 9);

  Future<void> pumpLine(WidgetTester tester, Appointment appt) => tester
      .pumpWidget(
        MaterialApp(
          home: Scaffold(body: LaterAppointmentLine(appt: appt, now: now)),
        ),
      );

  testWidgets('carries when, which day, and what it is', (tester) async {
    await pumpLine(
      tester,
      Appointment(
        id: 'a1',
        at: DateTime(2026, 8, 6, 14, 0),
        kind: AppointmentKind.vaccination,
        title: '4-month jabs',
      ),
    );

    final text = tester.widget<Text>(find.byType(Text)).data!;
    expect(text, contains('7 days'));
    expect(text, contains('Aug 6'));
    expect(text, contains('4-month jabs'));
  });

  testWidgets('is a single line that truncates rather than wrapping', (
    tester,
  ) async {
    await pumpLine(
      tester,
      Appointment(
        id: 'a2',
        at: DateTime(2026, 8, 6, 14, 0),
        title: 'A very long appointment title that will not fit on one line',
        provider: 'Dr Someone With A Long Name',
        location: 'A clinic several words long',
      ),
    );

    final widget = tester.widget<Text>(find.byType(Text));
    expect(widget.maxLines, 1);
    expect(widget.overflow, TextOverflow.ellipsis);
  });

  testWidgets('falls back to the kind when there is no title', (tester) async {
    await pumpLine(
      tester,
      Appointment(
        id: 'a3',
        at: DateTime(2026, 8, 6, 14, 0),
        kind: AppointmentKind.dental,
      ),
    );

    final text = tester.widget<Text>(find.byType(Text)).data!;
    expect(text.trim(), isNot(endsWith('·')));
    expect(text, contains('Aug 6'));
  });

  testWidgets('lines up with the row above rather than its icon', (
    tester,
  ) async {
    // The inset mirrors _StatusRow's 16 padding + 44 avatar + 16 gap. If that
    // row's metrics change, this drifts out of alignment silently.
    await pumpLine(
      tester,
      Appointment(id: 'a4', at: DateTime(2026, 8, 6, 14, 0)),
    );

    final padding = tester.widget<Padding>(
      find
          .ancestor(of: find.byType(Text), matching: find.byType(Padding))
          .first,
    );
    expect((padding.padding as EdgeInsets).left, 76.0);
  });
}
