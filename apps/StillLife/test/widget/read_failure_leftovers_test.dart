import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:openhearth_design/openhearth_design.dart';
import 'package:sanctuary_auth_core/sanctuary_auth_core.dart';
import 'package:still_life/core/errors/failures.dart';
import 'package:still_life/core/errors/result.dart';
import 'package:still_life/core/providers/billing_providers.dart';
import 'package:still_life/core/providers/database_provider.dart';
import 'package:still_life/core/providers/profile_providers.dart';
import 'package:still_life/core/providers/repository_providers.dart';
import 'package:still_life/core/providers/sync_providers.dart';
import 'package:still_life/core/sync/sync_stamp.dart';
import 'package:still_life/features/backup/presentation/photo_backup_tile.dart';
import 'package:still_life/features/billing/domain/account.dart';
import 'package:still_life/features/billing/domain/billing_service.dart';
import 'package:still_life/features/inventory/domain/entities/category.dart'
    as domain;
import 'package:still_life/features/inventory/domain/entities/item.dart';
import 'package:still_life/features/inventory/domain/entities/tag.dart';
import 'package:still_life/features/inventory/domain/repositories/category_repository.dart';
import 'package:still_life/features/inventory/domain/repositories/item_repository.dart';
import 'package:still_life/features/inventory/presentation/controllers/category_controller.dart';
import 'package:still_life/features/inventory/presentation/controllers/inventory_controller.dart';
import 'package:still_life/features/inventory/presentation/controllers/photo_controller.dart';
import 'package:still_life/features/inventory/presentation/controllers/tag_controller.dart';
import 'package:still_life/features/inventory/presentation/screens/item_edit_screen.dart';
import 'package:still_life/features/inventory/presentation/widgets/filter_dialog.dart';
import 'package:still_life/features/inventory/presentation/widgets/price_history_chart.dart';
import 'package:still_life/features/inventory/presentation/widgets/tag_selector_widget.dart';
import 'package:still_life/features/locations/domain/entities/room.dart';
import 'package:still_life/features/locations/presentation/controllers/location_controller.dart';
import 'package:still_life/features/profiles/domain/entities/profile.dart'
    as profile;
import 'package:still_life/features/search/presentation/screens/search_screen.dart';
import 'package:still_life/services/database/database.dart'
    hide Item, Tag, Room;

import '../test_setup.dart';

// The cases the first pass left: a failed read of the household's rooms,
// categories, tags, containers, photos, value history, backup key or plan
// says so in its place, with Try again. It is never a hidden dropdown, a
// missing chip row, "Unknown" for a room, an empty edit form, a New room
// that silently does nothing, or "Upgrade to Pro" for a paying household.

final _disk = Exception('disk read failed');

class _Categories extends Mock implements CategoryRepository {}

class _Billing extends Mock implements BillingService {}

class _NoProfile extends ActiveProfileNotifier {
  @override
  Future<profile.Profile?> build() async => null;
}

Room _room(String id, String name) => Room(
      id: id,
      propertyId: 'p1',
      name: name,
      createdAt: DateTime(2025),
      modifiedAt: DateTime(2025),
    );

final _tag = Tag(
  id: 't1',
  name: 'Fragile',
  createdAt: DateTime(2025),
  modifiedAt: DateTime(2025),
);

final _category = domain.Category(
  id: 'c1',
  name: 'Electronics',
  createdAt: DateTime(2025),
  modifiedAt: DateTime(2025),
);

