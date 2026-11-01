// test/core/root_scope_no_retry_test.dart
//
// The app's root scope turns riverpod 3's automatic retry off for every
// provider under it, including the shared backup packages' providers, which
// cannot name a policy of their own. A provider with no policy of its own
// fails once and stays failed until someone asks again.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantle/app/root_overrides.dart';

void main() {
  testWidgets('a provider without its own policy is read once under the root',
      (tester) async {
    var reads = 0;
    // Like a shared package's provider: no retry policy of its own.
    final keychain = FutureProvider.autoDispose<String>((ref) async {
      reads++;
      throw Exception('keychain locked');
    });

    await tester.pumpWidget(mantleProviderScope(
      overrides: const [],
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) => Text(
            ref.watch(keychain).hasError ? 'failed' : 'waiting',
          ),
        ),
      ),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }

    expect(find.text('failed'), findsOneWidget);
    expect(reads, 1);
  });
}
