// A failed read of the household's inventory is read once and stays failed
// until someone taps Try again. It never reloads by itself in a loop: a loop
// puts a spinner where the error belongs and reads the disk again and again.
//
// Riverpod 3 retries a failed provider by default (up to 10 times, from
// 200 ms apart). Still Life turns that off, at the root and on every async
// provider. Each test here fails a provider through the real database: an
// in-memory Drift database whose every select throws an Exception (riverpod
// retries an Exception, never an Error) and is counted. It then waits long
// enough for two retries and checks that no second read and no new state
// came.
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:still_life/core/providers/appraisal_providers.dart';
import 'package:still_life/core/providers/bootstrap_provider.dart';
import 'package:still_life/core/providers/database_provider.dart';
import 'package:still_life/core/providers/profile_providers.dart';
import 'package:still_life/core/providers/repository_providers.dart';
import 'package:still_life/features/appraisal/domain/entities/appraisal.dart';
import 'package:still_life/features/dashboard/presentation/controllers/dashboard_controller.dart';
import 'package:still_life/features/dashboard/presentation/widgets/warranty_expiry_widget.dart';
import 'package:still_life/features/inventory/presentation/controllers/category_controller.dart';
import 'package:still_life/features/inventory/presentation/controllers/inventory_controller.dart';
import 'package:still_life/features/inventory/presentation/controllers/photo_controller.dart';
import 'package:still_life/features/inventory/presentation/controllers/quantity_controller.dart';
import 'package:still_life/features/inventory/presentation/controllers/receipt_controller.dart';
import 'package:still_life/features/inventory/presentation/controllers/tag_controller.dart';
import 'package:still_life/features/loans/presentation/controllers/loan_controller.dart';
import 'package:still_life/features/locations/presentation/controllers/location_controller.dart';
import 'package:still_life/features/maintenance/presentation/controllers/maintenance_controller.dart';
import 'package:still_life/features/reports/presentation/controllers/policy_controller.dart';
import 'package:still_life/services/database/database.dart';

import '../../test_setup.dart';

/// Every select fails with an Exception, and is counted.
class _FailingReads extends QueryInterceptor {
  var reads = 0;

  @override
  Future<List<Map<String, Object?>>> runSelect(
      QueryExecutor executor, String statement, List<Object?> args) {
    reads++;
    return Future.error(Exception('disk read failed'));
  }
}

/// Listens to one provider and reports each new state. A closure, so the
/// test never names a riverpod listenable type (they moved between majors).
typedef _Listen = void Function(
    ProviderContainer c, void Function(AsyncValue<Object?> next) onChange);

const _appraisalKey = (itemId: 'item1', mode: AppraisalMode.resale);

final Map<String, _Listen> _cases = {
  'bootstrapProvider': (c, f) => c.listen(bootstrapProvider, (_, n) => f(n)),
  'profilesProvider': (c, f) => c.listen(profilesProvider, (_, n) => f(n)),
  'priceHistoryProvider': (c, f) =>
      c.listen(priceHistoryProvider('item1'), (_, n) => f(n)),
  'latestAppraisalProvider': (c, f) =>
      c.listen(latestAppraisalProvider(_appraisalKey), (_, n) => f(n)),
  'dashboardSummaryProvider': (c, f) =>
      c.listen(dashboardSummaryProvider, (_, n) => f(n)),
  'warrantyExpiringSoonProvider': (c, f) =>
      c.listen(warrantyExpiringSoonProvider, (_, n) => f(n)),
  'categoriesProvider': (c, f) => c.listen(categoriesProvider, (_, n) => f(n)),
  'inventoryItemsProvider': (c, f) =>
      c.listen(inventoryItemsProvider, (_, n) => f(n)),
  'itemSearchProvider': (c, f) =>
      c.listen(itemSearchProvider('lamp'), (_, n) => f(n)),
  'itemDetailProvider': (c, f) =>
      c.listen(itemDetailProvider('item1'), (_, n) => f(n)),
  'searchItemsProvider': (c, f) =>
      c.listen(searchItemsProvider('lamp'), (_, n) => f(n)),
  'itemPhotosProvider': (c, f) =>
      c.listen(itemPhotosProvider('item1'), (_, n) => f(n)),
  'lowStockItemsProvider': (c, f) =>
      c.listen(lowStockItemsProvider, (_, n) => f(n)),
  'itemReceiptProvider': (c, f) =>
      c.listen(itemReceiptProvider('item1'), (_, n) => f(n)),
  'tagsProvider': (c, f) => c.listen(tagsProvider, (_, n) => f(n)),
  'itemTagsProvider': (c, f) =>
      c.listen(itemTagsProvider('item1'), (_, n) => f(n)),
  'activeLoansProvider': (c, f) =>
      c.listen(activeLoansProvider, (_, n) => f(n)),
  'itemLoansProvider': (c, f) =>
      c.listen(itemLoansProvider('item1'), (_, n) => f(n)),
  'activeLoanedItemIdsProvider': (c, f) =>
      c.listen(activeLoanedItemIdsProvider, (_, n) => f(n)),
  'propertiesProvider': (c, f) => c.listen(propertiesProvider, (_, n) => f(n)),
  'roomsProvider': (c, f) => c.listen(roomsProvider, (_, n) => f(n)),
  'allRoomsProvider': (c, f) => c.listen(allRoomsProvider, (_, n) => f(n)),
  'containersInRoomProvider': (c, f) =>
      c.listen(containersInRoomProvider('room1'), (_, n) => f(n)),
  'allContainersProvider': (c, f) =>
      c.listen(allContainersProvider, (_, n) => f(n)),
  'roomDetailProvider': (c, f) =>
      c.listen(roomDetailProvider('room1'), (_, n) => f(n)),
  'containerDetailProvider': (c, f) =>
      c.listen(containerDetailProvider('box1'), (_, n) => f(n)),
  'maintenanceLogsProvider': (c, f) =>
      c.listen(maintenanceLogsProvider, (_, n) => f(n)),
  'upcomingMaintenanceProvider': (c, f) =>
      c.listen(upcomingMaintenanceProvider, (_, n) => f(n)),
  'maintenanceByItemProvider': (c, f) =>
      c.listen(maintenanceByItemProvider('item1'), (_, n) => f(n)),
  'policiesProvider': (c, f) => c.listen(policiesProvider, (_, n) => f(n)),
};

void main() {
  ensureSqlite3();

  for (final entry in _cases.entries) {
    test('${entry.key}: a failed read is read once, not retried', () async {
      final reads = _FailingReads();
      final db = AppDatabase(NativeDatabase.memory().interceptWith(reads));
      final c = ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(db),
      ]);
      addTearDown(() async {
        c.dispose();
        await db.close();
      });

      final states = <AsyncValue<Object?>>[];
      entry.value(c, states.add);
      // The failure arrives.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(states.where((s) => s.hasError && !s.isLoading), isNotEmpty,
          reason: 'the read failed and said so: $states');
      final readsAtError = reads.reads;
      final statesAtError = states.length;
      expect(readsAtError, greaterThan(0));

      // Long enough for riverpod 3's first two retries (200 ms, 400 ms).
      await Future<void>.delayed(const Duration(milliseconds: 900));

      expect(reads.reads, readsAtError, reason: 'no second read by itself');
      expect(states.length, statesAtError,
          reason: 'no reload after the failure');
    });
  }
}
