// A failed read of the phone's own log is read once and stays failed until
// someone taps Try again. It never reloads by itself in a loop: a loop puts a
// spinner where the error belongs and reads the disk again and again.
//
// Riverpod 3 retries a failed provider by default (up to 10 times). Lullaby
// turns that off, at the root and on every async provider. Each test here
// fails a provider through its real dependency with an Exception (riverpod
// retries an Exception, never an Error), then waits 5 s on the fake clock and
// checks that no second read and no new state came.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lullaby/core/errors/result.dart';
import 'package:lullaby/core/providers/repository_providers.dart';
import 'package:lullaby/features/babies/domain/entities/baby.dart';
import 'package:lullaby/features/babies/domain/repositories/baby_repository.dart';
import 'package:lullaby/features/babies/presentation/controllers/baby_controller.dart';
import 'package:lullaby/features/calendar/presentation/controllers/calendar_controller.dart';
import 'package:lullaby/features/doctor/presentation/controllers/doctor_controller.dart';
import 'package:lullaby/features/export/raw_export_controller.dart';
import 'package:lullaby/features/growth/domain/repositories/growth_repository.dart';
import 'package:lullaby/features/growth/presentation/controllers/growth_controller.dart';
import 'package:lullaby/features/handoff/domain/handoff_repository.dart';
import 'package:lullaby/features/handoff/presentation/handoff_card.dart';
import 'package:lullaby/features/health/medicine/domain/repositories/medicine_repository.dart';
import 'package:lullaby/features/health/medicine/presentation/controllers/medicine_controller.dart';
import 'package:lullaby/features/health/vaccine/domain/repositories/vaccine_repository.dart';
import 'package:lullaby/features/health/vaccine/presentation/controllers/vaccine_controller.dart';
import 'package:lullaby/features/settings/presentation/controllers/active_baby_controller.dart';
import 'package:lullaby/features/stats/presentation/controllers/stats_controller.dart';
import 'package:lullaby/features/timeline/presentation/controllers/timeline_controller.dart';
import 'package:lullaby/features/tracking/domain/entities/diaper_log.dart';
import 'package:lullaby/features/tracking/domain/entities/sleep_log.dart';
import 'package:lullaby/features/tracking/domain/repositories/diaper_repository.dart';
import 'package:lullaby/features/tracking/domain/repositories/feeding_repository.dart';
import 'package:lullaby/features/tracking/domain/repositories/sleep_repository.dart';
import 'package:lullaby/features/tracking/presentation/controllers/diaper_controller.dart';
import 'package:lullaby/features/tracking/presentation/controllers/feeding_controller.dart';
import 'package:lullaby/features/tracking/presentation/controllers/sleep_controller.dart';

class _Babies extends Mock implements BabyRepository {}

class _Feedings extends Mock implements FeedingRepository {}

class _Sleeps extends Mock implements SleepRepository {}

class _Diapers extends Mock implements DiaperRepository {}

class _Growth extends Mock implements GrowthRepository {}

class _Medicine extends Mock implements MedicineRepository {}

class _Vaccine extends Mock implements VaccineRepository {}

class _Handoff extends Mock implements HandoffRepository {}

final _baby = BabyEntity(
  id: 'baby1',
  name: 'Alice',
  dateOfBirth: DateTime(2024, 12, 1),
  isActive: true,
  createdAt: DateTime(2025, 1, 1),
  modifiedAt: DateTime(2025, 1, 1),
);

final _range = DateTimeRange(start: DateTime(2025, 1), end: DateTime(2025, 2));

