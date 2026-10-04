import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:baby_app/features/common/banded_track.dart';
import 'package:baby_app/features/home/home_status_card.dart';
import 'package:baby_app/features/reminders/feed_prediction.dart';

/// The track that depletes towards the next feed, banded like the fridge's
/// drink-by bar.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpChip(
    WidgetTester tester,
    double? remaining, {
    double? soonFrom,
  }) async {
    tester.view.physicalSize = const Size(400, 200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: DueChip(
              text: 'Next feed in 1h · 5:00 PM',
              state: DueState.upcoming,
              remaining: remaining,
              soonFrom: soonFrom,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder band(int i) => find.byKey(ValueKey('band-$i'));
  double widthOf(WidgetTester tester, Finder f) =>
      f.evaluate().isEmpty ? 0 : tester.getSize(f).width;
  double trackWidth(WidgetTester tester) =>
      tester.getSize(find.byKey(const ValueKey('track'))).width;
  Color colourOf(WidgetTester tester, Finder f) =>
      tester.widget<ColoredBox>(f).color;

  testWidgets('draws nothing without a fraction to draw', (tester) async {
    await pumpChip(tester, null);
    expect(find.byType(BandedTrack), findsNothing);
  });

  testWidgets('is as wide as the time left', (tester) async {
    await pumpChip(tester, 0.5);
    expect(widthOf(tester, band(0)), closeTo(trackWidth(tester) / 2, 1));
    expect(trackWidth(tester), greaterThan(20), reason: 'spans the chip');
  });

  testWidgets('and has real height, rather than painting nothing', (
    tester,
  ) async {
    await pumpChip(tester, 1.0);
    expect(tester.getSize(band(0)).height, greaterThan(0));
  });

  testWidgets('empties when the feed is due', (tester) async {
    await pumpChip(tester, 0.0, soonFrom: 0.1);
    expect(band(0), findsNothing);
    expect(band(1), findsNothing);
  });

  group('banded', () {
    testWidgets('amber for the heads-up stretch, the rest the app colour', (
      tester,
    ) async {
      // With a quarter of the gap left as heads-up, the bar shows how far
      // there is to go before the chip turns amber.
      await pumpChip(tester, 1.0, soonFrom: 0.25);
      final context = tester.element(band(0));
      final inks = warningInks(context);
      final w = trackWidth(tester);

      expect(colourOf(tester, band(0)), inks.soon);
      expect(widthOf(tester, band(0)), closeTo(w * 0.25, 1));
      expect(colourOf(tester, band(1)), inks.ok);
      expect(widthOf(tester, band(1)), closeTo(w * 0.75, 1));
    });

    testWidgets('and once into the heads-up, only amber is left', (
      tester,
    ) async {
      await pumpChip(tester, 0.1, soonFrom: 0.25);
      expect(band(1), findsNothing);
      expect(widthOf(tester, band(0)), closeTo(trackWidth(tester) * 0.1, 1));
    });

    testWidgets('one colour without a heads-up to mark', (tester) async {
      await pumpChip(tester, 0.6);
      final context = tester.element(band(0));
      expect(colourOf(tester, band(0)), warningInks(context).ok);
      expect(band(1), findsNothing);
    });
  });

  group('where the heads-up starts', () {
    test('is the heads-up as a share of the gap', () {
      expect(
        dueSoonShare(
          headsUp: const Duration(minutes: 15),
          interval: const Duration(hours: 3),
        ),
        closeTo(15 / 180, 1e-9),
      );
    });

    test('and is nothing to mark without a gap', () {
      expect(
        dueSoonShare(
          headsUp: const Duration(minutes: 15),
          interval: Duration.zero,
        ),
        isNull,
      );
      // A heads-up longer than the gap is amber all the way.
      expect(
        dueSoonShare(
          headsUp: const Duration(hours: 4),
          interval: const Duration(hours: 3),
        ),
        1,
      );
    });
  });
}
