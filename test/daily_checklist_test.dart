import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:baby_app/core/auth/auth_providers.dart';
import 'package:baby_app/core/theme/theme_mode_provider.dart';
import 'package:baby_app/data/models/baby.dart';
import 'package:baby_app/data/models/daily_check.dart';
import 'package:baby_app/data/repositories/babies_repository.dart';
import 'package:baby_app/data/repositories/checks_repository.dart';
import 'package:baby_app/data/repositories/repository_providers.dart';
import 'package:baby_app/features/checklist/checklist_logic.dart';
import 'package:baby_app/features/checklist/checklist_settings_screen.dart';
import 'package:baby_app/features/checklist/daily_checklist.dart';

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

  group('a streak', () {
    test('counts days in a row up to today', () {
      final checks = [for (var n = 0; n < 5; n++) daysAgo('vitamin-d', n)];
      expect(streak(checks, 'vitamin-d', now), 5);
    });

    test('is not broken by today not being done yet', () {
      final checks = [for (var n = 1; n <= 3; n++) daysAgo('vitamin-d', n)];
      expect(streak(checks, 'vitamin-d', now), 3);
    });

    test('starts again after a missed day', () {
      final checks = [
        daysAgo('vitamin-d', 0),
        daysAgo('vitamin-d', 1),
        daysAgo('vitamin-d', 3),
        daysAgo('vitamin-d', 4),
      ];
      expect(streak(checks, 'vitamin-d', now), 2);
      expect(streak([daysAgo('vitamin-d', 2)], 'vitamin-d', now), 0);
    });

    test('counts a day once however many ticks it has', () {
      final checks = [
        daysAgo('vitamin-d', 0),
        tick('vitamin-d', DateTime(2026, 10, 24, 10)),
      ];
      expect(streak(checks, 'vitamin-d', now), 1);
    });

    test('runs across the end of a month', () {
      final first = DateTime(2026, 11, 1, 9);
      final checks = [
        tick('bath', first),
        tick('bath', DateTime(2026, 10, 31, 9)),
        tick('bath', DateTime(2026, 10, 30, 9)),
      ];
      expect(streak(checks, 'bath', first), 3);
    });

    test('and the week ends today, oldest first', () {
      final week = recentDays(
        [daysAgo('bath', 0), daysAgo('bath', 6), daysAgo('bath', 7)],
        'bath',
        now,
      );
      expect(week, [true, false, false, false, false, false, true]);
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
