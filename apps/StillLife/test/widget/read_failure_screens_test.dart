import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:openhearth_design/openhearth_design.dart';
import 'package:still_life/core/providers/database_provider.dart';
import 'package:still_life/core/providers/repository_providers.dart';
import 'package:still_life/core/widgets/read_failure.dart';
import 'package:still_life/features/dashboard/presentation/widgets/items_by_month_chart.dart';
import 'package:still_life/features/dashboard/presentation/widgets/recent_activity_widget.dart';
import 'package:still_life/features/inventory/domain/entities/item.dart';
import 'package:still_life/features/inventory/domain/repositories/item_repository.dart';
import 'package:still_life/features/inventory/presentation/controllers/photo_controller.dart';
import 'package:still_life/features/inventory/presentation/controllers/quantity_controller.dart';
import 'package:still_life/features/inventory/presentation/controllers/tag_controller.dart';
import 'package:still_life/features/inventory/presentation/screens/item_detail_screen.dart';
import 'package:still_life/features/inventory/presentation/screens/low_stock_screen.dart';
import 'package:still_life/features/loans/presentation/controllers/loan_controller.dart';
import 'package:still_life/features/locations/presentation/controllers/location_controller.dart';
import 'package:still_life/features/locations/presentation/screens/container_detail_screen.dart';
import 'package:still_life/features/search/presentation/controllers/search_controller.dart';
import 'package:still_life/features/search/presentation/screens/search_screen.dart';
import 'package:still_life/services/database/database.dart' hide Item;

import '../test_setup.dart';

// A failed read of the household's own things says so, with Try again. It
// is never drawn as an item not on loan, an item with no photos or tags, a
// dashboard section that vanished, an empty container or no saved
// searches. After Try again, with a read that works, the data is there.

final _disk = Exception('disk read failed');

class _Items extends Mock implements ItemRepository {}

Item _item(String id, String name) => Item(
      id: id,
      name: name,
      description: '',
      categoryId: 'c1',
      roomId: 'r1',
      createdAt: DateTime(2025),
      modifiedAt: DateTime(2025),
    );

void expectSaid(WidgetTester tester, String title) {
  expect(tester.takeException(), isNull);
  expect(find.text(title), findsOneWidget);
  expect(find.text('Try again'), findsOneWidget);
}

Future<void> tryAgain(WidgetTester tester, void Function() fix) async {
  fix();
  await tester.tap(find.text('Try again'));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  expect(find.text('Try again'), findsNothing);
}

