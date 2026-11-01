// W4 presentation test harness: provider overrides around ONE FakeRelay
// and ONE controllable clock, reusing the W3 data harness for peers.
//
// `UiWorld.fresh()` is a never-launched install (no identity, no state);
// `UiWorld.onboarded()` is a device past onboarding with one group.
// Peers ("Bob's phone") are plain W3 TestDevices on the same world.
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:openhearth_design/openhearth_design.dart'
    show OhThemeModePreference;

import 'package:porch_app/data/backup_share.dart';
import 'package:porch_app/data/backup_sink.dart';
import 'package:porch_app/data/env.dart';
import 'package:porch_app/data/group_repo.dart';
import 'package:porch_app/data/identity_service.dart';
import 'package:porch_app/data/invite_repo.dart';
import 'package:porch_app/data/key_store.dart';
import 'package:porch_app/data/notification_service.dart';
import 'package:porch_app/data/porch_state.dart';
import 'package:porch_app/data/relay_config.dart';
import 'package:porch_app/data/state_store.dart';
import 'package:porch_app/data/theme_store.dart';
import 'package:porch_app/presentation/providers.dart';

import '../../data/support/harness.dart';
import '../../domain/support/test_sodium.dart';

export '../../data/support/harness.dart' show TestWorld, TestDevice;

/// Local-notification double for assertions.
class RecordingLocalNotifier implements LocalNotifier {
  final shown = <(String title, String body)>[];
  @override
  Future<void> show({required String title, required String body}) async {
    shown.add((title, body));
  }
}

/// A configured relay for screen tests (RFC 2606 reserved name; the
/// FakeRelay answers whatever the URL). Tests that exercise the shipped
/// "no relay configured" state set [UiWorld.relayUrl] to [defaultRelayUrl].
const testRelayUrl = 'https://relay.example';

class UiWorld {
  final TestWorld world;

  /// The relay URL in effect when the app is pumped. Defaults to a
  /// configured relay so feed/presence tests mean "the relay works".
  String relayUrl = testRelayUrl;
  final PorchKeyStore keys;

  /// The keystore under [keys]. With [openStateStoreAtLaunch] set, the
  /// saved relay URL is read from it too, as on a phone.
  final SecretStore secrets;
  final InMemoryStateStore store;

  /// Replaces [store] in the app's wiring when set, e.g. with one that
  /// fails to read, to drive the root gate's error path.
  StateStore? appStateStore;

  /// When set, the app is wired as bootstrap wires it (launchWiring): the
  /// state store opens with the state key the launch read, and the relay
  /// endpoint starts at the saved relay URL from [secrets]. Gets the key
  /// and returns the store the app uses.
  StateStore Function(Uint8List stateKey)? openStateStoreAtLaunch;
  final RecordingLocalNotifier notifier = RecordingLocalNotifier();
  final RecordingBackupSink backupSink = RecordingBackupSink();
  final RecordingBackupShare backupShare = RecordingBackupShare();

  /// Where the theme choice lands (inspect with ThemePreferenceStore.key).
  final InMemorySecretStore prefs = InMemorySecretStore();

  /// The theme the app opens with, as bootstrap would read it.
  OhThemeModePreference initialTheme = OhThemeModePreference.defaultValue;

  UiWorld._(this.world, this.secrets, this.store)
      : keys = PorchKeyStore(secrets);

  /// [secrets] replaces the in-memory key store, e.g. with one that
  /// fails, to drive the error paths.
  static Future<UiWorld> fresh({SecretStore? secrets}) async {
    // Fresh, in-zone sodium: testWidgets bodies each run in their own
    // FakeAsync zone, and a future completed in another zone never
    // resolves there (see test_sodium.dart).
    final world =
        await TestWorld.create(sodium: await loadTestSodiumFresh());
    return UiWorld._(
        world, secrets ?? InMemorySecretStore(), InMemoryStateStore());
  }

