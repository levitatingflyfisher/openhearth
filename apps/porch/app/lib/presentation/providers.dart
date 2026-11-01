// Riverpod wiring (BUILD-SPEC §2: presentation/providers.dart).
//
// Layering: widgets watch providers; providers call the W3 repositories;
// repositories stay Flutter-free. The leaf providers (sodium, relay,
// stores, clock, ports) are UnimplementedError placeholders that bootstrap
// overrides with production adapters and tests override with fakes — the
// same seam for both, so what the tests exercise IS what ships.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:openhearth_design/openhearth_design.dart'
    show OhThemeModePreference;
import 'package:sodium/sodium_sumo.dart' show SodiumSumo;

import '../data/backup_share.dart';
import '../data/backup_sink.dart';
import '../data/env.dart';
import '../data/group_repo.dart';
import '../data/identity_service.dart';
import '../data/invite_repo.dart';
import '../data/key_store.dart';
import '../data/metrics_service.dart';
import '../data/notification_service.dart';
import '../data/porch_state.dart';
import '../data/presence_repo.dart';
import '../data/push_port.dart';
import '../data/relay_api.dart';
import '../data/relay_config.dart';
import '../data/state_store.dart';
import '../data/sync_service.dart';
import '../data/theme_store.dart';
import '../data/widget_cache.dart';
import '../domain/domain.dart';

// ---------------------------------------------------------------------------
// Bootstrap-provided leaves (overridden in main.dart and in tests)
// ---------------------------------------------------------------------------

Never _unbootstrapped(String name) =>
    throw UnimplementedError('$name must be overridden at bootstrap');

/// Porch's retry policy: never retry. Riverpod 3 retries a provider that
/// fails with an Exception up to 10 times, about 38 s in all, and shows it
/// as loading in between. Every async provider here reads this phone's own
/// keystore or state file, so a retry only holds the root gate on a spinner
/// in front of an error the person should see. Set on each async provider
/// and at the root (porchProviderScope in app.dart).
Duration? noAutoRetry(int retryCount, Object error) => null;

final sodiumProvider =
    Provider<SodiumSumo>((ref) => _unbootstrapped('sodiumProvider'));
final relayProvider =
    Provider<RelayApi>((ref) => _unbootstrapped('relayProvider'));
final keyStoreProvider =
    Provider<PorchKeyStore>((ref) => _unbootstrapped('keyStoreProvider'));
final stateStoreProvider =
    Provider<StateStore>((ref) => _unbootstrapped('stateStoreProvider'));

/// Unix seconds. One clock for every screen and repository.
final clockProvider = Provider<int Function()>(
    (ref) => () => DateTime.now().millisecondsSinceEpoch ~/ 1000);

/// The 25 s foreground poll (§1.3). Tests turn it off; widget tests drive
/// refreshes explicitly.
final tickerEnabledProvider = Provider<bool>((ref) => true);

// Ports with safe defaults (progressive enhancements — §5.3(e), §1.3).
final widgetMirrorProvider =
    Provider<WidgetCacheMirror>((ref) => const NoopWidgetCacheMirror());
final localNotifierProvider =
    Provider<LocalNotifier>((ref) => const NoopLocalNotifier());
final pushPortProvider = Provider<PushPort>((ref) => const NoopPush());
final backupSinkProvider = Provider<BackupSink>(
    (ref) => _unbootstrapped('backupSinkProvider'));

/// The system share sheet for backup files (backup_share.dart); bootstrap
/// binds share_plus, tests a recording double.
final backupShareProvider = Provider<BackupShare>(
    (ref) => _unbootstrapped('backupShareProvider'));

/// A backup just written: where the sink put it, and the ciphertext itself
/// so the person can share a copy somewhere that lasts.
class SavedBackup {
  final String where;
  final Uint8List blob;
  const SavedBackup({required this.where, required this.blob});
}

