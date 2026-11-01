// Roster ops & fold (BUILD-SPEC §3.7) + admin succession (§3.6 step 2, PRD
// admin model). W2 acceptance: fold idempotence, signer-authority rejection
// (non-admin REMOVE, non-member PROFILE), successor elected identically on
// every client (property test over shuffled rosters/timestamps).
import 'dart:math';
import 'dart:typed_data';

import 'package:porch_app/domain/roster.dart';
import 'package:porch_app/domain/support/bytes.dart';
import 'package:test/test.dart';

Uint8List pk(int seed) => Uint8List.fromList(List.filled(32, seed));

RosterEntry entry(int seed,
        {int joinedAt = 0, bool isAdmin = false, String? name}) =>
    RosterEntry(
      signPk: pk(seed),
      boxPk: pk(seed + 100),
      displayName: name ?? 'user$seed',
      contactNote: '',
      joinedAt: joinedAt,
      isAdmin: isAdmin,
    );

void main() {
  final alice = entry(1, joinedAt: 100, isAdmin: true, name: 'Alice');
  final bob = entry(2, joinedAt: 200, name: 'Bob');
  final carol = entry(3, joinedAt: 300, name: 'Carol');

  Roster abcRoster() => foldRoster(Roster.genesis(alice), [
        JoinOp(senderSignPk: alice.signPk, seq: 1, issuedAt: 200, member: bob),
        JoinOp(
            senderSignPk: alice.signPk, seq: 2, issuedAt: 300, member: carol),
      ]).roster;

  group('genesis', () {
    test('creator is the sole member and admin (PRD: creator is admin)', () {
      final r = Roster.genesis(alice);
      expect(r.members, hasLength(1));
      expect(r.adminPk, alice.signPk);
    });
  });

  group('JOIN', () {
    test('a member (the fulfiller) can add a new member', () {
      final r = abcRoster();
      expect(r.members, hasLength(3));
      expect(r.isMember(bob.signPk), isTrue);
      expect(r.adminPk, alice.signPk, reason: 'joins do not move admin');
    });

    test('JOIN from a non-member is rejected', () {
      final result = foldRoster(Roster.genesis(alice), [
        JoinOp(senderSignPk: pk(99), seq: 1, issuedAt: 0, member: bob),
      ]);
      expect(result.roster.members, hasLength(1));
      expect(result.rejected, hasLength(1));
    });

    test('re-JOIN of an existing member is a no-op (idempotence)', () {
      final r = foldRoster(abcRoster(), [
        JoinOp(senderSignPk: alice.signPk, seq: 9, issuedAt: 9, member: bob),
      ]).roster;
      expect(r.members, hasLength(3));
    });
  });

  group('REMOVE (admin-only, §3.7)', () {
    test('admin removes a member', () {
      final r = foldRoster(abcRoster(), [
        RemoveOp(
            senderSignPk: alice.signPk, seq: 3, issuedAt: 0,
            memberPk: bob.signPk),
      ]).roster;
      expect(r.isMember(bob.signPk), isFalse);
      expect(r.members, hasLength(2));
    });

    test('non-admin REMOVE is rejected (W2 acceptance)', () {
      final result = foldRoster(abcRoster(), [
        RemoveOp(
            senderSignPk: bob.signPk, seq: 3, issuedAt: 0,
            memberPk: carol.signPk),
      ]);
      expect(result.roster.isMember(carol.signPk), isTrue);
      expect(result.rejected, hasLength(1));
    });
  });

  group('LEAVE (silent, sacred)', () {
    test('leaver disappears; nothing notification-shaped is produced', () {
      final result = foldRoster(abcRoster(), [
        LeaveOp(senderSignPk: bob.signPk, seq: 3, issuedAt: 0),
      ]);
      expect(result.roster.isMember(bob.signPk), isFalse);
      // The fold result carries a roster and rejections. Nothing else exists
      // to render a "Bob left" from — structural silence.
      expect(result.rejected, isEmpty);
    });

    test('admin LEAVE → oldest remaining member becomes admin', () {
      final r = foldRoster(abcRoster(), [
        LeaveOp(senderSignPk: alice.signPk, seq: 3, issuedAt: 0),
      ]).roster;
      expect(r.adminPk, bob.signPk, reason: 'bob joined before carol');
      expect(r.memberOf(bob.signPk)!.isAdmin, isTrue);
    });

    test('joinedAt tie broken by smallest sign_pk bytes', () {
      final low = entry(5, joinedAt: 200, name: 'low');
      final high = entry(9, joinedAt: 200, name: 'high');
      final r0 = foldRoster(Roster.genesis(alice), [
        JoinOp(senderSignPk: alice.signPk, seq: 1, issuedAt: 200, member: high),
        JoinOp(senderSignPk: alice.signPk, seq: 2, issuedAt: 200, member: low),
      ]).roster;
      final r = foldRoster(r0, [
        LeaveOp(senderSignPk: alice.signPk, seq: 3, issuedAt: 0),
      ]).roster;
      expect(r.adminPk, low.signPk);
    });
  });

  group('TRANSFER_ADMIN', () {
    test('admin transfers to a member; old admin stays a member', () {
      final r = foldRoster(abcRoster(), [
        TransferAdminOp(
            senderSignPk: alice.signPk, seq: 3, issuedAt: 0,
            toPk: carol.signPk),
      ]).roster;
      expect(r.adminPk, carol.signPk);
      expect(r.isMember(alice.signPk), isTrue);
      expect(r.memberOf(alice.signPk)!.isAdmin, isFalse);
    });

    test('non-admin transfer rejected; transfer to non-member rejected', () {
      final r1 = foldRoster(abcRoster(), [
        TransferAdminOp(
            senderSignPk: bob.signPk, seq: 3, issuedAt: 0, toPk: bob.signPk),
      ]);
      expect(r1.roster.adminPk, alice.signPk);
      expect(r1.rejected, hasLength(1));

      final r2 = foldRoster(abcRoster(), [
        TransferAdminOp(
            senderSignPk: alice.signPk, seq: 3, issuedAt: 0, toPk: pk(77)),
      ]);
      expect(r2.roster.adminPk, alice.signPk);
      expect(r2.rejected, hasLength(1));
    });
  });

  group('PROFILE', () {
    test('member updates own display name / contact note', () {
      final r = foldRoster(abcRoster(), [
        ProfileOp(
            senderSignPk: bob.signPk, seq: 3, issuedAt: 0,
            displayName: 'Bobby', contactNote: 'Signal: @bob'),
      ]).roster;
      final b = r.memberOf(bob.signPk)!;
      expect(b.displayName, 'Bobby');
      expect(b.contactNote, 'Signal: @bob');
    });

    test('non-member PROFILE is rejected (W2 acceptance)', () {
      final result = foldRoster(abcRoster(), [
        ProfileOp(
            senderSignPk: pk(88), seq: 3, issuedAt: 0, displayName: 'Eve'),
      ]);
      expect(result.rejected, hasLength(1));
    });
  });

  group('fold determinism + idempotence', () {
    final ops = [
      JoinOp(senderSignPk: alice.signPk, seq: 1, issuedAt: 200, member: bob),
      JoinOp(senderSignPk: alice.signPk, seq: 2, issuedAt: 300, member: carol),
      ProfileOp(
          senderSignPk: bob.signPk, seq: 3, issuedAt: 0, displayName: 'Bobby'),
      TransferAdminOp(
          senderSignPk: alice.signPk, seq: 4, issuedAt: 0, toPk: bob.signPk),
      LeaveOp(senderSignPk: alice.signPk, seq: 5, issuedAt: 0),
    ];

    test('ops are folded by seq regardless of delivery order', () {
      final sorted = foldRoster(Roster.genesis(alice), ops).roster;
      final shuffled = foldRoster(
              Roster.genesis(alice), List.of(ops)..shuffle(Random(42)))
          .roster;
      expect(shuffled.toJson(), sorted.toJson());
    });

    test('folding the same ops twice changes nothing (idempotence)', () {
      final once = foldRoster(Roster.genesis(alice), ops).roster;
      final twice = foldRoster(Roster.genesis(alice), [...ops, ...ops]).roster;
      expect(twice.toJson(), once.toJson());
    });
  });

  group('successorOf — the one succession rule (§3.6 step 2)', () {
    test('property: identical on every client for shuffled rosters', () {
      final rand = Random(1234);
      for (var trial = 0; trial < 200; trial++) {
        final n = 2 + rand.nextInt(8);
        final members = List.generate(n, (i) {
          return RosterEntry(
            signPk: Uint8List.fromList(
                List.generate(32, (_) => rand.nextInt(256))),
            boxPk: pk(i),
            displayName: 'm$i',
            contactNote: '',
            // Deliberately collide joinedAt often to exercise the tiebreak.
            joinedAt: 1000 + rand.nextInt(3),
            isAdmin: i == 0,
          );
        });
        final departed = members[0].signPk;
        final expected = _referenceSuccessor(members, departed);

        for (var shuffle = 0; shuffle < 5; shuffle++) {
          final view = List.of(members)..shuffle(rand);
          final got = successorOf(
              Roster(members: view), departed);
          expect(b64(got!), b64(expected),
              reason: 'trial $trial shuffle $shuffle');
        }
      }
    });

    test('returns null when nobody remains', () {
      expect(successorOf(Roster.genesis(alice), alice.signPk), isNull);
    });
  });
}

/// Independent restatement of the rule: oldest remaining member by joinedAt,
/// ties by smallest sign_pk (lexicographic bytes).
Uint8List _referenceSuccessor(List<RosterEntry> members, Uint8List departed) {
  final remaining =
      members.where((m) => !bytesEqual(m.signPk, departed)).toList();
  remaining.sort((a, b) {
    if (a.joinedAt != b.joinedAt) return a.joinedAt - b.joinedAt;
    for (var i = 0; i < 32; i++) {
      if (a.signPk[i] != b.signPk[i]) return a.signPk[i] - b.signPk[i];
    }
    return 0;
  });
  return remaining.first.signPk;
}
