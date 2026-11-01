// What the 6 backup words can open, said where people read it. The words
// are fixed by the identity, so the docs and the screen that shows them
// must say plainly: with any backup file they bring back the whole
// identity and every group; they cannot be changed, so a leak means a new
// identity; and on their own, without a file, they open nothing.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:porch_app/presentation/backup_saved_dialog.dart'
    show backupWordsNote;
import 'package:porch_app/presentation/settings/start_over_screen.dart'
    show startOverTitle;

void main() {
  // Markdown wraps lines anywhere: compare with runs of space as one.
  final doc = File('../docs/security-model.md')
      .readAsStringSync()
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll('**', '');

  test('the security model says what the 6 words open with a backup file',
      () {
    expect(doc, contains('The 6 backup words together with any backup file '
        'give the whole identity and every group.'));
  });

  test('the security model says the words cannot be changed, so a leak '
      'means a new identity', () {
    expect(doc, contains('The 6 backup words cannot be changed.'));
    // It names the control that does it, by the screen's own title.
    expect(doc, contains('"$startOverTitle"'));
  });

  test('the security model says the 6 words alone give nothing', () {
    expect(doc, contains('The 6 backup words alone, without a file, give '
        'nothing.'));
  });

  test('the note beside the 6 words says the same in plain words', () {
    expect(backupWordsNote, contains('Alone they open nothing'));
    expect(backupWordsNote,
        contains('with any backup file they bring back your identity and '
            'every group'));
    expect(backupWordsNote, contains('They can’t be changed'));
    expect(backupWordsNote, isNot(contains('—')));
    expect(backupWordsNote, isNot(contains("'")));
  });
}
