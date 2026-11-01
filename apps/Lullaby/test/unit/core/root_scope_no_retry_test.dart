// The app's root scope turns riverpod 3's automatic retry off for every
// provider, the shared backup packages' included: they still build against
// riverpod 2 and cannot name a retry policy of their own.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lullaby/core/providers/retry_policy.dart';

void main() {
  testWidgets('under the root scope a failed provider is built once',
      (tester) async {
    var builds = 0;
    // No retry policy of its own, as the shared packages' providers.
    final failing = FutureProvider<int>((ref) async {
      builds++;
      throw Exception('keychain locked');
    });

    await tester.pumpWidget(lullabyProviderScope(
      overrides: const [],
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) => ref.watch(failing).when(
                data: (_) => const Text('ok'),
                loading: () => const Text('loading'),
                error: (_, _) => const Text('failed'),
              ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.text('failed'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }

    expect(builds, 1);
    expect(find.text('failed'), findsOneWidget,
        reason: 'the failure stays on screen, no reload');
  });
}
