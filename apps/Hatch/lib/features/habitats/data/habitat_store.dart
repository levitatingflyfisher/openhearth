import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/storage/app_database.dart';
import '../domain/habitat_layout.dart';

/// Persists each profile's habitat as one JSON value in the Settings table
/// (key `habitat.<profileId>`). The Settings table rides in the OHBK backup,
/// so the arrangement she made travels with the household's data — a shelf
/// worth keeping is a shelf worth backing up.
class HabitatStore {
  HabitatStore(this._db);

  final AppDatabase _db;

  static String keyFor(int profileId) => 'habitat.$profileId';

  Future<HabitatLayout> load(int profileId) async {
    final row = await _row(profileId);
    if (row == null) return const HabitatLayout();
    // A corrupt value degrades to an empty meadow, silently: the habitat
    // is decoration and must never turn into an error screen.
    return _decode(row.value) ?? const HabitatLayout();
  }

  Future<Setting?> _row(int profileId) => (_db.select(
    _db.settings,
  )..where((t) => t.key.equals(keyFor(profileId)))).getSingleOrNull();

  static HabitatLayout? _decode(String value) {
    try {
      return HabitatLayout.fromJson(jsonDecode(value) as Map<String, Object?>);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<void> save(int profileId, HabitatLayout layout) async {
    // Load shows a corrupt value as an empty meadow, and this save would
    // overwrite it for good. Keep the old text aside under a dated name first.
    final old = await _row(profileId);
    if (old != null && _decode(old.value) == null) {
      await _db
          .into(_db.settings)
          .insertOnConflictUpdate(
            SettingsCompanion.insert(
              key:
                  'habitat.aside.$profileId.'
                  '${clock.now().toUtc().toIso8601String()}',
              value: old.value,
            ),
          );
    }
    await _db
        .into(_db.settings)
        .insertOnConflictUpdate(
          SettingsCompanion.insert(
            key: keyFor(profileId),
            value: jsonEncode(layout.toJson()),
          ),
        );
  }
}

final habitatStoreProvider = Provider<HabitatStore>(
  (ref) => HabitatStore(ref.watch(appDatabaseProvider)),
);
