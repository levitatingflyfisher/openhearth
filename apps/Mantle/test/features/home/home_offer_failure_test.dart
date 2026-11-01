// test/features/home/home_offer_failure_test.dart
//
// If the unfinished-round check fails to read the disk, Home still opens
// with Start a round, offers no Continue, and does not read again on its
// own. On riverpod 2, `.value` on a failed read threw inside Home's build;
// on riverpod 3 it gives null, so Home stays usable. The provider carries
// no automatic retry.

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantle/core/db/database.dart';
import 'package:mantle/core/providers.dart';
import 'package:mantle/core/theme/theme_preference.dart';
import 'package:mantle/features/home/presentation/home_screen.dart';

/// Fails every read of the rounds table, as a broken disk would.
class _FailRounds extends QueryInterceptor {
  int reads = 0;

  @override
  Future<List<Map<String, Object?>>> runSelect(
      QueryExecutor executor, String statement, List<Object?> args) {
    if (statement.contains('FROM "rounds"')) {
      reads++;
      throw Exception('disk read failed');
    }
    return executor.runSelect(statement, args);
  }
}

void main() {
  testWidgets('a failed unfinished-round check leaves Home usable, read once',
      (tester) async {
    final interceptor = _FailRounds();
    final db = MantleDatabase.forTesting(
        NativeDatabase.memory().interceptWith(interceptor));
    addTearDown(db.close);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        themePreferenceProvider
            .overrideWith((_) async => ThemePreference.light),
      ],
      child: const MaterialApp(home: HomeScreen()),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }

    expect(tester.takeException(), isNull);
    expect(find.text('Start a round'), findsOneWidget);
    expect(find.byKey(const Key('home-continue-round')), findsNothing);
    expect(interceptor.reads, 1);
  });
}
