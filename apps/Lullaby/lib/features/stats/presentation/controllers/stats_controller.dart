import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/providers/repository_providers.dart';
import '../../../../core/providers/retry_policy.dart';
import '../../../../core/providers/ui_choice.dart';
import '../../domain/entities/daily_summary.dart';
import '../../domain/services/stats_aggregator.dart';

enum StatsPeriod {
  week(7, '7d'),
  twoWeeks(14, '14d'),
  month(30, '30d');

  const StatsPeriod(this.days, this.label);
  final int days;
  final String label;
}

final statsPeriodProvider = NotifierProvider<UiChoice<StatsPeriod>, StatsPeriod>(
  () => UiChoice(() => StatsPeriod.week),
);

final statsAggregatorProvider = Provider<StatsAggregator>((ref) {
  return StatsAggregator(
    feedingRepo: ref.watch(feedingRepositoryProvider),
    sleepRepo: ref.watch(sleepRepositoryProvider),
    diaperRepo: ref.watch(diaperRepositoryProvider),
  );
});

// autoDispose so the screen recomputes (fresh data + fresh "now") each time
// it's reopened, instead of serving a stale snapshot for the whole session (M9).
final dailySummariesProvider =
    FutureProvider.autoDispose.family<List<DailySummary>, String>((ref, babyId) async {
  final period = ref.watch(statsPeriodProvider);
  final aggregator = ref.watch(statsAggregatorProvider);

  final now = DateTime.now();
  return aggregator.getDailySummaries(
    babyId,
    statsPeriodStart(now, period),
    now,
  );
},
  retry: noAutoRetry,
);

/// The first instant of [period] when it ends on the day of [now].
///
/// Whole local days ending today: exactly period.days buckets, with a full
/// first day. The previous `now - days` start was mid-day, which added an
/// extra partial bucket and undercounted the first day (H4).
///
/// Stepped back by calendar day: across spring forward 24-hour steps landed
/// at 23:00 the day before (an eighth bar), and across fall back at 01:00 on
/// the right day (the first hour's feeds went missing).
DateTime statsPeriodStart(DateTime now, StatsPeriod period) =>
    now.startOfDayPlus(-(period.days - 1));

final summariesInRangeProvider = FutureProvider.autoDispose.family<
    List<DailySummary>, ({String babyId, DateTimeRange range})>(
  (ref, args) async {
    final aggregator = ref.watch(statsAggregatorProvider);
    return aggregator.getDailySummaries(
      args.babyId,
      args.range.start,
      args.range.end,
    );
  },
  retry: noAutoRetry,
);
