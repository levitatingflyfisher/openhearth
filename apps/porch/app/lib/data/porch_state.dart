// PorchState — the §5.2 client data model, exactly.
//
// Everything the app knows lives in ONE versioned JSON document, encrypted
// as ONE file (state_store.dart). Total state is kilobytes for 15 friends.
// These classes are deliberately mutable records: repositories do
// load → mutate → save; immutability lives in the domain layer.
//
// JSON byte conventions match the wire (see domain/support/bytes.dart):
// keys/sigs/blobs = standard base64; capability ids = base64url strings.
import 'dart:typed_data';

import '../domain/domain.dart';

// ---------------------------------------------------------------------------
// Groups
// ---------------------------------------------------------------------------

/// One epoch key in storage form (§5.2 groups[].keys).
class StoredEpochKey {
  final int epoch;
  final Uint8List gk;
  final int? retiredAt;
  const StoredEpochKey({required this.epoch, required this.gk, this.retiredAt});

  Map<String, Object?> toJson() => {
        'epoch': epoch,
        'gk': b64(gk),
        if (retiredAt != null) 'retiredAt': retiredAt,
      };

  factory StoredEpochKey.fromJson(Map<String, Object?> json) => StoredEpochKey(
        epoch: json['epoch'] as int,
        gk: b64decode(json['gk'] as String),
        retiredAt: json['retiredAt'] as int?,
      );

  /// Snapshot a domain keyring into storage form (newest first).
  static List<StoredEpochKey> listFromKeyring(GroupKeyring keyring) => [
        for (final k in keyring.keys)
          StoredEpochKey(epoch: k.epoch, gk: k.gk, retiredAt: k.retiredAt),
      ];
}

/// One group as persisted (§5.2 groups[]).
class StoredGroup {
  final String groupUuid;
  final String name;

  /// Newest first; only the first entry encrypts (domain key policy).
  List<StoredEpochKey> keys;
  Roster roster;
  List<PendingInvite> pendingInvites;

  /// channelId → highest folded bulletin seq (per channel because the
  /// channelId changes with every rotation).
  Map<String, int> lastBulletinSeq;
  bool defaultBroadcast;

  StoredGroup({
    required this.groupUuid,
    required this.name,
    required this.keys,
    required this.roster,
    List<PendingInvite>? pendingInvites,
    Map<String, int>? lastBulletinSeq,
    this.defaultBroadcast = true,
  })  : pendingInvites = pendingInvites ?? [],
        lastBulletinSeq = lastBulletinSeq ?? {};

  int get epoch => keys.first.epoch;

  /// Rebuild the immutable domain keyring from storage. The reconstruction
  /// goes through the domain's own public API so its invariants (newest
  /// encrypts, ≤2 decryptable, retiredAt bookkeeping) cannot be bypassed.
  GroupKeyring keyring() {
    final sorted = List.of(keys)..sort((a, b) => b.epoch - a.epoch);
    if (sorted.isEmpty) {
      throw StateError('group $groupUuid has no epoch keys');
    }
    if (sorted.length == 1) {
      return GroupKeyring.fromGrant(epoch: sorted[0].epoch, gk: sorted[0].gk);
    }
    final newest = sorted[0], grace = sorted[1];
    return GroupKeyring.fromGrant(epoch: grace.epoch, gk: grace.gk)
        .adopt(epoch: newest.epoch, gk: newest.gk, nowSec: grace.retiredAt ?? 0);
  }

  Map<String, Object?> toJson() => {
        'groupUuid': groupUuid,
        'name': name,
        'keys': [for (final k in keys) k.toJson()],
        'roster': roster.toJson(),
        'pendingInvites': [for (final i in pendingInvites) inviteToJson(i)],
        'lastBulletinSeq': lastBulletinSeq,
        'defaultBroadcast': defaultBroadcast,
      };

  factory StoredGroup.fromJson(Map<String, Object?> json) => StoredGroup(
        groupUuid: json['groupUuid'] as String,
        name: json['name'] as String,
        keys: [
          for (final k in json['keys'] as List)
            StoredEpochKey.fromJson((k as Map).cast<String, Object?>()),
        ]..sort((a, b) => b.epoch - a.epoch),
        roster: Roster.fromJson(json['roster'] as List<Object?>),
        pendingInvites: [
          for (final i in json['pendingInvites'] as List)
            inviteFromJson((i as Map).cast<String, Object?>()),
        ],
        lastBulletinSeq:
            (json['lastBulletinSeq'] as Map).cast<String, int>(),
        defaultBroadcast: json['defaultBroadcast'] as bool,
      );
}

// --- PendingInvite (domain) ↔ §5.2 storage form ---

const _inviteStatusNames = {
  InviteStatus.open: 'open',
  InviteStatus.joined: 'joined',
  InviteStatus.granted: 'granted',
  InviteStatus.voided: 'void', // §5.2 spells it "void"
};