/// The persisted relay-URL override store and the one live endpoint holder the
/// HTTP client reads at call time (relay_config.dart). Both are set at
/// bootstrap; changing the endpoint's URL takes effect on the next relay call.
final relayConfigStoreProvider = Provider<RelayConfigStore>(
    (ref) => _unbootstrapped('relayConfigStoreProvider'));
final relayEndpointProvider = Provider<RelayEndpoint>(
    (ref) => _unbootstrapped('relayEndpointProvider'));

/// Argon2id cost overrides for the backup blob. null = libsodium MODERATE
/// (the §1.5 gate-3 default); tests override to MIN for speed.
final backupLimitsProvider =
    Provider<({int? ops, int? mem})>((ref) => (ops: null, mem: null));

/// Rotation fan-out jitter (§3.6): null = real randomness in [0, 30] s
/// (production); tests override with a scripted schedule (usually zero).
final rotationJitterProvider = Provider<int Function()?>((ref) => null);

/// Where the theme choice persists. Bootstrap binds the platform secret
/// store; the in-memory default keeps every test that does not care about
/// the theme free of wiring.
final themeStoreProvider = Provider<ThemePreferenceStore>(
    (ref) => ThemePreferenceStore(InMemorySecretStore()));

/// The stored theme choice, read by bootstrap before runApp. The fleet
/// default is to follow the phone.
final initialThemeProvider = Provider<OhThemeModePreference>(
    (ref) => OhThemeModePreference.defaultValue);

/// The theme choice for the first frame, read before runApp. A keystore
/// that refuses here must not stop the app from starting: the theme is only
/// a look, so it opens in the default and writes nothing. The same refusal
/// then shows at the root gate through [launchReadsProvider].
Future<OhThemeModePreference> readLaunchTheme(
    ThemePreferenceStore store) async {
  try {
    return OhThemeModePreference.fromStorage(await store.read());
  } on Object {
    return OhThemeModePreference.defaultValue;
  }
}

// ---------------------------------------------------------------------------
// Launch reads: the keystore reads the app needs before any screen
// ---------------------------------------------------------------------------

/// What launch reads from the keystore: the state-file key and the saved
/// relay URL.
class LaunchReads {
  final Uint8List stateKey;
  final String? storedRelayUrl;
  const LaunchReads({required this.stateKey, required this.storedRelayUrl});
}

/// The launch reads run under the root gate, not before runApp, so a
/// keystore that refuses at launch is shown like any other failed read,
/// with Try again, and nothing below the gate runs without them. A read
/// that throws mints no key: ensureStateKey writes only when the read
/// answers that there is none.
final launchReadsProvider = FutureProvider<LaunchReads>((ref) async {
  final stateKey = await ref
      .watch(keyStoreProvider)
      .ensureStateKey(ref.watch(sodiumProvider));
  final storedRelayUrl = await ref.watch(relayConfigStoreProvider).read();
  return LaunchReads(stateKey: stateKey, storedRelayUrl: storedRelayUrl);
}, retry: noAutoRetry);

/// Bootstrap's wiring of what launch read: the state store opens with the
/// state key, and the relay endpoint starts at the saved relay URL (else the
/// compile-time default). Both are read only below the root gate, which
/// waits for [launchReadsProvider], so `requireValue` always holds there.
List<Override> launchWiring({
  required StateStore Function(Uint8List stateKey) openStateStore,
}) =>
    [
      stateStoreProvider.overrideWith((ref) {
        final launch = ref.watch(launchReadsProvider).requireValue;
        return openStateStore(launch.stateKey);
      }),
      relayEndpointProvider.overrideWith((ref) {
        final launch = ref.watch(launchReadsProvider).requireValue;
        return RelayEndpoint(effectiveRelayUrl(
            stored: launch.storedRelayUrl, fallback: defaultRelayUrl));
      }),
    ];

/// The live theme choice: light, dark, or follow the phone.
final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, OhThemeModePreference>(
        ThemeModeNotifier.new);

class ThemeModeNotifier extends Notifier<OhThemeModePreference> {
  @override
  OhThemeModePreference build() => ref.read(initialThemeProvider);