void expectSaid(WidgetTester tester, String title) {
  expect(tester.takeException(), isNull);
  expect(find.text(title), findsOneWidget);
}

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  ensureSqlite3();
  setUpAll(() => registerFallbackValue(const ItemQuery()));

  group('Filter', () {
    Future<void> pumpFilter(
        WidgetTester tester, List<Override> overrides) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ProviderScope(
        overrides: overrides,
        child: const MaterialApp(
            home: Scaffold(body: FilterDialog(currentFilter: FilterResult()))),
      ));
      await settle(tester);
    }

    testWidgets('a failed read of the rooms is said, never a hidden choice',
        (tester) async {
      var failing = true;
      await pumpFilter(tester, [
        roomsProvider.overrideWith((ref) => failing
            ? Stream.error(_disk)
            : Stream.value([_room('r1', 'Garage')])),
        categoriesProvider.overrideWith((ref) => Stream.value([])),
        tagsProvider.overrideWith((ref) => Stream.value([])),
      ]);

      expectSaid(tester, 'Couldn’t read your rooms');
      failing = false;
      await tester.tap(find.text('Try again'));
      await settle(tester);
      expect(find.text('Try again'), findsNothing);
      expect(find.text('All rooms'), findsOneWidget);
    });

    testWidgets('a failed read of the categories is said', (tester) async {
      var failing = true;
      await pumpFilter(tester, [
        roomsProvider.overrideWith((ref) => Stream.value([])),
        categoriesProvider.overrideWith((ref) =>
            failing ? Stream.error(_disk) : Stream.value([_category])),
        tagsProvider.overrideWith((ref) => Stream.value([])),
      ]);

      expectSaid(tester, 'Couldn’t read your categories');
      failing = false;
      await tester.tap(find.text('Try again'));
      await settle(tester);
      expect(find.text('Try again'), findsNothing);
      expect(find.text('All categories'), findsOneWidget);
    });

    testWidgets('a failed read of the tags is said', (tester) async {
      var failing = true;
      await pumpFilter(tester, [
        roomsProvider.overrideWith((ref) => Stream.value([])),
        categoriesProvider.overrideWith((ref) => Stream.value([])),
        tagsProvider.overrideWith(
            (ref) => failing ? Stream.error(_disk) : Stream.value([_tag])),
      ]);

      expectSaid(tester, 'Couldn’t read your tags');
      failing = false;
      await tester.tap(find.text('Try again'));
      await settle(tester);
      expect(find.text('Try again'), findsNothing);
      expect(find.text('Fragile'), findsOneWidget);
    });
  });

  testWidgets('Value history: a failed read is said under its title',
      (tester) async {
    var failing = true;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        priceHistoryProvider.overrideWith((ref, id) => failing
            ? Stream.error(_disk)
            : Stream.value(<PriceHistoryEntry>[])),
      ],
      child: const MaterialApp(
          home: Scaffold(body: PriceHistoryChart(itemId: 'i1'))),
    ));
    await settle(tester);

    expectSaid(tester, 'Couldn’t read this item’s value history');
    expect(find.text('Value History'), findsOneWidget);
    failing = false;
    await tester.tap(find.text('Try again'));
    await settle(tester);
    expect(find.text('Try again'), findsNothing);
  });

  testWidgets(
      'Tags on the edit form: a failed read is said, and Add opens no '
      'empty picker', (tester) async {
    var failing = true;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        tagsProvider.overrideWith(
            (ref) => failing ? Stream.error(_disk) : Stream.value([_tag])),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: TagSelectorWidget(
              selectedTagIds: const ['t1'], onTagsChanged: (_) {}),
        ),
      ),
    ));
    await settle(tester);

    expectSaid(tester, 'Couldn’t read your tags');
    expect(find.text('No tags assigned'), findsNothing);
    await tester.tap(find.text('Add'));
    await settle(tester);
    expect(find.text('Select Tags'), findsNothing,
        reason: 'a picker over unread tags would replace the item’s tags');

    failing = false;
    await tester.tap(find.text('Try again'));
    await settle(tester);
    expect(find.text('Try again'), findsNothing);
    expect(find.text('Fragile'), findsOneWidget);
  });

  testWidgets('Photo backup: a failed read of the key is said, not hidden',
      (tester) async {
    var builds = 0;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authNotifierProvider.overrideWith(() => _FailingAuth(() => builds++)),
      ],
      child: const MaterialApp(home: Scaffold(body: PhotoBackupTile())),
    ));
    await settle(tester);

    expectSaid(tester, 'Couldn’t read this device’s backup key');
    expect(find.text('Try again'), findsOneWidget);
    expect(builds, 1);
    await tester.tap(find.text('Try again'));
    await settle(tester);
    expect(builds, 2, reason: 'Try again reads the key again');
  });

  group('Search, where is', () {
    final lamp = Item(
      id: 'i1',
      name: 'Lamp',
      description: '',
      categoryId: 'c1',
      roomId: 'r1',
      createdAt: DateTime(2025),
      modifiedAt: DateTime(2025),
    );

    testWidgets('a failed read of the rooms is said, never "Unknown"',
        (tester) async {
      var failing = true;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          searchItemsProvider
              .overrideWith((ref, q) => Stream.value([lamp])),
          roomsProvider.overrideWith((ref) => failing
              ? Stream.error(_disk)
              : Stream.value([_room('r1', 'Garage')])),
          categoriesProvider.overrideWith((ref) => Stream.value([])),
          allContainersProvider.overrideWith((ref) => Stream.value([])),
        ],
        child: const MaterialApp(home: SearchScreen()),
      ));
      await tester.enterText(find.byType(TextField), 'where is lamp');
      await settle(tester);

      expectSaid(tester, 'Couldn’t read your rooms');
      expect(find.text('Unknown'), findsNothing);

      failing = false;
      await tester.tap(find.text('Try again'));
      await settle(tester);
      expect(find.text('Try again'), findsNothing);
      expect(find.text('Garage'), findsOneWidget);
    });

    testWidgets('a failed filtered search is said, never "No results"',
        (tester) async {
      final repo = _Items();
      var failing = true;
      when(() => repo.watchItems(any())).thenAnswer((_) =>
          failing ? Stream.error(_disk) : Stream.value([lamp]));
      await tester.pumpWidget(ProviderScope(
        overrides: [
          itemRepositoryProvider.overrideWithValue(repo),
          searchItemsProvider.overrideWith((ref, q) => Stream.value([])),
          roomsProvider.overrideWith((ref) => Stream.value([])),
          categoriesProvider.overrideWith((ref) => Stream.value([])),
          allContainersProvider.overrideWith((ref) => Stream.value([])),
        ],
        child: const MaterialApp(home: SearchScreen()),
      ));
      await tester.enterText(find.byType(TextField), 'lamp with photo');
      await settle(tester);

      expect(tester.takeException(), isNull);
      expect(find.textContaining('No results'), findsNothing);
      expect(find.text('Couldn’t search your items'), findsOneWidget);

      failing = false;
      await tester.tap(find.text('Try again'));
      await settle(tester);
      expect(find.text('Lamp'), findsOneWidget);
    });
  });

  group('the plan (account) read', () {
    late _Billing svc;
    late bool bearer;

    setUp(() {
      svc = _Billing();
      bearer = true;
      when(() => svc.hasBearer()).thenAnswer((_) async => bearer);
    });

    Future<Object?> read() async {
      final c = ProviderContainer(
          overrides: [billingServiceProvider.overrideWithValue(svc)]);
      addTearDown(c.dispose);
      try {
        return await c.read(accountProvider.future);
      } catch (e) {
        return e;
      }
    }

    test('a failed read is an error, never "no account"', () async {
      when(() => svc.getAccount()).thenAnswer(
          (_) async => const Err(NetworkFailure('getAccount: timeout')));
      expect(await read(), isA<NetworkFailure>());
    });

    test('a revoked bearer, removed by the read, is no account', () async {
      when(() => svc.getAccount()).thenAnswer((_) async {
        bearer = false;
        return const Err(NetworkFailure('getAccount: 401'));
      });
      expect(await read(), isNull);
    });

    test('no bearer is no account, without a read', () async {
      bearer = false;
      expect(await read(), isNull);
      verifyNever(() => svc.getAccount());
    });

    test('an account read is the account', () async {
      final acc = Account(
        tier: 'pro',
        status: SubscriptionStatus.active,
        tokensUsedMonth: 1,
        tokensMonthCap: 10,
        monthResetAt: DateTime(2026),
      );
      when(() => svc.getAccount()).thenAnswer((_) async => Success(acc));
      expect(await read(), acc);
    });
  });

  group('the edit screen', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase.memory();
      final now = DateTime(2026);
      await db.into(db.properties).insert(PropertiesCompanion.insert(
          id: 'p1', name: 'Home', createdAt: now, modifiedAt: now));
      await db.into(db.rooms).insert(RoomsCompanion.insert(
          id: 'r1',
          propertyId: 'p1',
          name: 'Garage',
          createdAt: now,
          modifiedAt: now));
      await db.into(db.categories).insert(CategoriesCompanion.insert(
          id: 'c1', name: 'Tools', createdAt: now, modifiedAt: now));
      await db.itemDao.insertItem(ItemsCompanion.insert(
          id: 'i1',
          name: 'Drill',
          categoryId: 'c1',
          roomId: 'r1',
          createdAt: now,
          modifiedAt: now));
    });

    tearDown(() => db.close());

    Future<void> pumpEdit(WidgetTester tester, Widget screen,
        List<Override> overrides) async {
      tester.view.physicalSize = const Size(800, 6000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          syncStampProvider.overrideWithValue(SyncStamp.none),
          activeProfileProvider.overrideWith(_NoProfile.new),
          ...overrides,
        ],
        child: MaterialApp(home: screen),
      ));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await settle(tester);
    }

    Future<void> unmount(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 1));
    }

    testWidgets('a failed read of the item is said, never an empty form',
        (tester) async {
      var failing = true;
      await pumpEdit(tester, const ItemEditScreen(itemId: 'i1'), [
        itemDetailProvider.overrideWith((ref, id) => failing
            ? Stream.error(_disk)
            : Stream.value(Item(
                id: 'i1',
                name: 'Drill',
                description: '',
                categoryId: 'c1',
                roomId: 'r1',
                createdAt: DateTime(2026),
                modifiedAt: DateTime(2026),
              ))),
      ]);

      expect(tester.takeException(), isNull);
      expect(find.byType(OhReadError), findsOneWidget);
      expect(find.text('Couldn’t read this item'), findsOneWidget);
      expect(find.text('Edit Item'), findsOneWidget, reason: 'the frame stays');
      expect(find.text('Save'), findsNothing,
          reason: 'no Save over a form that never read the item');

      failing = false;
      await tester.tap(find.text('Try again'));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await settle(tester);
      expect(find.byType(OhReadError), findsNothing);
      expect(find.text('Drill'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets(
        'failed reads of categories, rooms, containers, photos and tags are '
        'each said in place', (tester) async {
      var failing = true;
      final categories = _Categories();
      when(() => categories.watchCategories()).thenAnswer((_) => failing
          ? Stream.error(_disk)
          : Stream.value([
              domain.Category(
                  id: 'c1',
                  name: 'Tools',
                  createdAt: DateTime(2026),
                  modifiedAt: DateTime(2026))
            ]));
      await pumpEdit(tester, const ItemEditScreen(itemId: 'i1'), [
        categoryRepositoryProvider.overrideWithValue(categories),
        roomsProvider.overrideWith((ref) => failing
            ? Stream.error(_disk)
            : Stream.value([_room('r1', 'Garage')])),
        containersInRoomProvider.overrideWith(
            (ref, id) => failing ? Stream.error(_disk) : Stream.value([])),
        itemPhotosProvider.overrideWith(
            (ref, id) => failing ? Stream.error(_disk) : Stream.value([])),
        tagsProvider.overrideWith(
            (ref) => failing ? Stream.error(_disk) : Stream.value([])),
      ]);

      expect(tester.takeException(), isNull);
      for (final title in [
        'Couldn’t read your categories',
        'Couldn’t read your rooms',
        'Couldn’t read the containers in this room',
        'Couldn’t read this item’s photos',
        'Couldn’t read your tags',
      ]) {
        expect(find.text(title), findsOneWidget, reason: title);
      }

      failing = false;
      for (var i = 0; i < 5; i++) {
        if (find.text('Try again').evaluate().isEmpty) break;
        await tester.ensureVisible(find.text('Try again').first);
        await tester.tap(find.text('Try again').first);
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)));
        await settle(tester);
      }
      expect(tester.takeException(), isNull);
      expect(find.text('Try again'), findsNothing);
      await unmount(tester);
    });

    testWidgets('New room with the homes unread says so and makes nothing',
        (tester) async {
      await pumpEdit(tester, const ItemEditScreen(), [
        propertiesProvider.overrideWith((ref) => Stream.error(_disk)),
      ]);

      await tester.tap(find.byTooltip('New room'));
      await settle(tester);
      await tester.enterText(
          find.descendant(
              of: find.byType(AlertDialog), matching: find.byType(TextField)),
          'Attic');
      await tester.pump();
      await tester.tap(find.text('Create'));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await settle(tester);

      expect(tester.takeException(), isNull);
      expect(
          find.textContaining('Couldn’t read your homes, so the room wasn’t '
              'added'),
          findsOneWidget);
      final rooms = await tester.runAsync(() => db.select(db.rooms).get());
      expect(rooms!.map((r) => r.name), isNot(contains('Attic')));
      await unmount(tester);
    });
  });
}

class _Items extends Mock implements ItemRepository {}

class _FailingAuth extends AuthNotifier {
  _FailingAuth(this.onBuild);
  final void Function() onBuild;

  @override
  Future<AuthState> build() async {
    onBuild();
    throw Exception('keychain read failed');
  }
}
