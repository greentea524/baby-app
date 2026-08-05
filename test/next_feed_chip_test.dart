import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:baby_app/features/home/home_status_card.dart';
import 'package:baby_app/features/reminders/feed_prediction.dart';

/// The chip is the only thing on Home that changes colour on its own, so the
/// three states have to be visibly different from each other — in both themes.
void main() {
  Future<void> pumpChip(
    WidgetTester tester,
    FeedDueState state, {
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
          body: NextFeedChip(state: state, text: 'Next feed in 12m · 2:15 PM'),
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
        of: find.byType(NextFeedChip),
        matching: find.byType(Container),
      ),
    );
    return ((container.decoration as BoxDecoration).color)!;
  }

  IconData icon(WidgetTester tester) =>
      tester.widget<Icon>(find.byType(Icon)).icon!;

  testWidgets('each state gets its own colour', (tester) async {
    final seen = <FeedDueState, Color>{};
    for (final state in FeedDueState.values) {
      await pumpChip(tester, state);
      seen[state] = background(tester);
    }
    expect(
      seen.values.toSet(),
      hasLength(3),
      reason: 'a shared colour would make a state invisible',
    );
  });

  testWidgets('the icon escalates with the state', (tester) async {
    await pumpChip(tester, FeedDueState.upcoming);
    expect(icon(tester), Icons.schedule);

    await pumpChip(tester, FeedDueState.soon);
    expect(icon(tester), Icons.notifications_none);

    await pumpChip(tester, FeedDueState.overdue);
    expect(icon(tester), Icons.notifications_active);
  });

  testWidgets('soon is amber, not the seed colour', (tester) async {
    // The accent picker offers four seeds and Material has no "warning" role,
    // so this colour is fixed rather than derived — a caution that turned pink
    // on the Blush accent would not read as caution.
    await pumpChip(tester, FeedDueState.soon);
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
          body: NextFeedChip(state: FeedDueState.soon, text: 'Next feed'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(background(tester), amber);
  });

  testWidgets('dark mode gets a dark amber, not the light one', (tester) async {
    await pumpChip(tester, FeedDueState.soon);
    final light = background(tester);
    await pumpChip(tester, FeedDueState.soon, brightness: Brightness.dark);
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
      for (final state in FeedDueState.values) {
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
}