/// Every read of the log fails with an Exception and is counted. With
/// [babiesWork] the baby reads succeed, so a provider that needs the active
/// baby gets as far as the log.
class _FailingDisk {
  _FailingDisk({bool babiesWork = false}) {
    Exception fail() {
      reads++;
      return Exception('disk read failed');
    }

    Stream<T> failStream<T>() => Stream<T>.error(fail());
    Future<T> failFuture<T>() => Future<T>.error(fail());

    if (babiesWork) {
      when(babies.watchActiveBaby).thenAnswer((_) => Stream.value(_baby));
      when(babies.watchAllBabies).thenAnswer((_) => Stream.value([_baby]));
    } else {
      when(babies.watchActiveBaby).thenAnswer((_) => failStream());
      when(babies.watchAllBabies).thenAnswer((_) => failStream());
    }

    when(() => feedings.watchAllForBaby(any())).thenAnswer((_) => failStream());
    when(() => feedings.watchLastFeeding(any()))
        .thenAnswer((_) => failStream());
    when(() => feedings.getAllForBaby(any())).thenAnswer((_) => failFuture());
    when(() => feedings.getInRange(any(), any(), any()))
        .thenAnswer((_) => failFuture());

    when(() => sleeps.watchAllForBaby(any())).thenAnswer((_) => failStream());
    when(() => sleeps.watchActiveSleep(any())).thenAnswer((_) => failStream());
    when(() => sleeps.getAllForBaby(any())).thenAnswer((_) => failFuture());
    // The stats read three ranges at once; the feeds failing is enough, and
    // a second failure would go unhandled.
    when(() => sleeps.getInRange(any(), any(), any()))
        .thenAnswer((_) async => const Success(<SleepLogEntity>[]));

    when(() => diapers.watchAllForBaby(any())).thenAnswer((_) => failStream());
    when(() => diapers.getAllForBaby(any())).thenAnswer((_) => failFuture());
    when(() => diapers.getInRange(any(), any(), any()))
        .thenAnswer((_) async => const Success(<DiaperLogEntity>[]));

    when(() => growth.watchAllForBaby(any())).thenAnswer((_) => failStream());
    when(() => growth.watchLatest(any())).thenAnswer((_) => failStream());
    when(() => growth.getAllForBaby(any())).thenAnswer((_) => failFuture());
    when(() => growth.getLatest(any())).thenAnswer((_) => failFuture());

    when(() => medicine.watchAllForBaby(any())).thenAnswer((_) => failStream());
    when(() => medicine.getAllForBaby(any())).thenAnswer((_) => failFuture());
    when(() => medicine.getInRange(any(), any(), any()))
        .thenAnswer((_) => failFuture());

    when(() => vaccine.watchAllForBaby(any())).thenAnswer((_) => failStream());
    when(() => vaccine.getAllForBaby(any())).thenAnswer((_) => failFuture());
    when(() => vaccine.getAdministered(any())).thenAnswer((_) => failFuture());

    when(() => handoff.watchRecent(any(), limit: any(named: 'limit')))
        .thenAnswer((_) => failStream());
  }

  int reads = 0;
  final babies = _Babies();
  final feedings = _Feedings();
  final sleeps = _Sleeps();
  final diapers = _Diapers();
  final growth = _Growth();
  final medicine = _Medicine();
  final vaccine = _Vaccine();
  final handoff = _Handoff();

  ProviderContainer container() => ProviderContainer(overrides: [
        babyRepositoryProvider.overrideWithValue(babies),
        feedingRepositoryProvider.overrideWithValue(feedings),
        sleepRepositoryProvider.overrideWithValue(sleeps),
        diaperRepositoryProvider.overrideWithValue(diapers),
        growthRepositoryProvider.overrideWithValue(growth),
        medicineRepositoryProvider.overrideWithValue(medicine),
        vaccineRepositoryProvider.overrideWithValue(vaccine),
        handoffRepositoryProvider.overrideWithValue(handoff),
      ]);
}

/// Listens to one provider and reports each new state. A closure, so the
/// test never names a riverpod listenable type (they moved between majors).
typedef _Listen = void Function(
    ProviderContainer c, void Function(AsyncValue<Object?> next) onChange);

