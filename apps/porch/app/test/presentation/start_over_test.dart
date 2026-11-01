// "Start over with a new identity" (Settings): leave every group, then
// forget the identity. The order is the point. Each LEAVE is sent while
// the identity still exists; the other members then change the group key,
// so the old identity is in no group and a leaked backup file opens
// nothing anyone still uses. Only then do the backup files, the state and
// the keys go. A group the relay could not reach stops the wipe until the
// person, told which group, chooses to go on.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:porch_app/data/key_store.dart';
import 'package:porch_app/domain/domain.dart';
import 'package:porch_app/presentation/providers.dart';
import 'package:porch_app/presentation/settings/start_over_screen.dart';

import 'support/pump.dart';
import 'support/ui_world.dart';

/// The keystore, telling the test the moment the identity is deleted.
class _WatchedSecrets implements SecretStore {
  final _inner = InMemorySecretStore();
  void Function()? onWipe;

  @override
  Future<String?> read(String key) => _inner.read(key);
  @override
  Future<void> write(String key, String value) => _inner.write(key, value);
  @override
  Future<void> delete(String key) async {
    if (key == PorchKeyStore.entropyKey) onWipe?.call();
    await _inner.delete(key);
  }
}

Future<String> _channelOfOnlyGroup(UiWorld u) async {
  final g = (await u.store.load())!.groups.single;
  return deriveChannelId(u.world.sodium, g.keyring().current.gk);
}

void main() {
  test('every leave is sent before the wipe', () async {
    final secrets = _WatchedSecrets();
    final u = await UiWorld.onboarded(secrets: secrets);
    await addFriend(u);
    final keys = (await u.store.load())!.groups.single.keyring();
    final channel = await _channelOfOnlyGroup(u);
    secrets.onWipe = () => u.world.relay.callLog.add('wipe');
    final c = u.container();
    addTearDown(c.dispose);
    await c.read(sessionProvider.future);

    final result = await c.read(actionsProvider).startOver();

    expect(result.forgotten, isTrue);
    final log = u.world.relay.callLog;
    expect(log, contains('wipe'));
    expect(log.lastIndexOf('bulletinPost'), lessThan(log.indexOf('wipe')));
    final last = (await u.world.relay.bulletinGet(channel)).last;
    expect(openEnvelope(u.world.sodium, wire: last.blob, keyring: keys)?.type,
        'LEAVE');
  });

  test('a wipe after a failed leave happens only when the person chooses '
      'to go on, and is refused otherwise', () async {
    final u = await UiWorld.onboarded();
    await addFriend(u);
    u.world.relay.unreachableChannels.add(await _channelOfOnlyGroup(u));
    final c = u.container();
    addTearDown(c.dispose);
    await c.read(sessionProvider.future);
    final actions = c.read(actionsProvider);
    await actions.saveBackup();

    final refused = await actions.startOver();

    expect(refused.forgotten, isFalse);
    expect(refused.unreached, ['My Porch']);
    expect(await u.keys.readEntropy(), isNotNull);
    expect((await u.store.load())!.groups, hasLength(1));
    expect(u.backupSink.saved, isNotEmpty);

    final goneOn = await actions.startOver(goOnWithoutUnreached: true);

    expect(goneOn.forgotten, isTrue);
    expect(goneOn.unreached, ['My Porch']);
    expect(await u.keys.readEntropy(), isNull);
    expect(await u.keys.readStateKey(), isNull);
    expect(await u.store.load(), isNull);
    expect(u.backupSink.saved, isEmpty);
  });

  test('the local backup files are gone afterwards', () async {
    final u = await UiWorld.onboarded();
    final c = u.container();
    addTearDown(c.dispose);
    await c.read(sessionProvider.future);
    await c.read(actionsProvider).saveBackup();
    await c.read(actionsProvider).saveBackup();
    expect(u.backupSink.saved, hasLength(2));

    await c.read(actionsProvider).startOver();

    expect(u.backupSink.saved, isEmpty);
  });

  testWidgets('the screen says what happens, before the person confirms',
      (tester) async {
    final u = await UiWorld.onboarded();
    await pumpPorch(tester, u);
    await openSettings(tester);
    await tapItem(tester, find.text(startOverTitle));

    expect(find.text(startOverLeavesEveryGroup), findsOneWidget);
    expect(find.text(startOverPhoneForgets), findsOneWidget);
    expect(find.text(startOverCopiesElsewhere), findsOneWidget);
    expect(find.text(startOverThen), findsOneWidget);
    expect(find.text(startOverTypeToConfirm), findsOneWidget);
  });

  test('the words say how to get back into a group, in plain terms', () {
    expect(startOverLeavesEveryGroup,
        'Porch takes you out of every group you are in. Once a friend’s '
        'phone sees you leave, it locks that group again, so your old words '
        'and files can’t get back in.');
    expect(startOverCopiesElsewhere,
        'Backup files you already shared or saved somewhere else are not '
        'deleted, but they no longer get anyone into your groups.');
    expect(startOverThen,
        'Then Porch starts fresh, as on a new phone. To be back in a group, '
        'ask someone in it to invite you again.');
  });

  testWidgets('it needs the typed words, then leaves, forgets, and shows '
      'onboarding', (tester) async {
    final u = await UiWorld.onboarded();
    await addFriend(u);
    await pumpPorch(tester, u);
    await openSettings(tester);
    await tapItem(tester, find.text(startOverTitle));

    final button = find.widgetWithText(FilledButton, startOverButton);
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'start');
    await tester.pump();
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    await tester.enterText(find.byType(TextField), ' Start over ');
    await tester.pump();
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);

    await tapItem(tester, button);

    expect(find.textContaining('13 or older'), findsOneWidget);
    expect(await u.keys.readEntropy(), isNull);
  });

  testWidgets('a group that could not be reached is named; Cancel keeps the '
      'identity, Go on anyway forgets it', (tester) async {
    final u = await UiWorld.onboarded();
    await addFriend(u);
    u.world.relay.unreachableChannels.add(await _channelOfOnlyGroup(u));
    await pumpPorch(tester, u);
    await openSettings(tester);
    await tapItem(tester, find.text(startOverTitle));
    await tester.enterText(find.byType(TextField), 'start over');
    await tester.pump();
    final button = find.widgetWithText(FilledButton, startOverButton);

    await tapItem(tester, button);
    expect(find.text(startOverUnreachedTitle), findsOneWidget);
    expect(find.textContaining('My Porch'), findsWidgets);
    await tapItem(tester, find.text('Cancel'));
    expect(await u.keys.readEntropy(), isNotNull);
    expect(find.text(startOverTitle), findsWidgets);

    await tapItem(tester, button);
    await tapItem(tester, find.text(startOverGoOn));

    expect(find.textContaining('13 or older'), findsOneWidget);
    expect(await u.keys.readEntropy(), isNull);
  });
}
