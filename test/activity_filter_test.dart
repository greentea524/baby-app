import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:baby_app/data/models/activity_entry.dart';
import 'package:baby_app/data/models/diaper_event.dart';
import 'package:baby_app/data/models/feeding_event.dart';
import 'package:baby_app/data/models/pumping_event.dart';
import 'package:baby_app/features/home/activity_filter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final base = DateTime(2026, 7, 30, 8);

  FeedingEntry feed(int hour) => FeedingEntry(
    FeedingEvent(
      id: 'f$hour',
      type: FeedingType.bottle,
      startTime: base.add(Duration(hours: hour)),
    ),
  );

  DiaperEntry diaper(int hour) => DiaperEntry(
    DiaperEvent(
      id: 'd$hour',
      type: DiaperType.wet,
      time: base.add(Duration(hours: hour)),
    ),
  );

  PumpingEntry pump(int hour) => PumpingEntry(
    PumpingEvent(id: 'p$hour', time: base.add(Duration(hours: hour))),
  );

  final entries = <ActivityEntry>[feed(1), diaper(2), pump(3), feed(4)];

  group('applyActivityFilter', () {
    test('all keeps everything', () {
      expect(applyActivityFilter(entries, ActivityFilter.all), entries);
    });

    test('feeds keeps only feedings', () {
      final got = applyActivityFilter(entries, ActivityFilter.feeds);
      expect(got.length, 2);
      expect(got.every((e) => e is FeedingEntry), isTrue);
    });

    test('diapers keeps only diapers', () {
      final got = applyActivityFilter(entries, ActivityFilter.diapers);
      expect(got.length, 1);
      expect(got.single, isA<DiaperEntry>());
    });

    test('pumping keeps only pump sessions', () {
      final got = applyActivityFilter(entries, ActivityFilter.pumps);
      expect(got.single, isA<PumpingEntry>());
    });

    test('preserves the incoming order', () {
      final got = applyActivityFilter(entries, ActivityFilter.feeds);
      expect(got.first.time.isBefore(got.last.time), isTrue);
    });

    test('an empty match is empty, not everything', () {
      final onlyFeeds = <ActivityEntry>[feed(1), feed(2)];
      expect(applyActivityFilter(onlyFeeds, ActivityFilter.diapers), isEmpty);
    });

    test('every filter has a label and an icon', () {
      for (final f in ActivityFilter.values) {
        expect(f.label, isNotEmpty);
        expect(f.icon, isNotNull);
      }
    });
  });

  group('ActivityFilterBar', () {
    Future<ProviderContainer> pumpBar(WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: Scaffold(body: ActivityFilterBar())),
        ),
      );
      return ProviderScope.containerOf(
        tester.element(find.byType(ActivityFilterBar)),
      );
    }

    testWidgets('shows a chip per filter and starts on All', (tester) async {
      final container = await pumpBar(tester);
      for (final f in ActivityFilter.values) {
        expect(find.text(f.label), findsOneWidget);
      }
      expect(container.read(activityFilterProvider), ActivityFilter.all);
    });

    testWidgets('tapping a chip selects that filter', (tester) async {
      final container = await pumpBar(tester);
      await tester.tap(find.text('Diapers'));
      await tester.pump();
      expect(container.read(activityFilterProvider), ActivityFilter.diapers);
    });

    testWidgets('re-tapping the active chip clears back to All', (
      tester,
    ) async {
      final container = await pumpBar(tester);
      await tester.tap(find.text('Feeds'));
      await tester.pump();
      expect(container.read(activityFilterProvider), ActivityFilter.feeds);

      await tester.tap(find.text('Feeds'));
      await tester.pump();
      expect(container.read(activityFilterProvider), ActivityFilter.all);
    });
  });
}
