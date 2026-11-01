// W3/W5: the localhost integration harness (BUILD-SPEC W3 "Integration"
// bullet) — boots the COMPILED Go relay (memstore) and drives two real
// clients through the production HttpRelayApi + repositories + SyncService:
//
//   onboard ×2 → group → invite → join → grant → both publish → both see
//   the other's tag → silent leave → admin rotates → departed member locked
//   out (no bundle, no new address).
//
// Until this file existed, every network test ran against FakeRelay (whose
// semantics are unit-pinned to match the Go conformance suite) — twinned
// fakes, not proven interop. This is the proof: the Dart wire encodings
// (base64url ids, std-base64 blobs, the `porch-drain|{mailboxId}|{ts}`
// signature, afterSeq paging) hit the real binary.
//
// Requires the Go toolchain to build relayd; if `go` is absent the test
// SKIPS VISIBLY rather than silently passing.
//
// The relay runs on the real wall clock (drain freshness is ±300 s), so
// these scenarios never time-travel; TTL/staleness behaviors stay with the
// fake-clock suites.
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:sodium/sodium_sumo.dart' show SodiumSumo;
import 'package:test/test.dart';

import 'package:porch_app/data/api_client.dart';
import 'package:porch_app/data/env.dart';
import 'package:porch_app/data/group_repo.dart';
import 'package:porch_app/data/identity_service.dart';
import 'package:porch_app/data/invite_repo.dart';
import 'package:porch_app/data/key_store.dart';
import 'package:porch_app/data/porch_state.dart';
import 'package:porch_app/data/presence_repo.dart';
import 'package:porch_app/data/relay_api.dart';
import 'package:porch_app/data/state_store.dart';
import 'package:porch_app/data/sync_service.dart';
import 'package:porch_app/domain/domain.dart';

import '../domain/support/test_sodium.dart';

/// One real client: production repositories over the production HTTP
/// client, in-memory persistence, real clock.
class LiveDevice {
  final String name;
  final HttpRelayApi relay;
  final InMemoryStateStore store;
  final PorchIdentity identity;
  final PorchEnv env;
  late final GroupRepo groups;
  late final PresenceRepo presence;
  late final InviteRepo invites;
  late final SyncService sync;

  LiveDevice._(this.name, this.relay, this.store, this.identity, this.env) {
    groups = GroupRepo(env);
    presence = PresenceRepo(env);
    invites = InviteRepo(env);
    sync = SyncService(env);
  }

  static Future<LiveDevice> onboard(Uri relayUrl,
      {required String name,
      required int seed,
      required SodiumSumo sodium}) async {
    final relay = HttpRelayApi(baseUrl: relayUrl);
    final keys = PorchKeyStore(InMemorySecretStore());
    final identity = await IdentityService(sodium, keys)
        .create(entropy: Uint8List.fromList(List.filled(16, seed)));
    final store = InMemoryStateStore();
    final state = PorchState.initial();
    state.profile.displayName = name;
    await store.save(state);
    final env = PorchEnv(
      sodium: sodium,
      relay: relay,
      stateStore: store,
      identity: identity,
      now: () => DateTime.now().millisecondsSinceEpoch ~/ 1000,
      rotationJitter: () => 0, // deterministic delivery for the transcript
    );
    return LiveDevice._(name, relay, store, identity, env);
  }

  Future<PorchState> state() async => (await store.load())!;
  void close() => relay.close();
}

Future<bool> _hasGo() async {
  try {
    final r = await Process.run('go', ['version']);
    return r.exitCode == 0;
  } on ProcessException {
    return false;
  }
}

