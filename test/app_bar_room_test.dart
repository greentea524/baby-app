import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:baby_app/core/layout/app_bar_room.dart';

/// How Home's app bar shares itself out (#29).
///
/// Three things want that bar — the clock, the baby's name, the next
/// appointment — and only the name was flexible, so it absorbed every
/// shortfall. On a 390pt phone it was left with 10pt and "Jonathan" rendered
/// as "J…".
void main() {
  Future<AppBarRoom> roomAt(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 896);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late AppBarRoom room;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            room = AppBarRoom.of(context);
            return const SizedBox();
          },
        ),
      ),
    );
    return room;
  }

  group('the clock', () {
    testWidgets('gives way on a phone, where the name needs the room', (
      tester,
    ) async {
      // And where the operating system is already showing the time a few
      // points above the bar, which is the second reason.
      for (final width in [375.0, 390.0, 414.0, 430.0]) {
        expect(
          (await roomAt(tester, width)).showsClock,
          isFalse,
          reason: 'at $width',
        );
      }
    });

    testWidgets('stays where there is room for both', (tester) async {
      for (final width in [560.0, 640.0, 834.0, 1194.0]) {
        expect(
          (await roomAt(tester, width)).showsClock,
          isTrue,
          reason: 'at $width',
        );
      }
    });

    testWidgets('is decided by width, not by platform', (tester) async {
      // Which gets three cases right for nothing: a narrow browser window, a
      // phone on its side, and an iPad sharing the screen.
      expect((await roomAt(tester, 480)).showsClock, isFalse);
      expect((await roomAt(tester, 700)).showsClock, isTrue);
    });
  });

  group('the bar itself', () {
    testWidgets('never measures wider than the content cap', (tester) async {
      // Above 640 the cap decides the bar, not the screen — which is why a
      // desktop window behaves the same at 1440 as at 640.
      expect(
        (await roomAt(tester, 1440)).width,
        (await roomAt(tester, 640)).width,
      );
    });

    testWidgets('leaves the name its floor at every width', (tester) async {
      // The property that stops this recurring: whatever else is in the bar,
      // the name keeps a readable share.
      for (final width in [375.0, 430.0, 560.0, 640.0]) {
        final room = await roomAt(tester, width);
        final forName =
            room.width -
            (room.showsClock ? AppBarRoom.clockWidth : 0) -
            room.appointmentWidth -
            AppBarRoom.barPadding;
        expect(
          forName,
          greaterThanOrEqualTo(AppBarRoom.nameFloor),
          reason: 'at $width',
        );
      }
    });

    testWidgets('shrinks the appointment on a narrow bar', (tester) async {
      // A share rather than a fixed 220, so the appointment gives way too
      // instead of the name being the only thing that does.
      expect((await roomAt(tester, 390)).appointmentWidth, lessThan(220));
      expect((await roomAt(tester, 640)).appointmentWidth, 220);
    });
  });
}
