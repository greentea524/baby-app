import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:baby_app/core/auth/auth_providers.dart';
import 'package:baby_app/core/theme/theme_mode_provider.dart';
import 'package:baby_app/data/models/baby.dart';
import 'package:baby_app/data/models/daily_check.dart';
import 'package:baby_app/data/repositories/checks_repository.dart';
import 'package:baby_app/data/repositories/repository_providers.dart';
import 'package:baby_app/features/checklist/checklist_day_sheet.dart';
import 'package:baby_app/features/checklist/checklist_months.dart';
import 'package:baby_app/features/checklist/daily_checklist.dart';

/// Putting a past day right from the calendar: the bath that was given and
/// never ticked.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 11, 3, 15, 20);
  const bath = ChecklistItem(id: 'bath', label: 'Bath');
  const drops = ChecklistItem(id: 'drops', label: 'Drops', perDay: 3);
  const tummy = ChecklistItem(
    id: 'tummy-time',
    label: 'Tummy time',
    minutes: 30,
  );

  DailyCheck on(String item, DateTime time, {String? id, int? minutes}) =>
      DailyCheck(
        id: id ?? '$item-${time.toIso8601String()}',
        itemId: item,
        time: time,
        minutes: minutes,
      );

  Future<_RecordingChecks> pump(
    WidgetTester tester,
    Widget child, {
    List<DailyCheck> checks = const [],
  }) async {
    SharedPreferences.setMockInitialValues({});
    final stored = await SharedPreferences.getInstance();
    final repo = _RecordingChecks();
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(stored),
          authStateProvider.overrideWith((ref) => Stream.value(null)),
          currentBabyProvider.overrideWithValue(
            Baby(
              id: 'b',
              name: 'Ada',
              birthDate: DateTime(2026, 7, 1),
              ownerUid: 'a',
              members: const {'a': CaregiverRole.owner},
              checklist: const [bath, drops, tummy],
            ),
          ),
          checksRepositoryProvider.overrideWithValue(repo),
          checksSinceProvider.overrideWith(
            (ref, start) => Stream.value(checks),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return repo;
  }

  final oct20 = DateTime(2026, 10, 20);

  testWidgets('ticks a forgotten bath, dated that day at noon', (tester) async {
    final repo = await pump(tester, ChecklistDaySheet(day: oct20, now: now));
    expect(find.text('Tuesday, October 20, 2026'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('day-status-bath'))).data,
      'Not done',
    );

    await tester.tap(find.byKey(const ValueKey('day-switch-bath')));
    await tester.pump();
    final added = repo.added.single;
    expect(added.itemId, 'bath');
    expect(added.time, DateTime(2026, 10, 20, 12));
  });

  testWidgets('and unticks one ticked by mistake, every tick of it', (
    tester,
  ) async {
    final repo = await pump(
      tester,
      ChecklistDaySheet(day: oct20, now: now),
      checks: [
        on('bath', DateTime(2026, 10, 20, 19), id: 'b1'),
        on('bath', DateTime(2026, 10, 20, 19, 1), id: 'b2'),
        // Another day's: left alone.
        on('bath', DateTime(2026, 10, 21, 19), id: 'b3'),
      ],
    );
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('day-status-bath'))).data,
      'Done',
    );
    await tester.tap(find.byKey(const ValueKey('day-switch-bath')));
    await tester.pump();
    expect(repo.deleted, unorderedEquals(['b1', 'b2']));
  });

  testWidgets('counts one more, or one fewer, up to the goal', (tester) async {
    final repo = await pump(
      tester,
      ChecklistDaySheet(day: oct20, now: now),
      checks: [
        on('drops', DateTime(2026, 10, 20, 8), id: 'd1'),
        on('drops', DateTime(2026, 10, 20, 14), id: 'd2'),
      ],
    );
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('day-status-drops'))).data,
      '2 of 3',
    );
    await tester.tap(find.byTooltip('One more'));
    await tester.pump();
    expect(repo.added.single.itemId, 'drops');

    await tester.tap(find.byTooltip('One fewer'));
    await tester.pump();
    // The latest of the day goes first.
    expect(repo.deleted, ['d2']);
  });

  testWidgets('adds minutes to a timed one, and takes the last back', (
    tester,
  ) async {
    final repo = await pump(
      tester,
      ChecklistDaySheet(day: oct20, now: now),
      checks: [
        on('tummy-time', DateTime(2026, 10, 20, 9), id: 't1', minutes: 10),
      ],
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('day-status-tummy-time')))
          .data,
      '10 min of 30 min',
    );
    await tester.tap(find.byKey(const ValueKey('day-add-tummy-time-10')));
    await tester.pump();
    expect(repo.added.single.minutes, 10);
    expect(repo.added.single.time, DateTime(2026, 10, 20, 12));

    await tester.tap(find.byTooltip('Take the last one back'));
    await tester.pump();
    expect(repo.deleted, ['t1']);
  });

  testWidgets('today is dated now, not at noon', (tester) async {
    final repo = await pump(
      tester,
      ChecklistDaySheet(day: DateTime(2026, 11, 3), now: now),
    );
    expect(find.text('Today'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('day-switch-bath')));
    await tester.pump();
    expect(repo.added.single.time, now);
  });

  group('from the calendar', () {
    testWidgets('a day gone by opens', (tester) async {
      DateTime? opened;
      await pump(
        tester,
        ChecklistMonths(
          items: const [bath],
          checks: const [],
          now: now,
          onDay: (day) => opened = day,
        ),
      );
      expect(find.text('Tap a day to put it right.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('day-2026-10-20-none')));
      expect(opened, DateTime(2026, 10, 20));
    });

    testWidgets('a day still to come does not', (tester) async {
      DateTime? opened;
      await pump(
        tester,
        ChecklistMonths(
          items: const [bath],
          checks: const [],
          now: now,
          onDay: (day) => opened = day,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('day-2026-11-20-none')));
      expect(opened, isNull);
    });

    testWidgets('and the streaks sheet opens it over itself', (tester) async {
      await pump(tester, ChecklistStreaks(now: now));
      await tester.tap(find.byKey(const ValueKey('day-2026-10-20-none')));
      await tester.pumpAndSettle();
      expect(find.text('Tuesday, October 20, 2026'), findsOneWidget);
      expect(find.text('Put right what was done this day.'), findsOneWidget);
    });
  });
}

class _RecordingChecks extends ChecksRepository {
  _RecordingChecks() : super(_NoFirestore(), 'b', 'a');

  final added = <DailyCheck>[];
  final deleted = <String>[];

  @override
  ({String id, Future<void> written}) addNow(DailyCheck event) {
    added.add(event);
    return (id: 'new-${added.length}', written: Future.value());
  }

  @override
  Future<void> delete(String id) async => deleted.add(id);
}

class _NoFirestore implements FirebaseFirestore {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
