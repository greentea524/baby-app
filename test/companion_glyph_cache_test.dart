import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:baby_app/core/theme/theme_mode_provider.dart';
import 'package:baby_app/data/models/feeding_event.dart';
import 'package:baby_app/data/repositories/repository_providers.dart';
import 'package:baby_app/features/home/feed_companion.dart';
import 'package:baby_app/features/reminders/reminder_providers.dart';

/// The companion repaints on every frame it animates. Laying out a glyph on
/// each of those frames means a `ui.Paragraph` per frame — native Skia memory
/// left to the garbage collector, sixty times a second, for as long as Home
/// is open. On the web that is a known way to grow a tab until it dies, and
/// it is exactly what this painter used to do.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 8, 10, 12);

  setUp(clearCompanionGlyphCache);

  Future<void> pumpCompanion(
    WidgetTester tester, {
    required String style,
    required DateTime due,
  }) async {
    SharedPreferences.setMockInitialValues({'home_companion_style': style});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          nextFeedDueProvider.overrideWithValue(due),
          lastClockFeedProvider.overrideWithValue(
            FeedingEvent(
              id: 'f',
              type: FeedingType.bottle,
              startTime: now.subtract(const Duration(hours: 1)),
            ),
          ),
        ],
        child: MaterialApp(home: Scaffold(body: FeedCompanion(now: now))),
      ),
    );
    await tester.pump();
  }

  testWidgets('a cruising plane holds its glyph however long it flies', (
    tester,
  ) async {
    await pumpCompanion(
      tester,
      style: 'plane',
      due: now.add(const Duration(hours: 2)),
    );

    final settled = companionGlyphCacheSize;
    expect(settled, greaterThan(0), reason: 'it should have drawn something');

    // Two seconds of animation at 60fps.
    for (var frame = 0; frame < 120; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(
      companionGlyphCacheSize,
      settled,
      reason: 'one glyph per frame would grow this without bound',
    );
  });

  testWidgets('the bottle draining does not mint a glyph per level', (
    tester,
  ) async {
    // The bottle paints twice, and its level moves continuously — the shape
    // most likely to defeat a cache keyed carelessly.
    await pumpCompanion(
      tester,
      style: 'bottle',
      due: now.add(const Duration(hours: 2)),
    );
    final settled = companionGlyphCacheSize;

    for (var frame = 0; frame < 120; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(companionGlyphCacheSize, settled);
  });

  testWidgets('the whole set of styles stays a handful of glyphs', (
    tester,
  ) async {
    // The cache is unbounded, which is only safe because the key space is
    // small. If a style ever keys on something continuous this fails loudly
    // rather than leaking quietly.
    for (final style in ['plane', 'bottle', 'hourglass', 'battery']) {
      for (final due in [
        now.add(const Duration(hours: 2)),
        now.add(const Duration(minutes: 5)),
        now.subtract(const Duration(minutes: 5)),
      ]) {
        await pumpCompanion(tester, style: style, due: due);
        for (var frame = 0; frame < 10; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
      }
    }

    expect(
      companionGlyphCacheSize,
      lessThan(20),
      reason: 'every style and phase in one theme should be a few entries',
    );
  });
}
