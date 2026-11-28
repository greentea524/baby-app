import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:baby_app/features/reminders/feed_prediction.dart';
import 'package:baby_app/features/home/home_status_card.dart';

/// The log icons' "+" badge cuts out against what the icon sits on (#45):
/// the card, or a coloured row's tint. It used the page colour, which left
/// a ring of the wrong colour around it.
void main() {
  Future<Color> groundIn(WidgetTester tester, Widget Function(Widget) wrap) {
    late Color ground;
    return tester
        .pumpWidget(
          MaterialApp(
            theme: ThemeData(
              cardTheme: const CardThemeData(color: Colors.teal),
            ),
            home: wrap(
              Builder(
                builder: (context) {
                  ground = AlertRowMark.groundOf(context);
                  return const SizedBox();
                },
              ),
            ),
          ),
        )
        .then((_) => ground);
  }

  testWidgets('a plain row: the card', (tester) async {
    expect(await groundIn(tester, (c) => c), Colors.teal);
  });

  testWidgets('a coloured row: its tint', (tester) async {
    expect(
      await groundIn(
        tester,
        (c) => AlertRowMark(
          state: DueState.overdue,
          ground: Colors.pink,
          child: c,
        ),
      ),
      Colors.pink,
    );
  });
}
