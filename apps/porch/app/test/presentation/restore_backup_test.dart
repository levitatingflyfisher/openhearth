// Restore from a backup file (audit: design-of-everyday-things-03). The app
// writes locked backup files and its copy promises they restore
// identity AND groups; `openBackup` existed but no screen reached it. The
// backup is canonical JSON text, so the way in is paste + the 6 backup
// words — no file
// picker plugin (none is a dependency, and none could be verified here
// without a device).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:porch_app/domain/domain.dart';

import 'package:porch_app/presentation/home/home_screen.dart';

import 'support/pump.dart';
import 'support/ui_world.dart';

/// A backup made on "the old phone": onboarded Alice with a second group.
Future<({String text, List<int> entropy, String words})>
    oldPhoneBackup() async {
  final old = await UiWorld.onboarded(name: 'Alice', seed: 9);
  final sodium = old.world.sodium;
  final state = (await old.store.load())!;
  expect(state.groups.single.name, 'My Porch');
  final entropy = (await old.keys.readEntropy())!;
  final blob = sealBackup(
    sodium,
    entropy: entropy,
    stateSnapshot: state.toJson(),
    opsLimit: sodium.crypto.pwhash.opsLimitMin,
    memLimit: sodium.crypto.pwhash.memLimitMin,
  );
  return (
    text: utf8.decode(blob),
    entropy: entropy,
    words: backupPassphrase(sodium, entropy).join(' '),
  );
}

Future<void> openBackupRestore(WidgetTester tester) async {
  await tapItem(tester, find.text('Restore an existing identity'));
  await tapItem(tester, find.text('Restore from a backup file instead'));
}

const _wordsLabel = 'Your 6 backup words';

void main() {
  testWidgets('the restore step offers the backup file, and a pasted file + '
      'its 6 backup words bring back identity, name and groups — relay '
      'hears nothing', (tester) async {
    final backup = await oldPhoneBackup();
    final u = await UiWorld.fresh();
    await pumpPorch(tester, u);
    await openBackupRestore(tester);

    await tester.enterText(
        find.widgetWithText(TextField, 'Backup file contents'), backup.text);
    await tester.enterText(
        find.widgetWithText(TextField, _wordsLabel), backup.words);
    await tapItem(tester, find.text('Restore from backup'));

    expect(await u.keys.readEntropy(), backup.entropy);
    final state = (await u.store.load())!;
    expect(state.profile.displayName, 'Alice');
    expect(state.groups.single.name, 'My Porch');
    // Onboarding is done: Home, not the name step.
    expect(find.byKey(porchLightKey), findsOneWidget);
    expect(lightShowsOn(tester), isFalse);
    expect(u.world.relay.callLog, isEmpty);
  });

  testWidgets('the restore step asks for words, never a PIN',
      (tester) async {
    final u = await UiWorld.fresh();
    await pumpPorch(tester, u);
    await openBackupRestore(tester);

    expect(find.textContaining('PIN'), findsNothing);
    final field = tester.widget<TextField>(
        find.widgetWithText(TextField, _wordsLabel));
    expect(field.keyboardType, isNot(TextInputType.number));
  });

  testWidgets('Restore from backup waits for both the file and the words',
      (tester) async {
    final u = await UiWorld.fresh();
    await pumpPorch(tester, u);
    await openBackupRestore(tester);

    bool enabled() => tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Restore from backup'))
            .onPressed !=
        null;
    expect(enabled(), isFalse);
    await tester.enterText(
        find.widgetWithText(TextField, 'Backup file contents'), '{"v":1}');
    await tester.pump();
    expect(enabled(), isFalse);
    await tester.enterText(find.widgetWithText(TextField, _wordsLabel), 'a');
    await tester.pump();
    expect(enabled(), isTrue);
  });

  testWidgets('wrong backup words say so and leave nothing behind',
      (tester) async {
    final backup = await oldPhoneBackup();
    final u = await UiWorld.fresh();
    await pumpPorch(tester, u);
    await openBackupRestore(tester);

    await tester.enterText(
        find.widgetWithText(TextField, 'Backup file contents'), backup.text);
    // Six real list words, but not this backup's.
    await tester.enterText(find.widgetWithText(TextField, _wordsLabel),
        'abandon ability able about above absent');
    await tapItem(tester, find.text('Restore from backup'));

    expect(find.textContaining('wrong words or corrupted backup'),
        findsOneWidget);
    // Colour, icon and word: not red text alone.
    expect(find.byKey(const Key('error-line-icon')), findsOneWidget);
    expect(find.textContaining('BackupException'), findsNothing,
        reason: 'the raw exception never reaches a person');
    expect(await u.keys.readEntropy(), isNull);
    expect(await u.store.load(), isNull);
  });

  testWidgets('an old 4-digit PIN is refused in plain words, before any '
      'work', (tester) async {
    final backup = await oldPhoneBackup();
    final u = await UiWorld.fresh();
    await pumpPorch(tester, u);
    await openBackupRestore(tester);

    await tester.enterText(
        find.widgetWithText(TextField, 'Backup file contents'), backup.text);
    await tester.enterText(find.widgetWithText(TextField, _wordsLabel), '2468');
    await tapItem(tester, find.text('Restore from backup'));

    expect(find.textContaining('That is not 6 backup words'), findsOneWidget);
    expect(find.textContaining('BackupException'), findsNothing);
    expect(await u.keys.readEntropy(), isNull);
  });

  testWidgets('pasting something that is not a backup says so',
      (tester) async {
    final u = await UiWorld.fresh();
    await pumpPorch(tester, u);
    await openBackupRestore(tester);

    await tester.enterText(
        find.widgetWithText(TextField, 'Backup file contents'), 'hello');
    await tester.enterText(find.widgetWithText(TextField, _wordsLabel),
        'abandon ability able about above absent');
    await tapItem(tester, find.text('Restore from backup'));

    expect(find.textContaining('not a Porch backup'), findsOneWidget);
    expect(await u.keys.readEntropy(), isNull);
  });

  testWidgets('settings tells where restoring happens', (tester) async {
    final u = await UiWorld.onboarded();
    await pumpPorch(tester, u);
    await openSettings(tester);

    expect(find.text('Restoring on a new phone'), findsOneWidget);
    expect(find.textContaining('Restore an existing identity'), findsOneWidget);
  });
}