final Map<String, _Listen> _cases = {
  'babyListProvider': (c, f) => c.listen(babyListProvider, (_, n) => f(n)),
  'activeBabyProvider': (c, f) => c.listen(activeBabyProvider, (_, n) => f(n)),
  'growthRecordsProvider': (c, f) =>
      c.listen(growthRecordsProvider('baby1'), (_, n) => f(n)),
  'latestGrowthProvider': (c, f) =>
      c.listen(latestGrowthProvider('baby1'), (_, n) => f(n)),
  'recentHandoffNotesProvider': (c, f) =>
      c.listen(recentHandoffNotesProvider('baby1'), (_, n) => f(n)),
  'medicineLogsProvider': (c, f) =>
      c.listen(medicineLogsProvider('baby1'), (_, n) => f(n)),
  'vaccineRecordsProvider': (c, f) =>
      c.listen(vaccineRecordsProvider('baby1'), (_, n) => f(n)),
  'timelineProvider': (c, f) => c.listen(timelineProvider('baby1'), (_, n) => f(n)),
  'allEventsProvider': (c, f) => c.listen(allEventsProvider('baby1'), (_, n) => f(n)),
  'recentDiapersProvider': (c, f) =>
      c.listen(recentDiapersProvider('baby1'), (_, n) => f(n)),
  'activeSleepProvider': (c, f) => c.listen(activeSleepProvider('baby1'), (_, n) => f(n)),
  'recentFeedingsProvider': (c, f) =>
      c.listen(recentFeedingsProvider('baby1'), (_, n) => f(n)),
  'lastFeedingProvider': (c, f) => c.listen(lastFeedingProvider('baby1'), (_, n) => f(n)),
  'dayDetailProvider': (c, f) => c.listen(dayDetailProvider((babyId: 'baby1', day: DateTime(2025, 1, 3))), (_, n) => f(n)),
  'rawExportProvider': (c, f) => c.listen(rawExportProvider('baby1'), (_, n) => f(n)),
  'doctorSummaryProvider': (c, f) =>
      c.listen(doctorSummaryProvider(_baby), (_, n) => f(n)),
  'doctorDailySummariesProvider': (c, f) => c.listen(doctorDailySummariesProvider((babyId: 'baby1', range: _range)), (_, n) => f(n)),
  'dailySummariesProvider': (c, f) =>
      c.listen(dailySummariesProvider('baby1'), (_, n) => f(n)),
  'summariesInRangeProvider': (c, f) => c.listen(summariesInRangeProvider((babyId: 'baby1', range: _range)), (_, n) => f(n)),
};

/// Fails once, then waits [settle] on the fake clock: one read, no new state.
Future<void> _expectOneFailedRead(
  WidgetTester tester,
  _FailingDisk disk,
  void Function(ProviderContainer c, void Function(AsyncValue<Object?>) f)
      listen,
) async {
  final c = disk.container();
  addTearDown(c.dispose);
  final states = <AsyncValue<Object?>>[];
  listen(c, states.add);
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
  expect(states.where((s) => s.hasError && !s.isLoading), isNotEmpty,
      reason: 'the read failed and said so: $states');
  final readsAtError = disk.reads;
  final statesAtError = states.length;
  expect(readsAtError, greaterThan(0));

  await tester.pump(const Duration(seconds: 5));
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 500));
  }

  expect(disk.reads, readsAtError, reason: 'no second read by itself');
  expect(states.length, statesAtError, reason: 'no reload after the failure');
}

void main() {
  setUpAll(() => registerFallbackValue(DateTime(2025)));

  for (final entry in _cases.entries) {
    testWidgets('${entry.key}: a failed read is read once, not retried',
        (tester) async {
      await _expectOneFailedRead(tester, _FailingDisk(), entry.value);
    });
  }

  // Needs the active baby to reach the log.
  testWidgets('calendarEventsProvider: a failed read is read once, not retried',
      (tester) async {
    await _expectOneFailedRead(
      tester,
      _FailingDisk(babiesWork: true),
      (c, f) => c.listen(calendarEventsProvider((start: _range.start, end: _range.end)), (_, n) => f(n)),
    );
  });

  // The calendar's own active-baby stream is private. A failed baby read
  // leaves the month with no baby; the stream itself must be read once.
  testWidgets('the calendar\'s active-baby stream is read once when it fails',
      (tester) async {
    final disk = _FailingDisk();
    final c = disk.container();
    addTearDown(c.dispose);
    c.listen(calendarEventsProvider((start: _range.start, end: _range.end)),
        (_, _) {});
    for (var i = 0; i < 10; i++) {
      await tester.pump();
    }
    expect(disk.reads, 1);
    await tester.pump(const Duration(seconds: 5));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(disk.reads, 1, reason: 'no second read by itself');
  });
}
