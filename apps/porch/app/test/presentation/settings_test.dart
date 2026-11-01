// W4 acceptance: settings — profile (fans out E2EE), seed re-reveal,
// encrypted backup, notification opt-ins OFF by default, on-device
// stats, and the "What leaves your device" honesty page.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:porch_app/data/porch_state.dart';
import 'package:porch_app/domain/domain.dart';
import 'package:porch_app/presentation/backup_saved_dialog.dart'
    show backupWordsNote;

import 'support/pump.dart';
import 'support/ui_world.dart';

void main() {

  testWidgets('profile: saving a contact note updates state and reaches a '
      'friend E2EE on their next refresh', (tester) async {
    final u = await UiWorld.onboarded();
    final bob = await addFriend(u);
    await pumpPorch(tester, u);
    await openSettings(tester);

    await tester.enterText(
        find.widgetWithText(TextField, 'Contact note'), 'Signal: @alice');
    await tapItem(tester, find.text('Save profile'));

    expect((await u.store.load())!.profile.contactNote, 'Signal: @alice');

    // Bob folds the PROFILE op from the bulletin.
    await bob.sync.refreshFeed();
    final bobState = await bob.state();
    final aliceEntry = bobState.groups.single.roster.members
        .firstWhere((m) => m.displayName == 'Alice');
    expect(aliceEntry.contactNote, 'Signal: @alice');
  });

  testWidgets('recovery words re-reveal matches the stored identity',
      (tester) async {
    final u = await UiWorld.onboarded();
    await pumpPorch(tester, u);
    await openSettings(tester);

    await tapItem(tester, find.text('Show recovery words'));
    final words = entropyToMnemonic((await u.keys.readEntropy())!);
    for (final w in words.toSet()) {
      expect(find.textContaining(w), findsWidgets);
    }
  });

  testWidgets('the re-reveal shows the 6 backup words beside the 12',
      (tester) async {
    final u = await UiWorld.onboarded();
    await pumpPorch(tester, u);
    await openSettings(tester);

    await tapItem(tester, find.text('Show recovery words'));
    final dialog = find.byType(AlertDialog);
    expect(
        find.descendant(of: dialog, matching: find.text(backupWordsNote)),
        findsOneWidget);
    final backupWords =
        backupPassphrase(u.world.sodium, (await u.keys.readEntropy())!);
    for (var i = 0; i < 6; i++) {
      expect(
          find.descendant(
              of: dialog, matching: find.text('${i + 1}. ${backupWords[i]}')),
          findsWidgets);
    }
  });

  testWidgets('backup: one encrypted blob in the sink, openable with this '
      'identity\'s 6 backup words only', (tester) async {
    final u = await UiWorld.onboarded();
    await pumpPorch(tester, u);
    await openSettings(tester);

    await tapItem(tester, find.text('Save encrypted backup'));
    await tapItem(tester, find.text('Create backup'));

    expect(u.backupSink.saved, hasLength(1));
    final entropy = (await u.keys.readEntropy())!;
    final contents = openBackup(u.world.sodium,
        passphrase: backupPassphrase(u.world.sodium, entropy).join(' '),
        blob: u.backupSink.saved.single);
    expect(contents.entropy, await u.keys.readEntropy());
    expect(contents.stateSnapshot['groups'], isNotEmpty,
        reason: 'backup restores groups too (§3.1 step 7)');
    expect(
        () => openBackup(u.world.sodium,
            passphrase: 'abandon ability able about above absent',
            blob: u.backupSink.saved.single),
        throwsA(isA<BackupException>()));
  });

  const androidBackupNote =
      'Android may also back up this app’s data to Google, if the phone’s '
      'owner allows it in Android settings. The encrypted backup here is '
      'the private choice.';

  testWidgets('Settings says Android may back up to Google, beside the '
      'encrypted backup', (tester) async {
    final u = await UiWorld.onboarded();
    await pumpPorch(tester, u);
    await openSettings(tester);

    expect(find.text(androidBackupNote), findsOneWidget);
  });

  testWidgets('the backup dialog says the same', (tester) async {
    final u = await UiWorld.onboarded();
    await pumpPorch(tester, u);
    await openSettings(tester);

    await tapItem(tester, find.text('Save encrypted backup'));
    // Once on the Settings page under the dialog, once in the dialog.
    expect(find.text(androidBackupNote), findsNWidgets(2));
    expect(
        find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text(androidBackupNote)),
        findsOneWidget);
  });

  testWidgets('notifications: every switch starts OFF; a toggle persists '
      'locally', (tester) async {
    final u = await UiWorld.onboarded();
    final bob = await addFriend(u);
    await pumpPorch(tester, u);
    await openSettings(tester);

    // Everything OFF on a fresh install — asserted on the actual widgets.
    final switches =
        tester.widgetList<SwitchListTile>(find.byType(SwitchListTile));
    expect(switches, isNotEmpty);
    for (final s in switches) {
      expect(s.value, isFalse, reason: 'opt-ins must default OFF');
    }

    await tapItem(tester, find.widgetWithText(SwitchListTile, 'Bob'));
    final state = (await u.store.load())!;
    expect(state.notifyPrefs.perFriend[b64(bob.identity.sign.publicKey)],
        isTrue);
  });

  testWidgets('stats are on-device numbers, shown to me only', (tester) async {
    final u = await UiWorld.onboarded();
    final st = (await u.store.load())!;
    st.metrics.addAll([
      MetricsDay(date: '2026-07-01', publishes: 2, firstAt: 1, lastAt: 2),
      MetricsDay(date: '2026-07-02', publishes: 1, firstAt: 3, lastAt: 3),
    ]);
    await u.store.save(st);

    await pumpPorch(tester, u);
    await openSettings(tester);
    expect(find.textContaining('3 taps'), findsOneWidget);
    expect(find.textContaining('2 days'), findsOneWidget);
  });

  testWidgets('"What leaves your device" names the residuals honestly',
      (tester) async {
    final u = await UiWorld.onboarded();
    await pumpPorch(tester, u);
    await openSettings(tester);

    await tapItem(tester, find.text('What leaves your device'));
    expect(find.textContaining('ciphertext'), findsWidgets);
    expect(find.textContaining('IP address'), findsWidgets,
        reason: 'the accepted residual is NAMED, not hidden (§1.6)');
    expect(find.textContaining('Never leaves'), findsWidgets);
  });
}
