// The onboarding backup is taken before any group exists (the name step
// creates "My Porch"), so it must not promise groups, and once a group
// exists Porch offers a fresh backup that holds it — dismissible.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:porch_app/data/porch_state.dart';
import 'package:porch_app/domain/domain.dart';

import 'support/pump.dart';
import 'support/ui_world.dart';

Future<void> onboardWithBackup(WidgetTester tester, UiWorld u) async {
  await pumpPorch(tester, u);
  await tapItem(tester, find.widgetWithText(FilledButton, "I’m 13 or older"));
  await tapItem(tester, find.text('I wrote them down'));
  await tapItem(tester, find.text('Create encrypted backup'));
  await tapItem(tester, find.text('Done'));
  await tester.enterText(find.byType(TextField), 'Alice');
  await tapItem(tester, find.text('Finish setup'));
}

void main() {
  testWidgets('the onboarding backup copy says what the file holds: identity, '
      'no groups yet', (tester) async {
    final u = await UiWorld.fresh();
    await pumpPorch(tester, u);
    await tapItem(tester, find.widgetWithText(FilledButton, "I’m 13 or older"));
    await tapItem(tester, find.text('I wrote them down'));

    expect(find.textContaining('AND your groups'), findsNothing);
    expect(find.textContaining('no groups yet'), findsOneWidget);
  });

  testWidgets('after a groupless onboarding backup, Home offers a fresh one; '
      'making it stores the group and retires the offer', (tester) async {
    final u = await UiWorld.fresh();
    await onboardWithBackup(tester, u);
    final words = backupPassphrase(
            u.world.sodium, (await u.keys.readEntropy())!)
        .join(' ');
    final first = openBackup(u.world.sodium,
        passphrase: words, blob: u.backupSink.saved.single);
    expect(first.stateSnapshot['groups'], isEmpty);

    expect(find.text('Back up your groups'), findsOneWidget);
    await tapItem(tester, find.text('Back up now'));
    await tapItem(tester, find.text('Create backup'));
    await tapItem(tester, find.text('Done'));

    expect(u.backupSink.saved, hasLength(2));
    final fresh = openBackup(u.world.sodium,
        passphrase: words, blob: u.backupSink.saved.last);
    expect(fresh.stateSnapshot['groups'], isNotEmpty);
    expect(find.text('Back up your groups'), findsNothing);
  });

  testWidgets('Not now dismisses the offer for good', (tester) async {
    final u = await UiWorld.fresh();
    await onboardWithBackup(tester, u);

    await tapItem(tester, find.text('Not now'));
    expect(find.text('Back up your groups'), findsNothing);
    // Relaunch: same stores, still gone.
    await tester.pumpWidget(const SizedBox());
    await pumpPorch(tester, u);
    expect(find.text('Back up your groups'), findsNothing);
  });

  testWidgets('no onboarding backup, no offer (nothing was promised)',
      (tester) async {
    final u = await UiWorld.onboarded();
    await pumpPorch(tester, u);
    expect(find.text('Back up your groups'), findsNothing);
  });

  test('state files written before the flag existed read as no offer', () {
    expect(
        Settings.fromJson({'defaultExpiry': 3600, 'customTags': <String>[]})
            .offerFreshBackup,
        isFalse);
  });
}
