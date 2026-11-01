import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lullaby/core/errors/failures.dart';
import 'package:lullaby/core/errors/result.dart';
import 'package:lullaby/core/providers/repository_providers.dart';
import 'package:lullaby/features/babies/domain/entities/baby.dart';
import 'package:lullaby/features/babies/presentation/screens/baby_profile_screen.dart';
import 'package:lullaby/features/doctor/presentation/controllers/doctor_controller.dart';
import 'package:lullaby/features/doctor/presentation/screens/doctor_summary_screen.dart';
import 'package:lullaby/features/export/data/export_file_share.dart';
import 'package:lullaby/features/export/raw_export_controller.dart';
import 'package:lullaby/features/growth/domain/entities/growth_record.dart';
import 'package:lullaby/features/growth/domain/repositories/growth_repository.dart';
import 'package:lullaby/features/health/medicine/domain/entities/medicine_log.dart';
import 'package:lullaby/features/health/medicine/domain/repositories/medicine_repository.dart';
import 'package:lullaby/features/health/vaccine/domain/entities/vaccine_record.dart';
import 'package:lullaby/features/health/vaccine/domain/repositories/vaccine_repository.dart';
import 'package:lullaby/features/settings/presentation/controllers/active_baby_controller.dart';
import 'package:lullaby/features/stats/domain/entities/daily_summary.dart';
import 'package:lullaby/features/stats/domain/services/stats_aggregator.dart';
import 'package:lullaby/features/tracking/domain/entities/diaper_log.dart';
import 'package:lullaby/features/tracking/domain/entities/feeding_log.dart';
import 'package:lullaby/features/tracking/domain/entities/sleep_log.dart';
import 'package:lullaby/features/tracking/domain/repositories/diaper_repository.dart';
import 'package:lullaby/features/tracking/domain/repositories/feeding_repository.dart';
import 'package:lullaby/features/tracking/domain/repositories/sleep_repository.dart';

// A failed read of the baby's log is an error with Try again. It is never
// a CSV, a chart or a doctor summary with nothing in it, and an export from
// a failed read writes no file at all: a parent who opens an empty export
// reads "the log is gone", and a doctor who gets one reads "no feeds".

class _Feedings extends Mock implements FeedingRepository {}

class _Sleeps extends Mock implements SleepRepository {}

class _Diapers extends Mock implements DiaperRepository {}

class _Growth extends Mock implements GrowthRepository {}

class _Medicines extends Mock implements MedicineRepository {}

class _Vaccines extends Mock implements VaccineRepository {}

Err<T> _failed<T>() =>
    Err<T>(DatabaseFailure.from(Exception('disk read failed'), StackTrace.current));

final _baby = BabyEntity(
  id: 'baby1',
  name: 'Alice',
  dateOfBirth: DateTime(2024, 12, 1),
  isActive: true,
  createdAt: DateTime(2025, 1, 1),
  modifiedAt: DateTime(2025, 1, 1),
);

/// The six reads behind the exports. Each works until its name is in
/// [failing].
class _Repos {
  _Repos(this.failing) {
    when(() => feedings.getAllForBaby(any())).thenAnswer((_) async =>
        failing.contains('feedings')
            ? _failed()
            : const Success(<FeedingLogEntity>[]));
    when(() => sleeps.getAllForBaby(any())).thenAnswer((_) async =>
        failing.contains('sleeps')
            ? _failed()
            : const Success(<SleepLogEntity>[]));
    when(() => diapers.getAllForBaby(any())).thenAnswer((_) async =>
        failing.contains('diapers')
            ? _failed()
            : const Success(<DiaperLogEntity>[]));
    when(() => growth.getAllForBaby(any())).thenAnswer((_) async =>
        failing.contains('growth')
            ? _failed()
            : const Success(<GrowthRecordEntity>[]));
    when(() => medicines.getAllForBaby(any())).thenAnswer((_) async =>
        failing.contains('medicines')
            ? _failed()
            : const Success(<MedicineLogEntity>[]));
    when(() => vaccines.getAllForBaby(any())).thenAnswer((_) async =>
        failing.contains('vaccines')
            ? _failed()
            : const Success(<VaccineRecordEntity>[]));

    when(() => feedings.getInRange(any(), any(), any())).thenAnswer(
        (_) async => failing.contains('feedings')
            ? _failed()
            : const Success(<FeedingLogEntity>[]));
    when(() => sleeps.getInRange(any(), any(), any())).thenAnswer(
        (_) async => failing.contains('sleeps')
            ? _failed()
            : const Success(<SleepLogEntity>[]));
    when(() => diapers.getInRange(any(), any(), any())).thenAnswer(
        (_) async => failing.contains('diapers')
            ? _failed()
            : const Success(<DiaperLogEntity>[]));
    when(() => growth.getLatest(any())).thenAnswer((_) async =>
        failing.contains('growth')
            ? _failed()
            : const Success<GrowthRecordEntity?>(null));
    when(() => medicines.getInRange(any(), any(), any())).thenAnswer(
        (_) async => failing.contains('medicines')
            ? _failed()
            : const Success(<MedicineLogEntity>[]));
    when(() => vaccines.getAdministered(any())).thenAnswer((_) async =>
        failing.contains('vaccines')
            ? _failed()
            : const Success(<VaccineRecordEntity>[]));
  }

