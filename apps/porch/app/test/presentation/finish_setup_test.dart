// Fleet ruling 48 (first run): open into the task, and keep unfinished
// setup visible as a dismissable "Finish setup" item so it is never
// forgotten. porch's unfinished setup is the backup onboarding lets you
// skip: Home carries the reminder until a backup exists or the person
// says Not now, and Settings keeps saying so either way.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:porch_app/data/porch_state.dart';

import 'restore_backup_test.dart' show oldPhoneBackup, openBackupRestore;
import 'support/pump.dart';
import 'support/ui_world.dart';

Future<void> onboardSkippingBackup(WidgetTester tester, UiWorld u) async {
  await pumpPorch(tester, u);
  await tapItem(tester, find.widgetWithText(FilledButton, 'I’m 13 or older'));
  await tapItem(tester, find.text('I wrote them down'));
  await tapItem(tester, find.text('Skip for now'));
  await tester.enterText(find.byType(TextField), 'Alice');
  await tapItem(tester, find.text('Finish setup'));
}

const _reminder = 'Finish setup: back up this phone';
const _settingsNotYet = 'Not backed up on this phone yet';

void main() {
  testWidgets('skipping the backup leaves a Finish setup item on Home; '
      'backing up clears it', (tester) async {
    final u = await UiWorld.fresh();
    await onboardSkippingBackup(tester, u);

    expect(find.text(_reminder), findsOneWidget);
    await tapItem(tester, find.text('Back up now'));
    await tapItem(tester, find.text('Create backup'));
    await tapItem(tester, find.text('Done'));

    expect(u.backupSink.saved, hasLength(1));
    expect(find.text(_reminder), findsNothing);
    // The backup held the group, so no "Back up your groups" follows.
    expect(find.text('Back up your groups'), findsNothing);

    await openSettings(tester);
    expect(find.text(_settingsNotYet), findsNothing);
  });

  testWidgets('Not now hides it from Home for good, and Settings still '
      'says the phone is not backed up', (tester) async {
    final u = await UiWorld.fresh();
    await onboardSkippingBackup(tester, u);

    await tapItem(tester, find.text('Not now'));
    expect(find.text(_reminder), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await pumpPorch(tester, u);
    expect(find.text(_reminder), findsNothing);

    await openSettings(tester);
    expect(find.text(_settingsNotYet), findsOneWidget);
  });

  testWidgets('a backup made during onboarding means no reminder',
      (tester) async {
    final u = await UiWorld.fresh();
    await pumpPorch(tester, u);
    await tapItem(tester, find.widgetWithText(FilledButton, 'I’m 13 or older'));
    await tapItem(tester, find.text('I wrote them down'));
    await tapItem(tester, find.text('Create encrypted backup'));
    await tapItem(tester, find.text('Done'));
    await tester.enterText(find.byType(TextField), 'Alice');
    await tapItem(tester, find.text('Finish setup'));

    expect(find.text(_reminder), findsNothing);
    // That backup predates the group, so the fresh-backup offer shows
    // instead: one backup card at a time.
    expect(find.text('Back up your groups'), findsOneWidget);
  });

  testWidgets('restoring from a backup file means no reminder',
      (tester) async {
    final backup = await oldPhoneBackup();
    final u = await UiWorld.fresh();
    await pumpPorch(tester, u);
    await openBackupRestore(tester);
    await tester.enterText(
        find.widgetWithText(TextField, 'Backup file contents'), backup.text);
    await tester.enterText(
        find.widgetWithText(TextField, 'Your 6 backup words'), backup.words);
    await tapItem(tester, find.text('Restore from backup'));

    expect(find.text(_reminder), findsNothing);
  });

  test('a state with no backup record reads as not backed up', () {
    final s = Settings.fromJson({'defaultExpiry': 3600, 'customTags': []});
    expect(s.hasBackup, isFalse);
    expect(s.finishSetupDismissed, isFalse);
  });
}
