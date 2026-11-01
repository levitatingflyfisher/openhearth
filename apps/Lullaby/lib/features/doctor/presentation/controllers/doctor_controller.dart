import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/result.dart';
import '../../../../core/providers/repository_providers.dart';
import '../../../../core/providers/retry_policy.dart';
import '../../../../core/providers/ui_choice.dart';
import '../../../growth/domain/entities/growth_record.dart';
import '../../../growth/domain/growth_percentiles.dart';
import '../../../babies/domain/entities/baby.dart';
import '../../../health/medicine/domain/entities/medicine_log.dart';
import '../../../health/vaccine/domain/entities/vaccine_record.dart';
import '../../../stats/domain/entities/daily_summary.dart';
import '../../../stats/presentation/controllers/stats_controller.dart';

final doctorDateRangeProvider =
    NotifierProvider<UiChoice<DateTimeRange>, DateTimeRange>(
        () => UiChoice(() {
    // Whole days, as the date picker returns them. A start at the current
    // time of day would drop the morning of the first day and understate the
    // averages.
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return DateTimeRange(
      start: DateTime(today.year, today.month, today.day - 30),
      end: today,
    );
  }),
);

class DoctorSummary {
  const DoctorSummary({
    required this.baby,
    required this.dateRange,
    required this.avgFeedsPerDay,
    required this.avgSleepHoursPerDay,
    required this.avgDiapersPerDay,
    this.latestGrowth,
    this.weightPercentile,
    this.heightPercentile,
    this.headPercentile,
    this.growthOutsideWhoRange = false,
    this.percentilesNeedRecordedSex = false,
    this.recentMedicines = const [],
    this.administeredVaccines = const [],
  });

  final BabyEntity baby;
  final DateTimeRange dateRange;
  final double avgFeedsPerDay;
  final double avgSleepHoursPerDay;
  final double avgDiapersPerDay;
  final GrowthRecordEntity? latestGrowth;
  final double? weightPercentile;
  final double? heightPercentile;
  final double? headPercentile;

  /// True when the latest measurement was taken outside the 0–24 month window
  /// the WHO tables cover — the percentiles above are null because no honest
  /// figure exists, and the UI should say so rather than stay silent.
  final bool growthOutsideWhoRange;

  /// True when the latest measurement is inside the WHO window but the baby
  /// has no recorded sex — the only thing standing between the user and a
  /// percentile. Distinct from [growthOutsideWhoRange] so the UI can name
  /// the actual blocker.
  final bool percentilesNeedRecordedSex;
  final List<MedicineLogEntity> recentMedicines;
  final List<VaccineRecordEntity> administeredVaccines;
}

// autoDispose so reopening the summary recomputes with current data (M9).
final doctorSummaryProvider =
    FutureProvider.autoDispose.family<DoctorSummary?, BabyEntity>((ref, baby) async {
  final range = ref.watch(doctorDateRangeProvider);
  final aggregator = ref.watch(statsAggregatorProvider);
  final growthRepo = ref.watch(growthRepositoryProvider);
  final medicineRepo = ref.watch(medicineRepositoryProvider);
  final vaccineRepo = ref.watch(vaccineRepositoryProvider);

  // showDateRangePicker returns the last selected day at 00:00, which the
  // aggregator treats as an exclusive bound — advance to the next midnight so
  // the final day is actually included in the averages (H5).
  final rangeEnd = doctorRangeExclusiveEnd(range);
  final averages = await aggregator.getAverages(
    baby.id,
    range.start,
    rangeEnd,
  );

  // A failed read is thrown, never "No growth measurements recorded", "No
  // medications" or "No vaccines recorded": the screen says the read failed.
  final latestGrowth = (await growthRepo.getLatest(baby.id)).orThrow();

  final now = DateTime.now();
  final thirtyDaysAgo = now.subtract(const Duration(days: 30));
  final recentMedicines =
      (await medicineRepo.getInRange(baby.id, thirtyDaysAgo, now)).orThrow();

  final administeredVaccines =
      (await vaccineRepo.getAdministered(baby.id)).orThrow();

  final percentiles = latestGrowth == null
      ? const GrowthPercentiles()
      : GrowthPercentiles.of(latestGrowth, baby);

  return DoctorSummary(
    baby: baby,
    dateRange: range,
    avgFeedsPerDay: averages.avgFeeds,
    avgSleepHoursPerDay: averages.avgSleepHours,
    avgDiapersPerDay: averages.avgDiapers,
    latestGrowth: latestGrowth,
    weightPercentile: percentiles.weight,
    heightPercentile: percentiles.height,
    headPercentile: percentiles.head,
    growthOutsideWhoRange: percentiles.outsideWhoRange,
    percentilesNeedRecordedSex: percentiles.needsRecordedSex,
    recentMedicines: recentMedicines,
    administeredVaccines: administeredVaccines,
  );
},
  retry: noAutoRetry,
);

/// The picker returns the last selected day at 00:00 and the aggregator treats
/// its end as exclusive, so the next midnight is what includes that day. The
/// header averages and the export rows must both use this one bound.
DateTime doctorRangeExclusiveEnd(DateTimeRange range) =>
    DateTime(range.end.year, range.end.month, range.end.day + 1);

/// The per-day rows behind the doctor export (CSV and PDF).
final doctorDailySummariesProvider = FutureProvider.autoDispose.family<
    List<DailySummary>, ({String babyId, DateTimeRange range})>(
  (ref, args) async {
    final aggregator = ref.watch(statsAggregatorProvider);
    return aggregator.getDailySummaries(
        args.babyId, args.range.start, doctorRangeExclusiveEnd(args.range));
  },
  retry: noAutoRetry,
);
