import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:baby_app/core/auth/auth_providers.dart';
import 'package:baby_app/core/theme/theme_mode_provider.dart';
import 'package:baby_app/data/models/feeding_event.dart';
import 'package:baby_app/data/repositories/feeding_repository.dart';
import 'package:baby_app/data/repositories/repository_providers.dart';
import 'package:baby_app/features/feeding/feeding_quick_log.dart';

class _FakeFeeds implements FeedingRepository {
  final added = <FeedingEvent>[];
  @override
  Future<String> add(FeedingEvent e) async {
    added.add(e);
    return 'new';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Breastfeeding parity (#43): typed minutes, a movable start time, notes,
/// and a timer that outlives the sheet.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<({_FakeFeeds feeds, SharedPreferences prefs})> pump(
    WidgetTester tester, {
    Map<String, Object> prefs = const {},
  }) async {
    SharedPreferences.setMockInitialValues({'unit_system': 'metric', ...prefs});
    final stored = await SharedPreferences.getInstance();
    final feeds = _FakeFeeds();
    tester.view.physicalSize = const Size(500, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(stored),
          authStateProvider.overrideWith((ref) => Stream.value(null)),
          feedingRepositoryProvider.overrideWithValue(feeds),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    showFeedingQuickLog(context, type: FeedingType.breast),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    return (feeds: feeds, prefs: stored);
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    final button = find.widgetWithText(FilledButton, 'Save');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets('a feed can be typed in, with notes', (tester) async {
    final fakes = await pump(tester);
    await open(tester);
    await tester.enterText(find.byKey(const ValueKey('nursing-minutes')), '15');
    await tester.enterText(
      find.widgetWithText(TextField, 'Notes (optional)'),
      'Sleepy',
    );
    await tester.pump();
    expect(find.text('15:00'), findsOneWidget);
    await save(tester);
    expect(fakes.feeds.added.single.durationMinutes, 15);
    expect(fakes.feeds.added.single.notes, 'Sleepy');
  });

  testWidgets('the timer survives closing the sheet', (tester) async {
    final fakes = await pump(tester);
    await open(tester);
    await tester.tap(find.text('Start'));
    await tester.pump();
    expect(find.text('Keeps running if you close this'), findsOneWidget);
    expect(fakes.prefs.getString('nursing_timer'), isNotNull);

    // Closed by accident.
    Navigator.of(tester.element(find.text('Breastfeeding'))).pop();
    await tester.pumpAndSettle();
    expect(find.text('Breastfeeding'), findsNothing);

    await open(tester);
    expect(find.text('Pause'), findsOneWidget);
    expect(find.text('Reset'), findsOneWidget);

    await save(tester);
    expect(fakes.feeds.added, hasLength(1));
    // Saved: nothing left over for the next feed.
    expect(fakes.prefs.getString('nursing_timer'), isNull);
  });

  testWidgets('a feed timed earlier comes back as it was', (tester) async {
    final started = DateTime.now().subtract(const Duration(minutes: 30));
    await pump(
      tester,
      prefs: {
        'nursing_timer': jsonEncode({
          'startedAt': started.millisecondsSinceEpoch,
          'elapsedMs': const Duration(minutes: 12).inMilliseconds,
          'runningSince': null,
          'side': 'right',
        }),
      },
    );
    await open(tester);
    expect(find.text('12:00'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    final seg = tester.widget<SegmentedButton<BreastSide>>(
      find.byType(SegmentedButton<BreastSide>),
    );
    expect(seg.selected, {BreastSide.right});

    await tester.tap(find.text('Reset'));
    await tester.pump();
    expect(find.text('00:00'), findsOneWidget);
  });
}
