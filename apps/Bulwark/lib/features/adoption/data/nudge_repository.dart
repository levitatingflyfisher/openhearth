import 'package:drift/drift.dart';

import 'package:bulwark/core/storage/app_database.dart';

/// Remembers, per habit, when the "you've been forgetting this one" offer was
/// answered (a new moment chosen, or "Not now"), so answers from before then
/// don't bring the offer straight back. Kept in the shell key→value table and
/// not in the export or the backup. The answers are the household's data, so
/// [AppDatabase.eraseUserData] clears them: on "Erase all data" and on a
/// restore, which carries none.
class NudgeRepository {
  NudgeRepository(this._db);
  final AppDatabase _db;

  static const _prefix = forgotNudgeKeyPrefix;

  Future<Map<String, DateTime>> forgotAcks() async {
    final rows = await (_db.select(_db.userPrefs)
          ..where((t) => t.key.like('$_prefix%')))
        .get();
    return {
      for (final r in rows)
        r.key.substring(_prefix.length): ?DateTime.tryParse(r.value),
    };
  }

  Future<void> ackForgot(String interventionId, DateTime at) =>
      _db.into(_db.userPrefs).insertOnConflictUpdate(UserPrefsCompanion.insert(
          key: '$_prefix$interventionId', value: at.toIso8601String()));
}
