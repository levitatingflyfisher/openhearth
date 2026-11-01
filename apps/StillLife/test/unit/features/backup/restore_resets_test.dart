import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:still_life/features/appraisal/domain/entities/appraisal.dart';
import 'package:still_life/features/appraisal/presentation/controllers/appraisal_controller.dart';
import 'package:still_life/features/dashboard/presentation/widgets/warranty_expiry_widget.dart';
import 'package:still_life/features/inventory/presentation/controllers/receipt_controller.dart';
import 'package:still_life/features/inventory/presentation/controllers/tag_controller.dart';
import 'package:still_life/features/maintenance/presentation/controllers/maintenance_controller.dart';
import 'package:still_life/features/recently_deleted/presentation/undo_providers.dart';
import 'package:still_life/services/database/database.dart';

import '../../../support/restore_harness.dart';
import '../../../test_setup.dart';

/// A restore merges the backup into this device. Every cached read of the
/// household's data must show the merged rows afterwards, and no Undo
/// offered before the restore may write over them.
void main() {
  setUpAll(ensureSqlite3);

  late AppDatabase db;
  late ProviderContainer container;

  setUp(() async {
    db = AppDatabase.memory();
    await seedHousehold(db);
    container = ProviderContainer(overrides: restoreOverrides(db));
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<void> restoreNewer() async => restoreBackup(
    container,
    await backupOf(
      (src) => seedHousehold(
        src,
        itemName: 'Brass lamp',
        tagName: 'Attic',
        storeName: 'New Store',
        appraisalCents: 2500,
        maintenanceTitle: 'Replace the bulb',
      ),
    ),
  );

  group('cached reads show the restored data', () {
    test('the item screen shows the restored tags', () async {
      final before = await container.read(itemTagsProvider('item_1').future);
      expect(before.map((t) => t.name), ['Garage']);

      await restoreNewer();

      final after = await container.read(itemTagsProvider('item_1').future);
      expect(after.map((t) => t.name), ['Attic']);
    });

    test('the item screen shows the restored receipt', () async {
      final before = await container.read(itemReceiptProvider('rc1').future);
      expect(before?.storeName, 'Old Store');

      await restoreNewer();

      final after = await container.read(itemReceiptProvider('rc1').future);
      expect(after?.storeName, 'New Store');
    });

    test('the appraise sheet shows the restored appraisal', () async {
      const key = (itemId: 'item_1', mode: AppraisalMode.resale);
      // The sheet watches it while open; it stays cached after it closes.
      final sub = container.listen(appraisalControllerProvider(key), (_, _) {});
      addTearDown(sub.close);
      final before = await container.read(
        appraisalControllerProvider(key).future,
      );
      expect(before?.valueCents, 1000);

      await restoreNewer();

      final after = await container.read(
        appraisalControllerProvider(key).future,
      );
      expect(after?.valueCents, 2500);
    });

    test('the warranty card shows the restored items', () async {
      final before = await container.read(warrantyExpiringSoonProvider.future);
      expect(before.map((i) => i.name), ['Old lamp']);

      await restoreNewer();

      final after = await container.read(warrantyExpiringSoonProvider.future);
      expect(after.map((i) => i.name), ['Brass lamp']);
    });

    test('the upcoming maintenance card shows the restored tasks', () async {
      final before = await container.read(upcomingMaintenanceProvider.future);
      expect(before.map((m) => m.title), ['Oil the hinge']);

      await restoreNewer();

      final after = await container.read(upcomingMaintenanceProvider.future);
      expect(after.map((m) => m.title), ['Replace the bulb']);
    });
  });

  group('no Undo offered before a restore can write over it', () {
    test('a pending item-delete Undo is dropped, so it cannot bring back an '
        'item the backup holds as deleted', () async {
      await deleteWithUndo(container, 'item_1');
      final undo = container.read(shellUndoControllerProvider);
      expect(undo.pending, isNotNull);

      await restoreBackup(
        container,
        await backupOf(
          (src) =>
              seedHousehold(src, itemName: 'Brass lamp', itemDeleted: true),
        ),
      );

      expect(undo.pending, isNull);
      await undo.undo();
      final row = await (db.select(
        db.items,
      )..where((t) => t.id.equals('item_1'))).getSingle();
      expect(row.isDeleted, isTrue);
    });

    test('a pending Undo on the Policies screen is dropped too', () async {
      // The Policies screen sits in the Reports tab, which stays alive
      // while Settings runs the restore.
      final sub = container.listen(
        screenUndoControllerProvider('policies'),
        (_, _) {},
      );
      addTearDown(sub.close);
      final undo = container.read(screenUndoControllerProvider('policies'));
      undo.show(message: 'Deleted the policy', onUndo: () async {});

      await restoreNewer();

      expect(undo.pending, isNull);
    });
  });
}
