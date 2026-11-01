// Roster: signed membership ops, deterministic fold, admin succession
// (BUILD-SPEC §3.7, §3.6 step 2).
//
// The fold is the group's source of truth about WHO. It is deterministic
// (ops totally ordered by server-assigned bulletin seq), idempotent
// (replayed ops are no-ops), and authority-checked per op type. Signature
// validity is the envelope layer's job; by the time an op reaches the fold,
// senderSignPk is cryptographically the author — the fold decides whether
// that author was ALLOWED.
//
// Silent leave is structural here: folding a LEAVE yields a roster and
// nothing else — there is no artifact a UI could render a notification from.
import 'dart:typed_data';

import 'envelope.dart';
import 'support/bytes.dart';

/// One member as the roster knows them (§5.2 state-file shape).
class RosterEntry {
  final Uint8List signPk;
  final Uint8List boxPk;
  final String displayName;
  final String contactNote;
  final int joinedAt;
  final bool isAdmin;

  const RosterEntry({
    required this.signPk,
    required this.boxPk,
    required this.displayName,
    required this.contactNote,
    required this.joinedAt,
    required this.isAdmin,
  });

  RosterEntry copyWith({
    String? displayName,
    String? contactNote,
    bool? isAdmin,
  }) =>
      RosterEntry(
        signPk: signPk,
        boxPk: boxPk,
        displayName: displayName ?? this.displayName,
        contactNote: contactNote ?? this.contactNote,
        joinedAt: joinedAt,
        isAdmin: isAdmin ?? this.isAdmin,
      );

  Map<String, Object?> toJson() => {
        'signPk': b64(signPk),
        'boxPk': b64(boxPk),
        'displayName': displayName,
        'contactNote': contactNote,
        'joinedAt': joinedAt,
        'isAdmin': isAdmin,
      };

  factory RosterEntry.fromJson(Map<String, Object?> json) => RosterEntry(
        signPk: b64decode(json['signPk'] as String),
        boxPk: b64decode(json['boxPk'] as String),
        displayName: json['displayName'] as String,
        contactNote: json['contactNote'] as String,
        joinedAt: json['joinedAt'] as int,
        isAdmin: json['isAdmin'] as bool,
      );
}

/// Immutable membership state. Single admin at any time (PRD admin model).
class Roster {
  final List<RosterEntry> members;

  Roster({required List<RosterEntry> members})
      : members = List.unmodifiable(members);

  /// Group creation: the creator, alone, as admin.
  factory Roster.genesis(RosterEntry creator) =>
      Roster(members: [creator.copyWith(isAdmin: true)]);

  Uint8List? get adminPk {
    for (final m in members) {
      if (m.isAdmin) return m.signPk;
    }
    return null;
  }

  bool isMember(Uint8List signPk) => memberOf(signPk) != null;

  RosterEntry? memberOf(Uint8List signPk) {
    for (final m in members) {
      if (bytesEqual(m.signPk, signPk)) return m;
    }
    return null;
  }

  bool isAdminPk(Uint8List signPk) {
    final a = adminPk;
    return a != null && bytesEqual(a, signPk);
  }

  List<Map<String, Object?>> toJson() =>
      [for (final m in members) m.toJson()];

  factory Roster.fromJson(List<Object?> json) => Roster(members: [
        for (final m in json)
          RosterEntry.fromJson((m as Map).cast<String, Object?>()),
      ]);
}

// ---------------------------------------------------------------------------
// Ops
// ---------------------------------------------------------------------------

/// A signed roster op as folded: sender authenticity was established by the
/// envelope signature; [seq] is the server-assigned bulletin sequence that
/// makes ordering total.
sealed class RosterOp {
  final Uint8List senderSignPk;
  final int seq;
  final int issuedAt;
  const RosterOp(
      {required this.senderSignPk, required this.seq, required this.issuedAt});

  /// Envelope payload type for this op.
  String get type;

