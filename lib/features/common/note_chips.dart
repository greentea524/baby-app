import 'package:flutter/material.dart';

/// The note that goes with most bottles, offered as a pill under the notes.
const bottleNoteSuggestions = ['Vitamin D'];

/// The note that goes with most diaper changes worth a note.
const diaperNoteSuggestions = ['Blowout'];

/// Whether [notes] already say [note], in any case.
bool hasNote(String notes, String note) =>
    notes.toLowerCase().contains(note.toLowerCase());

/// [notes] with [note] added on the end, after whatever was typed.
String addNote(String notes, String note) {
  final text = notes.trim();
  if (hasNote(text, note)) return text;
  return text.isEmpty ? note : '$text, $note';
}

/// [notes] with [note] taken out, and the comma it was joined by.
String removeNote(String notes, String note) {
  final at = notes.toLowerCase().indexOf(note.toLowerCase());
  if (at < 0) return notes.trim();
  final rest = notes.replaceRange(at, at + note.length, '');
  return rest
      .split(',')
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .join(', ');
}

/// Pills that write a common note for you: tap to add it, tap again to take
/// it out.
///
/// Fixed rather than learned from past notes: the one or two notes a
/// household writes over and over are known, and a list worked out from
/// history would shuffle under the thumb. Selected while the note is in the
/// field, so the pill says whether it is already there, and what was typed
/// around it is kept either way.
class NoteChips extends StatelessWidget {
  const NoteChips({super.key, required this.controller, required this.notes});

  final TextEditingController controller;
  final List<String> notes;

  void _set(String text) {
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final note in notes)
              FilterChip(
                label: Text(note),
                selected: hasNote(controller.text, note),
                onSelected: (on) => _set(
                  on
                      ? addNote(controller.text, note)
                      : removeNote(controller.text, note),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
