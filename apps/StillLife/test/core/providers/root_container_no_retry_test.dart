// The app's root container turns riverpod 3's automatic retry off for every
// provider, the shared backup packages' included: they still build against
// riverpod 2 and cannot name a retry policy of their own.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:still_life/core/providers/retry_policy.dart';

void main() {
  test('under the root container a failed provider is built once', () async {
    var builds = 0;
    // No retry policy of its own, as the shared packages' providers.
    final failing = FutureProvider<int>((ref) async {
      builds++;
      throw Exception('keychain locked');
    });
    final c = stillLifeContainer();
    addTearDown(c.dispose);
    final states = <AsyncValue<int>>[];
    c.listen(failing, (_, next) => states.add(next), fireImmediately: true);

    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(states.last.hasError, isTrue);
    // Long enough for riverpod 3's first two retries (200 ms, 400 ms).
    await Future<void>.delayed(const Duration(milliseconds: 900));

    expect(builds, 1);
    expect(states.last.hasError, isTrue);
    expect(states.last.isLoading, isFalse,
        reason: 'the failure stays, no reload');
  });
}
