import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:baby_app/data/models/appointment.dart';
import 'package:baby_app/features/appointments/next_appointment_button.dart';

/// The next visit sits in the app bar's top-right corner, carrying the day and
/// what the appointment is, and opens the Appointments screen when tapped.
void main() {
  final now = DateTime(2026, 7, 30, 9);

  Appointment at(DateTime when, {String? title, AppointmentKind? kind}) =>
      Appointment(
        id: 'a1',
        at: when,
        kind: kind ?? AppointmentKind.checkup,
        title: title,
      );

  /// [viewportWidth] drives the compact/full decision, which the button reads
  /// from MediaQuery.
  Future<void> pumpButton(
    WidgetTester tester,
    Appointment appt, {
    VoidCallback? onTap,
    double viewportWidth = 800,
  }) => tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(size: Size(viewportWidth, 600)),
      child: MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            title: const Text('Home'),
            actions: [
              NextAppointmentLabel(
                appt: appt,
                now: now,
                onTap: onTap ?? () {},
              ),
            ],
          ),
        ),
      ),
    ),
  );

  String labelText(WidgetTester tester) => tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data)
      .whereType<String>()
      .firstWhere((s) => s != 'Home');

  group('dayLabel', () {
    test('collapses today and tomorrow, dates the rest', () {
      expect(
        NextAppointmentLabel.dayLabel(DateTime(2026, 7, 30, 14), now: now),
        'Today',
      );
      expect(
        NextAppointmentLabel.dayLabel(DateTime(2026, 7, 31, 14), now: now),
        'Tomorrow',
      );
      expect(
        NextAppointmentLabel.dayLabel(DateTime(2026, 8, 6, 14), now: now),
        'Aug 6',
      );
    });

    test('stays shorter than the full weekday form', () {
      // The corner cannot afford "Mon, Aug 6"; the appointment's name is a
      // better use of those characters.
      final short = NextAppointmentLabel.dayLabel(
        DateTime(2026, 8, 6),
        now: now,
      );
      expect(short, isNot(contains(',')));
    });
  });

  testWidgets('shows the day, the time, and what the appointment is', (
    tester,
  ) async {
    await pumpButton(
      tester,
      at(DateTime(2026, 8, 6, 14), title: '4-month jabs'),
    );
    final text = labelText(tester);
    expect(text, contains('Aug 6'));
    expect(text, contains('2:00'), reason: 'the time you have to be there');
    expect(text, contains('4-month jabs'));
  });

  testWidgets('reads as tappable, not as a heading', (tester) async {
    await pumpButton(tester, at(DateTime(2026, 8, 6, 14)));
    // A filled pill with a chevron: an app bar full of bare text gives no
    // sign that this one responds to a tap.
    expect(find.byType(InkWell), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    final material = tester.widget<Material>(
      find.ancestor(of: find.byType(InkWell), matching: find.byType(Material)).first,
    );
    expect(material.color, isNotNull, reason: 'filled, not transparent');
  });

  testWidgets('falls back to the kind when untitled', (tester) async {
    await pumpButton(
      tester,
      at(DateTime(2026, 8, 6, 14), kind: AppointmentKind.dental),
    );
    expect(labelText(tester), contains('Dental'));
  });

  testWidgets('carries the kind icon', (tester) async {
    await pumpButton(
      tester,
      at(DateTime(2026, 8, 6, 14), kind: AppointmentKind.vaccination),
    );
    expect(find.byIcon(Icons.vaccines_outlined), findsOneWidget);
  });

  testWidgets('tapping opens the appointments screen', (tester) async {
    var tapped = false;
    await pumpButton(
      tester,
      at(DateTime(2026, 8, 6, 14)),
      onTap: () => tapped = true,
    );
    await tester.tap(find.byType(InkWell));
    expect(tapped, isTrue);
  });

  testWidgets('a visit today reads as Today, not a date', (tester) async {
    await pumpButton(tester, at(DateTime(2026, 7, 30, 16), title: 'Checkup'));
    expect(labelText(tester), startsWith('Today'));
  });

  testWidgets('drops the name on a phone so the baby switcher survives', (
    tester,
  ) async {
    // Below the breakpoint the app bar cannot hold day, time, name and the
    // switcher. When it is due is the part you cannot infer.
    await pumpButton(
      tester,
      at(DateTime(2026, 8, 6, 14), title: '4-month jabs'),
      viewportWidth: 400,
    );
    final text = labelText(tester);
    expect(text, contains('Aug 6'));
    expect(text, contains('2:00'));
    expect(text, isNot(contains('4-month jabs')));
  });

  testWidgets('truncates rather than pushing the title out of the bar', (
    tester,
  ) async {
    // Wide enough to show the name, but not one this long.
    await pumpButton(
      tester,
      at(
        DateTime(2026, 8, 6, 14),
        title: 'An extremely long appointment name that cannot possibly fit',
      ),
    );
    expect(tester.takeException(), isNull);
    final text = tester.widget<Text>(find.textContaining('extremely long'));
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);
  });
}