  /// Application fields for [sealEnvelope].
  Map<String, Object?> get fields;
}

class JoinOp extends RosterOp {
  final RosterEntry member;
  const JoinOp({
    required super.senderSignPk,
    required super.seq,
    required super.issuedAt,
    required this.member,
  });
  @override
  String get type => 'JOIN';
  @override
  Map<String, Object?> get fields => {'member': member.toJson()};
}

class RemoveOp extends RosterOp {
  final Uint8List memberPk;
  const RemoveOp({
    required super.senderSignPk,
    required super.seq,
    required super.issuedAt,
    required this.memberPk,
  });
  @override
  String get type => 'REMOVE';
  @override
  Map<String, Object?> get fields => {'memberPk': b64(memberPk)};
}

class LeaveOp extends RosterOp {
  const LeaveOp({
    required super.senderSignPk,
    required super.seq,
    required super.issuedAt,
  });
  @override
  String get type => 'LEAVE';
  @override
  Map<String, Object?> get fields => const {};
}

class TransferAdminOp extends RosterOp {
  final Uint8List toPk;
  const TransferAdminOp({
    required super.senderSignPk,
    required super.seq,
    required super.issuedAt,
    required this.toPk,
  });
  @override
  String get type => 'TRANSFER_ADMIN';
  @override
  Map<String, Object?> get fields => {'toPk': b64(toPk)};
}

class ProfileOp extends RosterOp {
  final String? displayName;
  final String? contactNote;
  const ProfileOp({
    required super.senderSignPk,
    required super.seq,
    required super.issuedAt,
    this.displayName,
    this.contactNote,
  });
  @override
  String get type => 'PROFILE';
  @override
  Map<String, Object?> get fields => {
        if (displayName != null) 'displayName': displayName,
        if (contactNote != null) 'contactNote': contactNote,
      };
}

