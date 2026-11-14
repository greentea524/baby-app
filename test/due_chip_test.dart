import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:baby_app/features/home/home_status_card.dart';
import 'package:baby_app/features/reminders/feed_prediction.dart';

/// The chip is the only thing on Home that changes colour on its own, so the
/// three states have to be visibly different from each other — in both themes.
void main() {
  Future<void> pumpChip(
    WidgetTester tester,
    DueState state, {
    Brightness brightness = Brightness.light,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          brightness: brightness,
          colorSchemeSeed: const Color(0xFF7E9BD0),
        ),
        home: Scaffold(
          body: DueChip(state: state, text: 'Next feed in 12m · 2:15 PM'),
        ),
      ),
    );
    // MaterialApp lerps between themes over kThemeAnimationDuration, so
    // re-pumping with a different brightness and reading straight away would
    // sample a blend of the two.
    await tester.pumpAndSettle();
  }

  Color background(WidgetTester tester) {
    final container = tester.widget<Container>(
      find.descendant(
        of: find.byType(DueChip),
        matching: find.byType(Container),
      ),
    );
    return ((container.decoration as BoxDecoration).color)!;
  }

  IconData icon(WidgetTester tester) =>
      tester.widget<Icon>(find.byType(Icon)).icon!;

  testWidgets('each state gets its own colour', (tester) async {
    final seen = <DueState, Color>{};
    for (final state in DueState.values) {
      await pumpChip(tester, state);
      seen[state] = background(tester);
    }
    expect(
      seen.values.toSet(),
      hasLength(DueState.values.length),
      reason: 'a shared colour would make a state invisible',
    );
  });

  testWidgets('the icon escalates with the state', (tester) async {
    await pumpChip(tester, DueState.upcoming);
    expect(icon(tester), Icons.schedule);

    await pumpChip(tester, DueState.soon);
    expect(icon(tester), Icons.notifications_none);

    await pumpChip(tester, DueState.overdue);
    expect(icon(tester), Icons.notifications_active);
  });

  testWidgets('soon is amber, not the seed colour', (tester) async {
    // The accent picker offers four seeds and Material has no "warning" role,
    // so this colour is fixed rather than derived — a caution that turned pink
    // on the Blush accent would not read as caution.
    await pumpChip(tester, DueState.soon);
    final amber = background(tester);
    expect(amber.r, greaterThan(amber.b));
    expect(amber.g, greaterThan(amber.b));

    // And it stays put when the seed changes.
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: const Color(0xFFD08A9B), // Blush
        ),
        home: const Scaffold(
          body: DueChip(state: DueState.soon, text: 'Next feed'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(background(tester), amber);
  });

  testWidgets('dark mode gets a dark amber, not the light one', (tester) async {
    await pumpChip(tester, DueState.soon);
    final light = background(tester);
    await pumpChip(tester, DueState.soon, brightness: Brightness.dark);
    final dark = background(tester);

    expect(dark, isNot(light));
    expect(
      dark.computeLuminance(),
      lessThan(light.computeLuminance()),
      reason: 'a light amber pill would glare in a night feed',
    );
  });

  testWidgets('text stays legible against every background', (tester) async {
    for (final brightness in Brightness.values) {
      for (final state in DueState.values) {
        await pumpChip(tester, state, brightness: brightness);
        final bg = background(tester);
        final fg = tester
            .widget<Text>(find.textContaining('Next feed'))
            .style!
            .color!;
        final l1 = fg.computeLuminance();
        final l2 = bg.computeLuminance();
        final ratio = l1 > l2
            ? (l1 + 0.05) / (l2 + 0.05)
            : (l2 + 0.05) / (l1 + 0.05);
        expect(
          ratio,
          greaterThan(4.5),
          reason: '$state in $brightness is only ${ratio.toStringAsFixed(1)}:1',
        );
      }
    }
  });

  test('the countdown and its clock time break as whole pieces', () {
    // A wrap used to land between "1h" and "30m", or leave a line starting
    // with a stray "·". Only the space after the lead and the one after the
    // dot can break now.
    final line = dueLine('Next feed', 'in 1h 30m', '2:15 PM');
    expect(line, 'Next feed in\u00a01h\u00a030m\u00a0· 2:15\u00a0PM');
    expect(line, isNot(contains(' ·')));
  });

  test('an hour past due is late, not merely overdue', () {
    final due = DateTime(2026, 11, 14, 9);
    DueState at(int minutesPast) =>
        feedDueState(due, now: due.add(Duration(minutes: minutesPast)));
    expect(at(0), DueState.overdue);
    expect(at(59), DueState.overdue);
    expect(at(60), DueState.late);
    expect(at(300), DueState.late);
    expect(DueState.late.isPast, isTrue);
    expect(DueState.overdue.isPast, isTrue);
    expect(DueState.soon.isPast, isFalse);
  });

  testWidgets('late is purple, in both themes', (tester) async {
    for (final brightness in Brightness.values) {
      await pumpChip(tester, DueState.late, brightness: brightness);
      final purple = background(tester);
      // Blue and red both over green: purple, not the red before it.
      expect(purple.b, greaterThan(purple.g), reason: '$brightness');
      expect(purple.r, greaterThan(purple.g), reason: '$brightness');
    }
  });

  test('an overdue line can break after "due", not inside the time', () {
    final line = dueLine('Pump', '20m overdue', 'due 8:06 AM');
    expect(line, 'Pump 20m\u00a0overdue\u00a0· due 8:06\u00a0AM');
  });
}