  Future<void> set(OhThemeModePreference choice) async {
    state = choice;
    await ref.read(themeStoreProvider).write(choice.storageValue);
  }
}

// ---------------------------------------------------------------------------
// Derived services
// ---------------------------------------------------------------------------

final identityServiceProvider = Provider<IdentityService>((ref) =>
    IdentityService(ref.watch(sodiumProvider), ref.watch(keyStoreProvider)));

final metricsServiceProvider =
    Provider<MetricsService>((ref) => const MetricsService());

final notificationServiceProvider = Provider<NotificationService>(
    (ref) => NotificationService(ref.watch(localNotifierProvider)));

// ---------------------------------------------------------------------------
// Session: everything that exists only once an identity exists
// ---------------------------------------------------------------------------

class PorchSession {
  final PorchIdentity identity;
  final PorchEnv env;
  final GroupRepo groups;
  final PresenceRepo presence;
  final InviteRepo invites;
  final SyncService sync;

  PorchSession._withMirror(this.identity, this.env, WidgetCacheMirror mirror)
      : groups = GroupRepo(env),
        presence = PresenceRepo(env),
        invites = InviteRepo(env),
        sync = SyncService(env, widgetMirror: mirror);
}

/// null = no identity yet → onboarding owns the screen.
final sessionProvider =
    AsyncNotifierProvider<SessionNotifier, PorchSession?>(SessionNotifier.new,
        retry: noAutoRetry);

class SessionNotifier extends AsyncNotifier<PorchSession?> {
  @override
  Future<PorchSession?> build() async {
    final identity = await ref.watch(identityServiceProvider).load();
    if (identity == null) return null;
    return _makeSession(identity);
  }

  /// Silent keygen (§3.1 steps 1–6): entirely local, zero network. Pass
  /// [entropy] (from 12 recovery words) to restore an identity instead.
  Future<void> createIdentity({Uint8List? entropy}) async {
    final identity =
        await ref.read(identityServiceProvider).create(entropy: entropy);
    state = AsyncData(_makeSession(identity));
  }

  PorchSession _makeSession(PorchIdentity identity) {
    final env = PorchEnv(
      sodium: ref.read(sodiumProvider),
      relay: ref.read(relayProvider),
      stateStore: ref.read(stateStoreProvider),
      identity: identity,
      now: ref.read(clockProvider),
      rotationJitter: ref.read(rotationJitterProvider),
    );
    return PorchSession._withMirror(
        identity, env, ref.read(widgetMirrorProvider));
  }
}

// ---------------------------------------------------------------------------
// The one reactive copy of PorchState
// ---------------------------------------------------------------------------

final porchStateProvider =
    AsyncNotifierProvider<PorchStateNotifier, PorchState?>(
        PorchStateNotifier.new,
        retry: noAutoRetry);

class PorchStateNotifier extends AsyncNotifier<PorchState?> {
  @override
  Future<PorchState?> build() => ref.watch(stateStoreProvider).load();

  /// Repositories persist to the store; the UI re-reads through here after
  /// every action (load → mutate → save → reload keeps one source of truth).
  Future<void> reload() async {
    state = AsyncData(await ref.read(stateStoreProvider).load());
  }
}

// ---------------------------------------------------------------------------
// Actions: every user intention, one method each
// ---------------------------------------------------------------------------

final actionsProvider = Provider<PorchActions>(PorchActions.new);

class PorchActions {
  final Ref _ref;
  PorchActions(this._ref);

  Future<PorchSession> _session() async {
    final s = await _ref.read(sessionProvider.future);
    if (s == null) {
      throw StateError('no identity yet: onboarding is not finished');
    }
    return s;
  }

  Future<void> _reload() => _ref.read(porchStateProvider.notifier).reload();

  Future<void> _mutate(void Function(PorchState state) fn) async {
    final store = _ref.read(stateStoreProvider);
    final state = await store.load() ?? PorchState.initial();
    fn(state);
    await store.save(state);
    await _reload();
  }

  // --- onboarding -----------------------------------------------------------

