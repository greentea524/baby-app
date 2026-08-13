import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:baby_app/features/common/app_sheet.dart';
import 'package:baby_app/features/common/save_and_close.dart';

/// The offline half of the app (#21).
///
/// A Firestore write future does not complete until the server acknowledges
/// it, so every sheet that awaited one before closing hung forever with no
/// signal — while the record sat safely in the local cache. Verified against
/// the emulator: with the network disabled the write stays pending
/// indefinitely, the cache already holds it, and it resolves on reconnect.
///
/// These tests use a save that never completes to stand in for that.
void main() {
  /// Opens a sheet whose Save button calls [saveAndClose] with [save].
  Future<void> openSheet(
    WidgetTester tester,
    Future<void> Function() save,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAppSheet<void>(
                context,
                builder: (sheetContext) => TextButton(
                  onPressed: () => saveAndClose(
                    sheetContext,
                    save,
                    failure: 'Could not save the feed',
                  ),
                  child: const Text('Save'),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Save'), findsOneWidget, reason: 'sheet did not open');
  }

  testWidgets('a write that never lands still closes the sheet', (
    tester,
  ) async {
    // Airplane mode. Before this fix the spinner ran until the app was
    // force-quit, and the caregiver logged the feed again on the way back.
    final offline = Completer<void>();
    await openSheet(tester, () => offline.future);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Save'), findsNothing);
    expect(
      offline.isCompleted,
      isFalse,
      reason: 'still queued, as it should be',
    );
  });

  testWidgets('a failure is reported even though the sheet has gone', (
    tester,
  ) async {
    // Offline, a rejection only arrives when the write reaches the server —
    // so this can land long after the sheet closed. It still has to be said.
    final offline = Completer<void>();
    await openSheet(tester, () => offline.future);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Save'), findsNothing);

    offline.completeError('permission-denied');
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Could not save the feed'),
      findsOneWidget,
      reason: 'the error had nowhere to go',
    );
  });

  testWidgets('a repository that throws on the spot is caught too', (
    tester,
  ) async {
    // Not every failure is asynchronous. A synchronous throw used to sail
    // past the pop and leave the sheet open saying nothing.
    await openSheet(tester, () => throw StateError('no baby'));

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Save'), findsNothing);
    expect(find.textContaining('Could not save the feed'), findsOneWidget);
  });

  testWidgets('the write is started exactly once', (tester) async {
    var calls = 0;
    final offline = Completer<void>();
    await openSheet(tester, () {
      calls++;
      return offline.future;
    });

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(calls, 1);
  });

  testWidgets('a write that succeeds says nothing', (tester) async {
    // The record showing up in the timeline is the confirmation. A snackbar
    // on every feed would be noise on the app's most repeated action.
    await openSheet(tester, () async {});

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsNothing);
  });
}
