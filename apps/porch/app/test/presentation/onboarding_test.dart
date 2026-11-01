// W4 acceptance: onboarding flow — age gate (13+) → silent keygen →
// 12-word reveal → optional backup → display name → "My Porch" auto-created;
// nothing (least of all the name) reaches the network in plaintext, because
// nothing reaches the network AT ALL.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:porch_app/domain/domain.dart';
import 'package:porch_app/presentation/backup_saved_dialog.dart'
    show backupWordsNote;

import 'support/pump.dart';
import 'support/ui_world.dart';

void main() {

  testWidgets('full onboarding: age gate → keygen → words → skip backup → '
      'name → home with My Porch; the relay hears nothing', (tester) async {
    final u = await UiWorld.fresh();
    await pumpPorch(tester, u);

    // 1. Age gate first — nothing else.
    expect(find.textContaining('13 or older'), findsOneWidget);
    expect(await u.keys.readEntropy(), isNull, reason: 'no keygen yet');

    await tapItem(tester, find.widgetWithText(FilledButton, "I’m 13 or older"));

    // 2. Keygen happened silently; the 12 words on screen ARE the entropy.
    final entropy = await u.keys.readEntropy();
    expect(entropy, isNotNull);
    final words = entropyToMnemonic(entropy!);
    expect(find.textContaining('recovery words'), findsWidgets);
    for (final w in words.toSet()) {
      expect(find.textContaining(w), findsWidgets,
          reason: 'word "$w" must be revealed');
    }
    // Honesty copy: no server recovery exists, by design (§1.6).
    expect(find.textContaining('No server'), findsOneWidget);
    // Beside them, the 6 backup words Porch picked, said plainly to be
    // what unlocks a backup file.
    expect(find.text('Your 6 backup words'), findsOneWidget);
    expect(find.text(backupWordsNote), findsOneWidget);
    final backupWords = backupPassphrase(u.world.sodium, entropy);
    for (var i = 0; i < 6; i++) {
      expect(find.text('${i + 1}. ${backupWords[i]}'), findsWidgets);
    }

    await tapItem(tester, find.text('I wrote them down'));

    // 3. Backup offer is OPTIONAL — skip it.
    expect(find.textContaining('backup'), findsWidgets);
    await tapItem(tester, find.text('Skip for now'));

    // 4. Display name, then done.
    await tester.enterText(find.byType(TextField), 'Alice');
    // The button names what it does: it finishes setup and saves the name.
    // It must not borrow the core action's words — that would teach a
    // wrong first meaning of "turn on the porch" (writing-is-designing-08).
    expect(find.textContaining('Turn on the porch'), findsNothing);
    await tapItem(tester, find.text('Finish setup'));

    // 5. Home. "My Porch" exists; profile carries the name; self is admin.
    expect(find.text('Porch'), findsWidgets);
    final state = (await u.store.load())!;
    expect(state.profile.displayName, 'Alice');
    expect(state.groups.single.name, 'My Porch');
    expect(state.groups.single.roster.members.single.isAdmin, isTrue);

    // 6. The whole flow was network-silent.
    expect(u.world.relay.callLog, isEmpty,
        reason: 'onboarding must not touch the relay');
  });

  testWidgets('backup offer path: one tap writes one encrypted blob '
      'to the sink and moves on', (tester) async {
    final u = await UiWorld.fresh();
    await pumpPorch(tester, u);
    await tapItem(tester, find.widgetWithText(FilledButton, "I’m 13 or older"));
    await tapItem(tester, find.text('I wrote them down'));
    await tapItem(tester, find.text('Create encrypted backup'));

    expect(u.backupSink.saved, hasLength(1));
    // The blob is ciphertext: the 6 backup words open it, entropy matches.
    final contents = openBackup(u.world.sodium,
        passphrase: backupPassphrase(
                u.world.sodium, (await u.keys.readEntropy())!)
            .join(' '),
        blob: u.backupSink.saved.single);
    expect(contents.entropy, await u.keys.readEntropy());

    // The saved-backup dialog (share offer — see backup_share_test.dart),
    // then the flow continues to the name step.
    await tapItem(tester, find.text('Done'));
    expect(find.textContaining('friends see you'), findsWidgets);
  });

  testWidgets('restore path: 12 words rebuild the same identity '
      'deterministically', (tester) async {
    final u = await UiWorld.fresh();
    // The identity to restore (a known entropy → known words).
    final entropy = Uint8List.fromList(List.filled(16, 7));
    final words = entropyToMnemonic(entropy);

    await pumpPorch(tester, u);
    await tapItem(tester, find.text('Restore an existing identity'));

    await tester.enterText(find.byType(TextField), words.join(' '));
    await tapItem(tester, find.text('Restore'));

    expect(await u.keys.readEntropy(), entropy);
    // Restore is identity-only (§3.1 step 8): the UI says so honestly.
    expect(find.textContaining('invite you again', findRichText: true), findsWidgets);
  });

  testWidgets('a relaunch mid-onboarding (identity exists, no name yet) '
      'resumes at the words step, not the age gate', (tester) async {
    final u = await UiWorld.fresh();
    await pumpPorch(tester, u);
    await tapItem(tester, find.widgetWithText(FilledButton, "I’m 13 or older"));

    // "Relaunch": fresh widget tree, same stores.
    await tester.pumpWidget(const SizedBox());
    await pumpPorch(tester, u);
    expect(find.textContaining('recovery words'), findsWidgets);
    expect(find.textContaining('13 or older'), findsNothing);
  });
}