  /// Set the display name and auto-create "My Porch" (§2 onboarding row).
  /// Still zero network: profile ops fan out only to groups that exist,
  /// and group creation is a client-side fact.
  Future<void> completeOnboarding({required String displayName}) async {
    final s = await _session();
    await s.groups.updateProfile(displayName: displayName);
    await s.groups.createGroup('My Porch');
    await _reload();
  }

  // --- presence -------------------------------------------------------------

  /// Tap Available (§3.4 step 1). Optimistic: never throws for network.
  Future<void> tapAvailable({
    List<String>? groupUuids,
    String tag = '',
    required int durationSeconds,
  }) async {
    final s = await _session();
    await s.presence.publishAvailable(
      groupUuids: groupUuids,
      tag: tag,
      expiresAt: _ref.read(clockProvider)() + durationSeconds,
    );
    await _reload();
  }

  /// Manual off (§3.4 step 4).
  Future<void> tapOff() async {
    final s = await _session();
    await s.presence.publishOff();
    await _reload();
  }

  /// RefreshFeed + fulfill redeemed invites + local notification diff.
  /// Never throws for network failure — offline keeps the old snapshot and
  /// its honest fetchedAt.
  Future<void> refresh() async {
    final s = await _session();
    final store = _ref.read(stateStoreProvider);
    final prev =
        (await store.load())?.presence ?? const <String, PresenceSnapshot>{};
    await s.sync.refreshFeed();
    final mid = await store.load();
    if (mid != null) {
      for (final g in mid.groups) {
        try {
          await s.invites.fulfillPending(g.groupUuid);
        } on RelayError {
          // Offline or refused: the next refresh retries; invites keep.
        }
      }
    }
    final next = await store.load();
    if (next != null) {
      await _ref.read(notificationServiceProvider).diffAndNotify(
          state: next, previous: prev, myPk: s.identity.sign.publicKey);
    }
    await _reload();
  }

  // --- groups ---------------------------------------------------------------

  Future<StoredGroup> createGroup(String name) async {
    final s = await _session();
    final g = await s.groups.createGroup(name);
    await _reload();
    return g;
  }

  Future<void> leaveGroup(String groupUuid) async {
    final s = await _session();
    await s.groups.leaveGroup(groupUuid);
    await _reload();
  }

  Future<void> removeMember(String groupUuid, Uint8List memberPk) async {
    final s = await _session();
    await s.groups.removeMember(groupUuid, memberPk: memberPk);
    await _reload();
  }

  Future<void> transferAdmin(String groupUuid, Uint8List toPk) async {
    final s = await _session();
    await s.groups.transferAdmin(groupUuid, toPk: toPk);
    await _reload();
  }

  Future<void> setGroupBroadcast(String groupUuid, bool broadcast) =>
      _mutate((state) {
        final g = state.groupByUuid(groupUuid);
        if (g != null) g.defaultBroadcast = broadcast;
      });

  // --- invites --------------------------------------------------------------

  Future<InviteHandle> mintInvite(String groupUuid) async {
    final s = await _session();
    final handle = await s.invites.mint(groupUuid);
    await _reload();
    return handle;
  }

  Future<void> voidInvite(String groupUuid, String inviteId) async {
    final s = await _session();
    await s.invites.voidInvite(groupUuid, inviteId);
    await _reload();
  }

  /// "void — regenerate" (§3.5 step 7). The repo's one-tap regenerate
  /// voids first; when the row was ALREADY voided (the UI's Regenerate
  /// button lives on dead rows), re-voiding would throw — mint fresh.
  Future<InviteHandle> regenerateInvite(
      String groupUuid, String inviteId) async {
    final s = await _session();
    final state = await _ref.read(stateStoreProvider).load();
    final invite = state
        ?.groupByUuid(groupUuid)
        ?.pendingInvites
        .where((i) => i.inviteId == inviteId)
        .firstOrNull;
    final handle = (invite != null && invite.status == InviteStatus.voided)
        ? await s.invites.mint(groupUuid)
        : await s.invites.regenerate(groupUuid, inviteId);
    await _reload();
    return handle;
  }

