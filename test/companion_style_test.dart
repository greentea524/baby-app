import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:baby_app/core/theme/theme_mode_provider.dart';
import 'package:baby_app/features/home/companion_art.dart';
import 'package:baby_app/features/home/home_prefs.dart';
import 'package:baby_app/features/reminders/feed_prediction.dart';

/// Picking a companion, and carrying an existing choice across from the
/// on/off switch this setting used to be (#16).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> containerWith(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('the stored choice', () {
    test('defaults to the plane', () async {
      final container = await containerWith({});
      expect(container.read(companionStyleProvider), CompanionStyle.plane);
    });

    test('is read back', () async {
      final container = await containerWith({
        'home_companion_style': 'hourglass',
      });
      expect(container.read(companionStyleProvider), CompanionStyle.hourglass);
    });

    test('survives a round trip', () async {
      final container = await containerWith({});
      await container
          .read(companionStyleProvider.notifier)
          .setStyle(CompanionStyle.battery);

      expect(container.read(companionStyleProvider), CompanionStyle.battery);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('home_companion_style'), 'battery');
    });

    test('falls back to the plane on a value it does not know', () async {
      // A style removed in a later version, or a hand-edited preference.
      final container = await containerWith({'home_companion_style': 'zeppelin'});
      expect(container.read(companionStyleProvider), CompanionStyle.plane);
    });
  });

  group('migrating from the old switch', () {
    test('someone who turned the plane off keeps it off', () async {
      // The whole point of the migration: without it, everyone who had
      // switched the plane off would find it handed back.
      final container = await containerWith({'show_feed_plane': false});
      expect(container.read(companionStyleProvider), CompanionStyle.off);
    });

    test('someone who kept the plane keeps the plane', () async {
      final container = await containerWith({'show_feed_plane': true});
      expect(container.read(companionStyleProvider), CompanionStyle.plane);
    });

    test('a new style wins over the old switch', () async {
      // Once a style is chosen, the legacy key is history.
      final container = await containerWith({
        'show_feed_plane': false,
        'home_companion_style': 'battery',
      });
      expect(container.read(companionStyleProvider), CompanionStyle.battery);
    });

    test('choosing a style stops the old switch mattering', () async {
      final container = await containerWith({'show_feed_plane': false});
      await container
          .read(companionStyleProvider.notifier)
          .setStyle(CompanionStyle.plane);

      final again = await SharedPreferences.getInstance();
      final fresh = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(again)],
      );
      addTearDown(fresh.dispose);
      expect(fresh.read(companionStyleProvider), CompanionStyle.plane);
    });
  });

  group('the styles themselves', () {
    test('off is the only one without art', () {
      expect(CompanionStyle.off.art, isNull);
      for (final style in CompanionStyle.values) {
        if (style == CompanionStyle.off) continue;
        expect(style.art, isNotNull, reason: '${style.name} needs art');
      }
    });

    test('every style has a distinct glyph for every phase', () {
      // Two phases sharing an icon is allowed — the plane lands and waits in
      // the same pose — but a style whose four phases are all one icon says
      // nothing at all.
      for (final style in CompanionStyle.values) {
        final art = style.art;
        if (art == null) continue;
        final icons = {
          for (final phase in CompanionPhase.values) art.icon(phase),
        };
        expect(
          icons.length,
          greaterThan(1),
          reason: '${style.name} draws the same thing whatever happens',
        );
      }
    });

    test('every style poses inside its box, whatever the phase', () {
      const size = Size(48, 56);
      for (final style in CompanionStyle.values) {
        final art = style.art;
        if (art == null) continue;
        for (final phase in CompanionPhase.values) {
          for (final t in [0.0, 0.25, 0.5, 0.75, 1.0]) {
            final pose = art.pose(phase, size, drift: t, celebrate: t);
            expect(
              pose.at.dx,
              inInclusiveRange(-4, size.width + 4),
              reason: '${style.name} $phase drifts out of the slot',
            );
            expect(pose.at.dy, inInclusiveRange(-4, size.height + 4));
            expect(pose.opacity, inInclusiveRange(0, 1));
          }
        }
      }
    });

    test('phases map one-to-one onto the chip states', () {
      expect(phaseFor(FeedDueState.upcoming), CompanionPhase.easy);
      expect(phaseFor(FeedDueState.soon), CompanionPhase.soon);
      expect(phaseFor(FeedDueState.overdue), CompanionPhase.due);
    });

    test('only the plane draws ground, and not while airborne', () {
      expect(const PlaneArt().ground(CompanionPhase.easy), isFalse);
      expect(const PlaneArt().ground(CompanionPhase.due), isTrue);
      for (final art in [const HourglassArt(), const BatteryArt()]) {
        for (final phase in CompanionPhase.values) {
          expect(art.ground(phase), isFalse);
        }
      }
    });

    test('the still styles do not ask for a loop', () {
      // An idle loop repaints for as long as Home is open, so a style that
      // holds still should not be running one.
      for (final art in [const HourglassArt(), const BatteryArt()]) {
        for (final phase in CompanionPhase.values) {
          expect(art.idles(phase), isFalse);
        }
      }
      expect(const PlaneArt().idles(CompanionPhase.easy), isTrue);
      expect(const PlaneArt().idles(CompanionPhase.due), isFalse);
    });

    test('the hourglass turns a full half-circle and lands upright', () {
      const art = HourglassArt();
      const size = Size(48, 56);
      final start = art.pose(
        CompanionPhase.justFed,
        size,
        drift: 0,
        celebrate: 0,
      );
      final end = art.pose(
        CompanionPhase.justFed,
        size,
        drift: 0,
        celebrate: 1,
      );
      expect(start.angle, 0);
      expect(end.angle, closeTo(3.14159, 0.001));
    });
  });
}
