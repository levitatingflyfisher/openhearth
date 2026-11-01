// Shared W3-data test harness: N simulated devices around ONE FakeRelay and
// ONE controllable clock — repository and sync tests read like protocol
// transcripts.
import 'dart:typed_data';

import 'package:sodium/sodium_sumo.dart';

import 'package:porch_app/data/env.dart';
import 'package:porch_app/data/fake_relay.dart';
import 'package:porch_app/data/group_repo.dart';
import 'package:porch_app/data/identity_service.dart';
import 'package:porch_app/data/invite_repo.dart';
import 'package:porch_app/data/key_store.dart';
import 'package:porch_app/data/porch_state.dart';
import 'package:porch_app/data/presence_repo.dart';
import 'package:porch_app/data/state_store.dart';
import 'package:porch_app/data/sync_service.dart';
import 'package:porch_app/data/widget_cache.dart';
import 'package:porch_app/domain/domain.dart';

import '../../domain/support/test_sodium.dart';

/// One clock shared by every device and the relay.
class TestClock {
  int nowSec;
  TestClock(this.nowSec);
}

class TestWorld {
  final SodiumSumo sodium;
  final FakeRelay relay;
  final TestClock clock;
  TestWorld._(this.sodium, this.relay, this.clock);

  static Future<TestWorld> create(
      {int nowSec = 1_700_000_000, SodiumSumo? sodium}) async {
    sodium ??= await loadTestSodium();
    return TestWorld._(sodium, FakeRelay(sodium, nowSec: nowSec), TestClock(nowSec));
  }

  void advance(int seconds) {
    clock.nowSec += seconds;
    relay.nowSec = clock.nowSec;
  }
}

class TestDevice {
  final String name;
  final TestWorld world;
  final InMemoryStateStore store;
  final PorchKeyStore keys;
  final PorchIdentity identity;
  final PorchEnv env;
  late final GroupRepo groups;
  late final PresenceRepo presence;
  late final InviteRepo invites;
  late final RecordingWidgetMirror widgetMirror;
  late final SyncService sync;

  TestDevice._(this.name, this.world, this.store, this.keys, this.identity,
      this.env) {
    groups = GroupRepo(env);
    presence = PresenceRepo(env);
    invites = InviteRepo(env);
    widgetMirror = RecordingWidgetMirror();
    sync = SyncService(env, widgetMirror: widgetMirror);
  }

  /// [rotationJitter] defaults to zero so protocol transcripts stay
  /// deterministic; the jitter schedule itself is tested in
  /// outbox_jitter_test.dart with scripted values.
  static Future<TestDevice> onboard(TestWorld world,
      {required String name,
      required int seed,
      int Function()? rotationJitter}) async {
    final keys = PorchKeyStore(InMemorySecretStore());
    final identityService = IdentityService(world.sodium, keys);
    final identity = await identityService.create(
        entropy: Uint8List.fromList(List.filled(16, seed)));
    final store = InMemoryStateStore();
    final state = PorchState.initial();
    state.profile.displayName = name;
    await store.save(state);
    final env = PorchEnv(
      sodium: world.sodium,
      relay: world.relay,
      stateStore: store,
      identity: identity,
      now: () => world.clock.nowSec,
      rotationJitter: rotationJitter ?? () => 0,
    );
    return TestDevice._(name, world, store, keys, identity, env);
  }

  Future<PorchState> state() async => (await store.load())!;
}

/// Widget mirror that records every write for assertions.
class RecordingWidgetMirror implements WidgetCacheMirror {
  final writes = <WidgetCacheSnapshot>[];
  @override
  Future<void> write(WidgetCacheSnapshot snapshot) async =>
      writes.add(snapshot);
}
