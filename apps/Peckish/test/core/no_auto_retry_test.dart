import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:openhearth_design/openhearth_design.dart';
import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/core/storage/app_database.dart' hide UserPrefs;
import 'package:peckish/features/ai/data/ai_config.dart';
import 'package:peckish/features/ai/data/ai_config_repository.dart';
import 'package:peckish/features/ai/presentation/guess_sheet.dart';
import 'package:peckish/features/diary/data/diary_repository.dart';
import 'package:peckish/features/diary/domain/diary_entry.dart';
import 'package:peckish/features/diary/presentation/regulars_rail.dart';
import 'package:peckish/features/diary/presentation/today_screen.dart';
import 'package:peckish/features/food/data/food_usage_repository.dart';
import 'package:peckish/features/food/data/usda_food_repository.dart';
import 'package:peckish/features/food/domain/food_usage.dart';
import 'package:peckish/features/groceries/data/grocery_repository.dart';
import 'package:peckish/features/groceries/domain/grocery_item.dart';
import 'package:peckish/features/groceries/presentation/groceries_screen.dart';
import 'package:peckish/features/plan/data/plan_repository.dart';
import 'package:peckish/features/plan/domain/plan_entry.dart';
import 'package:peckish/features/plan/presentation/plan_screen.dart';
import 'package:peckish/features/recipes/data/recipe_repository.dart';
import 'package:peckish/features/recipes/domain/recipe.dart';
import 'package:peckish/features/recipes/presentation/recipe_detail_screen.dart';
import 'package:peckish/features/recipes/presentation/recipes_screen.dart';
import 'package:peckish/features/settings/domain/settings_repository.dart';
import 'package:peckish/features/settings/domain/user_prefs.dart';
import 'package:peckish/shared/theme/app_theme.dart';
import 'package:peckish/shared/widgets/undo_host.dart';

// Every provider here reads the device's own storage. Riverpod 3 retries a
// failed provider by default (up to 10 times, from 200 ms apart). Peckish
// keeps riverpod 2's behaviour: a failed read is read once, and the failure
// stays visible. A read that fails once on a phone's own disk will fail
// again, and retrying it only hides the error behind a reload.
//
// Each dependency throws an Exception, never an Error: riverpod 3 retries
// only an Exception, so a test that throws StateError cannot catch a retry.
//
// A failed read reaches the screen as the fleet's read-error state with
// Try again, never as an empty list (an empty grocery list says "your list
// is gone") and never as a broken build. The checks below pin that too;
// read_failure_screens_test.dart pins Try again.
//
// Drift widget-test rules apply: see groceries_screen_test.dart.

final _disk = Exception('disk read failed');

class _FailingGroceries extends GroceryRepository {
  _FailingGroceries(super.db);
  int reads = 0;
  @override
  Stream<List<GroceryItem>> watchAll() {
    reads++;
    return Stream.error(_disk);
  }
}

class _FailingPlan extends PlanRepository {
  _FailingPlan(super.db);
  int reads = 0;
  @override
  Stream<List<PlanEntry>> watchDays(List<String> days) {
    reads++;
    return Stream.error(_disk);
  }
}

class _FailingRecipes extends RecipeRepository {
  _FailingRecipes(super.db);
  int lists = 0;
  int byIds = 0;
  @override
  Stream<List<Recipe>> watchAll() {
    lists++;
    return Stream.error(_disk);
  }

  @override
  Future<Recipe?> byId(String id) async {
    byIds++;
    throw _disk;
  }
}

class _FailingDiary extends DiaryRepository {
  _FailingDiary(super.db);
  int reads = 0;
  @override
  Stream<List<DiaryEntry>> watchEntriesForDay(String day) {
    reads++;
    return Stream.error(_disk);
  }
}

class _FailingUsage extends FoodUsageRepository {
  _FailingUsage(super.db);
  int reads = 0;
  @override
  Stream<List<FoodUsage>> watchVisible({int? limit}) {
    reads++;
    return Stream.error(_disk);
  }
}

class _FailingUsda extends UsdaFoodRepository {
  _FailingUsda(super.db);
  int checks = 0;
  @override
  Future<bool> spineCurrent() async {
    checks++;
    throw _disk;
  }
}

