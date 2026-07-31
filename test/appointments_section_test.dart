import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:baby_app/data/models/appointment.dart';
import 'package:baby_app/features/home/home_status_card.dart';

/// Upcoming appointments sit side by side in one card, each rendered the same
/// way, and stack instead when the columns would be too narrow for a date.
void main() {
  final now = DateTime(2026, 7, 30, 9);

  Appointment appt(int day, {String? title, AppointmentKind? kind}) =>
      Appointment(
        id: 'a$day',
        at: DateTime(2026, 8, day, 14, 0),
        kind: kind ?? AppointmentKind.checkup,
        title: title,
      );

  Future<void> pumpAt(
    WidgetTester tester,
    double width,
    List<Appointment> appointments,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: width,
            child: AppointmentsSection(appointments: appointments, now: now),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// Left edge of each block, to tell a side-by-side layout from a stacked one.
  List<double> blockLefts(WidgetTester tester) => tester
      .widgetList<AppointmentBlock>(find.byType(AppointmentBlock))
      .map((w) => tester.getTopLeft(find.byWidget(w)).dx)
      .toList();

  testWidgets('splits into columns when there is room', (tester) async {
    await pumpAt(tester, 800, [appt(6), appt(20)]);

    expect(find.byType(AppointmentBlock), findsNWidgets(2));
    final lefts = blockLefts(tester);
    expect(lefts[1], greaterThan(lefts[0]), reason: 'second sits to the right');
    // Same top edge means they are beside each other, not stacked.
    final tops = tester
        .widgetList<AppointmentBlock>(find.byType(AppointmentBlock))
        .map((w) => tester.getTopLeft(find.byWidget(w)).dy);
    expect(tops.first, tops.last);
  });

  testWidgets('stacks on a narrow screen rather than truncating dates', (
    tester,
  ) async {
    // A phone: two columns here would be ~150px each before the icon is
    // subtracted, so the date itself would ellipsize.
    await pumpAt(tester, 360, [appt(6), appt(20)]);

    expect(find.byType(AppointmentBlock), findsNWidgets(2));
    final lefts = blockLefts(tester);
    expect(lefts[0], lefts[1], reason: 'stacked blocks share a left edge');
  });

  testWidgets('a lone appointment never splits', (tester) async {
    await pumpAt(tester, 800, [appt(6)]);
    expect(find.byType(AppointmentBlock), findsOneWidget);
  });

  testWidgets('three appointments stack once the columns get too thin', (
    tester,
  ) async {
    await pumpAt(tester, 500, [appt(6), appt(13), appt(20)]);
    final lefts = blockLefts(tester);
    expect(lefts.toSet().length, 1, reason: 'all stacked');
  });

  testWidgets('every appointment is rendered the same way', (tester) async {
    // The thing that prompted this layout: the second appointment must not
    // read as a different kind of item from the first.
    await pumpAt(tester, 800, [
      appt(6, title: 'Six week check'),
      appt(20, title: 'Jabs'),
    ]);

    final blocks = find.byType(AppointmentBlock);
    for (var i = 0; i < 2; i++) {
      final texts = tester
          .widgetList<Text>(
            find.descendant(of: blocks.at(i), matching: find.byType(Text)),
          )
          .map((t) => t.data)
          .toList();
      // label, countdown, date+time, what it is.
      expect(texts.length, 4, reason: 'block $i has the same four lines');
      expect(texts[2], contains('Aug'));
    }
  });

  testWidgets('only the first is labelled as next', (tester) async {
    await pumpAt(tester, 800, [appt(6), appt(20)]);
    expect(find.text('Next appointment'), findsOneWidget);
    expect(find.text('Then'), findsOneWidget);
  });

  testWidgets('one icon for the section, not one per appointment', (
    tester,
  ) async {
    await pumpAt(tester, 800, [appt(6), appt(20)]);
    expect(find.byType(CircleAvatar), findsOneWidget);
  });
}
