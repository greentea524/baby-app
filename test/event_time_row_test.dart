import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:baby_app/features/common/event_time_row.dart';

/// Time and date are separate buttons, so changing one never makes you answer
/// for the other — and neither can land ahead of the clock, since every form
/// using this row logs something that already happened.
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

  const futureWarning =
      "That's in the future — pick a time that has already happened.";

  testWidgets('offers both buttons, date first', (tester) async {
    await pumpRow(tester, DateTime(2026, 7, 30, 14, 30));
    expect(find.text('Date'), findsOneWidget);
    expect(find.text('Time'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Date')).dx,
      lessThan(tester.getTopLeft(find.text('Time')).dx),
    );
  });

  testWidgets('reads date then time, matching the buttons', (tester) async {
    await pumpRow(tester, DateTime(2026, 7, 30, 14, 30));
    expect(find.text('7/30 · 2:30 PM'), findsOneWidget);
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

  group('no future times', () {
    test('is about the clock, not the calendar day', () {
      final now = DateTime(2026, 7, 30, 14, 30);
      expect(isFutureLogTime(DateTime(2026, 7, 30, 14, 31), now: now), isTrue);
      expect(isFutureLogTime(DateTime(2026, 7, 30, 14, 29), now: now), isFalse);
      expect(
        isFutureLogTime(now, now: now),
        isFalse,
        reason: 'this instant has already happened',
      );
      expect(isFutureLogTime(DateTime(2026, 7, 31), now: now), isTrue);
      expect(isFutureLogTime(DateTime(2026, 7, 29, 23, 59), now: now), isFalse);
    });

    testWidgets('a time later today is refused, with a reason', (tester) async {
      final now = DateTime.now();
      if (now.hour >= 22) {
        markTestSkipped('needs an hour left in the day to point at');
        return;
      }
      DateTime? saved;
      // Early today, so the row starts clean.
      await pumpRow(
        tester,
        DateTime(now.year, now.month, now.day),
        onChanged: (t) => saved = t,
      );
      expect(find.text(futureWarning), findsNothing);

      // Type a time two hours out, which is the one thing the dial cannot be
      // driven to reliably from a test.
      await tester.tap(find.text('Time'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.keyboard_outlined));
      await tester.pumpAndSettle();

      final later = now.add(const Duration(hours: 2));
      final hour12 = later.hour % 12 == 0 ? 12 : later.hour % 12;
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '$hour12');
      await tester.enterText(fields.at(1), '00');
      await tester.tap(find.text(later.hour < 12 ? 'AM' : 'PM'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(saved, isNull, reason: 'a future pick must not be applied');
      expect(find.text(futureWarning), findsOneWidget);
    });

    testWidgets('a later pick that is in the past clears the warning', (
      tester,
    ) async {
      final now = DateTime.now();
      if (now.hour < 2 || now.hour >= 22) {
        markTestSkipped('needs an hour either side of now within the day');
        return;
      }
      DateTime? saved;
      await pumpRow(
        tester,
        DateTime(now.year, now.month, now.day),
        onChanged: (t) => saved = t,
      );

      Future<void> pickHour(int hour24) async {
        await tester.tap(find.text('Time'));
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.keyboard_outlined));
        await tester.pumpAndSettle();
        final h = hour24 % 12 == 0 ? 12 : hour24 % 12;
        final fields = find.byType(TextField);
        await tester.enterText(fields.at(0), '$h');
        await tester.enterText(fields.at(1), '00');
        await tester.tap(find.text(hour24 < 12 ? 'AM' : 'PM'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
      }

      await pickHour(now.hour + 2);
      expect(find.text(futureWarning), findsOneWidget);
      expect(saved, isNull);

      await pickHour(now.hour - 1);
      expect(find.text(futureWarning), findsNothing);
      expect(saved, isNotNull);
      expect(saved!.hour, now.hour - 1);
    });

    testWidgets('a record already stamped ahead is flagged on sight', (
      tester,
    ) async {
      // The one way a future time can still reach this row: editing an entry
      // logged before the check existed.
      await pumpRow(tester, DateTime.now().add(const Duration(hours: 3)));
      expect(find.text(futureWarning), findsOneWidget);
    });

    testWidgets('the date picker still opens for such a record', (
      tester,
    ) async {
      // initialDate past lastDate is an assertion failure rather than a
      // clamp, so a future-stamped entry would crash the picker it needs in
      // order to be fixed.
      await pumpRow(tester, DateTime.now().add(const Duration(days: 5)));
      await tester.tap(find.text('Date'));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
    });

    testWidgets('tomorrow is not selectable', (tester) async {
      final now = DateTime.now();
      final tomorrow = now.add(const Duration(days: 1));
      if (tomorrow.month != now.month) {
        markTestSkipped('tomorrow is on the next page of the calendar');
        return;
      }
      DateTime? saved;
      await pumpRow(
        tester,
        DateTime(now.year, now.month, now.day),
        onChanged: (t) => saved = t,
      );
      await tester.tap(find.text('Date'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('${tomorrow.day}'), warnIfMissed: false);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // The disabled cell swallowed the tap, so the confirmed date is still
      // the one the row opened with, and nothing future was emitted.
      if (saved != null) {
        expect(isFutureLogTime(saved!), isFalse);
        expect(saved!.day, isNot(tomorrow.day));
      }
    });
  });
}
