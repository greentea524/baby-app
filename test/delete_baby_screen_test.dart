import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:baby_app/core/auth/auth_providers.dart';
import 'package:baby_app/data/models/baby.dart';
import 'package:baby_app/data/repositories/baby_data.dart';
import 'package:baby_app/data/repositories/repository_providers.dart';
import 'package:baby_app/features/settings/delete_baby_screen.dart';

/// The gate in front of an irreversible delete (#28).
class _FakeBabyData implements BabyData {
  _FakeBabyData(this.counts);

  final Map<String, int> counts;
  final deleted = <String>[];
  Object? failWith;

  @override
  Future<Map<String, int>> countAll(String babyId) async => counts;

  @override
  Future<void> deleteAll(String babyId, {void Function(int)? onProgress}) async {
    if (failWith case final e?) throw e;
    onProgress?.call(counts.values.fold(0, (a, b) => a + b));
    deleted.add(babyId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Baby babyOwnedBy(String uid, {Map<String, CaregiverRole>? members}) => Baby(
    id: 'baby1',
    name: 'Ada',
    birthDate: DateTime(2026, 2, 1),
    ownerUid: uid,
    members: members ?? {uid: CaregiverRole.owner},
  );

  Future<_FakeBabyData> pumpScreen(
    WidgetTester tester, {
    required Baby baby,
    String signedInAs = 'alice',
    Map<String, int> counts = const {'feedings': 12, 'diapers': 9},
  }) async {
    final data = _FakeBabyData(counts);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          babyDataProvider.overrideWithValue(data),
          currentUidProvider.overrideWithValue(signedInAs),
        ],
        child: MaterialApp(home: DeleteBabyScreen(baby: baby)),
      ),
    );
    await tester.pumpAndSettle();
    return data;
  }

  testWidgets('says what is about to go, with numbers', (tester) async {
    await pumpScreen(tester, baby: babyOwnedBy('alice'));

    expect(
      find.textContaining('12 feeds and 9 diaper changes'),
      findsOneWidget,
    );
  });

  testWidgets('offers the export before asking to confirm', (tester) async {
    // A way out offered after the decision is made is not much of an offer.
    await pumpScreen(tester, baby: babyOwnedBy('alice'));

    final export = tester.getRect(find.text('Export the data first'));
    final confirm = tester.getRect(find.byType(TextField));
    expect(export.top, lessThan(confirm.top));
  });

  testWidgets('and says why it is worth taking', (tester) async {
    // A bare "Export" button in front of a delete is one people tap past.
    // The reason to tap it is that there is no second copy.
    await pumpScreen(tester, baby: babyOwnedBy('alice'));

    expect(find.textContaining('only copy'), findsOneWidget);
    expect(find.textContaining('no undo'), findsOneWidget);
    // Names what an export actually gets them, so it is a decision rather
    // than a leap.
    expect(find.textContaining('CSV'), findsOneWidget);
    expect(find.textContaining('PDF'), findsOneWidget);

    final reason = tester.getRect(find.textContaining('only copy'));
    final button = tester.getRect(find.text('Export the data first'));
    expect(reason.top, lessThan(button.top));
  });

  testWidgets('will not delete until the name is typed', (tester) async {
    final data = await pumpScreen(tester, baby: babyOwnedBy('alice'));

    final button = find.widgetWithText(FilledButton, 'Delete permanently');
    expect(tester.widget<FilledButton>(button).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'Adb');
    await tester.pump();
    expect(tester.widget<FilledButton>(button).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'Ada');
    await tester.pump();
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);

    expect(data.deleted, isEmpty);
  });

  testWidgets('accepts the name whatever the case', (tester) async {
    // Typing a name to confirm is a speed bump, not a spelling test.
    await pumpScreen(tester, baby: babyOwnedBy('alice'));
    await tester.enterText(find.byType(TextField), '  ada  ');
    await tester.pump();

    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Delete permanently'),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('deletes once, when told to', (tester) async {
    final data = await pumpScreen(tester, baby: babyOwnedBy('alice'));
    await tester.enterText(find.byType(TextField), 'Ada');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete permanently'));
    await tester.pumpAndSettle();

    expect(data.deleted, ['baby1']);
  });

  testWidgets('warns that the others lose it too', (tester) async {
    await pumpScreen(
      tester,
      baby: babyOwnedBy('alice', members: const {
        'alice': CaregiverRole.owner,
        'bob': CaregiverRole.editor,
      }),
    );

    expect(
      find.textContaining('One other caregiver has access'),
      findsOneWidget,
    );
  });

  testWidgets('a non-owner is offered leaving, not deleting', (tester) async {
    // Not a UI convention: the rules allow a member to remove exactly
    // themselves, so offering Delete here offers what the database refuses.
    await pumpScreen(
      tester,
      baby: babyOwnedBy('alice'),
      signedInAs: 'bob',
    );

    expect(find.widgetWithText(FilledButton, 'Delete permanently'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('You can leave instead'), findsOneWidget);
  });

  testWidgets('a failure says the delete can simply be run again', (
    tester,
  ) async {
    // True because of the order: the baby document goes last, so until it
    // does the rules still admit the caller and nothing is stranded.
    final data = await pumpScreen(tester, baby: babyOwnedBy('alice'));
    data.failWith = Exception('network');

    await tester.enterText(find.byType(TextField), 'Ada');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete permanently'));
    await tester.pumpAndSettle();

    expect(find.textContaining('run it again'), findsOneWidget);
    expect(find.textContaining('Nothing is lost'), findsOneWidget);
  });
}
