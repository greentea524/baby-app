import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:baby_app/core/auth/auth_providers.dart';
import 'package:baby_app/core/theme/theme_mode_provider.dart';
import 'package:baby_app/data/models/activity_entry.dart';
import 'package:baby_app/data/models/baby.dart';
import 'package:baby_app/data/models/daily_check.dart';
import 'package:baby_app/data/repositories/babies_repository.dart';
import 'package:baby_app/data/repositories/checks_repository.dart';
import 'package:baby_app/data/repositories/repository_providers.dart';
import 'package:baby_app/features/activity/activity_tile.dart';
import 'package:baby_app/features/checklist/checklist_logic.dart';
import 'package:baby_app/features/checklist/checklist_settings_screen.dart';
import 'package:baby_app/features/checklist/daily_checklist.dart';
import 'package:baby_app/features/checklist/timed_item_sheet.dart';

/// The daily checklist: ticking things off on Home, and the streaks.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 10, 24, 15);
  const vitamin = ChecklistItem(
    id: 'vitamin-d',
    label: 'Vitamin D',
    icon: ChecklistIcon.vitamin,
  );
  const bath = ChecklistItem(
    id: 'bath',
    label: 'Bath',
    icon: ChecklistIcon.bath,
  );

  DailyCheck tick(
    String itemId,
    DateTime time, {
    String id = '',
    String? byName,
  }) => DailyCheck(
    id: id.isEmpty ? '$itemId-${time.toIso8601String()}' : id,
    itemId: itemId,
    time: time,
    byName: byName,
  );

  /// The tick for [itemId] [n] days back, at nine in the morning.
  DailyCheck daysAgo(String itemId, int n) =>
      tick(itemId, DateTime(now.year, now.month, now.day - n, 9));

  group('the day', () {
    test('counts the first tick of each item today', () {
      final early = tick('vitamin-d', DateTime(2026, 10, 24, 8));
      final late = tick('vitamin-d', DateTime(2026, 10, 24, 9));
      final done = ticksOn([
        late,
        early,
        tick('bath', DateTime(2026, 10, 23, 19)),
      ], now);
      expect(done.keys, ['vitamin-d']);
      expect(done['vitamin-d'], same(early));
    });

    test('starts fresh at midnight', () {
      final done = ticksOn([
        tick('vitamin-d', DateTime(2026, 10, 23, 23, 59)),
      ], now);
      expect(done, isEmpty);
    });

    test('unticking finds every tick of the item that day', () {
      final checks = [
        tick('vitamin-d', DateTime(2026, 10, 24, 8)),
        tick('vitamin-d', DateTime(2026, 10, 24, 8, 1)),
        tick('vitamin-d', DateTime(2026, 10, 23, 8)),
        tick('bath', DateTime(2026, 10, 24, 8)),
      ];
      expect(ticksOf(checks, 'vitamin-d', now), hasLength(2));
    });
  });

  /// An item to measure against: counted, or timed when given [minutes].
  ChecklistItem item(String id, {int perDay = 1, int? minutes}) =>
      ChecklistItem(id: id, label: id, perDay: perDay, minutes: minutes);

  group('a streak', () {
    test('counts days in a row up to today', () {
      final checks = [for (var n = 0; n < 5; n++) daysAgo('vitamin-d', n)];
      expect(streak(checks, item('vitamin-d'), now), 5);
    });

    test('is not broken by today not being done yet', () {
      final checks = [for (var n = 1; n <= 3; n++) daysAgo('vitamin-d', n)];
      expect(streak(checks, item('vitamin-d'), now), 3);
    });

    test('starts again after a missed day', () {
      final checks = [
        daysAgo('vitamin-d', 0),
        daysAgo('vitamin-d', 1),
        daysAgo('vitamin-d', 3),
        daysAgo('vitamin-d', 4),
      ];
      expect(streak(checks, item('vitamin-d'), now), 2);
      expect(streak([daysAgo('vitamin-d', 2)], item('vitamin-d'), now), 0);
    });

    test('counts a day once however many ticks it has', () {
      final checks = [
        daysAgo('vitamin-d', 0),
        tick('vitamin-d', DateTime(2026, 10, 24, 10)),
      ];
      expect(streak(checks, item('vitamin-d'), now), 1);
    });

    test('runs across the end of a month', () {
      final first = DateTime(2026, 11, 1, 9);
      final checks = [
        tick('bath', first),
        tick('bath', DateTime(2026, 10, 31, 9)),
        tick('bath', DateTime(2026, 10, 30, 9)),
      ];
      expect(streak(checks, item('bath'), first), 3);
    });

    test('and the week ends today, oldest first', () {
      final week = recentDays(
        [daysAgo('bath', 0), daysAgo('bath', 6), daysAgo('bath', 7)],
        item('bath'),
        now,
      );
      expect(week, [1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0]);
    });

    test('done several times a day, counts only the days all were done', () {
      final checks = [
        // Today, two of three so far: not done yet, but not a break either.
        daysAgo('tummy-time', 0),
        daysAgo('tummy-time', 0),
        for (var i = 0; i < 3; i++) daysAgo('tummy-time', 1),
        for (var i = 0; i < 3; i++) daysAgo('tummy-time', 2),
        // Short: ends the run.
        daysAgo('tummy-time', 3),
      ];
      expect(streak(checks, item('tummy-time', perDay: 3), now), 2);
      expect(recentDays(checks, item('tummy-time', perDay: 3), now, count: 4), [
        closeTo(1 / 3, 1e-9),
        1.0,
        1.0,
        closeTo(2 / 3, 1e-9),
      ]);
    });

    test('a day done more than asked is still just done', () {
      final checks = [for (var i = 0; i < 4; i++) daysAgo('bath', 0)];
      expect(recentDays(checks, item('bath'), now, count: 1), [1.0]);
    });

    test('counts every tick of the day, of items on the list', () {
      final progress = progressOn(
        [
          daysAgo('tummy-time', 0),
          daysAgo('tummy-time', 0),
          daysAgo('tummy-time', 1),
          daysAgo('bath', 0),
          daysAgo('gone', 0),
        ],
        [item('tummy-time', perDay: 3), item('bath')],
        now,
      );
      expect(progress, {'tummy-time': 2, 'bath': 1});
    });

    test('a timed item adds up minutes, not ticks', () {
      DailyCheck session(int daysAgo, int minutes) => DailyCheck(
        id: 's$daysAgo-$minutes',
        itemId: 'tummy-time',
        time: DateTime(now.year, now.month, now.day - daysAgo, 9),
        minutes: minutes,
      );
      final tummy = item('tummy-time', minutes: 30);
      final checks = [
        session(0, 10),
        session(0, 5),
        session(1, 20),
        session(1, 15),
        session(2, 30),
        session(3, 25),
      ];
      expect(progressOn(checks, [tummy], now), {'tummy-time': 15});
      expect(streak(checks, tummy, now), 2);
      expect(recentDays(checks, tummy, now, count: 4), [
        closeTo(25 / 30, 1e-9),
        1.0,
        1.0,
        0.5,
      ]);
    });

    test('reads out plainly', () {
      expect(streakLabel(0), 'No streak yet');
      expect(streakLabel(1), '1 day');
      expect(streakLabel(12), '12 days in a row');
    });
  });

  group('an item', () {
    test('survives the round trip, and an icon this build does not know', () {
      expect(ChecklistItem.fromMap(vitamin.toMap()), vitamin);
      expect(
        ChecklistItem.fromMap({'id': 'x', 'label': 'X', 'icon': 'rocket'}).icon,
        ChecklistIcon.other,
      );
    });

    test('is once a day unless it says otherwise', () {
      expect(ChecklistItem.fromMap({'id': 'x', 'label': 'X'}).perDay, 1);
      expect(
        ChecklistItem.fromMap({'id': 'x', 'label': 'X', 'perDay': 99}).perDay,
        ChecklistItem.maxPerDay,
      );
      const tummy = ChecklistItem(id: 't', label: 'Tummy time', perDay: 5);
      expect(ChecklistItem.fromMap(tummy.toMap()), tummy);
    });
  });

  Baby baby(List<ChecklistItem> checklist) => Baby(
    id: 'baby1',
    name: 'Ada',
    birthDate: DateTime(2026, 7, 1),
    ownerUid: 'alice',
    members: const {'alice': CaregiverRole.owner},
    checklist: checklist,
  );

  Future<_RecordingChecks> pumpCard(
    WidgetTester tester, {
    List<ChecklistItem> items = const [vitamin, bath],
    List<DailyCheck> checks = const [],
    double textScale = 1,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final stored = await SharedPreferences.getInstance();
    final repo = _RecordingChecks();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(stored),
          authStateProvider.overrideWith((ref) => Stream.value(null)),
          currentBabyProvider.overrideWithValue(baby(items)),
          checksRepositoryProvider.overrideWithValue(repo),
          checksSinceProvider.overrideWith(
            (ref, start) => Stream.value([
              for (final c in checks)
                if (!c.time.isBefore(start)) c,
            ]),
          ),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Scaffold(
            body: ListView(children: [DailyChecklistCard(now: now)]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return repo;
  }

  group('on Home', () {
    testWidgets('is not there until something is on the list', (tester) async {
      await pumpCard(tester, items: const []);
      expect(find.byType(Card), findsNothing);
    });

    testWidgets('shows each item, and how many are done', (tester) async {
      await pumpCard(tester, checks: [daysAgo('vitamin-d', 0)]);
      expect(find.text('Vitamin D'), findsOneWidget);
      expect(find.text('Bath'), findsOneWidget);
      expect(find.text('DAILY · 1 OF 2'), findsOneWidget);
      final chip = tester.widget<FilterChip>(
        find.byKey(const ValueKey('check-vitamin-d')),
      );
      expect(chip.selected, isTrue);
      expect(
        tester
            .widget<FilterChip>(find.byKey(const ValueKey('check-bath')))
            .selected,
        isFalse,
      );
    });

    testWidgets('says so once everything is done', (tester) async {
      await pumpCard(
        tester,
        checks: [daysAgo('vitamin-d', 0), daysAgo('bath', 0)],
      );
      expect(find.text('DAILY · ALL DONE TODAY'), findsOneWidget);
    });

    testWidgets('yesterday\'s ticks do not count today', (tester) async {
      await pumpCard(tester, checks: [daysAgo('vitamin-d', 1)]);
      expect(find.text('DAILY · 0 OF 2'), findsOneWidget);
    });

    testWidgets('one tap ticks it, with an undo', (tester) async {
      final repo = await pumpCard(tester);
      await tester.tap(find.text('Bath'));
      await tester.pumpAndSettle();

      expect(repo.added.single.itemId, 'bath');
      // Its name goes with it, for the activity log.
      expect(repo.added.single.label, 'Bath');
      expect(find.text('Bath done'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pump();
      expect(repo.deleted, ['new-1']);
    });

    testWidgets('a ticked item says when and by whom, and can be unticked', (
      tester,
    ) async {
      final repo = await pumpCard(
        tester,
        checks: [
          tick(
            'vitamin-d',
            DateTime(2026, 10, 24, 9, 12),
            id: 'c1',
            byName: 'Sam',
          ),
          // Both caregivers ticked it: unticking takes both.
          tick('vitamin-d', DateTime(2026, 10, 24, 9, 13), id: 'c2'),
        ],
      );
      await tester.tap(find.text('Vitamin D'));
      await tester.pumpAndSettle();

      expect(find.text('Done 9:12 AM by Sam'), findsOneWidget);
      expect(repo.added, isEmpty, reason: 'tapping a ticked item reads it');

      await tester.tap(find.text('Not done — untick it'));
      await tester.pumpAndSettle();
      expect(repo.deleted, unorderedEquals(['c1', 'c2']));
    });

    group('done several times a day', () {
      const tummy = ChecklistItem(
        id: 'tummy-time',
        label: 'Tummy time',
        icon: ChecklistIcon.tummyTime,
        perDay: 5,
      );
      List<DailyCheck> sessions(int n) => [
        for (var i = 0; i < n; i++)
          tick('tummy-time', DateTime(2026, 10, 24, 8 + i), id: 's$i'),
      ];

      testWidgets('shows how far along it is', (tester) async {
        await pumpCard(tester, items: const [tummy], checks: sessions(2));
        expect(find.text('Tummy time 2/5'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('progress-tummy-time')),
          findsOneWidget,
        );
        expect(
          tester
              .widget<FilterChip>(
                find.byKey(const ValueKey('check-tummy-time')),
              )
              .selected,
          isFalse,
        );
        // Part done is not done.
        expect(find.text('DAILY · 0 OF 1'), findsOneWidget);
      });

      testWidgets('each tap adds one, and says which', (tester) async {
        final repo = await pumpCard(
          tester,
          items: const [tummy],
          checks: sessions(2),
        );
        await tester.tap(find.text('Tummy time 2/5'));
        await tester.pumpAndSettle();
        expect(repo.added.single.itemId, 'tummy-time');
        expect(find.text('Tummy time 3 of 5'), findsOneWidget);
      });

      testWidgets('is ticked once they are all in', (tester) async {
        final repo = await pumpCard(
          tester,
          items: const [tummy],
          checks: sessions(5),
        );
        expect(find.text('DAILY · ALL DONE TODAY'), findsOneWidget);
        expect(
          tester
              .widget<FilterChip>(
                find.byKey(const ValueKey('check-tummy-time')),
              )
              .selected,
          isTrue,
        );

        // Done, a tap reads rather than adding a sixth.
        await tester.tap(find.text('Tummy time 5/5'));
        await tester.pumpAndSettle();
        expect(repo.added, isEmpty);
        expect(find.text('All 5 done today'), findsOneWidget);
      });

      testWidgets('a long press lists them, and takes the last one back', (
        tester,
      ) async {
        final repo = await pumpCard(
          tester,
          items: const [tummy],
          checks: sessions(2),
        );
        await tester.longPress(find.text('Tummy time 2/5'));
        await tester.pumpAndSettle();
        expect(find.text('2 of 5 today'), findsOneWidget);
        expect(find.textContaining('1. 8:00 AM'), findsOneWidget);
        expect(find.textContaining('2. 9:00 AM'), findsOneWidget);

        await tester.tap(find.text('Take the last one back'));
        await tester.pumpAndSettle();
        expect(repo.deleted, ['s1']);
        expect(repo.added, isEmpty);
      });
    });

    testWidgets('opens the streaks', (tester) async {
      await pumpCard(
        tester,
        checks: [for (var n = 0; n < 12; n++) daysAgo('vitamin-d', n)],
      );
      await tester.tap(find.byTooltip('Streaks'));
      await tester.pumpAndSettle();

      expect(find.text('12 days in a row'), findsOneWidget);
      expect(find.text('No streak yet'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Done 7 of the last 7 days'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Done 0 of the last 7 days'),
        findsOneWidget,
      );
    });

    testWidgets('fits a small phone at a large text size', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpCard(
        tester,
        items: checklistPresets,
        checks: [daysAgo('vitamin-d', 0)],
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('in Settings, how many times a day', () {
    Future<_RecordingBabies> pump(
      WidgetTester tester,
      List<ChecklistItem> items,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final stored = await SharedPreferences.getInstance();
      final repo = _RecordingBabies();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(stored),
            authStateProvider.overrideWith((ref) => Stream.value(null)),
            currentBabyProvider.overrideWithValue(baby(items)),
            babiesRepositoryProvider.overrideWithValue(repo),
          ],
          child: const MaterialApp(home: ChecklistSettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      return repo;
    }

    testWidgets('is set on an item, keeping its id', (tester) async {
      final repo = await pump(tester, const [
        ChecklistItem(id: 'tummy-time', label: 'Tummy time'),
      ]);
      await tester.tap(find.text('Tummy time'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byTooltip('More'));
        await tester.pump();
      }
      expect(find.text('5'), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final saved = repo.saved.single.single;
      expect(saved.id, 'tummy-time');
      expect(saved.perDay, 5);
      expect(find.text('5 times a day'), findsOneWidget);
    });

    testWidgets('the ready-made tummy time asks for thirty minutes', (
      tester,
    ) async {
      final repo = await pump(tester, const []);
      await tester.tap(find.byKey(const ValueKey('add-tummy-time')));
      await tester.pumpAndSettle();
      expect(repo.saved.single.single.minutes, 30);
    });

    testWidgets('or minutes, set on an item', (tester) async {
      final repo = await pump(tester, const [
        ChecklistItem(id: 'tummy-time', label: 'Tummy time', perDay: 5),
      ]);
      await tester.tap(find.text('Tummy time'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Minutes'));
      await tester.pumpAndSettle();
      // Starts at thirty, in fives.
      expect(find.text('30'), findsOneWidget);
      await tester.tap(find.byTooltip('More'));
      await tester.pump();
      expect(find.text('35'), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final saved = repo.saved.single.single;
      expect(saved.id, 'tummy-time');
      expect(saved.minutes, 35);
      expect(saved.goal, 35);
      expect(find.text('35 min a day'), findsOneWidget);
    });
  });

  group('timed', () {
    const tummy = ChecklistItem(
      id: 'tummy-time',
      label: 'Tummy time',
      icon: ChecklistIcon.tummyTime,
      minutes: 30,
    );
    DailyCheck session(String id, int hour, int minutes) => DailyCheck(
      id: id,
      itemId: 'tummy-time',
      time: DateTime(2026, 10, 24, hour),
      minutes: minutes,
    );

    testWidgets('fills up by the minute on Home', (tester) async {
      await pumpCard(
        tester,
        items: const [tummy],
        checks: [session('a', 8, 10), session('b', 11, 5)],
      );
      expect(find.text('Tummy time 15/30 min'), findsOneWidget);
      expect(find.byKey(const ValueKey('progress-tummy-time')), findsOneWidget);
      expect(find.text('DAILY · 0 OF 1'), findsOneWidget);
    });

    testWidgets('and is done at the goal', (tester) async {
      await pumpCard(
        tester,
        items: const [tummy],
        checks: [session('a', 8, 20), session('b', 11, 15)],
      );
      expect(find.text('Tummy time 35/30 min'), findsOneWidget);
      expect(find.text('DAILY · ALL DONE TODAY'), findsOneWidget);
    });

    testWidgets('a tap opens its timer', (tester) async {
      await pumpCard(
        tester,
        items: const [tummy],
        checks: [session('a', 8, 10)],
      );
      await tester.tap(find.text('Tummy time 10/30 min'));
      await tester.pumpAndSettle();
      // The sheet runs on the real clock, so today's minutes are its own;
      // the tests below fix it.
      expect(find.textContaining('of 30 min today'), findsOneWidget);
      expect(find.text('Start timer'), findsOneWidget);
    });

    Future<({_RecordingChecks repo, ProviderContainer container})> pumpSheet(
      WidgetTester tester, {
      required DateTime Function() clock,
      List<DailyCheck> checks = const [],
    }) async {
      SharedPreferences.setMockInitialValues({});
      final stored = await SharedPreferences.getInstance();
      final repo = _RecordingChecks();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(stored),
          authStateProvider.overrideWith((ref) => Stream.value(null)),
          currentBabyProvider.overrideWithValue(baby(const [tummy])),
          checksRepositoryProvider.overrideWithValue(repo),
          checksSinceProvider.overrideWith(
            (ref, start) => Stream.value(checks),
          ),
        ],
      );
      addTearDown(container.dispose);
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: TimedItemSheet(item: tummy, clock: clock),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (repo: repo, container: container);
    }

    testWidgets('adds minutes by hand', (tester) async {
      final (:repo, container: _) = await pumpSheet(tester, clock: () => now);
      await tester.tap(find.byKey(const ValueKey('add-10')));
      await tester.pump();
      final saved = repo.added.single;
      expect(saved.minutes, 10);
      expect(saved.itemId, 'tummy-time');
      expect(saved.time, now);
    });

    testWidgets('times a session, saved from when it started', (tester) async {
      var clock = now;
      final (:repo, :container) = await pumpSheet(tester, clock: () => clock);

      await tester.tap(find.text('Start timer'));
      await tester.pump();
      expect(
        container.read(checklistTimersProvider),
        {'baby1/tummy-time': now},
        reason: 'kept on the phone, so it outlives the sheet',
      );

      clock = now.add(const Duration(minutes: 12, seconds: 20));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('12:20'), findsOneWidget);

      await tester.tap(find.text('Stop and save'));
      await tester.pump();
      expect(repo.added.single.minutes, 12);
      expect(repo.added.single.time, now);
      expect(container.read(checklistTimersProvider), isEmpty);
    });

    testWidgets('does not save a start tapped by mistake', (tester) async {
      var clock = now;
      final (:repo, container: _) = await pumpSheet(tester, clock: () => clock);
      await tester.tap(find.text('Start timer'));
      await tester.pump();
      clock = now.add(const Duration(seconds: 5));
      await tester.tap(find.text('Stop and save'));
      await tester.pump();
      expect(repo.added, isEmpty);
      expect(find.text('Too short to count — not saved'), findsOneWidget);
    });

    testWidgets('shows on the chip while it runs', (tester) async {
      SharedPreferences.setMockInitialValues({
        'checklist_timers':
            '{"baby1/tummy-time": ${now.millisecondsSinceEpoch}}',
      });
      final stored = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(stored),
            authStateProvider.overrideWith((ref) => Stream.value(null)),
            currentBabyProvider.overrideWithValue(baby(const [tummy])),
            checksSinceProvider.overrideWith(
              (ref, start) => Stream.value(const []),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(body: DailyChecklistCard(now: now)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Tummy time 0/30 min · timing'), findsOneWidget);
      expect(find.byKey(const ValueKey('timing-tummy-time')), findsOneWidget);
    });

    test('a session is whole minutes, at least one', () {
      expect(sessionMinutes(const Duration(seconds: 10)), isNull);
      expect(sessionMinutes(const Duration(seconds: 40)), 1);
      expect(sessionMinutes(const Duration(minutes: 7, seconds: 31)), 8);
      expect(sessionMinutes(const Duration(hours: 9)), 240);
      expect(timerLabel(const Duration(minutes: 4, seconds: 5)), '4:05');
      expect(
        timerLabel(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '1:02:03',
      );
      expect(minutesLabel(70), '1 hr 10 min');
    });
  });

  group('in the activity log', () {
    Future<_RecordingChecks> pumpTile(
      WidgetTester tester,
      DailyCheck check,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final stored = await SharedPreferences.getInstance();
      final repo = _RecordingChecks();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(stored),
            authStateProvider.overrideWith((ref) => Stream.value(null)),
            currentBabyProvider.overrideWithValue(baby(const [vitamin])),
            checksRepositoryProvider.overrideWithValue(repo),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ActivityTile(entry: CheckEntry(check), now: now),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return repo;
    }

    testWidgets('reads as the item, who ticked it, and when', (tester) async {
      await pumpTile(
        tester,
        tick(
          'vitamin-d',
          DateTime(2026, 10, 24, 9, 12),
          id: 'c1',
          byName: 'Sam',
        ),
      );
      expect(find.text('Vitamin D'), findsOneWidget);
      expect(find.text('Daily checklist · by Sam'), findsOneWidget);
      expect(find.text('9:12 AM'), findsOneWidget);
    });

    testWidgets('keeps its name after the item leaves the list', (
      tester,
    ) async {
      await pumpTile(
        tester,
        DailyCheck(
          id: 'c1',
          itemId: 'bath',
          label: 'Bath',
          time: DateTime(2026, 10, 24, 9),
        ),
      );
      expect(find.text('Bath'), findsOneWidget);
    });

    testWidgets('tapping it offers the untick, which takes that tick', (
      tester,
    ) async {
      final repo = await pumpTile(
        tester,
        tick('vitamin-d', DateTime(2026, 10, 24, 9, 12), id: 'c1'),
      );
      await tester.tap(find.text('Vitamin D'));
      await tester.pumpAndSettle();
      expect(find.text('Done 9:12 AM'), findsOneWidget);

      await tester.tap(find.text('Not done — untick it'));
      await tester.pumpAndSettle();
      expect(repo.deleted, ['c1']);
    });
  });

  group('in Settings', () {
    Future<_RecordingBabies> pumpSettings(
      WidgetTester tester,
      List<ChecklistItem> items,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final stored = await SharedPreferences.getInstance();
      final repo = _RecordingBabies();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(stored),
            authStateProvider.overrideWith((ref) => Stream.value(null)),
            currentBabyProvider.overrideWithValue(baby(items)),
            babiesRepositoryProvider.overrideWithValue(repo),
          ],
          child: const MaterialApp(home: ChecklistSettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      return repo;
    }

    testWidgets('adds a ready-made item to the end', (tester) async {
      final repo = await pumpSettings(tester, const [vitamin]);
      // Already on the list, so not offered again.
      expect(find.byKey(const ValueKey('add-vitamin-d')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('add-bath')));
      await tester.pumpAndSettle();

      expect(repo.saved.single.map((i) => i.id), ['vitamin-d', 'bath']);
      expect(find.text('Bath'), findsOneWidget);
    });

    testWidgets('adds one of your own', (tester) async {
      final repo = await pumpSettings(tester, const []);
      await tester.tap(find.byKey(const ValueKey('add-own')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '  Read a book ');
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();

      final saved = repo.saved.single.single;
      expect(saved.label, 'Read a book');
      expect(saved.icon, ChecklistIcon.other);
    });

    testWidgets('removes one', (tester) async {
      final repo = await pumpSettings(tester, const [vitamin, bath]);
      await tester.tap(find.byTooltip('Remove Vitamin D'));
      await tester.pumpAndSettle();
      expect(repo.saved.single.map((i) => i.id), ['bath']);
    });

    testWidgets('renames one and keeps its id, so its streak carries on', (
      tester,
    ) async {
      final repo = await pumpSettings(tester, const [vitamin]);
      await tester.tap(find.text('Vitamin D'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Vitamin D drops');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final saved = repo.saved.single.single;
      expect(saved.id, 'vitamin-d');
      expect(saved.label, 'Vitamin D drops');
    });
  });
}

class _RecordingChecks extends ChecksRepository {
  _RecordingChecks() : super(_NoFirestore(), 'baby1', 'alice');

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

class _RecordingBabies extends BabiesRepository {
  _RecordingBabies() : super(_NoFirestore(), 'alice');

  final saved = <List<ChecklistItem>>[];

  @override
  Future<void> updateChecklist(
    String babyId,
    List<ChecklistItem> items,
  ) async => saved.add(items);
}

class _NoFirestore implements FirebaseFirestore {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
