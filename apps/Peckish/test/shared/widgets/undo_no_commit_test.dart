import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Erase and restore end the app-wide Undo with OhUndoController.cancel(),
// which runs no onCommit, so they no longer need this rule. Ordinary
// dismissals still run onCommit (the bar's close button, a newer delete,
// leaving the screen), and nothing in Peckish needs it: a delete here happens
// at once (soft or hard) and the Undo only puts it back. The rule stays so a
// commit written against old data cannot appear unseen.
void main() {
  // Looks for the named argument, so a comment that names onCommit is fine.
  test('no Undo offer in lib/ has an onCommit', () {
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains('onCommit:')) {
          offenders.add('${f.path}:${i + 1}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'no Undo in Peckish needs an onCommit; see '
            '_forgetCachedData in settings_actions.dart');
  });
}
