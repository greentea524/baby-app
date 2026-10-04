import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:baby_app/features/common/note_chips.dart';

/// The pills under a notes field that write a common note for you.
void main() {
  group('adding a note', () {
    test('fills an empty field', () {
      expect(addNote('', 'Vitamin D'), 'Vitamin D');
    });

    test('goes after what was typed', () {
      expect(addNote('fussy', 'Vitamin D'), 'fussy, Vitamin D');
    });

    test('and not twice', () {
      expect(addNote('vitamin d given', 'Vitamin D'), 'vitamin d given');
    });
  });

  group('taking it out', () {
    test('leaves what was typed around it', () {
      expect(removeNote('fussy, Vitamin D', 'Vitamin D'), 'fussy');
      expect(
        removeNote('Blowout, changed outfit', 'Blowout'),
        'changed outfit',
      );
      expect(removeNote('Vitamin D', 'Vitamin D'), '');
    });

    test('in any case', () {
      expect(hasNote('BLOWOUT', 'Blowout'), isTrue);
      expect(removeNote('a, blowout, b', 'Blowout'), 'a, b');
    });
  });

  testWidgets('the pill adds, shows it is there, and takes it out', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'fussy');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteChips(controller: controller, notes: const ['Vitamin D']),
        ),
      ),
    );
    bool selected() =>
        tester.widget<FilterChip>(find.byType(FilterChip)).selected;

    expect(selected(), isFalse);
    await tester.tap(find.text('Vitamin D'));
    await tester.pump();
    expect(controller.text, 'fussy, Vitamin D');
    expect(selected(), isTrue);

    await tester.tap(find.text('Vitamin D'));
    await tester.pump();
    expect(controller.text, 'fussy');
    expect(selected(), isFalse);
  });
}