  Future<JoinedInvite> redeemInvite(String linkOrCode) async {
    final s = await _session();
    return s.invites.redeem(linkOrCode);
  }

  Future<StoredGroup?> completeJoin(JoinedInvite joined) async {
    final s = await _session();
    final g = await s.invites.completeJoin(joined);
    await _reload();
    return g;
  }

  // --- profile & settings ---------------------------------------------------

  Future<void> updateProfile({String? displayName, String? contactNote}) async {
    final s = await _session();
    await s.groups.updateProfile(
        displayName: displayName, contactNote: contactNote);
    await _reload();
  }

  Future<void> setNotifyFriend(String signPkB64, bool on) =>
      _mutate((state) => state.notifyPrefs.perFriend[signPkB64] = on);

  Future<void> setNotifyGroup(String groupUuid, bool on) =>
      _mutate((state) => state.notifyPrefs.perGroup[groupUuid] = on);

  Future<void> setDefaultExpiry(int seconds) =>
      _mutate((state) => state.settings.defaultExpiry = seconds);

  // --- relay endpoint (runtime-configurable) --------------------------------

  /// The user's saved relay-URL override, or null if they never set one (the
  /// app then uses the shipped compile-time [defaultRelayUrl]).
  Future<String?> relayUrlSetting() =>
      _ref.read(relayConfigStoreProvider).read();

  /// False while the relay in effect is the shipped placeholder: nothing can
  /// leave this phone, and the UI must say so rather than imply delivery.
  bool relayConfigured() =>
      !isPlaceholderRelay(_ref.read(relayEndpointProvider).url);

  /// The relay URL actually in effect right now (override, else default).
  String effectiveRelayUrlString() =>
      _ref.read(relayEndpointProvider).url.toString();

  /// Persist a relay URL override (empty clears it) and apply it live: the HTTP
  /// client reads the endpoint holder on its next call, so nothing rebuilds.
  /// Returns false, saving nothing, for an address Porch will not use
  /// ([isAllowedRelayUrl]: https only).
  Future<bool> setRelayUrl(String raw) async {
    final normalized = normalizeRelayInput(raw);
    if (normalized != null) {
      final u = Uri.tryParse(normalized);
      if (u == null || !isAllowedRelayUrl(u)) return false;
    }
    final store = _ref.read(relayConfigStoreProvider);
    if (normalized == null) {
      await store.clear();
    } else {
      await store.write(normalized);
    }
    _ref.read(relayEndpointProvider).url =
        effectiveRelayUrl(stored: normalized, fallback: defaultRelayUrl);
    return true;
  }

  Future<void> dismissFeedbackPrompt() => _mutate((state) => _ref
      .read(metricsServiceProvider)
      .dismissPrompt(state, _ref.read(clockProvider)()));

  // --- recovery -------------------------------------------------------------

  /// The 12 words, re-revealable (§3.1 step 2). Purely local.
  Future<List<String>> recoveryWords() async {
    final entropy = await _ref.read(keyStoreProvider).readEntropy();
    if (entropy == null) throw StateError('no identity yet');
    return entropyToMnemonic(entropy);
  }

  /// Restore identity AND state from a pasted backup file (the blob is
  /// canonical JSON text). Order matters: open first, so wrong words or a
  /// non-backup leaves nothing behind (throws [BackupException]); save the
  /// state before the identity exists, so the root gate never renders a
  /// half-restored device (no name → the words step). Zero network.
  Future<void> restoreFromBackup(
      {required String passphrase, required String backupText}) async {
    final contents = openBackup(
      _ref.read(sodiumProvider),
      passphrase: passphrase,
      blob: Uint8List.fromList(utf8.encode(backupText.trim())),
    );
    final PorchState state;
    try {
      state = PorchState.fromJson(contents.stateSnapshot);
    } on Object {
      throw const BackupException('backup payload malformed');
    }
    // The file itself is this phone's backup: setup is not unfinished.
    state.settings.hasBackup = true;
    await _ref.read(stateStoreProvider).save(state);
    await _ref
        .read(sessionProvider.notifier)
        .createIdentity(entropy: contents.entropy);
    await _reload();
  }

