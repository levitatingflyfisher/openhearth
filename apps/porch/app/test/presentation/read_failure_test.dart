// A failed read of this phone's own identity or state file (riverpod 3).
//
// Two riverpod 3 defaults meet the root gate here:
// - automatic retry: a provider that fails with an Exception runs again up
//   to 10 times over about 38 s, and shows as loading in between, so the
//   gate would sit on a spinner;
// - `AsyncValue.value` is null on a failure, so the gate would read a
//   failed read as "no identity yet" or "not onboarded" and show
//   onboarding, whose restore step saves over the unreadable state file.
//
// Porch turns retry off and shows the failure. These pins fail if either
// comes back.
//
// The keystore reads launch needs (the state key, the saved relay URL) run
// under the same gate, not before runApp, so a keystore that refuses at
// launch is shown the same way and Try again reads it again.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhearth_design/openhearth_design.dart';

import 'package:porch_app/data/key_store.dart';
import 'package:porch_app/data/porch_state.dart';
import 'package:porch_app/data/relay_config.dart';
import 'package:porch_app/data/state_store.dart';
import 'package:porch_app/data/theme_store.dart';
import 'package:porch_app/presentation/home/home_screen.dart';
import 'package:porch_app/presentation/onboarding/onboarding_flow.dart';
import 'package:porch_app/presentation/providers.dart';

import 'support/pump.dart';
import 'support/ui_world.dart';

/// A keystore whose reads can be made to fail, and counts reads per key
/// and writes. [failOnly] limits the failure to some keys.
class _FlakySecretStore extends InMemorySecretStore {
  Object? failReads;
  Set<String>? failOnly;
  final reads = <String, int>{};
  int writes = 0;

  int get entropyReads => reads[PorchKeyStore.entropyKey] ?? 0;
  int get stateKeyReads => reads[PorchKeyStore.stateKeyKey] ?? 0;

  @override
  Future<String?> read(String key) async {
    reads[key] = (reads[key] ?? 0) + 1;
    final failure = failReads;
    final only = failOnly;
    if (failure != null && (only == null || only.contains(key))) {
      throw failure;
    }
    return super.read(key);
  }

  @override
  Future<void> write(String key, String value) {
    writes++;
    return super.write(key, value);
  }
}

/// A state store whose load can be made to fail, and counts loads and saves.
class _FlakyStateStore implements StateStore {
  final StateStore inner;
  Object? failLoads;
  int loads = 0;
  int saves = 0;
  _FlakyStateStore(this.inner);

  @override
  Future<PorchState?> load() async {
    loads++;
    final failure = failLoads;
    if (failure != null) throw failure;
    return inner.load();
  }

  @override
  Future<void> save(PorchState state) {
    saves++;
    return inner.save(state);
  }

  @override
  Future<void> clear() => inner.clear();
}

Exception _keystoreBusy() =>
    Exception('PlatformException(keystore-busy, read refused)');

