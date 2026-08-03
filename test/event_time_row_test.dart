import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:baby_app/features/common/event_time_row.dart';

/// Almost everything is logged on the day it happens, so the time picker
/// comes first and the date follows.
void main() {
  Future<void> pumpRow(
    WidgetTester tester,
    DateTime time, {
    ValueChanged<DateTime>? onChanged,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: EventTimeRow(time: time, onChanged: onChanged ?? (_) {}),
      ),
    ),
  );

  testWidgets('Change opens the time picker first', (tester) async {
    await pumpRow(tester, DateTime(2026, 7, 30, 14, 30));
    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();

    expect(find.byType(TimePickerDialog), findsOneWidget);
    expect(
      find.byType(DatePickerDialog),
      findsNothing,
      reason: 'no calendar to dismiss before reaching the time',
    );
  });

  testWidgets('the date picker follows once a time is chosen', (tester) async {
    await pumpRow(tester, DateTime(2026, 7, 30, 14, 30));
    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.byType(DatePickerDialog), findsOneWidget);
  });

  testWidgets('cancelling the time picker never reaches the date', (
    tester,
  ) async {
    var calls = 0;
    await pumpRow(
      tester,
      DateTime(2026, 7, 30, 14, 30),
      onChanged: (_) => calls++,
    );
    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(DatePickerDialog), findsNothing);
    expect(calls, 0);
  });

  testWidgets('cancelling the date picker leaves the value alone', (
    tester,
  ) async {
    // The time was already chosen by this point, but a half-applied change is
    // worse than none — the caller hears nothing.
    var calls = 0;
    await pumpRow(
      tester,
      DateTime(2026, 7, 30, 14, 30),
      onChanged: (_) => calls++,
    );
    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(calls, 0);
  });

  testWidgets('both pickers accepted keeps the existing day', (tester) async {
    DateTime? saved;
    await pumpRow(
      tester,
      DateTime(2026, 7, 30, 14, 30),
      onChanged: (t) => saved = t,
    );
    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.year, 2026);
    expect(saved!.month, 7);
    expect(saved!.day, 30, reason: 'the date defaults to what was already set');
  });
}
