// metrics_service — on-device metrics ONLY (BUILD-SPEC §1.4).
//
// presence_repo records the raw counts (publishes / firstAt / lastAt per
// day); this service turns them into the "Your Porch stats" numbers and
// owns the 30-day dismissible "How's Porch working for you?" prompt.
// Nothing here touches the network, by construction: no relay import
// exists, and a test decrypts everything the relay holds to prove nothing
// metric-shaped ever left the device.
import 'porch_state.dart';

/// The user-facing stats ("Your Porch stats" in Settings).
class PorchStats {
  /// Total availability taps ever recorded on this device.
  final int totalPublishes;

  /// Days with at least one tap.
  final int daysActive;

  /// Days with MORE than one tap — the same-day re-availability proxy
  /// (§1.4): coming back for a second porch-light the same day is the
  /// on-device signal that the first one led to something.
  final int sameDayReturnDays;

  const PorchStats({
    required this.totalPublishes,
    required this.daysActive,
    required this.sameDayReturnDays,
  });

  double get sameDayReturnRate =>
      daysActive == 0 ? 0 : sameDayReturnDays / daysActive;
}

class MetricsService {
  static const promptIntervalSeconds = 30 * 86400;

  const MetricsService();

  PorchStats compute(List<MetricsDay> days) {
    var publishes = 0, returns = 0;
    for (final d in days) {
      publishes += d.publishes;
      if (d.publishes > 1) returns++;
    }
    return PorchStats(
      totalPublishes: publishes,
      daysActive: days.length,
      sameDayReturnDays: returns,
    );
  }

  /// The 30-day dismissible feedback prompt (§1.4): due 30 days after first
  /// recorded use, then 30 days after each dismissal. Never due before the
  /// user has actually used Porch.
  bool promptDue(PorchState state, int nowSec) {
    final anchor = state.feedback.lastPromptAt > 0
        ? state.feedback.lastPromptAt
        : _firstUse(state);
    if (anchor == null) return false;
    return nowSec - anchor > promptIntervalSeconds;
  }

  /// Dismiss = "asked and answered for another 30 days". Mutates [state];
  /// the caller persists.
  void dismissPrompt(PorchState state, int nowSec) {
    state.feedback.lastPromptAt = nowSec;
  }

  int? _firstUse(PorchState state) {
    int? first;
    for (final d in state.metrics) {
      if (d.firstAt > 0 && (first == null || d.firstAt < first)) {
        first = d.firstAt;
      }
    }
    return first;
  }
}
