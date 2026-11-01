import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilt/core/providers/database_provider.dart';
import 'package:lilt/core/providers/repository_providers.dart';
import 'package:lilt/domain/repositories/names_repository.dart';
import 'package:lilt/services/database/database.dart';
import 'package:lilt/domain/models/ranking.dart';
import 'package:lilt/domain/repositories/session_repository.dart';
import 'package:lilt/features/results/solo_results_screen.dart';

import '../../navigation/nav_harness.dart';

/// The methodology view told people to "see the top names in each cluster",
/// but the screen lists no clusters. The text must promise only what the
/// screen shows.
class _TwoDimensionRepo extends SessionRepository {
  _TwoDimensionRepo(AppDatabase db, NamesRepository names)
    : super(db.sessionDao, db.eloMatchesDao, names);

  @override
  Future<Methodology> methodology(String sessionId) async => const Methodology(
    kendallTau: 0.95,
    rankability: 1.0,
    preferenceDimensions: 2,
    cycleStrength: 0.0,
    disagreements: [],
  );
}

void main() {
  late NavHarness h;
  setUp(
    () async => h = await NavHarness.create(
      extraOverrides: [
        sessionRepositoryProvider.overrideWith((ref) {
          final db = ref.watch(databaseProvider);
          return _TwoDimensionRepo(db, ref.watch(namesRepositoryProvider));
        }),
      ],
    ),
  );
  tearDown(() async => h.dispose());

  testWidgets('two-dimensions note does not promise clusters', (tester) async {
    final id = (await tester.runAsync(() => h.rankedSession()))!;
    final container = h.container;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: SoloResultsScreen(sessionId: id)),
      ),
    );
    await NavHarness.settle(tester);

    final toggle = find.byType(Switch);
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await NavHarness.settle(tester);

    final heading = find.text('Two Dimensions Detected');
    await tester.ensureVisible(heading);
    expect(heading, findsOneWidget);
    expect(
      find.textContaining('cluster'),
      findsNothing,
      reason: 'the screen lists no clusters',
    );
    expect(find.textContaining('two distinct dimensions'), findsOneWidget);
  });
}
