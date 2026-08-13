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
      final container = await containerWith({
        'home_companion_style': 'zeppelin',
      });
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

    test('every style tells its phases apart somehow', () {
      // By icon, by fill, or by pose — the bottle keeps one glyph and says
      // everything with its level, so requiring distinct icons would have
      // ruled out the style with the most to say.
      const size = Size(48, 56);
      for (final style in CompanionStyle.values) {
        final art = style.art;
        if (art == null) continue;
        final looks = <String>{};
        for (final phase in CompanionPhase.values) {
          final pose = art.pose(phase, size, celebrate: 0.5);
          final level = art.level(phase, progress: 0.5, celebrate: 0.5);
          looks.add('${art.icon(phase).codePoint}|$pose|$level');
        }
        expect(
          looks.length,
          greaterThan(1),
          reason: '${style.name} looks the same whatever happens',
        );
      }
    });

    test('only the bottle draws a level, and it runs full to empty', () {
      const bottle = BottleArt();
      // Full the moment a feed lands, empty by the time the next is due.
      expect(bottle.level(CompanionPhase.easy, progress: 0, celebrate: 0), 1);
      expect(bottle.level(CompanionPhase.due, progress: 1, celebrate: 0), 0);
      expect(
        bottle.level(CompanionPhase.soon, progress: 0.5, celebrate: 0),
        closeTo(0.5, 0.001),
      );

      for (final art in [
        const PlaneArt(),
        const HourglassArt(),
        const BatteryArt(),
      ]) {
        for (final phase in CompanionPhase.values) {
          expect(art.level(phase, progress: 0.5, celebrate: 0.5), isNull);
        }
      }
    });

    test('the bottle never overfills or goes negative', () {
      // progress is clamped upstream, but an overdue feed pushing past 1 or a
      // clock skew pushing below 0 would otherwise clip outside the glyph.
      const bottle = BottleArt();
      for (final progress in [-0.5, 0.0, 0.5, 1.0, 1.5]) {
        for (final phase in CompanionPhase.values) {
          final level = bottle.level(phase, progress: progress, celebrate: 0.5);
          expect(level, isNotNull);
          expect(level!, inInclusiveRange(0, 1));
        }
      }
    });

    test('the bottle pours back to full when a feed lands', () {
      const bottle = BottleArt();
      final start = bottle.level(
        CompanionPhase.justFed,
        progress: 1,
        celebrate: 0,
      );
      final end = bottle.level(
        CompanionPhase.justFed,
        progress: 1,
        celebrate: 1,
      );
      expect(start, 0, reason: 'starts from empty, whatever the clock says');
      expect(end, 1);
    });

    test('every style poses inside its box, whatever the phase', () {
      const size = Size(48, 56);
      for (final style in CompanionStyle.values) {
        final art = style.art;
        if (art == null) continue;
        for (final phase in CompanionPhase.values) {
          for (final t in [0.0, 0.25, 0.5, 0.75, 1.0]) {
            final pose = art.pose(phase, size, celebrate: t);
            expect(
              pose.at.dx,
              inInclusiveRange(-4, size.width + 4),
              reason: '${style.name} $phase sits outside the slot',
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

    test('nothing but the celebration moves', () {
      // The plane used to fly a loop between feeds, repainting every frame
      // for as long as Home was open — hours at a time — and it was the only
      // style that did. A resting pose now has to be the same pose whatever
      // else is going on, so no style can quietly start animating again.
      const size = Size(48, 56);
      final resting = CompanionPhase.values
          .where((p) => p != CompanionPhase.justFed)
          .toList();
      for (final style in CompanionStyle.values) {
        final art = style.art;
        if (art == null) continue;
        for (final phase in resting) {
          final poses = <CompanionPose>{
            for (final t in [0.0, 0.3, 0.6, 1.0])
              art.pose(phase, size, celebrate: t),
          };
          expect(
            poses,
            hasLength(1),
            reason: '${style.name} $phase moves while resting',
          );
        }
      }
    });

    test('the hourglass turns a full half-circle and lands upright', () {
      const art = HourglassArt();
      const size = Size(48, 56);
      final start = art.pose(CompanionPhase.justFed, size, celebrate: 0);
      final end = art.pose(CompanionPhase.justFed, size, celebrate: 1);
      expect(start.angle, 0);
      expect(end.angle, closeTo(3.14159, 0.001));
    });
  });
}
