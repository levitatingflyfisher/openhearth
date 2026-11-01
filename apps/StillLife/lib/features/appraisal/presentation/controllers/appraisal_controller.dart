import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:still_life/core/providers/retry_policy.dart';

import '../../../../core/providers/appraisal_providers.dart';
import '../../../inventory/domain/entities/item.dart';
import '../../domain/entities/appraisal.dart';

/// AsyncNotifier managing appraisal state for a single item+mode pair.
/// Invoked by the AppraisalCard when the user taps a mode chip.
///
/// State shape:
///   AsyncData(Appraisal?) — null when no fresh cache and no request yet.
///   AsyncLoading         — request in flight.
///   AsyncError           — parse / network / validation failure.
class AppraisalController extends AsyncNotifier<Appraisal?> {
  // Riverpod 3 drops FamilyAsyncNotifier: the family hands the key to the
  // constructor instead of build.
  AppraisalController(this.arg);

  final ({String itemId, AppraisalMode mode}) arg;

  @override
  Future<Appraisal?> build() {
    return ref
        .watch(appraisalRepositoryProvider)
        .getLatestByItemAndMode(arg.itemId, arg.mode);
  }

  /// Triggers a (cached-or-fresh) appraisal for the given item.
  Future<void> appraise(Item item, {bool forceRefresh = false}) async {
    state = const AsyncLoading();
    final svc = ref.read(appraiserServiceProvider);
    final res = await svc.appraise(item, arg.mode, forceRefresh: forceRefresh);
    res.when(
      success: (a) => state = AsyncData(a),
      failure: (f) => state = AsyncError(f, StackTrace.current),
    );
  }
}

final appraisalControllerProvider =
    AsyncNotifierProvider.family<
      AppraisalController,
      Appraisal?,
      ({String itemId, AppraisalMode mode})
    >(AppraisalController.new, name: 'appraisalControllerProvider',
  retry: noAutoRetry,
);
