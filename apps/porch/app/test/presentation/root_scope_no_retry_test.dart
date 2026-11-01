// The app's root scope turns riverpod 3's automatic retry off for every
// provider under it, including one that names no policy of its own.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:porch_app/presentation/app.dart';

void main() {
  testWidgets('under porchProviderScope a failing provider runs once',
      (tester) async {
    var runs = 0;
    final failing = FutureProvider<int>((ref) async {
      runs++;
      throw Exception('read failed');
    });

    await tester.pumpWidget(porchProviderScope(
      overrides: const [],
      child: Consumer(
        builder: (context, ref, _) => Text(
          ref.watch(failing).hasError ? 'failed' : 'waiting',
          textDirection: TextDirection.ltr,
        ),
      ),
    ));
    // The default policy would run it again at 200 ms, 600 ms, 1.4 s ...
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 5));

    expect(runs, 1);
    expect(find.text('failed'), findsOneWidget);
  });
}