  /// A device that already finished onboarding: identity (from [seed]),
  /// display name, and one group.
  static Future<UiWorld> onboarded({
    String name = 'Alice',
    int seed = 1,
    String group = 'My Porch',
    SecretStore? secrets,
  }) async {
    final u = await fresh(secrets: secrets);
    final identity = await IdentityService(u.world.sodium, u.keys)
        .create(entropy: Uint8List.fromList(List.filled(16, seed)));
    final state = PorchState.initial();
    state.profile.displayName = name;
    await u.store.save(state);
    final env = PorchEnv(
      sodium: u.world.sodium,
      relay: u.world.relay,
      stateStore: u.store,
      identity: identity,
      now: () => u.world.clock.nowSec,
      rotationJitter: () => 0,
    );
    await GroupRepo(env).createGroup(group);
    return u;
  }

  /// Another person's phone on the same relay (W3 harness device).
  Future<TestDevice> peer(String name, {required int seed}) =>
      TestDevice.onboard(world, name: name, seed: seed);

  void advance(int seconds) => world.advance(seconds);

  List<Override> get overrides {
    final openAtLaunch = openStateStoreAtLaunch;
    return [
      sodiumProvider.overrideWithValue(world.sodium),
      relayProvider.overrideWithValue(world.relay),
      keyStoreProvider.overrideWithValue(keys),
      if (openAtLaunch != null) ...[
        ...launchWiring(openStateStore: openAtLaunch),
        relayConfigStoreProvider.overrideWithValue(RelayConfigStore(secrets)),
      ] else ...[
        stateStoreProvider.overrideWithValue(appStateStore ?? store),
        // Runtime relay-URL config, mirroring bootstrap: an in-memory
        // override store and a live endpoint holder seeded with [relayUrl].
        relayConfigStoreProvider
            .overrideWithValue(RelayConfigStore(InMemorySecretStore())),
        relayEndpointProvider
            .overrideWithValue(RelayEndpoint(Uri.parse(relayUrl))),
      ],
      clockProvider.overrideWithValue(() => world.clock.nowSec),
      tickerEnabledProvider.overrideWithValue(false),
      // Deterministic transcripts; the schedule itself is unit-tested
      // in test/data/outbox_jitter_test.dart.
      rotationJitterProvider.overrideWithValue(() => 0),
      localNotifierProvider.overrideWithValue(notifier),
      backupSinkProvider.overrideWithValue(backupSink),
      backupShareProvider.overrideWithValue(backupShare),
      themeStoreProvider.overrideWithValue(ThemePreferenceStore(prefs)),
      initialThemeProvider.overrideWithValue(initialTheme),
      // Argon2id at test speed; production uses MODERATE defaults.
      backupLimitsProvider.overrideWithValue((
        ops: world.sodium.crypto.pwhash.opsLimitMin,
        mem: world.sodium.crypto.pwhash.memLimitMin,
      )),
    ];
  }

  ProviderContainer container() {
    final c = ProviderContainer(overrides: overrides);
    return c;
  }

  /// This device's own repositories OUTSIDE the widget tree (same stores
  /// the UI uses) — for arranging scenarios around the screen under test.
  Future<PorchEnv> env() async {
    final identity = await IdentityService(world.sodium, keys).load();
    if (identity == null) throw StateError('UiWorld has no identity yet');
    return PorchEnv(
      sodium: world.sodium,
      relay: world.relay,
      stateStore: store,
      identity: identity,
      now: () => world.clock.nowSec,
      rotationJitter: () => 0,
    );
  }
}

/// Wire a peer into this device's single group, headlessly: mint → redeem
/// → fulfill → complete. Returns the peer's device.
Future<TestDevice> addFriend(
  UiWorld u, {
  String name = 'Bob',
  int seed = 2,
  String contactNote = '',
}) async {
  final env = await u.env();
  final invites = InviteRepo(env);
  final state = await u.store.load();
  final groupUuid = state!.groups.single.groupUuid;
  final handle = await invites.mint(groupUuid);
  final friend = await u.peer(name, seed: seed);
  final joined = await friend.invites.redeem(handle.code);
  await invites.fulfillPending(groupUuid);
  await friend.invites.completeJoin(joined);
  if (contactNote.isNotEmpty) {
    await friend.groups.updateProfile(contactNote: contactNote);
  }
  return friend;
}
