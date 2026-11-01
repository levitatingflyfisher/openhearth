import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/result.dart';
import '../../../../core/providers/repository_providers.dart';
import '../../../tracking/presentation/controllers/timer_controller.dart';
import '../../../../services/home_widget_service.dart';

final homeWidgetControllerProvider = Provider<HomeWidgetController>((ref) {
  return HomeWidgetController(ref);
});

class HomeWidgetController {
  HomeWidgetController(this._ref);
  final Ref _ref;

  /// Redraws the home-screen widget from the database as it is now.
  ///
  /// It reads the database on every call, never a provider's cached value.
  /// Cached "last sleep" and "last diaper" reads once kept the first values
  /// they saw for the app's lifetime, and a watch stream can lag a write by a
  /// beat: the update that follows a log, or a restore, came too early for
  /// it and drew the old record.
  Future<void> triggerUpdate() async {
    final baby =
        await _ref.read(babyRepositoryProvider).watchActiveBaby().first;
    final babyId = baby?.id ?? '';

    T? found<T>(Result<T?> r) => r is Success<T?> ? r.value : null;
    final lastFeeding = found(
        await _ref.read(feedingRepositoryProvider).getLastFeeding(babyId));
    final lastSleep =
        found(await _ref.read(sleepRepositoryProvider).getLastSleep(babyId));
    final lastDiaper = found(
        await _ref.read(diaperRepositoryProvider).getLastDiaper(babyId));

    final timers = _ref.read(activeTimersProvider);
    final activeTimer = timers.isEmpty
        ? null
        : (timers.where((t) => t.type == TimerType.feeding).firstOrNull ??
           timers.where((t) => t.type == TimerType.sleep).firstOrNull ??
           timers.first);

    await HomeWidgetService.update(
      baby: baby,
      lastFeeding: lastFeeding,
      lastSleep: lastSleep,
      lastDiaper: lastDiaper,
      activeTimer: activeTimer,
    );
  }
}
