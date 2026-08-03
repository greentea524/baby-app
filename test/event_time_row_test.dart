import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:baby_app/features/common/event_time_row.dart';

/// Time and date are separate buttons, so changing one never makes you answer
/// for the other.
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

  testWidgets('offers both buttons', (tester) async {
    await pumpRow(tester, DateTime(2026, 7, 30, 14, 30));
    expect(find.text('Time'), findsOneWidget);
    expect(find.text('Date'), findsOneWidget);
  });

  testWidgets('Time opens only the time picker', (tester) async {
    await pumpRow(tester, DateTime(2026, 7, 30, 14, 30));
    await tester.tap(find.text('Time'));
    await tester.pumpAndSettle();

    expect(find.byType(TimePickerDialog), findsOneWidget);
    expect(find.byType(DatePickerDialog), findsNothing);
  });

  testWidgets('Date opens only the date picker', (tester) async {
    await pumpRow(tester, DateTime(2026, 7, 30, 14, 30));
    await tester.tap(find.text('Date'));
    await tester.pumpAndSettle();

    expect(find.byType(DatePickerDialog), findsOneWidget);
    expect(find.byType(TimePickerDialog), findsNothing);
  });

  testWidgets('accepting the time leaves the day alone', (tester) async {
    DateTime? saved;
    await pumpRow(
      tester,
      DateTime(2026, 7, 30, 14, 30),
      onChanged: (t) => saved = t,
    );
    await tester.tap(find.text('Time'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.year, 2026);
    expect(saved!.month, 7);
    expect(saved!.day, 30);
  });

  testWidgets('picking a date keeps the time already set', (tester) async {
    DateTime? saved;
    await pumpRow(
      tester,
      DateTime(2026, 7, 30, 14, 30),
      onChanged: (t) => saved = t,
    );
    await tester.tap(find.text('Date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('29'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.day, 29);
    expect(saved!.hour, 14, reason: 'the clock survives a date change');
    expect(saved!.minute, 30);
  });

  testWidgets('cancelling either picker changes nothing', (tester) async {
    var calls = 0;
    await pumpRow(
      tester,
      DateTime(2026, 7, 30, 14, 30),
      onChanged: (_) => calls++,
    );

    await tester.tap(find.text('Time'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(calls, 0);
  });
}