void main() {
  group('the provider itself does not retry', () {
    test('sessionProvider: a failed keystore read is read once and stays '
        'an error', () async {
      final secrets = _FlakySecretStore()..failReads = _keystoreBusy();
      final u = await UiWorld.fresh(secrets: secrets);
      final c = u.container();
      addTearDown(c.dispose);
      final seen = <AsyncValue<PorchSession?>>[];
      c.listen(sessionProvider, (_, next) => seen.add(next),
          fireImmediately: true);

      // The default policy would run it again at 200 ms and 600 ms.
      await Future<void>.delayed(const Duration(seconds: 1));

      expect(secrets.entropyReads, 1);
      final now = c.read(sessionProvider);
      expect(now.hasError, isTrue);
      expect(now.isLoading, isFalse, reason: 'no retry is pending');
      expect(seen.whereType<AsyncData<PorchSession?>>(), isEmpty);
    });

    test('porchStateProvider: a failed state file read is read once and '
        'stays an error', () async {
      final u = await UiWorld.onboarded();
      final store = _FlakyStateStore(u.store)
        ..failLoads = Exception('FileSystemException: read failed');
      u.appStateStore = store;
      final c = u.container();
      addTearDown(c.dispose);
      final seen = <AsyncValue<PorchState?>>[];
      c.listen(porchStateProvider, (_, next) => seen.add(next),
          fireImmediately: true);

      await Future<void>.delayed(const Duration(seconds: 1));

      expect(store.loads, 1);
      final now = c.read(porchStateProvider);
      expect(now.hasError, isTrue);
      expect(now.isLoading, isFalse, reason: 'no retry is pending');
      expect(seen.whereType<AsyncData<PorchState?>>(), isEmpty);
    });
  });

  group('the root gate shows a failed read as a failure', () {
    testWidgets('a keystore that cannot be read: an error, never '
        'onboarding; Try again opens Home once it answers', (tester) async {
      final secrets = _FlakySecretStore();
      final u = await UiWorld.onboarded(secrets: secrets);
      secrets
        ..reads.clear()
        ..failOnly = {PorchKeyStore.entropyKey}
        ..failReads = _keystoreBusy();

      await pumpPorch(tester, u);

      expect(find.byType(OhErrorState), findsOneWidget);
      expect(find.byType(OnboardingFlow), findsNothing,
          reason: 'onboarding would offer a new identity or a restore');
      expect(find.textContaining('keystore-busy'), findsNothing,
          reason: 'the raw exception stays behind Details');
      expect(secrets.entropyReads, 1, reason: 'no retry loop');

      secrets.failReads = null;
      await tapItem(tester, find.text('Try again'));

      expect(find.byType(OhErrorState), findsNothing);
      expect(find.byKey(porchLightKey), findsOneWidget);
    });

    testWidgets('a state file that cannot be opened: an error, never '
        'onboarding, nothing saved over it; Try again opens Home once it '
        'reads', (tester) async {
      final u = await UiWorld.onboarded();
      final store = _FlakyStateStore(u.store)
        ..failLoads =
            StateCorruptError('decryption failed (wrong key or tampering)');
      u.appStateStore = store;

      await pumpPorch(tester, u);

      expect(find.byType(OhErrorState), findsOneWidget);
      expect(find.byType(OnboardingFlow), findsNothing,
          reason: 'onboarding would show the words step and a restore '
              'that saves over the file');
      expect(find.textContaining('decryption failed'), findsNothing);
      expect(store.loads, 1);
      expect(store.saves, 0);

      store.failLoads = null;
      await tapItem(tester, find.text('Try again'));

      expect(find.byType(OhErrorState), findsNothing);
      expect(find.byKey(porchLightKey), findsOneWidget);
      expect(store.saves, 0);
    });
  });
  group('a garbled secret in the keystore', () {
    testWidgets('a garbled identity: an error, never onboarding, and the '
        'stored value is not written over', (tester) async {
      final secrets = _FlakySecretStore();
      final u = await UiWorld.onboarded(secrets: secrets);
      // This phone already has its state key, so launch writes nothing.
      await u.keys.ensureStateKey(u.world.sodium);
      await secrets.write(PorchKeyStore.entropyKey, 'not-hex-at-all');
      secrets.writes = 0;

      await pumpPorch(tester, u);

      expect(find.byType(OhErrorState), findsOneWidget);
      expect(find.byType(OnboardingFlow), findsNothing,
          reason: 'onboarding would write a new identity over the old one');
      expect(secrets.writes, 0);
      expect(await secrets.read(PorchKeyStore.entropyKey), 'not-hex-at-all');
    });

    testWidgets('a garbled identity offers a restore, behind a confirm; '
        'Cancel changes nothing', (tester) async {
      final secrets = _FlakySecretStore();
      final u = await UiWorld.onboarded(secrets: secrets);
      await u.keys.ensureStateKey(u.world.sodium);
      await secrets.write(PorchKeyStore.entropyKey, 'not-hex-at-all');
      secrets.writes = 0;

      await pumpPorch(tester, u);
      await tapItem(tester, find.text('Restore from words or backup'));

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('set aside'), findsOneWidget);
      await tapItem(tester, find.text('Cancel'));

      expect(find.byType(OhErrorState), findsOneWidget);
      expect(secrets.writes, 0);
      expect(await secrets.read(PorchKeyStore.entropyKey), 'not-hex-at-all');
    });

    testWidgets('confirming sets the garbled identity aside under a dated '
        'key, then opens the restore', (tester) async {
      final secrets = _FlakySecretStore();
      final u = await UiWorld.onboarded(secrets: secrets);
      await u.keys.ensureStateKey(u.world.sodium);
      await secrets.write(PorchKeyStore.entropyKey, 'not-hex-at-all');

      await pumpPorch(tester, u);
      await tapItem(tester, find.text('Restore from words or backup'));
      await tapItem(tester, find.text('Set aside and restore'));

      final aside = await u.keys.setAsideKeys();
      expect(aside, hasLength(1));
      expect(aside.single, startsWith('porch.entropy.v1.garbled-'));
      expect(await secrets.read(aside.single), 'not-hex-at-all',
          reason: 'the garbled value is kept, never deleted');
      expect(find.byType(OhErrorState), findsNothing);
      expect(find.byType(OnboardingFlow), findsOneWidget);
    });

    testWidgets('a keystore that refuses (not garbled) offers no restore',
        (tester) async {
      final secrets = _FlakySecretStore();
      final u = await UiWorld.onboarded(secrets: secrets);
      secrets
        ..failOnly = {PorchKeyStore.entropyKey}
        ..failReads = _keystoreBusy();

      await pumpPorch(tester, u);

      expect(find.byType(OhErrorState), findsOneWidget);
      expect(find.text('Restore from words or backup'), findsNothing,
          reason: 'a busy keystore may answer on Try again');
    });

    testWidgets('a garbled state key: an error at launch, no fresh key over '
        'it, no state store opened', (tester) async {
      final secrets = _FlakySecretStore();
      final u = await UiWorld.onboarded(secrets: secrets);
      await secrets.write(PorchKeyStore.stateKeyKey, 'abcd');
      final opened = <Uint8List>[];
      u.openStateStoreAtLaunch = (key) {
        opened.add(key);
        return u.store;
      };
      secrets.writes = 0;

      await pumpPorch(tester, u);

      expect(find.byType(OhErrorState), findsOneWidget);
      expect(find.byType(OnboardingFlow), findsNothing);
      expect(secrets.writes, 0,
          reason: 'no fresh state key over one that could not be read');
      expect(await secrets.read(PorchKeyStore.stateKeyKey), 'abcd');
      expect(opened, isEmpty);
    });
  });
  group('a keystore that refuses at launch', () {
    testWidgets('the app starts and shows the failure, never onboarding; '
        'Try again reads again and opens Home; nothing is written',
        (tester) async {
      final secrets = _FlakySecretStore();
      final u = await UiWorld.onboarded(secrets: secrets);
      // This phone already has its state key and a saved relay URL.
      final stateKey = await u.keys.ensureStateKey(u.world.sodium);
      await RelayConfigStore(secrets).write(testRelayUrl);
      final store = _FlakyStateStore(u.store);
      final openedWith = <Uint8List>[];
      u.openStateStoreAtLaunch = (key) {
        openedWith.add(key);
        return store;
      };
      secrets
        ..reads.clear()
        ..writes = 0
        ..failReads = _keystoreBusy();

      await pumpPorch(tester, u);

      expect(find.byType(OhErrorState), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.byType(OnboardingFlow), findsNothing,
          reason: 'onboarding would offer a new identity or a restore');
      expect(find.textContaining('keystore-busy'), findsNothing,
          reason: 'the raw exception stays behind Details');
      expect(secrets.stateKeyReads, 1, reason: 'read once, no retry loop');
      expect(secrets.writes, 0,
          reason: 'no fresh state key over one that could not be read');
      expect(openedWith, isEmpty, reason: 'no state store without its key');
      expect(store.loads, 0);
      expect(store.saves, 0);

      secrets.failReads = null;
      await tapItem(tester, find.text('Try again'));

      expect(find.byType(OhErrorState), findsNothing);
      expect(find.byKey(porchLightKey), findsOneWidget);
      expect(secrets.stateKeyReads, 2, reason: 'Try again read it again');
      expect(openedWith.single, stateKey,
          reason: 'the state file opens with the key the phone holds');
      final container =
          ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
      expect(container.read(relayEndpointProvider).url,
          Uri.parse(testRelayUrl),
          reason: 'the saved relay URL is read at launch too');
      expect(secrets.writes, 0);
      expect(store.saves, 0);
    });

    test('a theme read that fails opens in the default theme and writes '
        'nothing', () async {
      final secrets = _FlakySecretStore()..failReads = _keystoreBusy();
      expect(await readLaunchTheme(ThemePreferenceStore(secrets)),
          OhThemeModePreference.defaultValue);
      expect(secrets.writes, 0);
    });

    test('a theme read that answers opens in the saved theme', () async {
      final secrets = _FlakySecretStore();
      final themes = ThemePreferenceStore(secrets);
      await themes.write(OhThemeModePreference.dark.storageValue);
      expect(await readLaunchTheme(themes), OhThemeModePreference.dark);
    });
  });
}
