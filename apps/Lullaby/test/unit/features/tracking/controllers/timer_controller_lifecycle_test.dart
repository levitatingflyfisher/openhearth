// The running feed and sleep timers follow the active baby and the restored
// record, even when no screen is watching them.
//
// Two riverpod 3 traps live here:
//  - A provider that loses its last listener pauses its own ref.listen. The
//    home widget and the controllers only read the timers, so a baby switch
//    must still reach them when no screen watches.
//  - A rebuild (a restore invalidates the timers) keeps the same Notifier
//    object. A load started before the rebuild must not write the old
//    record's session into the new state.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lullaby/core/errors/result.dart';
import 'package:lullaby/core/providers/repository_providers.dart';
import 'package:lullaby/features/babies/domain/entities/baby.dart';
import 'package:lullaby/features/home_widget/presentation/controllers/home_widget_controller.dart';
import 'package:lullaby/features/settings/presentation/controllers/active_baby_controller.dart';
import 'package:lullaby/features/tracking/domain/entities/feeding_log.dart';
import 'package:lullaby/features/tracking/domain/entities/sleep_log.dart';
import 'package:lullaby/features/tracking/domain/repositories/feeding_repository.dart';
import 'package:lullaby/features/tracking/domain/repositories/sleep_repository.dart';
import 'package:lullaby/features/tracking/presentation/controllers/timer_controller.dart';

class _NoOpHomeWidgetController extends HomeWidgetController {
  _NoOpHomeWidgetController(super.ref);
  @override
  Future<void> triggerUpdate() async {}
}

/// Answers each getActiveSleep from [answers], in order; a Completer lets a
/// test hold a read in flight.
class _QueuedSleepRepo implements SleepRepository {
  _QueuedSleepRepo(this.answers);
  final List<Future<Result<SleepLogEntity?>> Function(String babyId)> answers;
  var calls = 0;

  @override
  Future<Result<SleepLogEntity?>> getActiveSleep(String babyId) {
    final i = calls < answers.length ? calls : answers.length - 1;
    calls++;
    return answers[i](babyId);
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoFeedRepo implements FeedingRepository {
  @override
  Future<Result<FeedingLogEntity?>> getActiveBreastFeeding(
          String babyId) async =>
      const Success(null);

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

BabyEntity _baby(String id) => BabyEntity(
      id: id,
      name: id,
      dateOfBirth: DateTime(2024, 1, 1),
      isActive: true,
      createdAt: DateTime(2025, 1, 1),
      modifiedAt: DateTime(2025, 1, 1),
    );

SleepLogEntity _sleep(String id, String babyId) => SleepLogEntity(
      id: id,
      babyId: babyId,
      startTime: DateTime.now().subtract(const Duration(minutes: 10)),
      type: SleepType.nap,
      createdAt: DateTime(2025, 1, 1),
      modifiedAt: DateTime(2025, 1, 1),
    );

void main() {
  test('a baby switch reaches the timers while no screen watches them',
      () async {
    final babies = StreamController<BabyEntity?>.broadcast();
    addTearDown(babies.close);
    final sleeps = _QueuedSleepRepo([
      (babyId) async =>
          Success(babyId == 'b2' ? _sleep('sleep-b2', 'b2') : null),
    ]);
    final c = ProviderContainer(overrides: [
      homeWidgetControllerProvider
          .overrideWith((ref) => _NoOpHomeWidgetController(ref)),
      activeBabyProvider.overrideWith((ref) => babies.stream),
      sleepRepositoryProvider.overrideWithValue(sleeps),
      feedingRepositoryProvider.overrideWithValue(_NoFeedRepo()),
    ]);
    addTearDown(c.dispose);

    // Read once, as the home widget and the controllers do. Nothing watches.
    expect(c.read(activeTimersProvider), isEmpty);
    await pumpEventQueue();
    babies.add(_baby('b1'));
    await pumpEventQueue();
    babies.add(_baby('b2'));
    await pumpEventQueue();

    final timers = c.read(activeTimersProvider);
    expect(timers.map((t) => t.logId), ['sleep-b2'],
        reason: 'the new baby\'s running sleep, read without a watcher');
  });

  test('a load started before a restore never writes the old session',
      () async {
    final before = Completer<Result<SleepLogEntity?>>();
    final sleeps = _QueuedSleepRepo([
      // The load started before the restore: still reading.
      (_) => before.future,
      // The restored record has no running sleep.
      (_) async => const Success(null),
    ]);
    final c = ProviderContainer(overrides: [
      homeWidgetControllerProvider
          .overrideWith((ref) => _NoOpHomeWidgetController(ref)),
      activeBabyProvider.overrideWith((ref) => Stream.value(_baby('b1'))),
      sleepRepositoryProvider.overrideWithValue(sleeps),
      feedingRepositoryProvider.overrideWithValue(_NoFeedRepo()),
    ]);
    addTearDown(c.dispose);
    c.listen(activeTimersProvider, (_, _) {});
    await pumpEventQueue();
    expect(sleeps.calls, 1, reason: 'the first load is in flight');

    // The restore hook resets the timers (stored_data_caches.dart).
    c.invalidate(activeTimersProvider);
    c.read(activeTimersProvider);
    await pumpEventQueue();
    expect(sleeps.calls, 2, reason: 'the restored record was read');
    expect(c.read(activeTimersProvider), isEmpty);

    // The old read now lands, with a sleep the restore removed.
    before.complete(Success(_sleep('sleep-old', 'b1')));
    await pumpEventQueue();

    expect(c.read(activeTimersProvider), isEmpty,
        reason: 'the old record\'s sleep must not come back as a timer');
  });
}
