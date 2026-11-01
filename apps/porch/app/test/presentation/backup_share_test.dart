// A backup file must be reachable: the sink writes into the app's own
// storage (deleted on uninstall on Android), so after every backup the
// person is told where it went and offered the share sheet to put a copy
// somewhere that lasts.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/pump.dart';
import 'support/ui_world.dart';

void main() {
  testWidgets('settings: after a backup, Share / save backup file hands the '
      'same blob to the share sheet as a .porchbackup file', (tester) async {
    final u = await UiWorld.onboarded();
    await pumpPorch(tester, u);
    await openSettings(tester);
    await tapItem(tester, find.text('Save encrypted backup'));
    await tapItem(tester, find.text('Create backup'));

    expect(find.text('Backup saved'), findsOneWidget);
    expect(find.textContaining('deleted if you uninstall'), findsOneWidget);
    expect(u.backupShare.shared, isEmpty, reason: 'sharing is the person\'s call');

    await tapItem(tester, find.text('Share / save backup file'));
    expect(u.backupShare.shared, hasLength(1));
    final s = u.backupShare.shared.single;
    expect(s.blob, u.backupSink.saved.single);
    expect(s.fileName, startsWith('porch-'));
    expect(s.fileName, endsWith('.porchbackup'));
    expect(u.world.relay.callLog, isEmpty);
  });

  testWidgets('onboarding: the backup step offers the share sheet too, then '
      'moves on to the name', (tester) async {
    final u = await UiWorld.fresh();
    await pumpPorch(tester, u);
    await tapItem(tester, find.widgetWithText(FilledButton, "I’m 13 or older"));
    await tapItem(tester, find.text('I wrote them down'));
    await tapItem(tester, find.text('Create encrypted backup'));

    await tapItem(tester, find.text('Share / save backup file'));
    expect(u.backupShare.shared.single.blob, u.backupSink.saved.single);
    await tapItem(tester, find.text('Done'));
    expect(find.textContaining('friends see you'), findsWidgets);
  });
}
