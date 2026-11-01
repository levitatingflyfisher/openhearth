import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:still_life/core/providers/retry_policy.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../../core/providers/repository_providers.dart';
import '../../../../core/providers/stored_data_caches.dart';
import '../../domain/entities/maintenance_log.dart';
import '../../domain/repositories/maintenance_repository.dart';

/// Reactive list of all maintenance logs.
final maintenanceLogsProvider = StreamProvider<List<MaintenanceLog>>((ref) {
  return ref.watch(maintenanceRepositoryProvider).watchAll();
},
  retry: noAutoRetry,
);

/// Upcoming maintenance (nextDueAt in the future).
final upcomingMaintenanceProvider = FutureProvider<List<MaintenanceLog>>((
  ref,
) async {
  rereadOnDatabaseWrites(ref);
  final result = await ref.watch(maintenanceRepositoryProvider).getUpcoming();
  // A failed read says so, never as nothing due.
  return result.when(success: (v) => v, failure: (f) => throw f);
},
  retry: noAutoRetry,
);

/// Logs for a specific item.
final maintenanceByItemProvider =
    StreamProvider.family<List<MaintenanceLog>, String>((ref, itemId) {
      return ref.watch(maintenanceRepositoryProvider).watchByItem(itemId);
    },
  retry: noAutoRetry,
);

/// CRUD controller.
final maintenanceControllerProvider =
    StateNotifierProvider<MaintenanceController, AsyncValue<void>>((ref) {
      return MaintenanceController(ref.watch(maintenanceRepositoryProvider));
    });

class MaintenanceController extends StateNotifier<AsyncValue<void>> {
  final MaintenanceRepository _repo;

  MaintenanceController(this._repo) : super(const AsyncData(null));

  Future<bool> add(MaintenanceLog log) async {
    state = const AsyncLoading();
    final result = await _repo.create(log);
    return result.when(
      success: (_) {
        state = const AsyncData(null);
        return true;
      },
      failure: (f) {
        state = AsyncError(f.message, StackTrace.current);
        return false;
      },
    );
  }

  Future<bool> edit(MaintenanceLog log) async {
    state = const AsyncLoading();
    final result = await _repo.update(log);
    return result.when(
      success: (_) {
        state = const AsyncData(null);
        return true;
      },
      failure: (f) {
        state = AsyncError(f.message, StackTrace.current);
        return false;
      },
    );
  }

  Future<bool> remove(String id) async {
    state = const AsyncLoading();
    final result = await _repo.delete(id);
    return result.when(
      success: (_) {
        state = const AsyncData(null);
        return true;
      },
      failure: (f) {
        state = AsyncError(f.message, StackTrace.current);
        return false;
      },
    );
  }
}