void main() {
  ensureSqlite3();
  setUpAll(() => registerFallbackValue(const ItemQuery()));

  group('item lists', () {
    testWidgets('a failed read of the loans is said above the list',
        (tester) async {
      var failing = true;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          activeLoanedItemIdsProvider.overrideWith((ref) =>
              failing ? Stream.error(_disk) : Stream.value(<String>{})),
          lowStockItemsProvider.overrideWith((ref) => Stream.value([])),
        ],
        child: const MaterialApp(home: Scaffold(body: ItemMarksReadError())),
      ));
      await tester.pumpAndSettle();

      expectSaid(tester, 'Couldn’t read which items are on loan');
      await tryAgain(tester, () => failing = false);
    });

    testWidgets('a failed read of the low-stock list is said',
        (tester) async {
      var failing = true;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          activeLoanedItemIdsProvider
              .overrideWith((ref) => Stream.value(<String>{})),
          lowStockItemsProvider.overrideWith(
              (ref) => failing ? Stream.error(_disk) : Stream.value([])),
        ],
        child: const MaterialApp(home: Scaffold(body: ItemMarksReadError())),
      ));
      await tester.pumpAndSettle();

      expectSaid(tester, 'Couldn’t read which items are running low');
      await tryAgain(tester, () => failing = false);
    });

    testWidgets('Container: loans and items failed reads are said',
        (tester) async {
      var itemsFailing = true;
      var loansFailing = true;
      final repo = _Items();
      when(() => repo.watchItems(any())).thenAnswer((_) => itemsFailing
          ? Stream.error(_disk)
          : Stream.value([_item('i1', 'Lamp')]));
      await tester.pumpWidget(ProviderScope(
        overrides: [
          itemRepositoryProvider.overrideWithValue(repo),
          containerDetailProvider.overrideWith((ref, id) => Stream.value(null)),
          activeLoanedItemIdsProvider.overrideWith((ref) =>
              loansFailing ? Stream.error(_disk) : Stream.value(<String>{})),
          lowStockItemsProvider.overrideWith((ref) => Stream.value([])),
        ],
        child: const MaterialApp(home: ContainerDetailScreen(containerId: 'k')),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(OhReadError), findsOneWidget);
      expectSaid(tester, 'Couldn’t read what’s in this container');
      expect(find.text('No items in this container'), findsNothing);
      itemsFailing = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Lamp'), findsOneWidget);

      // The loans are still unread: said above the list.
      expectSaid(tester, 'Couldn’t read which items are on loan');
      await tryAgain(tester, () => loansFailing = false);
    });
  });

  testWidgets('Low stock: a failed read is the read error', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        lowStockItemsProvider.overrideWith((ref) => Stream.error(_disk)),
      ],
      child: const MaterialApp(home: LowStockScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(OhReadError), findsOneWidget);
    expectSaid(tester, 'Couldn’t read what’s running low');
  });

  testWidgets('Search: a failed read of saved searches is said',
      (tester) async {
    var failing = true;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        itemRepositoryProvider.overrideWithValue(_Items()),
        savedSearchesProvider.overrideWith((ref) async {
          if (failing) throw _disk;
          return [];
        }),
      ],
      child: const MaterialApp(home: SearchScreen()),
    ));
    await tester.pumpAndSettle();

    expectSaid(tester, 'Couldn’t read your saved searches');
    await tryAgain(tester, () => failing = false);
  });

  group('with the database', () {
    late AppDatabase db;
    final now = DateTime(2025, 1, 1);

    setUp(() async {
      db = AppDatabase.memory();
      await db.into(db.properties).insert(PropertiesCompanion.insert(
          id: 'p1', name: 'Home', createdAt: now, modifiedAt: now));
      await db.into(db.rooms).insert(RoomsCompanion.insert(
          id: 'r1',
          propertyId: 'p1',
          name: 'Living Room',
          createdAt: now,
          modifiedAt: now));
      await db.into(db.categories).insert(CategoriesCompanion.insert(
          id: 'c1', name: 'Electronics', createdAt: now, modifiedAt: now));
      await db.itemDao.insertItem(ItemsCompanion.insert(
          id: 'i1',
          name: 'Samsung TV',
          categoryId: 'c1',
          roomId: 'r1',
          createdAt: now,
          modifiedAt: now));
    });

    tearDown(() => db.close());

    testWidgets('Dashboard: failed section reads are said, never vanish',
        (tester) async {
      // The items table away: every read of it fails, as a broken disk.
      await tester.runAsync(
          () => db.customStatement('ALTER TABLE items RENAME TO items_away'));
      await tester.pumpWidget(ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [RecentActivityWidget(), ItemsByMonthChart()],
              ),
            ),
          ),
        ),
      ));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Couldn’t read recent activity'), findsOneWidget);
      expect(find.text('Couldn’t read items added by month'), findsOneWidget);
      expect(find.text('Try again'), findsNWidgets(2));
    });

    testWidgets('Item: failed reads of loans, photos and tags are said',
        (tester) async {
      var failing = true;
      await tester.binding.setSurfaceSize(const Size(600, 3000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          itemLoansProvider.overrideWith((ref, id) =>
              failing ? Stream.error(_disk) : Stream.value([])),
          itemPhotosProvider.overrideWith((ref, id) =>
              failing ? Stream.error(_disk) : Stream.value([])),
          itemTagsProvider.overrideWith((ref, id) async {
            if (failing) throw _disk;
            return [];
          }),
        ],
        child: const MaterialApp(home: ItemDetailScreen(itemId: 'i1')),
      ));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Couldn’t read this item’s loans'), findsOneWidget);
      expect(find.text('Couldn’t read this item’s photos'), findsOneWidget);
      expect(find.text('Couldn’t read this item’s tags'), findsOneWidget);
      expect(find.text('Lend this item'), findsNothing,
          reason: 'never offer Lend for an item whose loans are unread');

      // Try again on each, with reads that work: the loan card comes back.
      failing = false;
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('Try again').first);
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      expect(find.text('Try again'), findsNothing);
      expect(find.text('Lend this item'), findsOneWidget);

      // Drift's stream timers drain once the screen is gone.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 1));
    });
  });
}