void main() async {
  final goAvailable = await _hasGo();

  Process? relayd;
  late Uri baseUrl;
  final relaydStderr = StringBuffer();
  final relaydStdout = StringBuffer();

  setUpAll(() async {
    // The fleet's test/flutter_test_config.dart initializes the widget test
    // binding for every file, and that binding swaps in HttpOverrides that
    // answer every request with 400 without touching the network. This
    // test needs the real socket to the relay it just started.
    HttpOverrides.global = null;
    if (!goAvailable) return;

    // 1. Compile the actual relay binary from this repo's relay/. `flutter
    //    test` runs with the package root (app/) as the working directory,
    //    so the relay source is its sibling — never a machine-specific path.
    final relayDir = Directory('${Directory.current.path}/../relay');
    expect(File('${relayDir.path}/go.mod').existsSync(), isTrue,
        reason: 'relay source not found at ${relayDir.path} — run this '
            'test from app/ inside the porch repo');
    final binDir = await Directory.systemTemp.createTemp('porch-relayd');
    addTearDown(() => binDir.delete(recursive: true));
    final bin = '${binDir.path}/relayd';
    final build = await Process.run('go', ['build', '-o', bin, './cmd/relayd'],
        workingDirectory: relayDir.path);
    expect(build.exitCode, 0, reason: 'go build failed:\n${build.stderr}');

    // 2. Boot it on an ephemeral port (memstore — zero services).
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    await probe.close();
    final p = await Process.start(bin, ['-addr', '127.0.0.1:$port']);
    relayd = p;
    p.stderr
        .transform(const SystemEncoding().decoder)
        .listen(relaydStderr.write);
    p.stdout
        .transform(const SystemEncoding().decoder)
        .listen(relaydStdout.write);
    baseUrl = Uri.parse('http://127.0.0.1:$port');

    // 3. Wait for healthz.
    final client = HttpClient();
    var up = false;
    for (var i = 0; i < 100 && !up; i++) {
      try {
        final rq = await client.getUrl(baseUrl.replace(path: '/v1/healthz'));
        final rs = await rq.close();
        await rs.drain<void>();
        up = rs.statusCode == 200;
      } on SocketException {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    client.close(force: true);
    expect(up, isTrue, reason: 'relayd never answered healthz');
  });

  tearDownAll(() async {
    final p = relayd;
    if (p == null) return;
    p.kill(ProcessSignal.sigterm); // exercises the graceful-shutdown path
    await p.exitCode.timeout(const Duration(seconds: 10), onTimeout: () {
      p.kill(ProcessSignal.sigkill);
      return -9;
    });
    // Structural silence: the binary must have produced NO output while
    // serving the entire transcript (zero-logging is a wire fact, not a
    // promise).
    expect(relaydStderr.toString(), isEmpty);
    expect(relaydStdout.toString(), isEmpty);
  });

  test(
      'full two-device transcript over the compiled relay: invite → grant → '
      'mutual presence → silent leave → rotation locks the departed out',
      skip: goAvailable ? false : 'Go toolchain not on PATH — cannot build relayd',
      () async {
    final sodium = await loadTestSodium();
    final alice = await LiveDevice.onboard(baseUrl,
        name: 'Alice', seed: 11, sodium: sodium);
    final bob = await LiveDevice.onboard(baseUrl,
        name: 'Bob', seed: 22, sodium: sodium);
    addTearDown(alice.close);
    addTearDown(bob.close);

    // --- group + invite handshake (§3.5) over real HTTP ---------------
    final g = await alice.groups.createGroup('My Porch');
    final handle = await alice.invites.mint(g.groupUuid);
    final joined = await bob.invites.redeem(handle.code);
    expect(await alice.invites.fulfillPending(g.groupUuid), 1);
    final bobGroup = await bob.invites.completeJoin(joined);
    expect(bobGroup, isNotNull, reason: 'grant must be waiting');

    // Both ends hold the SAME group key → the same wire address.
    final ag = (await alice.state()).groupByUuid(g.groupUuid)!;
    final bg = (await bob.state()).groupByUuid(g.groupUuid)!;
    expect(bg.epoch, ag.epoch);
    expect(deriveChannelId(sodium, bg.keyring().current.gk),
        deriveChannelId(sodium, ag.keyring().current.gk));
    expect(bg.roster.isMember(alice.identity.sign.publicKey), isTrue);
    expect(bg.roster.isMember(bob.identity.sign.publicKey), isTrue);

    // The grant is delete-after-retrieval on the REAL wire: a second take
    // finds nothing (the repo reads an absent grant as "not yet").
    expect(await bob.invites.completeJoin(joined), isNull);

    // --- mutual presence (§3.4) ----------------------------------------
    final now = alice.env.now();
    await alice.presence.publishAvailable(tag: '🚶', expiresAt: now + 3600);
    await bob.presence.publishAvailable(tag: '📖', expiresAt: now + 1800);

    await alice.sync.refreshFeed();
    await bob.sync.refreshFeed();

    final bobSnap = (await bob.state()).presence[g.groupUuid]!;
    final aliceInBobFeed = bobSnap.entries.singleWhere(
        (e) => b64(e.memberSignPk) == b64(alice.identity.sign.publicKey));
    expect(aliceInBobFeed.tag, '🚶');
    expect(aliceInBobFeed.expiresAt, now + 3600);
    expect(bobSnap.fetchedAt, greaterThan(0));

    final aliceSnap = (await alice.state()).presence[g.groupUuid]!;
    final bobInAliceFeed = aliceSnap.entries.singleWhere(
        (e) => b64(e.memberSignPk) == b64(bob.identity.sign.publicKey));
    expect(bobInAliceFeed.tag, '📖');

    // --- silent leave → rotation (§3.6) --------------------------------
    final oldChannel = deriveChannelId(sodium, ag.keyring().current.gk);
    await bob.groups.leaveGroup(g.groupUuid);
    expect((await bob.state()).groups, isEmpty, reason: 'local wipe');

    // Alice's next poll folds the LEAVE; as admin she rotates.
    await alice.sync.refreshFeed();
    final rotated = (await alice.state()).groupByUuid(g.groupUuid)!;
    expect(rotated.epoch, 2, reason: 'departure rotates');
    expect(rotated.roster.isMember(bob.identity.sign.publicKey), isFalse);
    final newChannel = deriveChannelId(sodium, rotated.keyring().current.gk);
    expect(newChannel, isNot(oldChannel),
        reason: 'the departed member loses the ADDRESS too');

    // Bob's mailbox got NO rotation bundle — he is the departed one.
    // ts is nudged forward: Bob's refreshFeed already drained this second,
    // and Ed25519 is deterministic — an identical ts would produce an
    // identical signature and (correctly) trip the relay's replay cache.
    final bobAuth = buildDrainAuth(sodium,
        sign: bob.identity.sign,
        mailboxId: bob.identity.mailboxId,
        ts: alice.env.now() + 5);
    final bobMail = await bob.relay
        .mailboxDrain(mailboxId: bob.identity.mailboxId, auth: bobAuth);
    expect(bobMail, isEmpty);

    // Alice can publish and read herself on the NEW channel; the transcript
    // ends with the relay still structurally silent (asserted in teardown).
    await alice.presence
        .publishAvailable(tag: '🧹', expiresAt: alice.env.now() + 1800);
    await alice.sync.refreshFeed();
    final finalSnap = (await alice.state()).presence[g.groupUuid]!;
    expect(finalSnap.entries.map((e) => e.tag), contains('🧹'));
  });
}
