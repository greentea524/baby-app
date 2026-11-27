import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:baby_app/core/auth/auth_providers.dart';
import 'package:baby_app/core/theme/theme_mode_provider.dart';
import 'package:baby_app/data/models/diaper_event.dart';
import 'package:baby_app/data/models/feeding_event.dart';
import 'package:baby_app/data/repositories/diaper_repository.dart';
import 'package:baby_app/data/repositories/feeding_repository.dart';
import 'package:baby_app/data/repositories/repository_providers.dart';
import 'package:baby_app/features/diaper/diaper_quick_log.dart';
import 'package:baby_app/features/feeding/feeding_quick_log.dart';

class _FakeFeeds implements FeedingRepository {
  final deleted = <String>[];
  @override
  Future<void> delete(String id) async => deleted.add(id);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDiapers implements DiaperRepository {
  final deleted = <String>[];
  @override
  Future<void> delete(String id) async => deleted.add(id);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Deleting from inside an edit sheet (#42): reachable with a mouse, a
/// keyboard or a screen reader, where a swipe is not.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final feed = FeedingEvent(
    id: 'f1',
    type: FeedingType.bottle,
    startTime: DateTime.now().subtract(const Duration(hours: 1)),
    amountMl: 120,
  );
  final diaper = DiaperEvent(
    id: 'd1',
    type: DiaperType.wet,
    time: DateTime.now().subtract(const Duration(hours: 1)),
  );

  Future<({_FakeFeeds feeds, _FakeDiapers diapers})> pump(
    WidgetTester tester,
    void Function(BuildContext) open,
  ) async {
    SharedPreferences.setMockInitialValues({'unit_system': 'metric'});
    final stored = await SharedPreferences.getInstance();
    final feeds = _FakeFeeds();
    final diapers = _FakeDiapers();
    tester.view.physicalSize = const Size(500, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(stored),
          authStateProvider.overrideWith((ref) => Stream.value(null)),
          feedingRepositoryProvider.overrideWithValue(feeds),
          diaperRepositoryProvider.overrideWithValue(diapers),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => open(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return (feeds: feeds, diapers: diapers);
  }

  testWidgets('editing a feed offers Delete, and asks first', (tester) async {
    final fakes = await pump(
      tester,
      (c) => showFeedingQuickLog(c, existing: feed),
    );
    await tester.ensureVisible(find.text('Delete feed'));
    await tester.tap(find.text('Delete feed'));
    await tester.pumpAndSettle();
    expect(find.text('Delete feed?'), findsOneWidget);
    expect(fakes.feeds.deleted, isEmpty);

    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(fakes.feeds.deleted, ['f1']);
    // The sheet has gone, and says what happened.
    expect(find.text('Delete feed'), findsNothing);
    expect(find.text('Feed deleted'), findsOneWidget);
  });

  testWidgets('cancelling leaves the feed alone', (tester) async {
    final fakes = await pump(
      tester,
      (c) => showFeedingQuickLog(c, existing: feed),
    );
    await tester.ensureVisible(find.text('Delete feed'));
    await tester.tap(find.text('Delete feed'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(fakes.feeds.deleted, isEmpty);
    expect(find.text('Delete feed'), findsOneWidget);
  });

  testWidgets('logging a new one has nothing to delete', (tester) async {
    await pump(tester, (c) => showFeedingQuickLog(c, type: FeedingType.bottle));
    expect(find.byKey(const ValueKey('delete-entry')), findsNothing);
  });

  testWidgets('the diaper sheet has it too', (tester) async {
    final fakes = await pump(
      tester,
      (c) => showDiaperQuickLog(c, existing: diaper),
    );
    await tester.ensureVisible(find.text('Delete diaper change'));
    await tester.tap(find.text('Delete diaper change'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(fakes.diapers.deleted, ['d1']);
    expect(find.text('Diaper change deleted'), findsOneWidget);
  });
}
