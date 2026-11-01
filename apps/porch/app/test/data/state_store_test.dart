// W3-data: state_store — ONE versioned JSON state file (§5.2) encrypted with
// XChaCha20-Poly1305 under the state key (§1.5 client-storage row: no
// SQLCipher, no Drift). Atomic write+rename; a kill mid-write must leave the
// old state intact. The social graph never touches disk in plaintext.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sodium/sodium.dart' show SecureKey;
import 'package:test/test.dart';

import 'package:porch_app/data/porch_state.dart';
import 'package:porch_app/data/state_store.dart';
import 'package:porch_app/domain/domain.dart';

import '../domain/support/test_sodium.dart';

void main() {
  late Directory dir;
  late Uint8List stateKey;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('porch_state_test');
    final sodium = await loadTestSodium();
    stateKey = sodium.randombytes.buf(32);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<EncryptedFileStateStore> makeStore(
          {Map<String, Object?> Function(Map<String, Object?>)? migrate}) async =>
      EncryptedFileStateStore(
        await loadTestSodium(),
        directory: dir.path,
        stateKey: stateKey,
        migrate: migrate,
      );

  /// A state exercising every §5.2 section.
  Future<PorchState> fullState() async {
    final sodium = await loadTestSodium();
    final alice = PorchIdentity.fromEntropy(
        sodium, Uint8List.fromList(List.filled(16, 1)));
    final bob = PorchIdentity.fromEntropy(
        sodium, Uint8List.fromList(List.filled(16, 2)));

    final gk2 = Uint8List.fromList(List.generate(32, (i) => i));
    final gk3 = Uint8List.fromList(List.generate(32, (i) => 100 + i));
    final keyring = GroupKeyring.fromGrant(epoch: 2, gk: gk2)
        .adopt(epoch: 3, gk: gk3, nowSec: 1_700_000_500);

    final roster = Roster(members: [
      RosterEntry(
          signPk: alice.sign.publicKey,
          boxPk: alice.box.publicKey,
          displayName: 'Alice',
          contactNote: 'Signal me',
          joinedAt: 1_700_000_000,
          isAdmin: true),
      RosterEntry(
          signPk: bob.sign.publicKey,
          boxPk: bob.box.publicKey,
          displayName: 'Bob',
          contactNote: '',
          joinedAt: 1_700_000_100,
          isAdmin: false),
    ]);

    final state = PorchState.initial();
    state.profile
      ..displayName = 'Alice'
      ..contactNote = 'Signal me';
    state.groups.add(StoredGroup(
      groupUuid: 'uuid-1',
      name: 'My Porch',
      keys: StoredEpochKey.listFromKeyring(keyring),
      roster: roster,
      pendingInvites: [
        PendingInvite(
            inviteId: 'i' * 22,
            t: Uint8List.fromList(List.filled(32, 9)),
            expiresAt: 1_700_100_000,
            status: InviteStatus.joined),
      ],
      lastBulletinSeq: {'chan-a': 42},
      defaultBroadcast: true,
    ));
    state.presence['uuid-1'] = PresenceSnapshot(entries: [
      PresenceEntry(
          memberSignPk: bob.sign.publicKey,
          tag: '🚶',
          issuedAt: 1_700_000_400,
          expiresAt: 1_700_004_000),
    ], fetchedAt: 1_700_000_450);
    state.outbox.add(OutboxEntry(
        id: 'ob-1',
        op: OutboxOp.presence,
        payload: {'channelId': 'chan-a', 'x': 1},
        attempts: 2,
        createdAt: 1_700_000_300));
    state.notifyPrefs.perFriend[b64(bob.sign.publicKey)] = true;
    state.settings
      ..defaultExpiry = 7200
      ..customTags.add('🎣');
    state.metrics.add(MetricsDay(
        date: '2026-07-10', publishes: 2, firstAt: 1, lastAt: 2));
    state.feedback.lastPromptAt = 1_600_000_000;
    return state;
  }

  test('full §5.2 model round-trips through encrypt → disk → decrypt',
      () async {
    final store = await makeStore();
    final saved = await fullState();
    await store.save(saved);

    final loaded = await (await makeStore()).load();
    expect(loaded, isNotNull);
    expect(loaded!.profile.displayName, 'Alice');
    expect(loaded.profile.contactNote, 'Signal me');

    final g = loaded.groups.single;
    expect(g.groupUuid, 'uuid-1');
    expect(g.name, 'My Porch');
    expect(g.keys, hasLength(2));
    expect(g.keys.first.epoch, 3, reason: 'newest first');
    expect(g.keys.first.retiredAt, isNull);
    expect(g.keys.last.epoch, 2);
    expect(g.keys.last.retiredAt, 1_700_000_500);
    expect(g.roster.members, hasLength(2));
    expect(g.roster.members.first.displayName, 'Alice');
    expect(g.roster.members.first.isAdmin, isTrue);
    expect(g.pendingInvites.single.status, InviteStatus.joined);
    expect(g.pendingInvites.single.t, List.filled(32, 9));
    expect(g.lastBulletinSeq, {'chan-a': 42});
    expect(g.defaultBroadcast, isTrue);

    final snap = loaded.presence['uuid-1']!;
    expect(snap.fetchedAt, 1_700_000_450);
    expect(snap.entries.single.tag, '🚶');
    expect(snap.entries.single.expiresAt, 1_700_004_000);

    expect(loaded.outbox.single.op, OutboxOp.presence);
    expect(loaded.outbox.single.attempts, 2);
    expect(loaded.outbox.single.payload['x'], 1);
    expect(loaded.notifyPrefs.perFriend.values.single, isTrue);
    expect(loaded.settings.defaultExpiry, 7200);
    expect(loaded.settings.customTags, ['🎣']);
    expect(loaded.metrics.single.publishes, 2);
    expect(loaded.feedback.lastPromptAt, 1_600_000_000);
  });

  test('keyring round-trip: StoredGroup.keyring() rebuilds the domain object',
      () async {
    final saved = await fullState();
    final store = await makeStore();
    await store.save(saved);
    final g = (await store.load())!.groups.single;

    final kr = g.keyring();
    expect(kr.current.epoch, 3);
    expect(kr.decryptable, hasLength(2));
    expect(kr.decryptable.last.epoch, 2);
    expect(kr.decryptable.last.retiredAt, 1_700_000_500);
    // Round-trip back to storage form is identity.
    final again = StoredEpochKey.listFromKeyring(kr);
    expect(again.length, g.keys.length);
    expect(again.first.gk, g.keys.first.gk);
  });

  test('the file on disk is ciphertext — no plaintext social graph', () async {
    final store = await makeStore();
    await store.save(await fullState());
    final bytes = await File('${dir.path}/state.v1.enc').readAsBytes();
    final asString = String.fromCharCodes(bytes);
    expect(asString, isNot(contains('Alice')));
    expect(asString, isNot(contains('My Porch')));
    expect(asString, isNot(contains('Signal')));
    expect(asString, isNot(contains('displayName')));
  });

  test('load with the wrong key → StateCorruptError', () async {
    final store = await makeStore();
    await store.save(await fullState());
    final sodium = await loadTestSodium();
    final wrong = EncryptedFileStateStore(sodium,
        directory: dir.path, stateKey: sodium.randombytes.buf(32));
    await expectLater(wrong.load(), throwsA(isA<StateCorruptError>()));
  });

  test('truncated file → StateCorruptError; absent file → null', () async {
    final store = await makeStore();
    expect(await store.load(), isNull);
    await store.save(await fullState());
    final f = File('${dir.path}/state.v1.enc');
    await f.writeAsBytes((await f.readAsBytes()).sublist(0, 10));
    await expectLater(store.load(), throwsA(isA<StateCorruptError>()));
  });

  test('kill mid-write: stray tmp garbage never shadows the good state',
      () async {
    final store = await makeStore();
    final saved = await fullState();
    await store.save(saved);
    // Simulate a crash mid-way through the NEXT save: a partial tmp file.
    await File('${dir.path}/state.v1.enc.tmp')
        .writeAsBytes([1, 2, 3, 4, 5]);
    final loaded = await store.load();
    expect(loaded!.groups.single.name, 'My Porch',
        reason: 'old state intact');
    // And a subsequent save still succeeds over the stray tmp.
    await store.save(loaded);
    expect((await store.load())!.groups.single.name, 'My Porch');
  });

  test('unknown version without a migrator → StateVersionError; the '
      'migration hook rewrites it', () async {
    // Craft a v2 document with the store's exact file format: this also
    // pins the format (nonce ‖ AEAD, AD "porch/state/v1").
    final sodium = await loadTestSodium();
    final future = PorchState.initial();
    future.profile.displayName = 'Zed';
    final doc = future.toJson()..['v'] = 2;
    final nonce = sodium.randombytes
        .buf(sodium.crypto.aeadXChaCha20Poly1305IETF.nonceBytes);
    final key = SecureKey.fromList(sodium, stateKey);
    final ct = sodium.crypto.aeadXChaCha20Poly1305IETF.encrypt(
      message: Uint8List.fromList(utf8.encode(jsonEncode(doc))),
      nonce: nonce,
      key: key,
      additionalData: Uint8List.fromList(utf8.encode('porch/state/v1')),
    );
    await File('${dir.path}/state.v1.enc')
        .writeAsBytes(concatBytes([nonce, ct]));

    final plain = await makeStore();
    await expectLater(plain.load(), throwsA(isA<StateVersionError>()));

    final migrating = await makeStore(migrate: (json) {
      expect(json['v'], 2);
      return json..['v'] = 1;
    });
    final loaded = await migrating.load();
    expect(loaded!.profile.displayName, 'Zed');
  });

  // Start over: the state file goes with the keys. Left behind, it would
  // meet the next launch's new state key and read as corrupt.
  test('clear removes the state file and any stray tmp; load is null after',
      () async {
    final store = await makeStore();
    await store.save(await fullState());
    await File('${dir.path}/state.v1.enc.tmp').writeAsBytes([1, 2, 3]);
    await store.clear();
    expect(File('${dir.path}/state.v1.enc').existsSync(), isFalse);
    expect(File('${dir.path}/state.v1.enc.tmp').existsSync(), isFalse);
    expect(await store.load(), isNull);
    await store.clear(); // nothing there: still fine
  });

  test('InMemoryStateStore.clear forgets the state', () async {
    final store = InMemoryStateStore();
    await store.save(await fullState());
    await store.clear();
    expect(await store.load(), isNull);
  });

  test('InMemoryStateStore round-trips through real JSON (fake honesty)',
      () async {
    final store = InMemoryStateStore();
    expect(await store.load(), isNull);
    await store.save(await fullState());
    final loaded = await store.load();
    expect(loaded!.groups.single.roster.members.first.displayName, 'Alice');
    // Mutating the loaded copy must not leak back into the store.
    loaded.profile.displayName = 'Mallory';
    expect((await store.load())!.profile.displayName, 'Alice');
  });

  // The web build reuses the SAME EncryptedStateStore crypto over a
  // localStorage-backed StateBlobStore (state_store_web.dart). That adapter can
  // only run in a browser, but the crypto+versioning contract it depends on is
  // exercised here against a non-file blob store — the seam that made the web
  // path possible without duplicating the AEAD.
  test('EncryptedStateStore round-trips over a non-file StateBlobStore',
      () async {
    final blobs = _FakeBlobStore();
    final sodium = await loadTestSodium();
    final store =
        EncryptedStateStore(sodium, blobs: blobs, stateKey: stateKey);
    expect(await store.load(), isNull);
    await store.save(await fullState());
    // The stored blob is opaque ciphertext, not the JSON graph.
    expect(utf8.decode(blobs.bytes!, allowMalformed: true), isNot(contains('Alice')));
    final loaded = await store.load();
    expect(loaded!.groups.single.roster.members.first.displayName, 'Alice');
    // A garbled blob surfaces loudly rather than silently starting fresh.
    blobs.bytes = blobs.bytes!.sublist(0, 8);
    await expectLater(store.load(), throwsA(isA<StateCorruptError>()));
  });
}

/// Minimal in-memory [StateBlobStore] standing in for the file / localStorage
/// adapters: it just holds one blob.
class _FakeBlobStore implements StateBlobStore {
  Uint8List? bytes;
  @override
  Future<Uint8List?> read() async => bytes;
  @override
  Future<void> write(Uint8List b) async => bytes = b;
  @override
  Future<void> clear() async => bytes = null;
}