Map<String, Object?> inviteToJson(PendingInvite invite) => {
      'inviteId': invite.inviteId,
      't': b64(invite.t),
      'expiresAt': invite.expiresAt,
      'state': _inviteStatusNames[invite.status],
    };

PendingInvite inviteFromJson(Map<String, Object?> json) => PendingInvite(
      inviteId: json['inviteId'] as String,
      t: b64decode(json['t'] as String),
      expiresAt: json['expiresAt'] as int,
      status: _inviteStatusNames.entries
          .firstWhere((e) => e.value == json['state'])
          .key,
    );

// --- PresenceSnapshot (domain) ↔ §5.2 storage form ---

Map<String, Object?> snapshotToJson(PresenceSnapshot snap) => {
      'fetchedAt': snap.fetchedAt,
      'entries': [
        for (final e in snap.entries)
          {
            'memberSignPk': b64(e.memberSignPk),
            'tag': e.tag,
            'issuedAt': e.issuedAt,
            'expiresAt': e.expiresAt,
          },
      ],
    };

PresenceSnapshot snapshotFromJson(Map<String, Object?> json) =>
    PresenceSnapshot(
      fetchedAt: json['fetchedAt'] as int,
      entries: [
        for (final e in json['entries'] as List)
          PresenceEntry(
            memberSignPk:
                b64decode((e as Map)['memberSignPk'] as String),
            tag: e['tag'] as String,
            issuedAt: e['issuedAt'] as int,
            expiresAt: e['expiresAt'] as int,
          ),
      ],
    );

// ---------------------------------------------------------------------------
// Outbox (§3.4 step 1: optimistic outbox-first)
// ---------------------------------------------------------------------------

enum OutboxOp { presence, bulletin, mailbox }

const _outboxOpNames = {
  OutboxOp.presence: 'presence',
  OutboxOp.bulletin: 'bulletin',
  OutboxOp.mailbox: 'mailbox',
};

class OutboxEntry {
  final String id;
  final OutboxOp op;
  final Map<String, Object?> payload;
  int attempts;
  final int createdAt;

  /// Unix seconds before which the drain will not deliver this entry
  /// (rotation fan-out jitter, §3.6). 0 = due immediately; pre-jitter
  /// state files deserialize to 0.
  final int notBefore;

  OutboxEntry({
    required this.id,
    required this.op,
    required this.payload,
    this.attempts = 0,
    required this.createdAt,
    this.notBefore = 0,
  });

  Map<String, Object?> toJson() => {
        'id': id,
        'op': _outboxOpNames[op],
        'payload': payload,
        'attempts': attempts,
        'createdAt': createdAt,
        'notBefore': notBefore,
      };

  factory OutboxEntry.fromJson(Map<String, Object?> json) => OutboxEntry(
        id: json['id'] as String,
        op: _outboxOpNames.entries
            .firstWhere((e) => e.value == json['op'])
            .key,
        payload: (json['payload'] as Map).cast<String, Object?>(),
        attempts: json['attempts'] as int,
        createdAt: json['createdAt'] as int,
        notBefore: json['notBefore'] as int? ?? 0,
      );
}

// ---------------------------------------------------------------------------
// The small leaves
// ---------------------------------------------------------------------------

class Profile {
  String displayName;
  String contactNote;
  Profile({this.displayName = '', this.contactNote = ''});

  Map<String, Object?> toJson() =>
      {'displayName': displayName, 'contactNote': contactNote};

  factory Profile.fromJson(Map<String, Object?> json) => Profile(
        displayName: json['displayName'] as String,
        contactNote: json['contactNote'] as String,
      );
}

/// ALL default off (§5.2); local only — never serialized into any network
/// payload (the W4 notification service owns that assertion).
class NotifyPrefs {
  final Map<String, bool> perFriend;
  final Map<String, bool> perGroup;
  NotifyPrefs({Map<String, bool>? perFriend, Map<String, bool>? perGroup})
      : perFriend = perFriend ?? {},
        perGroup = perGroup ?? {};

  Map<String, Object?> toJson() =>
      {'perFriend': perFriend, 'perGroup': perGroup};

  factory NotifyPrefs.fromJson(Map<String, Object?> json) => NotifyPrefs(
        perFriend: (json['perFriend'] as Map).cast<String, bool>(),
        perGroup: (json['perGroup'] as Map).cast<String, bool>(),
      );
}

class Settings {
  int defaultExpiry;
  final List<String> customTags;

  /// True after a backup was saved while there were no groups (the
  /// onboarding backup): once a group exists, Home offers a fresh backup
  /// that holds it. Cleared by a backup with groups, or by "Not now".
  /// Absent in older state files → false.
  bool offerFreshBackup;

  /// True once this phone has a backup: one was saved here, or the state
  /// came from a backup file. False means setup is unfinished (onboarding
  /// lets you skip the backup), so Home shows "Finish setup".
  bool hasBackup;

  /// "Not now" on Home's Finish setup item. Settings keeps saying the
  /// phone is not backed up either way.
  bool finishSetupDismissed;