  /// Offer a backup blob to the system share sheet as a timestamped
  /// .porchbackup file. Purely local: the platform, not Porch, moves it.
  Future<void> shareBackup(Uint8List blob) {
    final now = DateTime.fromMillisecondsSinceEpoch(
        _ref.read(clockProvider)() * 1000,
        isUtc: true);
    return _ref
        .read(backupShareProvider)
        .share(blob, fileName: 'porch-${backupStamp(now)}.porchbackup');
  }

  /// The 6 backup words that unlock this identity's backup files, shown
  /// beside the 12 recovery words. Purely local.
  Future<List<String>> backupWords() async {
    final entropy = await _ref.read(keyStoreProvider).readEntropy();
    if (entropy == null) throw StateError('no identity yet');
    return backupPassphrase(_ref.read(sodiumProvider), entropy);
  }

  /// Seal the backup blob under the 6 backup words (§3.1 step 7) and hand
  /// it to the configured sink. Returns where it went and the blob (for
  /// sharing).
  Future<SavedBackup> saveBackup() async {
    final entropy = await _ref.read(keyStoreProvider).readEntropy();
    if (entropy == null) throw StateError('no identity yet');
    final state =
        await _ref.read(stateStoreProvider).load() ?? PorchState.initial();
    final limits = _ref.read(backupLimitsProvider);
    final blob = sealBackup(
      _ref.read(sodiumProvider),
      entropy: entropy,
      stateSnapshot: state.toJson(),
      opsLimit: limits.ops,
      memLimit: limits.mem,
    );
    final where = await _ref.read(backupSinkProvider).save(blob);
    // A groupless backup (onboarding) cannot bring groups back: remember to
    // offer a fresh one once a group exists. A backup with groups retires it.
    final hadGroups = state.groups.isNotEmpty;
    await _mutate((s) {
      s.settings.offerFreshBackup = !hadGroups;
      s.settings.hasBackup = true;
    });
    return SavedBackup(where: where, blob: blob);
  }

  /// "Not now" on Home's Finish setup item (the skipped backup).
  Future<void> dismissFinishSetup() =>
      _mutate((s) => s.settings.finishSetupDismissed = true);

  /// "Not now" on Home's fresh-backup offer.
  Future<void> dismissFreshBackupOffer() =>
      _mutate((s) => s.settings.offerFreshBackup = false);

  // --- start over -----------------------------------------------------------

  /// Start over with a new identity. First leave every group, sending each
  /// LEAVE while this identity still exists (GroupRepo.leaveEveryGroup).
  /// If any group could not be reached, stop there and name it: nothing is
  /// deleted unless [goOnWithoutUnreached] says the person, told which
  /// groups, chose to go on. Then the backup files on this phone go, then
  /// the state file, then the keys, and onboarding takes the screen. The
  /// relay address and the theme stay: they are not the identity.
  Future<StartOverResult> startOver({bool goOnWithoutUnreached = false}) async {
    final s = await _session();
    final unreached = await s.groups.leaveEveryGroup();
    if (unreached.isNotEmpty && !goOnWithoutUnreached) {
      await _reload();
      return (forgotten: false, unreached: unreached);
    }
    await _ref.read(backupSinkProvider).deleteAll();
    await _ref.read(stateStoreProvider).clear();
    await _ref.read(keyStoreProvider).wipe();
    // A new state key on the next launch read, then no identity: the root
    // gate shows onboarding, as on a new phone.
    _ref.invalidate(launchReadsProvider);
    _ref.invalidate(sessionProvider);
    _ref.invalidate(porchStateProvider);
    return (forgotten: true, unreached: unreached);
  }
}

/// What Start over did: whether this phone has forgotten the identity, and
/// the groups whose LEAVE did not reach the relay.
typedef StartOverResult = ({bool forgotten, List<String> unreached});
