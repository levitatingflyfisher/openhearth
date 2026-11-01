import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:still_life/core/providers/retry_policy.dart';

import '../../../../core/providers/database_provider.dart';
import '../../../../core/providers/stored_data_caches.dart';
import '../../../../services/database/database.dart';

/// The receipt row an item links to via `Items.receiptId`, or null when
/// the row is gone (soft-deleted or never synced to this device).
///
/// Reads the drift row directly — receipts have no domain entity; the
/// detail screen only renders what the import persisted.
final itemReceiptProvider = FutureProvider.family<Receipt?, String>((
  ref,
  receiptId,
) {
  rereadOnDatabaseWrites(ref);
  return ref.watch(databaseProvider).receiptDao.getReceipt(receiptId);
},
  retry: noAutoRetry,
);
