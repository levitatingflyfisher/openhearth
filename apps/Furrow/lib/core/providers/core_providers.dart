// lib/core/providers/core_providers.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openhearth_design/openhearth_design.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:furrow/core/auth/auth_repository.dart';
import 'package:furrow/core/auth/ghost_auth_repository.dart';
import 'package:furrow/core/providers/retry_policy.dart';
import 'package:furrow/core/storage/app_database.dart' hide UserPrefs;
import 'package:furrow/features/habits/data/awards_dao.dart';
import 'package:furrow/features/habits/data/habit_marks_dao.dart';
import 'package:furrow/features/habits/data/habits_dao.dart';
import 'package:furrow/features/habits/data/habits_repository.dart';
import 'package:furrow/features/settings/data/local_settings_repository.dart';
import 'package:furrow/features/settings/domain/settings_repository.dart';
import 'package:furrow/features/settings/domain/user_prefs.dart';

part 'core_providers.g.dart';

// Seeded from main() before ProviderScope.
// Named so the stored-data guard can match it (a hand-written provider has
// no name otherwise).
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError(),
  name: 'sharedPreferencesProvider',
);

@riverpod
AppDatabase appDatabase(Ref ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
}

@riverpod
HabitsRepository habitsRepository(Ref ref) {
  final db = ref.watch(appDatabaseProvider);
  return HabitsRepository(HabitsDao(db), HabitMarksDao(db));
}

@riverpod
AwardsDao awardsDao(Ref ref) =>
    AwardsDao(ref.watch(appDatabaseProvider));

/// Active (non-archived) habits in display order — the Today grid + Garden.
@Riverpod(retry: noAutoRetry)
Stream<List<Habit>> activeHabits(Ref ref) =>
    ref.watch(habitsRepositoryProvider).watchActive();

/// Resting (archived) habits — Settings' way back to the field.
@Riverpod(retry: noAutoRetry)
Stream<List<Habit>> restingHabits(Ref ref) =>
    ref.watch(habitsRepositoryProvider).watchArchived();

/// Removed (soft-deleted) habits: Settings' Recently removed list.
@Riverpod(retry: noAutoRetry)
Stream<List<Habit>> removedHabits(Ref ref) =>
    ref.watch(habitsRepositoryProvider).watchRemoved();

/// All marks recorded on a given `yyyy-MM-dd` (the Today grid cells).
@Riverpod(retry: noAutoRetry)
Stream<List<HabitMark>> marksForDay(Ref ref, String dateDay) =>
    ref.watch(habitsRepositoryProvider).watchMarksForDay(dateDay);

/// All marks for one habit (Habit Detail heatmap + history).
@Riverpod(retry: noAutoRetry)
Stream<List<HabitMark>> marksForHabit(Ref ref, String habitId) =>
    ref.watch(habitsRepositoryProvider).watchMarksForHabit(habitId);

/// Every mark (Stats whole-field heatmap + consistency counts).
@Riverpod(retry: noAutoRetry)
Stream<List<HabitMark>> allMarks(Ref ref) =>
    ref.watch(habitsRepositoryProvider).watchAllMarks();

/// All awards (earned + unearned) for the badge shelf.
@Riverpod(retry: noAutoRetry)
Stream<List<HabitBadge>> awards(Ref ref) =>
    ref.watch(awardsDaoProvider).watchAll();

@riverpod
SettingsRepository settingsRepository(Ref ref) {
  final db = ref.watch(appDatabaseProvider);
  return LocalSettingsRepository(db);
}

@riverpod
AuthRepository authRepository(Ref ref) => GhostAuthRepository();

@Riverpod(retry: noAutoRetry)
Stream<UserPrefs> userPrefs(Ref ref) =>
    ref.watch(settingsRepositoryProvider).watchUserPrefs();

@riverpod
ThemeMode themeMode(Ref ref) {
  final prefs = ref.watch(userPrefsProvider);
  return prefs.when(
    data: (p) => p.themeMode.themeMode,
    loading: () => ThemeMode.system,
    error: (_, _) => ThemeMode.system,
  );
}

/// The app-wide Undo offer for removing a habit. The detail screen pops
/// after Remove, so the offer has to outlive it: the bar lives in the
/// AppShell. No timer (fleet delete ruling); it ends on Undo, Dismiss, or the
/// next removal. The habit is soft-deleted, so letting the offer go loses
/// nothing: Settings' Recently removed list keeps the way back. A restore
/// dismisses it (stored_data_caches.dart).
final habitUndoProvider = Provider<OhUndoController>((ref) {
  final controller = OhUndoController();
  ref.onDispose(controller.dispose);
  return controller;
}, name: 'habitUndoProvider');

/// Awards earned by the most recent mark write. Set after each mark write
/// (recheckAwards and the time sheet), consumed and cleared by AppShell to
/// trigger the gentle confetti. Kept alive like the StateProvider it
/// replaced: it is only ever read and written, and AppShell's listen must
/// still see an award set while nothing else watches it.
@Riverpod(keepAlive: true)
class NewlyEarnedAwards extends _$NewlyEarnedAwards {
  @override
  List<HabitBadge> build() => const [];

  void show(List<HabitBadge> awards) => state = awards;

  void clear() => state = const [];
}
