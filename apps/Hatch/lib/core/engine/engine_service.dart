import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:mastery_core/mastery_core.dart';

import '../storage/app_database.dart';

/// The seam between mastery_core and the app: one engine per profile, fed
/// AnswerEvents, persisted as (append-only ledger row + snapshot upsert) in a
/// single transaction so a kill mid-answer can never split them. The engine
/// stays pure — every 'now' here flows through package:clock so tests can
/// freeze the calendar (the spacing clock is calendar days, engine law 2).
class EngineService extends ChangeNotifier {
  EngineService(this._db, this.profileId);

  final AppDatabase _db;
  final int profileId;

  late MasteryEngine _engine;
  var _loaded = false;

  /// Set when the provider lets this service go (a restore or a profile
  /// removal resets it, see `stored_data_caches.dart`). From then on the
  /// database holds data this engine never saw, so it must never write: its
  /// snapshot would replace the restored progress.
  var _retired = false;

  @override
  void dispose() {
    _retired = true;
    super.dispose();
  }

  void _refuseIfRetired() {
    if (_retired) {
      throw StateError(
        'EngineService for profile $profileId was retired; its progress is '
        'out of date and must not be saved',
      );
    }
  }

  /// Direct engine access for read-only queries (samplerView, stats,
  /// familyStatus, nextVignette, pendingRequeues). Mutations must go through
  /// [record] / [completeVignette] or they will not be persisted.
  MasteryEngine get engine {
    assert(_loaded, 'EngineService.load() must complete before use');
    return _engine;
  }

  Future<void> load() async {
    final row = await (_db.select(
      _db.engineSnapshots,
    )..where((t) => t.profileId.equals(profileId))).getSingleOrNull();
    if (row == null) {
      _engine = MasteryEngine.fresh(now: clock.now());
    } else {
      try {
        _engine = MasteryEngine.fromSnapshot(
          jsonDecode(row.json) as Map<String, Object?>,
        );
      } on FormatException {
        _engine = await _startFreshKeeping(row.json);
      } on TypeError {
        _engine = await _startFreshKeeping(row.json);
      } on ArgumentError {
        // `byName` on an unknown enum value in a snapshot from another build.
        _engine = await _startFreshKeeping(row.json);
      }
    }
    _loaded = true;
  }

  /// A snapshot that cannot be read must not lock the child out, and the next
  /// save would overwrite it. So the old text is kept in the settings table
  /// (it rides in the backup) under a dated name, and play starts fresh.
  Future<MasteryEngine> _startFreshKeeping(String unreadable) async {
    final now = clock.now();
    await _db
        .into(_db.settings)
        .insertOnConflictUpdate(
          SettingsCompanion.insert(
            key: 'engine.aside.$profileId.${now.toUtc().toIso8601String()}',
            value: unreadable,
          ),
        );
    return MasteryEngine.fresh(now: now);
  }

  RoundSpec assembleRound(RoundIntent intent) =>
      engine.assembleRound(intent, now: clock.now());

  SamplerView samplerView() => engine.samplerView(now: clock.now());

  EngineStats stats() => engine.stats(now: clock.now());

  Future<RecordResult> record(AnswerEvent event) async {
    _refuseIfRetired();
    final result = engine.record(event);
    await _db.transaction(() async {
      await _db
          .into(_db.answerEvents)
          .insert(
            AnswerEventsCompanion.insert(
              profileId: profileId,
              factA: event.fact.a,
              factB: event.fact.b,
              direction: event.direction.index,
              kind: event.kind.index,
              rung: event.rung.index,
              correct: event.correct,
              latencyMs: Value(event.latencyMs),
              production: event.production,
              at: event.at,
            ),
          );
      await _persistSnapshot();
    });
    // Retired between the write and here: no one may listen any more.
    if (!_retired) notifyListeners();
    return result;
  }

  Future<void> completeVignette(Family family) async {
    _refuseIfRetired();
    engine.markVignetteComplete(family, now: clock.now());
    await _persistSnapshot();
    if (!_retired) notifyListeners();
  }

  /// Checks again at the moment of writing: a save queued behind a restore
  /// runs after it, and throwing here rolls back the whole answer.
  Future<void> _persistSnapshot() async {
    _refuseIfRetired();
    await _db
        .into(_db.engineSnapshots)
        .insertOnConflictUpdate(
          EngineSnapshotsCompanion.insert(
            profileId: Value(profileId),
            json: jsonEncode(engine.snapshot()),
            updatedAt: clock.now(),
          ),
        );
  }
}