/// Parse a decrypted, signature-verified bulletin envelope into a roster op.
/// Returns null for non-roster types or malformed fields (dropped upstream).
RosterOp? rosterOpFromEnvelope(OpenedEnvelope env, {required int seq}) {
  try {
    switch (env.type) {
      case 'JOIN':
        return JoinOp(
          senderSignPk: env.senderSignPk,
          seq: seq,
          issuedAt: env.issuedAt,
          member: RosterEntry.fromJson(
              (env.fields['member'] as Map).cast<String, Object?>()),
        );
      case 'REMOVE':
        return RemoveOp(
          senderSignPk: env.senderSignPk,
          seq: seq,
          issuedAt: env.issuedAt,
          memberPk: b64decode(env.fields['memberPk'] as String),
        );
      case 'LEAVE':
        return LeaveOp(
            senderSignPk: env.senderSignPk, seq: seq, issuedAt: env.issuedAt);
      case 'TRANSFER_ADMIN':
        return TransferAdminOp(
          senderSignPk: env.senderSignPk,
          seq: seq,
          issuedAt: env.issuedAt,
          toPk: b64decode(env.fields['toPk'] as String),
        );
      case 'PROFILE':
        return ProfileOp(
          senderSignPk: env.senderSignPk,
          seq: seq,
          issuedAt: env.issuedAt,
          displayName: env.fields['displayName'] as String?,
          contactNote: env.fields['contactNote'] as String?,
        );
      default:
        return null;
    }
  } on Object {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Fold
// ---------------------------------------------------------------------------

class RejectedOp {
  final RosterOp op;
  final String reason;
  const RejectedOp(this.op, this.reason);
}

class FoldResult {
  final Roster roster;
  final List<RejectedOp> rejected;
  const FoldResult({required this.roster, required this.rejected});
}

/// Fold [ops] into [initial], ordered by seq. Deterministic and idempotent;
/// unauthorized or nonsensical ops are rejected (surfaced for tests,
/// silently dropped by product code).
FoldResult foldRoster(Roster initial, Iterable<RosterOp> ops) {
  final ordered = ops.toList()..sort((a, b) => a.seq - b.seq);
  var roster = initial;
  final rejected = <RejectedOp>[];

  void reject(RosterOp op, String reason) => rejected.add(RejectedOp(op, reason));

  for (final op in ordered) {
    switch (op) {
      case JoinOp():
        if (!roster.isMember(op.senderSignPk)) {
          reject(op, 'JOIN signer is not a member');
        } else if (roster.isMember(op.member.signPk)) {
          // Replay / duplicate fulfillment — idempotent no-op.
        } else {
          roster = Roster(members: [
            ...roster.members,
            op.member.copyWith(isAdmin: false),
          ]);
        }
      case RemoveOp():
        if (!roster.isAdminPk(op.senderSignPk)) {
          reject(op, 'REMOVE requires admin');
        } else if (!roster.isMember(op.memberPk)) {
          reject(op, 'REMOVE of non-member');
        } else {
          roster = _depart(roster, op.memberPk);
        }
      case LeaveOp():
        if (!roster.isMember(op.senderSignPk)) {
          // Replayed leave — idempotent no-op.
        } else {
          roster = _depart(roster, op.senderSignPk);
        }
      case TransferAdminOp():
        if (!roster.isAdminPk(op.senderSignPk)) {
          reject(op, 'TRANSFER_ADMIN requires admin');
        } else if (!roster.isMember(op.toPk)) {
          reject(op, 'TRANSFER_ADMIN to non-member');
        } else {
          roster = Roster(members: [
            for (final m in roster.members)
              m.copyWith(isAdmin: bytesEqual(m.signPk, op.toPk)),
          ]);
        }
      case ProfileOp():
        if (!roster.isMember(op.senderSignPk)) {
          reject(op, 'PROFILE from non-member');
        } else {
          roster = Roster(members: [
            for (final m in roster.members)
              bytesEqual(m.signPk, op.senderSignPk)
                  ? m.copyWith(
                      displayName: op.displayName,
                      contactNote: op.contactNote)
                  : m,
          ]);
        }
    }
  }
  return FoldResult(roster: roster, rejected: rejected);
}

/// Remove [departedPk]; if the admin departed, promote the deterministic
/// successor. THE succession rule (one implementation, §3.6 step 2 / PRD):
/// oldest remaining member by joinedAt, ties by smallest sign_pk bytes.
Roster _depart(Roster roster, Uint8List departedPk) {
  final wasAdmin = roster.isAdminPk(departedPk);
  final remaining = [
    for (final m in roster.members)
      if (!bytesEqual(m.signPk, departedPk)) m,
  ];
  if (!wasAdmin || remaining.isEmpty) return Roster(members: remaining);
  final successor = successorOf(Roster(members: remaining), departedPk)!;
  return Roster(members: [
    for (final m in remaining)
      m.copyWith(isAdmin: bytesEqual(m.signPk, successor)),
  ]);
}

/// The deterministic successor after [departedPk] departs: oldest remaining
/// member by roster joinedAt, ties broken by smallest sign_pk (lexicographic
/// bytes). Every client computes the same answer — no server involvement.
/// Rotation's rotator election (§3.6) calls this same function.
Uint8List? successorOf(Roster roster, Uint8List departedPk) {
  RosterEntry? best;
  for (final m in roster.members) {
    if (bytesEqual(m.signPk, departedPk)) continue;
    if (best == null || _older(m, best)) best = m;
  }
  return best?.signPk;
}

bool _older(RosterEntry a, RosterEntry b) {
  if (a.joinedAt != b.joinedAt) return a.joinedAt < b.joinedAt;
  for (var i = 0; i < a.signPk.length && i < b.signPk.length; i++) {
    if (a.signPk[i] != b.signPk[i]) return a.signPk[i] < b.signPk[i];
  }
  return a.signPk.length < b.signPk.length;
}
