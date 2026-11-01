// A timer started while Home is covered (from a log screen, a notification
// or the other phone) shows on Home's timer cards when Home comes back.
//
// Riverpod 3 pauses ref.watch in a widget that is not visible. Lullaby takes
// that default: Home's cards catch up when it shows again. This test asserts
// Home's TickerMode is off while covered, so it really runs the paused case.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lullaby/core/errors/result.dart';
import 'package:lullaby/core/providers/repository_providers.dart';
import 'package:lullaby/features/babies/domain/entities/baby.dart';
import 'package:lullaby/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:lullaby/features/dashboard/presentation/widgets/active_timer_card.dart';
import 'package:lullaby/features/handoff/domain/handoff_note.dart';
import 'package:lullaby/features/handoff/presentation/handoff_card.dart';
import 'package:lullaby/features/settings/presentation/controllers/active_baby_controller.dart';
import 'package:lullaby/features/timeline/presentation/controllers/timeline_controller.dart';
import 'package:lullaby/features/tracking/domain/entities/feeding_log.dart';
import 'package:lullaby/features/tracking/domain/entities/sleep_log.dart';
import 'package:lullaby/features/tracking/domain/repositories/feeding_repository.dart';
import 'package:lullaby/features/tracking/domain/repositories/sleep_repository.dart';
import 'package:lullaby/features/tracking/presentation/controllers/diaper_controller.dart';
import 'package:lullaby/features/tracking/presentation/controllers/feeding_controller.dart';
import 'package:lullaby/features/tracking/presentation/controllers/sleep_controller.dart';
import 'package:lullaby/features/tracking/presentation/controllers/timer_controller.dart';

class _FakeSleepController extends SleepController {
  @override
  AsyncValue<void> build() => const AsyncData(null);
  @override
  Future<Duration> getTodaySleepDuration(String babyId) async => Duration.zero;
}

class _FakeDiaperController extends DiaperController {
  @override
  AsyncValue<void> build() => const AsyncData(null);
  @override
  Future<int> getTodayDiaperCount(String babyId) async => 0;
}

class _NoSleepRepo implements SleepRepository {
  @override
  Future<Result<SleepLogEntity?>> getActiveSleep(String babyId) async =>
      const Success(null);
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

void main() {
  final baby = BabyEntity(
    id: 'b1',
    name: 'Nora',
    dateOfBirth: DateTime(2025, 11, 1),
    createdAt: DateTime(2025, 11, 1),
    modifiedAt: DateTime(2025, 11, 1),
  );

  testWidgets('a timer started while Home is covered shows when Home is back',
      (tester) async {
    final router = GoRouter(
      initialLocation: '/dashboard',
      routes: [
        GoRoute(
          path: '/dashboard',
          builder: (_, _) => const DashboardScreen(),
        ),
        GoRoute(
          path: '/sleep',
          builder: (_, _) => const Scaffold(body: Text('sleep log')),
        ),
      ],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        activeBabyProvider.overrideWith((ref) => Stream.value(baby)),
        allEventsProvider.overrideWith(
            (ref, babyId) => Stream.value(const <TimelineEvent>[])),
        lastFeedingProvider.overrideWith((ref, babyId) => Stream.value(null)),
        recentHandoffNotesProvider.overrideWith(
            (ref, babyId) => Stream.value(const <HandoffNote>[])),
        sleepControllerProvider.overrideWith(() => _FakeSleepController()),
        diaperControllerProvider.overrideWith(() => _FakeDiaperController()),
        sleepRepositoryProvider.overrideWithValue(_NoSleepRepo()),
        feedingRepositoryProvider.overrideWithValue(_NoFeedRepo()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(ActiveTimerCard), findsNothing);

    router.push('/sleep');
    await tester.pumpAndSettle();
    expect(find.text('sleep log'), findsOneWidget);

    final home = tester.element(find.byType(DashboardScreen, skipOffstage: false));
    expect(TickerMode.of(home), isFalse,
        reason: 'Home is covered, so its watches are paused');

    ProviderScope.containerOf(home)
        .read(activeTimersProvider.notifier)
        .startTimer(ActiveTimer(
          id: 't1',
          type: TimerType.sleep,
          startTime: DateTime.now(),
          label: 'Nap',
          elapsed: Duration.zero,
          logId: 'sleep1',
        ));
    await tester.pump();

    router.pop();
    await tester.pumpAndSettle();

    expect(find.byType(ActiveTimerCard), findsOneWidget,
        reason: 'Home catches up with the timer started while covered');

    // Unmount, so the timer's ticker is cancelled with the provider.
    await tester.pumpWidget(const SizedBox());
  });
}
