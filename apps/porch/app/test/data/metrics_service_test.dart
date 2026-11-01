// W4: metrics_service — on-device metrics ONLY (BUILD-SPEC §1.4).
// Recording happens in presence_repo (W3); this service computes the
// user-facing stats and owns the 30-day dismissible feedback prompt.
import 'package:test/test.dart';

import 'package:porch_app/data/metrics_service.dart';
import 'package:porch_app/data/porch_state.dart';

void main() {
  const service = MetricsService();
  const day = 86400;

  group('stats computation', () {
    test('empty metrics → zeroed stats', () {
      final stats = service.compute(const []);
      expect(stats.totalPublishes, 0);
      expect(stats.daysActive, 0);
      expect(stats.sameDayReturnDays, 0);
      expect(stats.sameDayReturnRate, 0);
    });

    test('same-day re-availability = share of active days with >1 publish',
        () {
      final stats = service.compute([
        MetricsDay(date: '2026-07-01', publishes: 1, firstAt: 10, lastAt: 10),
        MetricsDay(date: '2026-07-02', publishes: 3, firstAt: 20, lastAt: 90),
        MetricsDay(date: '2026-07-04', publishes: 2, firstAt: 30, lastAt: 40),
      ]);
      expect(stats.totalPublishes, 6);
      expect(stats.daysActive, 3);
      expect(stats.sameDayReturnDays, 2);
      expect(stats.sameDayReturnRate, closeTo(2 / 3, 1e-9));
    });
  });

  group('30-day feedback prompt', () {
    test('never due before any use', () {
      final state = PorchState.initial();
      expect(service.promptDue(state, 1_700_000_000), isFalse);
    });

    test('due 30 days after first recorded use, then again 30 days after '
        'dismissal', () {
      final state = PorchState.initial();
      const first = 1_700_000_000;
      state.metrics.add(MetricsDay(
          date: '2026-07-01', publishes: 1, firstAt: first, lastAt: first));

      expect(service.promptDue(state, first + 29 * day), isFalse);
      expect(service.promptDue(state, first + 30 * day + 1), isTrue);

      final dismissedAt = first + 31 * day;
      service.dismissPrompt(state, dismissedAt);
      expect(state.feedback.lastPromptAt, dismissedAt);
      expect(service.promptDue(state, dismissedAt + day), isFalse);
      expect(service.promptDue(state, dismissedAt + 30 * day + 1), isTrue);
    });
  });
}
