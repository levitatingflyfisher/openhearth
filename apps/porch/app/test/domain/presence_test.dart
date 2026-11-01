// Presence (BUILD-SPEC §3.4): encrypt → route → TTL, and the typed-honesty
// snapshot (§1.4): PresenceSnapshot cannot be constructed without fetchedAt
// (compile-enforced — the constructor has no default), staleness is a pure
// function, the fold verifies → dedupes → drops expired.
import 'dart:typed_data';

import 'package:porch_app/domain/envelope.dart';
import 'package:porch_app/domain/identity.dart';
import 'package:porch_app/domain/keyring.dart';
import 'package:porch_app/domain/presence.dart';
import 'package:porch_app/domain/roster.dart';
import 'package:sodium/sodium_sumo.dart';
import 'package:test/test.dart';

import 'support/test_sodium.dart';

void main() {
  late SodiumSumo sodium;
  late PorchIdentity alice, bob, mallory;
  late Uint8List gk;
  late GroupKeyring keyring;
  late Roster roster;

  setUpAll(() async {
    sodium = await loadTestSodium();
    Uint8List e(int n) => Uint8List.fromList(List.filled(16, n));
    alice = PorchIdentity.fromEntropy(sodium, e(1));
    bob = PorchIdentity.fromEntropy(sodium, e(2));
    mallory = PorchIdentity.fromEntropy(sodium, e(66));
  });

  RosterEntry entryFor(PorchIdentity id, String name, int joinedAt,
          {bool isAdmin = false}) =>
      RosterEntry(
          signPk: id.sign.publicKey,
          boxPk: id.box.publicKey,
          displayName: name,
          contactNote: '',
          joinedAt: joinedAt,
          isAdmin: isAdmin);

  setUp(() {
    gk = mintGroupKey(sodium);
    keyring = GroupKeyring.genesis(gk);
    roster = Roster(members: [
      entryFor(alice, 'Alice', 1, isAdmin: true),
      entryFor(bob, 'Bob', 2),
    ]);
  });

  group('encodePresenceOn (§3.4 steps 1–2)', () {
    test('routes to the current channel and my slot, ttl = expiresAt − now',
        () {
      final post = encodePresenceOn(sodium,
          keyring: keyring,
          senderSign: alice.sign,
          tag: '🚶',
          now: 1000,
          expiresAt: 1000 + 3600);
      expect(post.channelId, deriveChannelId(sodium, gk));
      expect(post.slotId, deriveSlotId(sodium, gk, alice.sign.publicKey));
      expect(post.ttlSec, 3600);
      expect(post.blob.length, lessThanOrEqualTo(presenceMaxBlobBytes));

      // Members decode it as a normal envelope.
      final opened = openEnvelope(sodium, wire: post.blob, keyring: keyring)!;
      expect(opened.type, 'presence');
      expect(opened.fields['status'], 'on');
      expect(opened.fields['tag'], '🚶');
      expect(opened.fields['expiresAt'], 4600);
    });

    test('ttl is capped at the relay maximum (14700 s)', () {
      final post = encodePresenceOn(sodium,
          keyring: keyring,
          senderSign: alice.sign,
          tag: '',
          now: 0,
          expiresAt: 999999);
      expect(post.ttlSec, presenceMaxTtlSeconds);
    });

    test('rejects an expiry in the past and an oversized tag', () {
      expect(
          () => encodePresenceOn(sodium,
              keyring: keyring,
              senderSign: alice.sign,
              tag: '',
              now: 100,
              expiresAt: 100),
          throwsArgumentError);
      expect(
          () => encodePresenceOn(sodium,
              keyring: keyring,
              senderSign: alice.sign,
              // Large enough that the sealed envelope must exceed the 1 KiB
              // relay cap regardless of framing overhead.
              tag: 'x' * 1200,
              now: 100,
              expiresAt: 200),
          throwsArgumentError);
    });
  });

  group('manual off (§3.4 step 4)', () {
    test('is a short-lived signed tombstone, not a delete endpoint', () {
      final post = encodePresenceOff(sodium,
          keyring: keyring, senderSign: alice.sign, now: 5000);
      expect(post.ttlSec, presenceOffTtlSeconds);
      expect(post.slotId, deriveSlotId(sodium, gk, alice.sign.publicKey));
      final opened = openEnvelope(sodium, wire: post.blob, keyring: keyring)!;
      expect(opened.fields['status'], 'off');
    });
  });

  group('PresenceSnapshot honesty (§1.4)', () {
    // `fetchedAt` is a REQUIRED constructor argument with no default —
    // that is compile-enforced; these tests pin the staleness semantics.
    test('staleness is >15 min old, on the boundary it is fresh', () {
      final snap = PresenceSnapshot(entries: const [], fetchedAt: 1000);
      expect(snap.isStaleAt(1000 + 15 * 60), isFalse);
      expect(snap.isStaleAt(1000 + 15 * 60 + 1), isTrue);
    });

    test('remembers exactly when it was fetched', () {
      expect(PresenceSnapshot(entries: const [], fetchedAt: 42).fetchedAt, 42);
    });
  });

  group('foldPresenceFeed (§3.4 step 5: verify → dedupe → drop-expired)', () {
    Uint8List on(PorchIdentity who, String tag, int issuedAt, int expiresAt,
            {GroupKeyring? kr}) =>
        encodePresenceOn(sodium,
                keyring: kr ?? keyring,
                senderSign: who.sign,
                tag: tag,
                now: issuedAt,
                expiresAt: expiresAt)
            .blob;

    test('keeps the newest event per member, drops expired and garbage', () {
      final blobs = <Uint8List>[
        on(alice, '🚶', 100, 5000), // superseded
        on(alice, '🧹', 200, 5000), // newest alice
        on(bob, '🚗', 150, 300), // expired by now=1000
        Uint8List.fromList([1, 2, 3]), // vandal garbage
      ];
      final snap = foldPresenceFeed(sodium,
          blobs: blobs,
          keyring: keyring,
          roster: roster,
          now: 1000,
          fetchedAt: 1001);
      expect(snap.fetchedAt, 1001);
      expect(snap.entries, hasLength(1));
      expect(snap.entries.single.tag, '🧹');
      expect(snap.entries.single.memberSignPk, alice.sign.publicKey);
      expect(snap.entries.single.issuedAt, 200);
      expect(snap.entries.single.expiresAt, 5000);
    });

    test('dedupe is order-independent', () {
      final a = on(alice, 'old', 100, 5000);
      final b = on(alice, 'new', 300, 5000);
      for (final order in [
        [a, b],
        [b, a],
      ]) {
        final snap = foldPresenceFeed(sodium,
            blobs: order,
            keyring: keyring,
            roster: roster,
            now: 500,
            fetchedAt: 500);
        expect(snap.entries.single.tag, 'new');
      }
    });

    test('a later off tombstone suppresses the earlier on', () {
      final blobs = [
        on(bob, '🚗', 100, 9000),
        encodePresenceOff(sodium,
                keyring: keyring, senderSign: bob.sign, now: 200)
            .blob,
      ];
      final snap = foldPresenceFeed(sodium,
          blobs: blobs,
          keyring: keyring,
          roster: roster,
          now: 300,
          fetchedAt: 300);
      expect(snap.entries, isEmpty);
    });

    test('an event from a non-roster signer is dropped even though it '
        'decrypts and verifies (link thief with the capability)', () {
      final blobs = [on(mallory, '👀', 100, 9000)];
      final snap = foldPresenceFeed(sodium,
          blobs: blobs,
          keyring: keyring,
          roster: roster,
          now: 200,
          fetchedAt: 200);
      expect(snap.entries, isEmpty);
    });

    test('grace: an old-epoch straggler event still renders after rotation',
        () {
      final oldBlob = on(bob, '📖', 100, 9000);
      final gk2 = mintGroupKey(sodium);
      final rotated = keyring.adopt(epoch: 2, gk: gk2, nowSec: 150);
      final snap = foldPresenceFeed(sodium,
          blobs: [oldBlob],
          keyring: rotated,
          roster: roster,
          now: 200,
          fetchedAt: 200);
      expect(snap.entries.single.tag, '📖');
    });
  });
}