  final Set<String> failing;
  final feedings = _Feedings();
  final sleeps = _Sleeps();
  final diapers = _Diapers();
  final growth = _Growth();
  final medicines = _Medicines();
  final vaccines = _Vaccines();

  ProviderContainer container() {
    final c = ProviderContainer(overrides: [
      feedingRepositoryProvider.overrideWithValue(feedings),
      sleepRepositoryProvider.overrideWithValue(sleeps),
      diaperRepositoryProvider.overrideWithValue(diapers),
      growthRepositoryProvider.overrideWithValue(growth),
      medicineRepositoryProvider.overrideWithValue(medicines),
      vaccineRepositoryProvider.overrideWithValue(vaccines),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  StatsAggregator aggregator() => StatsAggregator(
      feedingRepo: feedings, sleepRepo: sleeps, diaperRepo: diapers);
}

void main() {
  setUpAll(() => registerFallbackValue(DateTime(2025)));

  group('the raw CSV export', () {
    for (final part in [
      'feedings',
      'sleeps',
      'diapers',
      'growth',
      'medicines',
      'vaccines'
    ]) {
      test('a failed read of the $part is an error, never a CSV without them',
          () async {
        final c = _Repos({part}).container();
        c.listen(rawExportProvider('baby1'), (_, _) {});
        await expectLater(
            c.read(rawExportProvider('baby1').future), throwsException);
      });
    }

    test('with every read working it is a CSV', () async {
      final c = _Repos({}).container();
      c.listen(rawExportProvider('baby1'), (_, _) {});
      expect(await c.read(rawExportProvider('baby1').future), isA<String>());
    });
  });

  group('the stats', () {
    for (final part in ['feedings', 'sleeps', 'diapers']) {
      test('a failed read of the $part is an error, never days of zeros',
          () async {
        await expectLater(
            _Repos({part}).aggregator().getDailySummaries(
                'baby1', DateTime(2025, 1, 1), DateTime(2025, 1, 8)),
            throwsException);
      });
    }
  });

  group('the doctor summary', () {
    for (final part in [
      'feedings',
      'growth',
      'medicines',
      'vaccines',
    ]) {
      test('a failed read of the $part is an error, never "none recorded"',
          () async {
        final c = _Repos({part}).container();
        c.listen(doctorSummaryProvider(_baby), (_, _) {});
        await expectLater(
            c.read(doctorSummaryProvider(_baby).future), throwsException);
      });
    }

    test('a failed read of the daily rows is an error, never empty rows',
        () async {
      final c = _Repos({'sleeps'}).container();
      final args = (
        babyId: 'baby1',
        range: DateTimeRange(start: DateTime(2025, 1, 1), end: DateTime(2025, 1, 7)),
      );
      c.listen(doctorDailySummariesProvider(args), (_, _) {});
      await expectLater(
          c.read(doctorDailySummariesProvider(args).future), throwsException);
    });
  });

  group('on screen, nothing is written', () {
    testWidgets(
        'Export all data from a failed read says so, writes no file, and '
        'Try again exports once the read works', (tester) async {
      final shared = <Uint8List>[];
      var failing = true;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          activeBabyProvider.overrideWith((ref) => Stream.value(_baby)),
          rawExportProvider.overrideWith((ref, babyId) async {
            if (failing) throw Exception('disk read failed');
            return 'type,started_at\nfeed,x';
          }),
          exportFileShareProvider.overrideWithValue(
            ({required bytes, required fileName, required mimeType}) async {
              shared.add(bytes);
            },
          ),
        ],
        child: const MaterialApp(home: BabyProfileScreen()),
      ));
      await tester.pump();

      await tester.tap(find.text('Export all data'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(shared, isEmpty, reason: 'no file from a failed read');
      expect(
          find.text('Couldn’t read your baby’s log, so nothing was '
              'exported.'),
          findsOneWidget);

      failing = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(shared, hasLength(1));
    });

    testWidgets(
        'Share on the doctor summary from failed daily rows says so and '
        'writes no file', (tester) async {
      final shared = <Uint8List>[];
      var failing = true;
      final now = DateTime.now();
      final summary = DoctorSummary(
        baby: _baby,
        dateRange: DateTimeRange(
            start: now.subtract(const Duration(days: 30)), end: now),
        avgFeedsPerDay: 8.5,
        avgSleepHoursPerDay: 14.2,
        avgDiapersPerDay: 6.3,
      );
      await tester.pumpWidget(ProviderScope(
        overrides: [
          activeBabyProvider.overrideWith((ref) => Stream.value(_baby)),
          doctorSummaryProvider.overrideWith((ref, b) async => summary),
          doctorDailySummariesProvider.overrideWith((ref, args) async {
            if (failing) throw Exception('disk read failed');
            return <DailySummary>[];
          }),
          exportFileShareProvider.overrideWithValue(
            ({required bytes, required fileName, required mimeType}) async {
              shared.add(bytes);
            },
          ),
        ],
        child: const MaterialApp(home: DoctorSummaryScreen()),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(shared, isEmpty, reason: 'no file from a failed read');
      expect(find.byType(BottomSheet), findsNothing);
      expect(
          find.text('Couldn’t read the daily log, so nothing was shared.'),
          findsOneWidget);

      failing = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget,
          reason: 'with the rows read, Share offers the files');
    });
  });
}
