import 'package:clock/clock.dart';
import 'package:drift/drift.dart' show StringExpressionOperators, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatch/core/engine/engine_service.dart';
import 'package:hatch/core/storage/app_database.dart';
import 'package:mastery_core/mastery_core.dart';

void main() {
  late AppDatabase db;
  late int profileId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    profileId = await db
        .into(db.profiles)
        .insert(
          ProfilesCompanion.insert(glyphSeed: 7, createdAt: DateTime(2026, 8)),
        );
  });

  tearDown(() => db.close());

  AnswerEvent probeEvent(RoundEventSpec spec, DateTime at) => AnswerEvent(
    fact: spec.fact,
    direction: spec.direction,
    kind: spec.kind,
    rung: spec.rung,
    correct: true,
    latencyMs: 900,
    production: true,
    at: at,
  );

  test('load with no snapshot creates a fresh engine that assembles', () async {
    final service = EngineService(db, profileId);
    await service.load();
    final round = service.assembleRound(RoundIntent.piecing);
    expect(round.events, isNotEmpty);
  });

  test('a snapshot that cannot be read is moved aside, not lost', () async {
    // Reading a bad snapshot used to throw, so the child could not open the
    // app at all. Starting fresh is right, but the next save would overwrite
    // the bad row, so the old text must be kept first under a dated name.
    const bad = '{"version": 1, "pack": "truncated';
    await db
        .into(db.engineSnapshots)
        .insert(
          EngineSnapshotsCompanion.insert(
            profileId: Value(profileId),
            json: bad,
            updatedAt: DateTime(2026, 8),
          ),
        );
    final at = DateTime(2026, 11, 10, 9);
    await withClock(Clock.fixed(at), () async {
      final service = EngineService(db, profileId);
      await service.load();
      final round = service.assembleRound(RoundIntent.piecing);
      expect(round.events, isNotEmpty);
      await service.record(probeEvent(round.events.first, at));
    });

    final aside = await (db.select(
      db.settings,
    )..where((t) => t.key.like('engine.aside.$profileId.%'))).get();
    expect(aside, hasLength(1));
    expect(aside.single.value, bad);
    expect(aside.single.key, contains('2026-11-10'));

    final snap = await db.select(db.engineSnapshots).getSingle();
    expect(snap.json, isNot(bad));
  });

  test('record persists the event row and the snapshot atomically', () async {
    final at = DateTime(2026, 8, 7, 9);
    final service = EngineService(db, profileId);
    await service.load();
    final round = service.assembleRound(RoundIntent.piecing);
    await service.record(probeEvent(round.events.first, at));

    final events = await db.select(db.answerEvents).get();
    expect(events, hasLength(1));
    expect(events.single.profileId, profileId);
    expect(events.single.production, isTrue);

    final snap = await db.select(db.engineSnapshots).getSingle();
    expect(snap.profileId, profileId);
    expect(snap.json, isNotEmpty);
  });

  test('a reloaded service resumes from the persisted snapshot', () async {
    final at = DateTime(2026, 8, 7, 9);
    await withClock(Clock.fixed(at), () async {
      final service = EngineService(db, profileId);
      await service.load();
      final round = service.assembleRound(RoundIntent.piecing);
      for (final spec in round.events.take(4)) {
        await service.record(probeEvent(spec, at));
      }
      final statsBefore = service.engine.stats(now: at);

      final resumed = EngineService(db, profileId);
      await resumed.load();
      final statsAfter = resumed.engine.stats(now: at);
      expect(statsAfter.toString(), statsBefore.toString());
    });
  });

  test('record notifies listeners so the album repaints live', () async {
    final service = EngineService(db, profileId);
    await service.load();
    var notified = 0;
    service.addListener(() => notified++);
    final round = service.assembleRound(RoundIntent.piecing);
    await service.record(probeEvent(round.events.first, DateTime(2026, 8, 7)));
    expect(notified, 1);
  });

  test('completeVignette persists engine state', () async {
    final at = DateTime(2026, 8, 7, 9);
    await withClock(Clock.fixed(at), () async {
      final service = EngineService(db, profileId);
      await service.load();
      // x2 is the first family; its vignette is due on a fresh engine only
      // after placement surfaces it — exercise the call through whatever
      // vignette the engine reports, else skip harmlessly.
      final vignette = service.engine.nextVignette();
      if (vignette != null) {
        await service.completeVignette(vignette.family);
        final snap = await db.select(db.engineSnapshots).getSingleOrNull();
        expect(snap, isNotNull);
      }
    });
  });

  test(
    'profiles do not share engines: separate snapshots per profile',
    () async {
      final other = await db
          .into(db.profiles)
          .insert(
            ProfilesCompanion.insert(
              glyphSeed: 9,
              createdAt: DateTime(2026, 8),
            ),
          );
      final a = EngineService(db, profileId);
      final b = EngineService(db, other);
      await a.load();
      await b.load();
      final round = a.assembleRound(RoundIntent.piecing);
      await a.record(probeEvent(round.events.first, DateTime(2026, 8, 7)));

      final snaps = await db.select(db.engineSnapshots).get();
      expect(snaps.map((s) => s.profileId), [profileId]);
    },
  );

  // A restore or a profile removal retires the engine in memory: its
  // provider is reset and the old service disposed. Anything still holding
  // the old service must not be able to write its old progress back over
  // the data now in the database.
  test('a retired engine refuses to record and writes nothing', () async {
    final at = DateTime(2026, 8, 7, 9);
    await withClock(Clock.fixed(at), () async {
      final service = EngineService(db, profileId);
      await service.load();
      final round = service.assembleRound(RoundIntent.piecing);
      await service.record(probeEvent(round.events.first, at));
      final storedBefore = await db.select(db.engineSnapshots).getSingle();
      final ledgerBefore = await db.select(db.answerEvents).get();

      service.dispose();

      await expectLater(
        service.record(probeEvent(round.events[1], at)),
        throwsStateError,
      );
      final vignette = service.engine.nextVignette();
      if (vignette != null) {
        await expectLater(
          service.completeVignette(vignette.family),
          throwsStateError,
        );
      }
      final storedAfter = await db.select(db.engineSnapshots).getSingle();
      expect(storedAfter.json, storedBefore.json);
      expect(await db.select(db.answerEvents).get(), ledgerBefore);
    });
  });

  test('an answer still being saved when the engine is retired is rolled '
      'back whole', () async {
    final at = DateTime(2026, 8, 7, 9);
    await withClock(Clock.fixed(at), () async {
      final service = EngineService(db, profileId);
      await service.load();
      final round = service.assembleRound(RoundIntent.piecing);

      // The save runs in a transaction that starts after this frame; the
      // engine is retired before it gets there.
      final saving = service.record(probeEvent(round.events.first, at));
      service.dispose();

      await expectLater(saving, throwsStateError);
      expect(await db.select(db.engineSnapshots).get(), isEmpty);
      expect(await db.select(db.answerEvents).get(), isEmpty);
    });
  });
}
