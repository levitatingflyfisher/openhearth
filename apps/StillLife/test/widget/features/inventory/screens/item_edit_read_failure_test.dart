// Editing an item whose record cannot be read must fail, never open an empty
// form: saving an empty form would write blank fields over the item.
//
// On riverpod 2 `AsyncValue.value` threw on a failure; on riverpod 3 it is
// null. The edit screen keeps the throw (shownValue), and so does the
// Rooms screen's Add button, which would otherwise offer to add a home again
// when the homes cannot be read.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:still_life/core/providers/database_provider.dart';
import 'package:still_life/core/providers/profile_providers.dart';
import 'package:still_life/core/providers/sync_providers.dart';
import 'package:still_life/core/sync/sync_stamp.dart';
import 'package:still_life/features/inventory/presentation/controllers/inventory_controller.dart';
import 'package:still_life/features/inventory/presentation/screens/item_edit_screen.dart';
import 'package:still_life/features/locations/presentation/controllers/location_controller.dart';
import 'package:still_life/features/locations/presentation/screens/rooms_screen.dart';
import 'package:still_life/features/profiles/domain/entities/profile.dart'
    as domain;
import 'package:still_life/services/database/database.dart';

import '../../../../test_setup.dart';

class _NoProfile extends ActiveProfileNotifier {
  @override
  Future<domain.Profile?> build() async => null;
}

void main() {
  ensureSqlite3();
  late AppDatabase db;
  setUp(() => db = AppDatabase.memory());
  tearDown(() => db.close());

  testWidgets('a failed read of the item being edited is no empty form', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          syncStampProvider.overrideWithValue(SyncStamp.none),
          activeProfileProvider.overrideWith(_NoProfile.new),
          itemDetailProvider.overrideWith(
            (ref, id) => Stream.error(Exception('disk read failed')),
          ),
        ],
        child: const MaterialApp(home: ItemEditScreen(itemId: 'item1')),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNotNull,
        reason: 'the failure is said, as on riverpod 2');
    expect(find.byType(TextFormField), findsNothing,
        reason: 'no empty form to save over the item');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('a failed read of the homes does not offer to add one again', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          syncStampProvider.overrideWithValue(SyncStamp.none),
          propertiesProvider.overrideWith(
            (ref) => Stream.error(Exception('disk read failed')),
          ),
        ],
        child: const MaterialApp(home: RoomsScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();
    tester.takeException();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();

    expect(tester.takeException(), isNotNull,
        reason: 'the failure is said, as on riverpod 2');
    expect(find.byType(AlertDialog), findsNothing,
        reason: 'no "add a home" offer when the homes are unknown');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 20));
  });

  // The edit screen does not watch the homes. On riverpod 3 a bare read of a
  // provider nobody listens to can stay "not loaded", and "New room" would
  // silently make nothing.
  testWidgets('New room on the edit screen makes the room in the home', (
    tester,
  ) async {
    final now = DateTime(2025, 1, 1);
    await db.into(db.properties).insert(PropertiesCompanion.insert(
        id: 'p1', name: 'Home', createdAt: now, modifiedAt: now));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          syncStampProvider.overrideWithValue(SyncStamp.none),
          activeProfileProvider.overrideWith(_NoProfile.new),
        ],
        child: const MaterialApp(home: ItemEditScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byTooltip('New room'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).last, 'Attic');
    await tester.pump();
    await tester.tap(find.text('Create'));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();

    final rooms = await tester.runAsync(
        () => (db.select(db.rooms)..where((r) => r.name.equals('Attic'))).get());
    expect(rooms, hasLength(1), reason: 'the room was made');
    expect(rooms!.single.propertyId, 'p1');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 20));
  });
}
