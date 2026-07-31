import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:baby_app/data/models/activity_entry.dart';
import 'package:baby_app/data/models/diaper_event.dart';
import 'package:baby_app/data/models/feeding_event.dart';
import 'package:baby_app/data/models/pumping_event.dart';
import 'package:baby_app/features/activity/activity_filter.dart';
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

    test('preserves newest-first order too', () {
      // Home merges descending, the Timeline ascending — filtering must not
      // impose an order of its own on either.
      final descending = <ActivityEntry>[feed(4), pump(3), diaper(2), feed(1)];
      final got = applyActivityFilter(descending, ActivityFilter.feeds);
      expect(got.first.time.isAfter(got.last.time), isTrue);
    });

    test('All short-circuits, so it never reaches an empty-filter state', () {
      // The Timeline distinguishes "empty day" from "nothing of this kind";
      // that second message would read "No all on this day." if All could ever
      // filter something out.
      expect(
        applyActivityFilter(entries, ActivityFilter.all),
        same(entries),
      );
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

    testWidgets('the choice is shared across surfaces', (tester) async {
      // Home and the Timeline are the same data at two sizes — Home links to
      // the timeline as "see all" — so a filter picked on one applies to the
      // other rather than each keeping its own.
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  ActivityFilterBar(key: Key('home')),
                  ActivityFilterBar(key: Key('timeline')),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('home')),
          matching: find.text('Diapers'),
        ),
      );
      await tester.pump();

      final container = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('timeline'))),
      );
      expect(container.read(activityFilterProvider), ActivityFilter.diapers);
    });
  });
}