class _FailingSettings implements SettingsRepository {
  int reads = 0;
  @override
  Stream<UserPrefs> watchUserPrefs() {
    reads++;
    return Stream.error(_disk);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FailingAiConfig implements AiConfigRepository {
  int loads = 0;
  @override
  Future<AiConfig> load() async {
    loads++;
    throw _disk;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _host(AppDatabase db, Widget home, List<Override> overrides) =>
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        spineReadyProvider.overrideWith((ref) async {}),
        ...overrides,
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => UndoHost(child: child!),
        home: home,
      ),
    );

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

/// Pumps [home] over a failing dependency and checks two things: the
/// failure reaches the screen as the read-error state (it is not drawn as
/// an empty list), and after 5 s the dependency was still read only once.
Future<void> _failsOnceAndShows(
  WidgetTester tester,
  AppDatabase db,
  Widget home,
  List<Override> overrides,
  int Function() reads,
) async {
  await tester.pumpWidget(_host(db, home, overrides));
  await tester.pump();
  await tester.pump();
  expect(tester.takeException(), isNull,
      reason: 'a failed read is a calm state, not a broken build');
  expect(find.byType(OhReadError), findsOneWidget,
      reason: 'the failed read must reach the screen, not an empty state');
  await tester.pump(const Duration(seconds: 5));
  expect(tester.takeException(), isNull,
      reason: 'no second attempt fails again');
  expect(find.byType(OhReadError), findsOneWidget);
  expect(reads(), 1, reason: 'a failed read is not retried');
  await _unmount(tester);
}

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));

  testWidgets('Groceries: a failed list read is read once and shown',
      (tester) async {
    final repo = _FailingGroceries(db);
    await _failsOnceAndShows(tester, db, const GroceriesScreen(),
        [groceryRepositoryProvider.overrideWithValue(repo)], () => repo.reads);
  });

  testWidgets('Plan: a failed week read is read once and shown',
      (tester) async {
    final repo = _FailingPlan(db);
    await _failsOnceAndShows(tester, db, const PlanScreen(),
        [planRepositoryProvider.overrideWithValue(repo)], () => repo.reads);
  });

  testWidgets('Recipes: a failed recipe list read is read once and shown',
      (tester) async {
    final repo = _FailingRecipes(db);
    await _failsOnceAndShows(tester, db, const RecipesScreen(),
        [recipeRepositoryProvider.overrideWithValue(repo)], () => repo.lists);
  });

  testWidgets('Recipe page: a failed recipe read is read once and shown',
      (tester) async {
    final repo = _FailingRecipes(db);
    await _failsOnceAndShows(
        tester,
        db,
        const RecipeDetailScreen(recipeId: 'r1'),
        [recipeRepositoryProvider.overrideWithValue(repo)],
        () => repo.byIds);
  });

  testWidgets('Today: a failed day read is read once and shown',
      (tester) async {
    final repo = _FailingDiary(db);
    await _failsOnceAndShows(tester, db, const TodayScreen(),
        [diaryRepositoryProvider.overrideWithValue(repo)], () => repo.reads);
  });

  // Providers that are not tied to one screen: checked on a container.

  testWidgets('the regulars rail reads a failed list once', (tester) async {
    final repo = _FailingUsage(db);
    final c = ProviderContainer(
        overrides: [foodUsageRepositoryProvider.overrideWithValue(repo)]);
    addTearDown(c.dispose);
    c.listen(regularsProvider, (_, _) {});
    await tester.pump();
    expect(c.read(regularsProvider).hasError, isTrue);
    await tester.pump(const Duration(seconds: 5));
    expect(repo.reads, 1);
  });

  testWidgets('user settings: a failed read happens once', (tester) async {
    final repo = _FailingSettings();
    final c = ProviderContainer(
        overrides: [settingsRepositoryProvider.overrideWithValue(repo)]);
    addTearDown(c.dispose);
    c.listen(userPrefsProvider, (_, _) {});
    await tester.pump();
    expect(c.read(userPrefsProvider).hasError, isTrue);
    await tester.pump(const Duration(seconds: 5));
    expect(repo.reads, 1);
  });

  testWidgets('the food spine check runs once when it fails', (tester) async {
    final repo = _FailingUsda(db);
    final c = ProviderContainer(
        overrides: [usdaFoodRepositoryProvider.overrideWithValue(repo)]);
    addTearDown(c.dispose);
    c.listen(spineReadyProvider, (_, _) {});
    await tester.pump();
    expect(c.read(spineReadyProvider).hasError, isTrue);
    await tester.pump(const Duration(seconds: 5));
    expect(repo.checks, 1,
        reason: 'a failed check must not reload the 2.5 MB spine in a loop');
  });

  testWidgets('the AI settings load runs once when it fails', (tester) async {
    final repo = _FailingAiConfig();
    final c = ProviderContainer(
        overrides: [aiConfigRepositoryProvider.overrideWithValue(repo)]);
    addTearDown(c.dispose);
    c.listen(aiConfigProvider, (_, _) {});
    await tester.pump();
    expect(c.read(aiConfigProvider).hasError, isTrue);
    await tester.pump(const Duration(seconds: 5));
    expect(repo.loads, 1);
  });
}
