// A restore replaces every engine snapshot in the database, but each
// profile's mastery engine is a keepAlive provider that loaded its snapshot
// once and keeps it in memory. These tests hold the line: after the restore
// hook runs, the engine is the restored one, and the next answer builds on
// the restored progress instead of saving the old progress over it.
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatch/core/engine/engine_providers.dart';
import 'package:hatch/core/engine/engine_service.dart';
import 'package:hatch/core/providers/core_providers.dart';
import 'package:hatch/core/router/app_router.dart';
import 'package:hatch/core/storage/app_database.dart';
import 'package:hatch/features/home/presentation/home_screen.dart';
import 'package:hatch/features/profiles/domain/active_profile.dart';
import 'package:hatch/features/sanctuary_backup/backup_config.dart';
import 'package:hatch/features/sanctuary_backup/data/backup_serializer.dart';
import 'package:hatch/shared/theme/app_theme.dart';
import 'package:mastery_core/mastery_core.dart';

import '../album/engine_harness.dart';

final _refProvider = Provider<Ref>((ref) => ref);

/// Runs the hook the backup controller runs after a restore, with a real Ref.
void _runRestoreHook(ProviderContainer container) =>
    hatchBackupConfig.onAfterRestore!(container.read(_refProvider));

String _snapshotOf(EngineService service) =>
    jsonEncode(service.engine.snapshot());

Future<String?> _storedSnapshot(AppDatabase db, int profileId) async {
  final row = await (db.select(
    db.engineSnapshots,
  )..where((t) => t.profileId.equals(profileId))).getSingleOrNull();
  return row?.json;
}

/// The first event of a fresh piecing round, answered correctly on [at].
AnswerEvent _oneAnswer(EngineService service, DateTime at) {
  final spec = withClock(
    Clock.fixed(at),
    () => service.assembleRound(RoundIntent.piecing),
  ).events.first;
  return AnswerEvent(
    fact: spec.fact,
    direction: spec.direction,
    kind: spec.kind,
    rung: spec.rung,
    correct: true,
    latencyMs: 900,
    production: true,
    at: at,
  );
}

void main() {
  test('after a restore the engine holds the restored progress, not the '
      'progress from before', () async {
    final (container, id) = await makeContainerWithProfile();
    final db = container.read(appDatabaseProvider);

    final service = await driveEngine(container, id, days: 2);
    final backedUp = _snapshotOf(service);
    final backup = await HatchBackupSerializer(db).dumpAll();

    // More play after the backup: the in-memory engine moves on.
    await driveEngine(container, id, days: 4);
    expect(_snapshotOf(service), isNot(backedUp));

    await HatchBackupSerializer(db).restoreAll(backup);
    _runRestoreHook(container);

    final after = await container.read(engineServiceProvider(id).future);
    expect(_snapshotOf(after), backedUp);
  });

  test('the next answer after a restore builds on the restored snapshot and '
      'does not save the old progress over it', () async {
    final (container, id) = await makeContainerWithProfile();
    final db = container.read(appDatabaseProvider);

    final service = await driveEngine(container, id, days: 2);
    final backedUp = _snapshotOf(service);
    final backup = await HatchBackupSerializer(db).dumpAll();
    await driveEngine(container, id, days: 4);

    await HatchBackupSerializer(db).restoreAll(backup);
    _runRestoreHook(container);

    final at = kDriveStart.add(const Duration(days: 9));
    final after = await container.read(engineServiceProvider(id).future);
    final answer = _oneAnswer(after, at);
    await withClock(Clock.fixed(at), () => after.record(answer));

    // What the restored progress plus this one answer must look like.
    final expected = MasteryEngine.fromSnapshot(
      jsonDecode(backedUp) as Map<String, Object?>,
    )..record(answer);
    expect(await _storedSnapshot(db, id), jsonEncode(expected.snapshot()));
  });

  testWidgets('Home, which stays open under Settings, shows the restored '
      'hatcher at once', (tester) async {
    final (container, id) = await makeContainerWithProfile();
    final db = container.read(appDatabaseProvider);
    await container.read(activeProfileProvider.notifier).select(id);

    // The backup is from before she played: nothing started yet.
    final backup = await HatchBackupSerializer(db).dumpAll();
    await driveEngine(container, id, days: 2);

    final router = container.read(appRouterProvider);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    router.go('/home');
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('build & hatch'), findsOneWidget);

    await tester.runAsync(() => HatchBackupSerializer(db).restoreAll(backup));
    _runRestoreHook(container);
    await tester.runAsync(
      () => container.read(engineServiceProvider(id).future),
    );
    await tester.pumpAndSettle();

    expect(find.text('start here — an egg is waiting'), findsOneWidget);
  });
}
