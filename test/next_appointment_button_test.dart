import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:baby_app/data/models/appointment.dart';
import 'package:baby_app/features/appointments/next_appointment_button.dart';

/// The next visit sits in the app bar's top-right corner as a two-line pill —
/// when it is above what it is — and opens the Appointments screen when
/// tapped.
void main() {
  final now = DateTime(2026, 7, 30, 9);

  Appointment at(DateTime when, {String? title, AppointmentKind? kind}) =>
      Appointment(
        id: 'a1',
        at: when,
        kind: kind ?? AppointmentKind.checkup,
        title: title,
      );

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
              NextAppointmentLabel(appt: appt, now: now, onTap: onTap ?? () {}),
            ],
          ),
        ),
      ),
    ),
  );

  /// The pill's lines, in order, ignoring the app bar title.
  List<String> lines(WidgetTester tester) => tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data)
      .whereType<String>()
      .where((s) => s != 'Home')
      .toList();

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
      // The corner cannot afford "Mon, Aug 6".
      expect(
        NextAppointmentLabel.dayLabel(DateTime(2026, 8, 6), now: now),
        isNot(contains(',')),
      );
    });
  });

  testWidgets('when it is on top, what it is underneath', (tester) async {
    await pumpButton(
      tester,
      at(DateTime(2026, 8, 6, 14), title: '4-month jabs'),
    );
    final text = lines(tester);
    expect(text, hasLength(2));
    expect(text.first, 'Aug 6, 2:00 PM');
    expect(text.last, '4-month jabs');
  });

  testWidgets('reads as tappable, not as a heading', (tester) async {
    await pumpButton(tester, at(DateTime(2026, 8, 6, 14)));
    // A filled pill with a chevron: an app bar full of bare text gives no
    // sign that this one responds to a tap.
    expect(find.byType(InkWell), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    final material = tester.widget<Material>(
      find
          .ancestor(of: find.byType(InkWell), matching: find.byType(Material))
          .first,
    );
    expect(material.color, isNotNull, reason: 'filled, not transparent');
  });

  testWidgets('falls back to the kind when untitled', (tester) async {
    await pumpButton(
      tester,
      at(DateTime(2026, 8, 6, 14), kind: AppointmentKind.dental),
    );
    expect(lines(tester).last, 'Dental');
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
    expect(lines(tester).first, startsWith('Today'));
  });

  testWidgets('keeps both lines on a phone', (tester) async {
    // Stacking is what buys this: on one line, day + time + name crowded the
    // baby switcher out of the bar.
    await pumpButton(
      tester,
      at(DateTime(2026, 8, 6, 14), title: '4-month jabs'),
      viewportWidth: 360,
    );
    expect(tester.takeException(), isNull);
    expect(lines(tester), ['Aug 6, 2:00 PM', '4-month jabs']);
  });

  testWidgets('a long name truncates rather than widening the pill', (
    tester,
  ) async {
    await pumpButton(
      tester,
      at(
        DateTime(2026, 8, 6, 14),
        title: 'Paediatric cardiology follow-up appointment',
      ),
      viewportWidth: 360,
    );
    expect(tester.takeException(), isNull);
    final name = tester.widget<Text>(find.textContaining('Paediatric'));
    expect(name.maxLines, 1);
    expect(name.overflow, TextOverflow.ellipsis);
  });
}
