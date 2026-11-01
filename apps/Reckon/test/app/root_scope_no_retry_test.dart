import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reckon/app/root_overrides.dart';

/// The root scope decides for providers that name no retry policy of their
/// own: the shared backup packages' providers, and any new one. Under
/// [reckonProviderScope] such a provider fails once and is not read again.
void main() {
  testWidgets('a provider with no policy of its own is read once under the '
      'root scope', (tester) async {
    var reads = 0;
    final failing = FutureProvider<int>((ref) async {
      reads++;
      throw Exception('keychain is locked');
    });

    await tester.pumpWidget(reckonProviderScope(
      overrides: const [],
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Consumer(
          builder: (context, ref, _) => Text(ref.watch(failing).when(
                data: (_) => 'data',
                error: (_, _) => 'error',
                loading: () => 'loading',
              )),
        ),
      ),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }

    expect(find.text('error'), findsOneWidget);
    expect(reads, 1);
  });
}
