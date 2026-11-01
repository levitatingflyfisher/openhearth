import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart' show pumpEventQueue;
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';
import 'package:still_life/core/providers/database_provider.dart';
import 'package:still_life/core/providers/repository_providers.dart';
import 'package:still_life/core/providers/sync_providers.dart';
import 'package:still_life/core/sync/sync_stamp.dart';
import 'package:still_life/features/backup/backup_wiring.dart';
import 'package:still_life/features/recently_deleted/presentation/undo_providers.dart';
import 'package:still_life/features/recently_deleted/data/recently_deleted_repository.dart';
import 'package:still_life/services/database/database.dart';
import 'package:still_life/services/export/import_service.dart';
import 'package:still_life/services/export/json_export_service.dart';

/// A [Ref] out of a plain container, so a test can run the real restore
/// hook, which takes the backup controller's [Ref].
final _refProvider = Provider<Ref>((ref) => ref);

/// StillLife's real backup wiring over an in-memory database. Sync stamps
/// and the photo folder are switched off: no keystore or path_provider in a
/// test.
List<Override> restoreOverrides(AppDatabase db) => [
  ...sanctuaryBackupOverrides(web: false),
  databaseProvider.overrideWithValue(db),
  syncStampProvider.overrideWithValue(SyncStamp.none),
  importServiceProvider.overrideWith(
    (ref) => ImportService(
      ref.watch(databaseProvider),
      photoRootResolver: () async => null,
    ),
  ),
  recentlyDeletedRepositoryProvider.overrideWith(
    (ref) => RecentlyDeletedRepository(ref.watch(databaseProvider)),
  ),
];

/// What one household holds, in small: one item with a tag, a receipt, an
/// appraisal and a maintenance task. Two calls with different words give a
/// device and a backup that share every id, so the merge restore overwrites
/// each row.
Future<void> seedHousehold(
  AppDatabase db, {
  String itemName = 'Old lamp',
  String tagName = 'Garage',
  String storeName = 'Old Store',
  int appraisalCents = 1000,
  String maintenanceTitle = 'Oil the hinge',
  DateTime? createdAt,
  bool itemDeleted = false,
}) async {
  final now = DateTime.now();
  final made = createdAt ?? now;
  await db
      .into(db.properties)
      .insertOnConflictUpdate(
        PropertiesCompanion.insert(
          id: 'p1',
          name: 'Home',
          createdAt: made,
          modifiedAt: made,
        ),
      );
  await db
      .into(db.rooms)
      .insertOnConflictUpdate(
        RoomsCompanion.insert(
          id: 'r1',
          propertyId: 'p1',
          name: 'Hall',
          createdAt: made,
          modifiedAt: made,
        ),
      );
  await db
      .into(db.categories)
      .insertOnConflictUpdate(
        CategoriesCompanion.insert(
          id: 'c1',
          name: 'Lighting',
          createdAt: made,
          modifiedAt: made,
        ),
      );
  await db
      .into(db.receipts)
      .insertOnConflictUpdate(
        ReceiptsCompanion.insert(
          id: 'rc1',
          photoPath: '',
          createdAt: made,
          storeName: Value(storeName),
        ),
      );
  await db
      .into(db.items)
      .insertOnConflictUpdate(
        ItemsCompanion.insert(
          id: 'item_1',
          name: itemName,
          categoryId: 'c1',
          roomId: 'r1',
          createdAt: made,
          modifiedAt: made,
          warrantyExpiration: Value(now.add(const Duration(days: 30))),
          receiptId: const Value('rc1'),
          isDeleted: Value(itemDeleted),
        ),
      );
  await db
      .into(db.tags)
      .insertOnConflictUpdate(
        TagsCompanion.insert(
          id: 't1',
          name: tagName,
          createdAt: made,
          modifiedAt: made,
        ),
      );
  await db
      .into(db.itemTags)
      .insertOnConflictUpdate(
        ItemTagsCompanion.insert(
          itemId: 'item_1',
          tagId: 't1',
          createdAt: made,
        ),
      );
  await db
      .into(db.appraisals)
      .insertOnConflictUpdate(
        AppraisalsCompanion.insert(
          id: 'a1',
          itemId: 'item_1',
          mode: 'resale',
          valueCents: appraisalCents,
          itemModelKey: 'lamp',
          queriedAt: now.millisecondsSinceEpoch,
          expiresAt: now.add(const Duration(days: 365)).millisecondsSinceEpoch,
        ),
      );
  await db
      .into(db.maintenanceLogs)
      .insertOnConflictUpdate(
        MaintenanceLogsCompanion.insert(
          id: 'm1',
          title: maintenanceTitle,
          performedAt: made,
          createdAt: made,
          modifiedAt: made,
          itemId: const Value('item_1'),
          nextDueAt: Value(now.add(const Duration(days: 10))),
        ),
      );
}

/// A backup of [seed]'s household, as the bytes the restore decrypts to.
Future<Uint8List> backupOf(Future<void> Function(AppDatabase db) seed) async {
  final src = AppDatabase.memory();
  try {
    await seed(src);
    final json = await JsonExportService(src).exportToJson();
    return Uint8List.fromList(utf8.encode(json));
  } finally {
    await src.close();
  }
}

/// StillLife's restore, as the backup screen runs it: the serializer's
/// merge, then the app's restore hook.
Future<void> restoreBackup(ProviderContainer container, Uint8List bytes) async {
  await container.read(backupSerializerProvider).restoreAll(bytes);
  container
      .read(sanctuaryBackupConfigProvider)
      .onAfterRestore
      ?.call(container.read(_refProvider));
  // Let the database's change notices reach their listeners, as they do
  // before the next frame in the app.
  await pumpEventQueue();
}

/// The shell's Undo offer for an item delete, as the item screen makes it.
Future<void> deleteWithUndo(ProviderContainer container, String itemId) async {
  final trash = container.read(recentlyDeletedRepositoryProvider);
  final deletion = await trash.snapshot([itemId]);
  await container.read(itemRepositoryProvider).deleteItem(itemId);
  container
      .read(shellUndoControllerProvider)
      .show(
        message: 'Deleted the item',
        onUndo: () => trash.restoreItems(deletion),
      );
}