  Settings(
      {this.defaultExpiry = 3600,
      List<String>? customTags,
      this.offerFreshBackup = false,
      this.hasBackup = false,
      this.finishSetupDismissed = false})
      : customTags = customTags ?? [];

  Map<String, Object?> toJson() => {
        'defaultExpiry': defaultExpiry,
        'customTags': customTags,
        'offerFreshBackup': offerFreshBackup,
        'hasBackup': hasBackup,
        'finishSetupDismissed': finishSetupDismissed,
      };

  factory Settings.fromJson(Map<String, Object?> json) => Settings(
        defaultExpiry: json['defaultExpiry'] as int,
        customTags: (json['customTags'] as List).cast<String>(),
        offerFreshBackup: json['offerFreshBackup'] as bool? ?? false,
        hasBackup: json['hasBackup'] as bool? ?? false,
        finishSetupDismissed: json['finishSetupDismissed'] as bool? ?? false,
      );
}

/// On-device only, never transmitted (§1.4).
class MetricsDay {
  final String date;
  int publishes;
  int firstAt;
  int lastAt;
  MetricsDay(
      {required this.date,
      this.publishes = 0,
      this.firstAt = 0,
      this.lastAt = 0});

  Map<String, Object?> toJson() => {
        'date': date,
        'publishes': publishes,
        'firstAt': firstAt,
        'lastAt': lastAt,
      };

  factory MetricsDay.fromJson(Map<String, Object?> json) => MetricsDay(
        date: json['date'] as String,
        publishes: json['publishes'] as int,
        firstAt: json['firstAt'] as int,
        lastAt: json['lastAt'] as int,
      );
}

class Feedback {
  int lastPromptAt;
  Feedback({this.lastPromptAt = 0});
  Map<String, Object?> toJson() => {'lastPromptAt': lastPromptAt};
  factory Feedback.fromJson(Map<String, Object?> json) =>
      Feedback(lastPromptAt: json['lastPromptAt'] as int);
}

// ---------------------------------------------------------------------------
// The root document
// ---------------------------------------------------------------------------

class PorchState {
  static const version = 1;

  final Profile profile;
  final List<StoredGroup> groups;

  /// groupUuid → last fetched snapshot. The domain type makes fetchedAt
  /// mandatory, so nothing staleness-blind can ever be persisted either.
  final Map<String, PresenceSnapshot> presence;
  final List<OutboxEntry> outbox;
  final NotifyPrefs notifyPrefs;
  final Settings settings;
  final List<MetricsDay> metrics;
  final Feedback feedback;

  PorchState._({
    required this.profile,
    required this.groups,
    required this.presence,
    required this.outbox,
    required this.notifyPrefs,
    required this.settings,
    required this.metrics,
    required this.feedback,
  });

  factory PorchState.initial() => PorchState._(
        profile: Profile(),
        groups: [],
        presence: {},
        outbox: [],
        notifyPrefs: NotifyPrefs(),
        settings: Settings(),
        metrics: [],
        feedback: Feedback(),
      );

  StoredGroup? groupByUuid(String groupUuid) {
    for (final g in groups) {
      if (g.groupUuid == groupUuid) return g;
    }
    return null;
  }

  Map<String, Object?> toJson() => {
        'v': version,
        'profile': profile.toJson(),
        'groups': [for (final g in groups) g.toJson()],
        'presence': {
          for (final e in presence.entries) e.key: snapshotToJson(e.value),
        },
        'outbox': [for (final o in outbox) o.toJson()],
        'notifyPrefs': notifyPrefs.toJson(),
        'settings': settings.toJson(),
        'metrics': [for (final m in metrics) m.toJson()],
        'feedback': feedback.toJson(),
      };

  /// Parses a VERSION-1 document; state_store handles version dispatch.
  factory PorchState.fromJson(Map<String, Object?> json) => PorchState._(
        profile:
            Profile.fromJson((json['profile'] as Map).cast<String, Object?>()),
        groups: [
          for (final g in json['groups'] as List)
            StoredGroup.fromJson((g as Map).cast<String, Object?>()),
        ],
        presence: {
          for (final e in (json['presence'] as Map).entries)
            e.key as String:
                snapshotFromJson((e.value as Map).cast<String, Object?>()),
        },
        outbox: [
          for (final o in json['outbox'] as List)
            OutboxEntry.fromJson((o as Map).cast<String, Object?>()),
        ],
        notifyPrefs: NotifyPrefs.fromJson(
            (json['notifyPrefs'] as Map).cast<String, Object?>()),
        settings: Settings.fromJson(
            (json['settings'] as Map).cast<String, Object?>()),
        metrics: [
          for (final m in json['metrics'] as List)
            MetricsDay.fromJson((m as Map).cast<String, Object?>()),
        ],
        feedback: Feedback.fromJson(
            (json['feedback'] as Map).cast<String, Object?>()),
      );
}
