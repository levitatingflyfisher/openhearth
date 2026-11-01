import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:openhearth_design/openhearth_design.dart';
import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/diary/data/diary_repository.dart';
import 'package:peckish/features/diary/domain/diary_entry.dart';
import 'package:peckish/features/diary/presentation/history_screen.dart';
import 'package:peckish/features/diary/presentation/today_screen.dart';
import 'package:peckish/features/food/data/food_usage_repository.dart';
import 'package:peckish/features/food/domain/food_usage.dart';
import 'package:peckish/features/food/domain/macro_set.dart';
import 'package:peckish/features/food/presentation/foods_screen.dart';
import 'package:peckish/features/groceries/data/grocery_repository.dart';
import 'package:peckish/features/groceries/domain/grocery_item.dart';
import 'package:peckish/features/groceries/presentation/groceries_screen.dart';
import 'package:peckish/features/plan/data/plan_repository.dart';
import 'package:peckish/features/plan/domain/plan_entry.dart';
import 'package:peckish/features/plan/domain/week.dart';
import 'package:peckish/features/plan/presentation/plan_screen.dart';
import 'package:peckish/features/recipes/data/recipe_repository.dart';
import 'package:peckish/features/recipes/domain/recipe.dart';
import 'package:peckish/features/recipes/presentation/recipe_detail_screen.dart';
import 'package:peckish/features/recipes/presentation/recipes_screen.dart';
import 'package:peckish/shared/theme/app_theme.dart';
import 'package:peckish/shared/widgets/undo_host.dart';

// A failed read of the household's own lists shows the fleet's read-error
// state with Try again. It is never drawn as an empty list (an empty grocery
// list reads "my list is gone") and never as Flutter's grey error box. After
// Try again, with a read that works, the data is there.
//
// Each fake reads the real in-memory database once [_Switch.failing] is
// cleared. Drift widget-test rules apply: see groceries_screen_test.dart.

final _disk = Exception('disk read failed');

class _Switch {
  bool failing = true;
}

class _Groceries extends GroceryRepository {
  _Groceries(super.db, this.sw);
  final _Switch sw;
  @override
  Stream<List<GroceryItem>> watchAll() =>
      sw.failing ? Stream.error(_disk) : super.watchAll();
}

class _Plan extends PlanRepository {
  _Plan(super.db, this.sw);
  final _Switch sw;
  @override
  Stream<List<PlanEntry>> watchDays(List<String> days) =>
      sw.failing ? Stream.error(_disk) : super.watchDays(days);
}

class _Recipes extends RecipeRepository {
  _Recipes(super.db, this.sw);
  final _Switch sw;
  @override
  Stream<List<Recipe>> watchAll() =>
      sw.failing ? Stream.error(_disk) : super.watchAll();
  @override
  Future<Recipe?> byId(String id) async {
    if (sw.failing) throw _disk;
    return super.byId(id);
  }
}

class _Diary extends DiaryRepository {
  _Diary(super.db, this.sw);
  final _Switch sw;
  @override
  Stream<List<DiaryEntry>> watchEntriesForDay(String day) =>
      sw.failing ? Stream.error(_disk) : super.watchEntriesForDay(day);
  @override
  Stream<Map<String, MacroSet>> watchTotalsForDays(List<String> days) =>
      sw.failing ? Stream.error(_disk) : super.watchTotalsForDays(days);
}

class _Usage extends FoodUsageRepository {
  _Usage(super.db, this.sw);
  final _Switch sw;
  @override
  Stream<List<FoodUsage>> watchVisible({int? limit}) =>
      sw.failing ? Stream.error(_disk) : super.watchVisible(limit: limit);
}

DiaryEntry _entry(String id, String day, String label) => DiaryEntry(
      id: id,
      day: day,
      at: DateTime.parse('${day}T12:00:00'),
      food: const FoodRef.quick(),
      label: label,
      qty: 1,
      unitLabel: 'serving',
      grams: null,
      macros: const MacroSet(kcal: 300),
      source: EntrySource.manual,
      createdAt: DateTime.parse('${day}T12:00:00'),
    );

