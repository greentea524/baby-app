import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:baby_app/core/auth/auth_providers.dart';
import 'package:baby_app/core/theme/theme_mode_provider.dart';
import 'package:baby_app/data/models/feeding_event.dart';
import 'package:baby_app/data/models/milk_kind.dart';
import 'package:baby_app/data/models/pumping_event.dart';
import 'package:baby_app/data/repositories/feeding_repository.dart';
import 'package:baby_app/data/repositories/repository_providers.dart';
import 'package:baby_app/features/feeding/feeding_quick_log.dart';

/// What was in the bottle: asked on every bottle feed, and remembered from
/// one to the next.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RecordingFeeds feeds;

  Future<void> openBottleForm(
    WidgetTester tester, {
    List<FeedingEvent> history = const [],
    List<PumpingEvent> pumps = const [],
    FeedingEvent? existing,
    Size size = const Size(390, 1000),
    double textScale = 1.0,
  }) async {
    SharedPreferences.setMockInitialValues({'unit_system': 'metric'});
    final stored = await SharedPreferences.getInstance();
    feeds = _RecordingFeeds();
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(stored),
          authStateProvider.overrideWith((ref) => Stream.value(null)),
          feedingRepositoryProvider.overrideWithValue(feeds),
          recentFeedingsProvider.overrideWith((ref) => Stream.value(history)),
          recentPumpingProvider.overrideWith((ref) => Stream.value(pumps)),
          fridgeBottlesProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => showFeedingQuickLog(
                      context,
                      type: FeedingType.bottle,
                      existing: existing,
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // Let the history stream arrive before the form reads it, as it has on
    // Home long before anyone opens the sheet.
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Set<MilkKind> selected(WidgetTester tester) => tester
      .widget<SegmentedButton<MilkKind>>(find.byType(SegmentedButton<MilkKind>))
      .selected;

  FeedingEvent bottle(MilkKind? milk, {required int hoursAgo}) => FeedingEvent(
    id: 'f$hoursAgo',
    type: FeedingType.bottle,
    startTime: DateTime.now().subtract(Duration(hours: hoursAgo)),
    amountMl: 120,
    milk: milk,
  );

  Future<void> saveWith(WidgetTester tester, String amount) async {
    await tester.enterText(find.widgetWithText(TextField, 'Amount'), amount);
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
  }

  testWidgets('offers all three', (tester) async {
    await openBottleForm(tester);
    for (final label in ['Breast milk', 'Formula', 'Whole milk']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('starts on breast milk with nothing to go by', (tester) async {
    await openBottleForm(tester);
    expect(selected(tester), {MilkKind.expressed});

    await saveWith(tester, '90');
    expect(feeds.added.single.milk, MilkKind.expressed);
  });

  testWidgets('and on whatever the last bottle held', (tester) async {
    // A baby is on one milk for months; the switch is worth one tap, not
    // one every feed.
    await openBottleForm(
      tester,
      history: [
        bottle(MilkKind.expressed, hoursAgo: 9),
        bottle(MilkKind.wholeMilk, hoursAgo: 3),
        // Too old to know: passed over rather than read as breast milk.
        bottle(null, hoursAgo: 1),
      ],
    );
    expect(selected(tester), {MilkKind.wholeMilk});
  });

  testWidgets('saves the one picked', (tester) async {
    await openBottleForm(tester);
    await tester.tap(find.text('Whole milk'));
    await tester.pumpAndSettle();
    await saveWith(tester, '150');

    expect(feeds.added.single.milk, MilkKind.wholeMilk);
  });

  testWidgets('a pump chip is breast milk', (tester) async {
    await openBottleForm(
      tester,
      history: [bottle(MilkKind.formula, hoursAgo: 3)],
      pumps: [
        PumpingEvent(
          id: 'p',
          time: DateTime.now().subtract(const Duration(hours: 1)),
          amountMl: 95,
        ),
      ],
    );
    expect(selected(tester), {MilkKind.formula});

    await tester.tap(find.widgetWithText(ActionChip, '95 ml'));
    await tester.pumpAndSettle();
    expect(selected(tester), {MilkKind.expressed});
  });

  testWidgets('a feed logged before the question stays unknown', (
    tester,
  ) async {
    // Unknown is not the same as breast milk, so nothing is picked for it —
    // and saving an edit does not quietly answer the question.
    await openBottleForm(tester, existing: bottle(null, hoursAgo: 2));
    expect(selected(tester), isEmpty);

    await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
    await tester.pumpAndSettle();
    expect(feeds.updated.single.milk, isNull);
  });

  testWidgets('until one is picked', (tester) async {
    await openBottleForm(tester, existing: bottle(null, hoursAgo: 2));
    await tester.tap(find.text('Formula'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
    await tester.pumpAndSettle();

    expect(feeds.updated.single.milk, MilkKind.formula);
  });

  for (final (size, scale) in [
    (const Size(320, 900), 1.0),
    (const Size(390, 1000), 1.3),
    (const Size(320, 1200), 1.5),
  ]) {
    testWidgets('fits across ${size.width.toInt()} wide at ${scale}x text', (
      tester,
    ) async {
      await openBottleForm(tester, size: size, textScale: scale);
      expect(tester.takeException(), isNull);
      final row = tester.getRect(find.byType(SegmentedButton<MilkKind>));
      expect(row.right, lessThanOrEqualTo(size.width));
    });
  }
}

class _RecordingFeeds extends FeedingRepository {
  _RecordingFeeds() : super(_NoFirestore(), 'baby1', 'alice');

  final added = <FeedingEvent>[];
  final updated = <FeedingEvent>[];

  @override
  Future<String> add(FeedingEvent event) async {
    added.add(event);
    return 'f1';
  }

  @override
  Future<void> update(FeedingEvent event) async => updated.add(event);
}

/// Never touched: the recording repository overrides every call that would
/// reach it.
class _NoFirestore implements FirebaseFirestore {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
