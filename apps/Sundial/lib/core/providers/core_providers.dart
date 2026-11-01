// lib/core/providers/core_providers.dart
import 'package:flutter/material.dart' hide Badge;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sundial/core/auth/auth_repository.dart';
import 'package:sundial/core/auth/ghost_auth_repository.dart';
import 'package:sundial/core/storage/app_database.dart' hide UserPrefs;
import 'package:sundial/features/badges/data/badges_dao.dart';
import 'package:sundial/features/badges/data/local_badges_repository.dart';
import 'package:sundial/features/badges/domain/badges_repository.dart';
import 'package:sundial/features/profiles/data/local_profiles_repository.dart';
import 'package:sundial/features/profiles/data/profiles_dao.dart';
import 'package:sundial/features/profiles/domain/profiles_repository.dart';
import 'package:sundial/features/sessions/data/local_sessions_repository.dart';
import 'package:sundial/features/sessions/data/sessions_dao.dart';
import 'package:sundial/features/sessions/domain/sessions_repository.dart';
import 'package:sundial/features/settings/data/local_settings_repository.dart';
import 'package:sundial/features/settings/domain/settings_repository.dart';
import 'package:sundial/features/settings/domain/user_prefs.dart';
import 'package:sundial/core/providers/retry_policy.dart';

part 'core_providers.g.dart';

/// Sentinel profile ID meaning "all profiles simultaneously".
/// When the timer stops with this ID, one session per profile is saved.
const kEveryoneProfileId = 'everyone';

// Seeded from main() before ProviderScope
final sharedPreferencesProvider =
    Provider<SharedPreferences>((ref) => throw UnimplementedError(),
        name: 'sharedPreferencesProvider');

@riverpod
AppDatabase appDatabase(Ref ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
}

@riverpod
SessionsRepository sessionsRepository(Ref ref) {
  final db = ref.watch(appDatabaseProvider);
  return LocalSessionsRepository(SessionsDao(db));
}

@riverpod
BadgesRepository badgesRepository(Ref ref) {
  final db = ref.watch(appDatabaseProvider);
  return LocalBadgesRepository(BadgesDao(db), SessionsDao(db));
}

@riverpod
ProfilesRepository profilesRepository(Ref ref) {
  final db = ref.watch(appDatabaseProvider);
  return LocalProfilesRepository(ProfilesDao(db), SessionsDao(db));
}

@Riverpod(retry: noAutoRetry)
Stream<List<Profile>> profilesList(Ref ref) =>
    ref.watch(profilesRepositoryProvider).watchAll();

/// The currently selected profile ID. Persisted in SharedPreferences.
/// Defaults to [kEveryoneProfileId] on fresh installs; existing installs
/// read their saved value (typically 'default').
///
/// keepAlive: the selection belongs to the app, as the StateNotifierProvider
/// it replaces was never auto-disposed.
@Riverpod(keepAlive: true)
class ActiveProfileId extends _$ActiveProfileId {
  static const _key = 'active_profile_id';

  @override
  String build() =>
      ref.read(sharedPreferencesProvider).getString(_key) ?? kEveryoneProfileId;

  void select(String profileId) {
    state = profileId;
    ref.read(sharedPreferencesProvider).setString(_key, profileId);
  }
}

@riverpod
SettingsRepository settingsRepository(Ref ref) {
  final db = ref.watch(appDatabaseProvider);
  return LocalSettingsRepository(db);
}

@riverpod
AuthRepository authRepository(Ref ref) => GhostAuthRepository();

@Riverpod(retry: noAutoRetry)
Stream<AppMode> appMode(Ref ref) =>
    ref.watch(settingsRepositoryProvider).watchAppMode();

@Riverpod(retry: noAutoRetry)
Stream<UserPrefs> userPrefs(Ref ref) =>
    ref.watch(settingsRepositoryProvider).watchUserPrefs();

@riverpod
ThemeMode themeMode(Ref ref) {
  final prefs = ref.watch(userPrefsProvider);
  return prefs.when(
    data: (p) => p.themeMode.themeMode,
    loading: () => ThemeMode.system,
    error: (_, __) => ThemeMode.system,
  );
}

/// Badges earned in the most recent save.
/// Set by TimerNotifier and the session sheets, shown and cleared by AppShell.
/// keepAlive, as the StateProvider it replaces was: whoever sets it has no
/// listener of its own.
@Riverpod(keepAlive: true)
class NewlyEarnedBadges extends _$NewlyEarnedBadges {
  @override
  List<Badge> build() => const [];

  void show(List<Badge> badges) => state = badges;

  void clear() => state = const [];
}

/// Transient flag: when true, AppShell forces FlowScreen regardless of the
/// user's durable [AppMode] preference. Set via the `launchSource=widget`
/// MethodChannel path wired up in main.dart. Cleared on
/// [AppLifecycleState.paused] by the [widgetLaunchLifecycleObserverProvider]
/// and by ModePill's Rich tap, so the user can exit Flow mode.
///
/// keepAlive, as the StateProvider it replaces was: main.dart sets it from a
/// platform call with no listener of its own.
@Riverpod(keepAlive: true)
class WidgetLaunchOverride extends _$WidgetLaunchOverride {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

class _WidgetLaunchLifecycleObserver with WidgetsBindingObserver {
  _WidgetLaunchLifecycleObserver(this._ref);
  final Ref _ref;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _ref.read(widgetLaunchOverrideProvider.notifier).set(false);
    }
  }
}

/// Reading this provider as a side-effect attaches a lifecycle observer that
/// clears [widgetLaunchOverrideProvider] on app pause. Read it once from
/// main.dart after the first frame so the override never outlives a single
/// foreground session.
final widgetLaunchLifecycleObserverProvider = Provider<WidgetsBindingObserver>(
  (ref) {
    final observer = _WidgetLaunchLifecycleObserver(ref);
    WidgetsBinding.instance.addObserver(observer);
    ref.onDispose(() => WidgetsBinding.instance.removeObserver(observer));
    return observer;
  },
  name: 'widgetLaunchLifecycleObserverProvider',
);