void main() {
  late AppDatabase db;
  late _Switch sw;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    sw = _Switch();
  });

  Future<void> pump(
      WidgetTester tester, Widget home, List<Override> overrides) async {
    await tester.pumpWidget(ProviderScope(
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
    ));
    await tester.pumpAndSettle();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  /// The read-error state is up, with Try again, no Flutter error, and
  /// none of [emptyTexts].
  void expectReadError(
      WidgetTester tester, String title, List<String> emptyTexts) {
    expect(tester.takeException(), isNull,
        reason: 'a failed read is a calm state, not a broken build');
    expect(find.byType(ErrorWidget), findsNothing);
    expect(find.byType(OhReadError), findsOneWidget);
    expect(find.text(title), findsOneWidget);
    expect(find.text(OhErrorMessages.readFailed), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    for (final t in emptyTexts) {
      expect(find.textContaining(t), findsNothing, reason: 'drawn as empty');
    }
  }

  Future<void> tryAgainWorking(WidgetTester tester) async {
    sw.failing = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(OhReadError), findsNothing);
  }

  testWidgets('Groceries', (tester) async {
    await tester.runAsync(() => GroceryRepository(db).addManual('Milk'));
    await pump(tester, const GroceriesScreen(),
        [groceryRepositoryProvider.overrideWithValue(_Groceries(db, sw))]);

    expectReadError(
        tester, 'Couldn’t read your grocery list', ['The list is empty']);

    await tryAgainWorking(tester);
    expect(find.text('Milk'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('Plan', (tester) async {
    // Monday: the first row, on screen without a scroll.
    final monday = weekDays(mondayOf(DateTime.now())).first;
    await tester.runAsync(() async {
      await RecipeRepository(db).create(Recipe(
        id: 'r-1',
        title: 'Soup',
        servings: 4,
        createdAt: DateTime(2026, 7, 25),
        ingredients: const [RecipeIngredient(id: 'i-1', text: '1 onion')],
      ));
      await PlanRepository(db).upsert(PlanEntry(
        id: 'p-1',
        day: monday,
        slot: PlanSlot.dinner,
        kind: PlanKind.recipe,
        refId: 'r-1',
      ));
    });
    await pump(tester, const PlanScreen(),
        [planRepositoryProvider.overrideWithValue(_Plan(db, sw))]);

    expectReadError(tester, 'Couldn’t read this week’s plan', []);

    await tryAgainWorking(tester);
    expect(find.textContaining('Soup'), findsWidgets);
    await unmount(tester);
  });

  testWidgets('Recipes', (tester) async {
    await tester.runAsync(() => RecipeRepository(db).create(Recipe(
          id: 'r-1',
          title: 'Soup',
          servings: 4,
          createdAt: DateTime(2026, 7, 25),
          ingredients: const [RecipeIngredient(id: 'i-1', text: '1 onion')],
        )));
    await pump(tester, const RecipesScreen(),
        [recipeRepositoryProvider.overrideWithValue(_Recipes(db, sw))]);

    expectReadError(tester, 'Couldn’t read your recipes', ['An empty box']);

    await tryAgainWorking(tester);
    expect(find.text('Soup'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('Recipe page', (tester) async {
    await tester.runAsync(() => RecipeRepository(db).create(Recipe(
          id: 'r-1',
          title: 'Soup',
          servings: 4,
          createdAt: DateTime(2026, 7, 25),
          ingredients: const [RecipeIngredient(id: 'i-1', text: '1 onion')],
        )));
    await pump(tester, const RecipeDetailScreen(recipeId: 'r-1'),
        [recipeRepositoryProvider.overrideWithValue(_Recipes(db, sw))]);

    expectReadError(tester, 'Couldn’t read this recipe', []);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tryAgainWorking(tester);
    expect(find.text('Soup'), findsWidgets);
    await unmount(tester);
  });

  testWidgets('Today: a failed read of the day', (tester) async {
    final today = DiaryEntry.dayOf(DateTime.now());
    await tester.runAsync(
        () => DiaryRepository(db).log(_entry('e-1', today, 'Porridge')));
    await pump(tester, const TodayScreen(),
        [diaryRepositoryProvider.overrideWithValue(_Diary(db, sw))]);

    expectReadError(tester, 'Couldn’t read today’s log', ['Nothing logged']);

    await tryAgainWorking(tester);
    expect(find.text('Porridge'), findsWidgets);
    await unmount(tester);
  });

  testWidgets('Today: a failed read of the regulars', (tester) async {
    await pump(tester, const TodayScreen(),
        [foodUsageRepositoryProvider.overrideWithValue(_Usage(db, sw))]);

    expectReadError(tester, 'Couldn’t read today’s log', ['Nothing logged']);

    await tryAgainWorking(tester);
    expect(find.textContaining('Nothing logged yet'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('History: a failed read of the month', (tester) async {
    await pump(tester, const HistoryScreen(),
        [diaryRepositoryProvider.overrideWithValue(_Diary(db, sw))]);

    expectReadError(tester, 'Couldn’t read your history', []);
    // The month bar stays, so another month is one tap away.
    expect(find.byTooltip('Previous month'), findsOneWidget);

    await tryAgainWorking(tester);
    await unmount(tester);
  });

  testWidgets('History: a failed read of one day', (tester) async {
    await tester.runAsync(
        () => DiaryRepository(db).log(_entry('e-1', '2026-11-02', 'Stew')));
    await pump(tester, const HistoryDayScreen(day: '2026-11-02'),
        [diaryRepositoryProvider.overrideWithValue(_Diary(db, sw))]);

    expectReadError(
        tester, 'Couldn’t read this day', ['Nothing logged this day']);

    await tryAgainWorking(tester);
    expect(find.text('Stew'), findsWidgets);
    await unmount(tester);
  });

  testWidgets('Foods: a failed read of the regulars', (tester) async {
    await pump(tester, const FoodsScreen(),
        [foodUsageRepositoryProvider.overrideWithValue(_Usage(db, sw))]);

    expectReadError(tester, 'Couldn’t read your foods', []);

    await tryAgainWorking(tester);
    await unmount(tester);
  });
}
