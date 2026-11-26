import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:baby_app/core/auth/auth_providers.dart';
import 'package:baby_app/core/theme/theme_mode_provider.dart';
import 'package:baby_app/data/models/baby.dart';
import 'package:baby_app/data/models/care_stay.dart';
import 'package:baby_app/data/models/feeding_event.dart';
import 'package:baby_app/data/models/milk_kind.dart';
import 'package:baby_app/data/repositories/feeding_repository.dart';
import 'package:baby_app/data/repositories/repository_providers.dart';
import 'package:baby_app/features/away/auto_feed.dart';
import 'package:baby_app/features/away/drop_off.dart';

/// Records what would be written, instead of writing it.
class _FakeFeeds implements FeedingRepository {
  _FakeFeeds(List<FeedingEvent> feeds) : _feeds = [...feeds];

  final List<FeedingEvent> _feeds;
  final _stream = StreamController<List<FeedingEvent>>.broadcast();

  /// The feeds as stored, updating as they change.
  Stream<List<FeedingEvent>> watch() async* {
    yield [..._feeds];
    yield* _stream.stream;
  }

  final updated = <FeedingEvent>[];
  final deleted = <String>[];
  final putBackFeeds = <FeedingEvent>[];

  @override
  Future<void> update(FeedingEvent event) async => updated.add(event);

  @override
  Future<void> delete(String id) async {
    deleted.add(id);
    _feeds.removeWhere((f) => f.id == id);
    _stream.add([..._feeds]);
  }

  @override
  Future<void> putBack(FeedingEvent event) async => putBackFeeds.add(event);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Putting right what was logged automatically while the baby was away
/// (#48): the carer's account rarely matches the guess exactly.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime.now();
  DateTime ago(int h) => now.subtract(Duration(hours: h));

  final stay = CareStay(
    id: 's1',
    droppedAt: ago(10),
    pickedUpAt: ago(1),
    carer: 'Grandparents',
    amountMl: 120,
    milk: MilkKind.expressed,
    intervalMinutes: 180,
  );
  FeedingEvent auto(int h) => FeedingEvent(
    id: autoFeedId(stay, ago(h)),
    type: FeedingType.bottle,
    startTime: ago(h),
    amountMl: 120,
    milk: MilkKind.expressed,
    notes: 'Auto-logged · with Grandparents',
  );
  final feeds = [auto(2), auto(5), auto(8)];

  Future<_FakeFeeds> open(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'unit_system': 'metric'});
    final stored = await SharedPreferences.getInstance();
    final fake = _FakeFeeds(feeds);
    tester.view.physicalSize = const Size(500, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(stored),
          authStateProvider.overrideWith((ref) => Stream.value(null)),
          babiesStreamProvider.overrideWith(
            (ref) => Stream.value([
              Baby(
                id: 'b',
                name: 'Ada',
                birthDate: DateTime(2026, 2, 1),
                ownerUid: 'alice',
                members: const {'alice': CaregiverRole.owner},
              ),
            ]),
          ),
          recentFeedingsProvider.overrideWith((ref) => fake.watch()),
          feedingRepositoryProvider.overrideWithValue(fake),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showStaySheet(context, stay),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return fake;
  }

  testWidgets('one amount for every feed', (tester) async {
    // "She had 150 each time."
    final fake = await open(tester);
    expect(find.text('Set all 3 feeds'), findsOneWidget);
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('set-all-amount')),
        matching: find.byType(TextField),
      ),
      '150',
    );
    await tester.tap(find.byKey(const ValueKey('set-all')));
    await tester.pumpAndSettle();

    expect(fake.updated, hasLength(3));
    expect(fake.updated.map((f) => f.amountMl).toSet(), {150});
    // Still the same automatic feeds, at the same times.
    expect(
      fake.updated.map((f) => f.id).toSet(),
      feeds.map((f) => f.id).toSet(),
    );
  });

  testWidgets('a nudge on one', (tester) async {
    // "The last one was a bit more."
    final fake = await open(tester);
    final row = find.byKey(ValueKey('auto-${feeds.first.id}'));
    await tester.tap(
      find.descendant(of: row, matching: find.byTooltip('More')),
    );
    await tester.pumpAndSettle();
    expect(fake.updated.single.id, feeds.first.id);
    expect(fake.updated.single.amountMl, 130);

    await tester.tap(
      find.descendant(of: row, matching: find.byTooltip('Less')),
    );
    await tester.pumpAndSettle();
    expect(fake.updated.last.amountMl, 110);
  });

  testWidgets('one that did not happen, taken out and put back', (
    tester,
  ) async {
    final fake = await open(tester);
    final row = find.byKey(ValueKey('auto-${feeds.last.id}'));
    await tester.tap(
      find.descendant(of: row, matching: find.byTooltip('Did not happen')),
    );
    await tester.pumpAndSettle();
    expect(fake.deleted, [feeds.last.id]);
    // Kept on the sheet, struck through, with its undo where it can be
    // reached.
    final removed = find.byKey(ValueKey('removed-${feeds.last.id}'));
    expect(removed, findsOneWidget);

    await tester.tap(find.descendant(of: removed, matching: find.text('Undo')));
    await tester.pumpAndSettle();
    expect(fake.putBackFeeds.single.id, feeds.last.id);
  });

  testWidgets('and a way to add one given between due times', (tester) async {
    await open(tester);
    expect(find.byKey(const ValueKey('add-away-feed')), findsOneWidget);
  });

  test('a changed amount leaves the feed the same feed', () {
    final changed = withAmount(feeds.first, 90);
    expect(changed.id, feeds.first.id);
    expect(changed.startTime, feeds.first.startTime);
    expect(changed.milk, feeds.first.milk);
    expect(changed.notes, feeds.first.notes);
    expect(changed.amountMl, 90);
  });
}
