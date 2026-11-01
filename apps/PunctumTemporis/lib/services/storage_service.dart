import 'dart:convert';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:home_widget/home_widget.dart';
import 'package:media_scanner/media_scanner.dart';
import 'package:openhearth_design/openhearth_design.dart'
    show OhThemeModePreference;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/clip.dart';
import '../platform/file_storage.dart';
import 'face_crop.dart';
import '../utils/date_arithmetic.dart';
import '../utils/person_name.dart';
import '../utils/date_format_util.dart';

class StorageService {
  final SharedPreferences _prefs;

  String _clipsDir = '';
  String _thumbnailsDir = '';
  String _compiledDir = '';
  String _appDocDir = '';
  late String _facesDir;
  late String _metadataPath;

  final _uuid = const Uuid();

  Map<String, List<Clip>> _clips = {};
  List<Compilation> _compilations = [];

  StorageService(this._prefs, {DateTime Function()? clock})
      : _now = clock ?? DateTime.now;

  /// The time now; a fixed clock in tests.
  final DateTime Function() _now;

  /// How many calendar days a deleted item waits, after its delete or its
  /// owner's last Keep, before the app asks once whether to delete it for
  /// good. Nothing is destroyed when the days run out (owner rulings,
  /// board-0124 and board-0138).
  static const deletedKeepDays = 30;

  static const _themeKey = 'theme_mode';
  static const _accentKey = 'accent_color';
  static const _crtKey = 'crt_effects';
  static const _dateFormatKey = 'date_format';
  static const _captureLocationKey = 'capture_location';
  static const _includeLocationOverlayKey = 'include_location_overlay';
  static const _clipsMigratedKey = 'clips_migrated_v2';
  static const _visualStyleKey = 'visual_style';
  static const _includeMontagesInBackupKey = 'backup_include_montages';
  static const _pinnedTagsKey = 'pinned_tags';
  static const _pinnedLocationsKey = 'pinned_locations';

  /// The metadata.json key for clips and montages waiting on Undo or a
  /// confirmed delete.
  /// Device-local: backups leave it out and restores keep the device's own.
  static const pendingDeleteKey = 'pendingDelete';

  /// True after a [initialize] with `readOnly`: the move page build, which
  /// reads the journal at the old web address and must write nothing there.
  bool _readOnly = false;

  /// Initialize storage directories. With [readOnly] it only reads: no
  /// folders are made, no migration runs, and a file it cannot read stays
  /// where it is, with no notice recorded.
  Future<void> initialize({bool readOnly = false}) async {
    _readOnly = readOnly;
    final appDoc = await FileStorage.appDocDir();
    _appDocDir = appDoc;

    _clipsDir = '$appDoc/clips';
    _thumbnailsDir = '$appDoc/thumbnails';
    _facesDir = '$appDoc/faces';
    _metadataPath = '$appDoc/metadata.json';

    // Compilations: public Movies dir on Android, app doc fallback (or web)
    final externalBase = await FileStorage.externalStorageDir();
    if (externalBase != null) {
      final basePath = externalBase.split('Android')[0];
      _compiledDir = '${basePath}Movies/OneSecondADay/compilations';
    } else {
      _compiledDir = '$appDoc/compiled';
    }

    if (!readOnly) {
      await FileStorage.ensureDir(_clipsDir);
      await FileStorage.ensureDir(_thumbnailsDir);
      await FileStorage.ensureDir(_compiledDir);
    }

    await _loadMetadata();
    // With the journal unread, a move would mark clips migrated that the
    // empty index never named.
    if (readFailed || readOnly) return;
    await _migrateClipsToPrivate();
  }

  /// One-time migration: move clips from old public dir to app-private dir
  Future<void> _migrateClipsToPrivate() async {
    if (kIsWeb) return; // Migration is Android-only
    if (_prefs.getBool(_clipsMigratedKey) == true) return;

    final externalBase = await FileStorage.externalStorageDir();
    if (externalBase == null) {
      await _prefs.setBool(_clipsMigratedKey, true);
      return;
    }

    final basePath = externalBase.split('Android')[0];
    final oldClipsDir = '${basePath}Movies/OneSecondADay/clips';
    if (!await FileStorage.dirExists(oldClipsDir)) {
      await _prefs.setBool(_clipsMigratedKey, true);
      return;
    }

    bool migrated = false;
    for (final date in _clips.keys.toList()) {
      final clipList = _clips[date]!;
      for (var i = 0; i < clipList.length; i++) {
        final clip = clipList[i];
        if (clip.filePath.startsWith(oldClipsDir)) {
          if (await FileStorage.exists(clip.filePath)) {
            final newPath = '$_clipsDir/${clip.filePath.split('/').last}';
            await FileStorage.copyFile(clip.filePath, newPath);
            await FileStorage.deleteFile(clip.filePath);
            clipList[i] = clip.copyWith(filePath: newPath);
            migrated = true;
          }
        }
      }
    }

    if (migrated) await _saveMetadata();
    await _prefs.setBool(_clipsMigratedKey, true);
  }

  /// True while an unreadable metadata.json still sits at the live path
  /// because setting it aside failed. A save must not replace it until the
  /// set-aside has worked.
  bool _setAsidePending = false;

  /// Set when metadata.json is there but reading it failed: an I/O error,
  /// which says nothing about the file. The file stays where it is, nothing
  /// is set aside, and every save refuses until a read works, because the
  /// journal in memory is empty. The app shows the read error with Try
  /// again ([retryRead]).
  Object? _readError;
  StackTrace? _readErrorStack;

  /// True while the journal could not be read (see [readError]).
  bool get readFailed => _readError != null;

  /// What the last read of metadata.json threw, or null when it worked.
  /// For the Details of the read-error screen, never shown by default.
  Object? get readError => _readError;
  StackTrace? get readErrorStack => _readErrorStack;

  /// Try again after a failed read: reads metadata.json again, finishes
  /// the start-up steps the failed read skipped, and moves [changes].
  Future<void> retryRead() async {
    await initialize();
    if (!readFailed) await keepOldPendingFiles();
    _changed();
  }

  Future<void> _loadMetadata() async {
    _setAsidePending = false;
    _readError = null;
    _readErrorStack = null;
    _pending = [];
    _undatedRows = false;
    // The read and the parse are apart on purpose. A read that fails says
    // nothing about the file, so it stays where it is and the app says so.
    // Only a file that was read and will not parse is set aside.
    final Uint8List? bytes;
    try {
      if (!await FileStorage.exists(_metadataPath)) return;
      bytes = await FileStorage.readBytes(_metadataPath);
    } catch (e, st) {
      debugPrint('metadata.json could not be read (${e.runtimeType}); '
          'keeping it where it is.');
      _clips = {};
      _compilations = [];
      _knownPeople = {};
      _readError = e;
      _readErrorStack = st;
      return;
    }
    if (bytes == null) return;
    {
      // One row this build cannot read must not cost the whole journal.
      var badRows = 0;
      T? readRow<T>(Object? row, T Function(Map<String, dynamic>) parse) {
        try {
          return parse(row as Map<String, dynamic>);
        } catch (_) {
          badRows++;
          return null;
        }
      }

      try {
        // Bytes that are not UTF-8 were read; they are a corrupt file.
        final content = utf8.decode(bytes);
        final data = jsonDecode(content) as Map<String, dynamic>;

        if (data['clips'] != null) {
          final clipsData = data['clips'] as Map<String, dynamic>;
          _clips = {};
          for (final entry in clipsData.entries) {
            final value = entry.value;
            final rows = value is List ? value : (value is Map ? [value] : null);
            if (rows == null) {
              badRows++;
              continue;
            }
            final good = rows
                .map((e) => readRow(e, Clip.fromJson))
                .whereType<Clip>()
                .toList();
            // A day whose rows were all bad must not show as a captured day.
            if (good.isNotEmpty) _clips[entry.key] = good;
          }
        }

        if (data['compilations'] != null) {
          _compilations = (data['compilations'] as List)
              .map((e) => readRow(e, Compilation.fromJson))
              .whereType<Compilation>()
              .toList();
        }

        // Clips and montages waiting on Undo or a confirmed delete. A row
        // whose clip or montage is also live (a restore brought it back) is
        // live, not pending, so "Delete for good" can never reach it.
        final pendingData = data[pendingDeleteKey];
        if (pendingData is List) {
          final live = {
            for (final list in _clips.values)
              for (final c in list) c.id,
            for (final c in _compilations) c.id,
          };
          final loadedAt = _now();
          for (final row in pendingData) {
            final removal = readRow(row, (json) {
              final r = Removal.fromJson(json, loadedAt);
              if (json['deletedAt'] == null) _undatedRows = true;
              return r;
            });
            if (removal == null) continue;
            if (live.contains(removal.id)) continue;
            if (_pending.any((r) => r.id == removal.id)) continue;
            _pending.add(removal);
          }
        }

        if (data['knownPeople'] != null) {
          final peopleData = data['knownPeople'] as Map<String, dynamic>;
          _knownPeople = peopleData.map((name, embeddings) => MapEntry(
                name,
                (embeddings as List)
                    .map((e) =>
                        (e as List).map((v) => (v as num).toDouble()).toList())
                    .toList(),
              ));
        }
      } catch (e) {
        // The type only: a parse error's message quotes the file, which
        // holds place names and tags, and this goes to the device log.
        debugPrint('metadata.json is unreadable (${e.runtimeType}); '
            'setting it aside and starting empty.');
        _clips = {};
        _compilations = [];
        _knownPeople = {};
        if (!_readOnly) await _setAsideMetadata(keepLiveFile: false);
        return;
      }

      if (badRows > 0) {
        debugPrint('metadata.json has $badRows unreadable rows; '
            'keeping the rest and setting a copy of the original aside.');
        // A copy, and no rewrite here: the live file changes only when the
        // next save would have replaced it anyway. A start that finds the
        // same bytes it already copied makes no second copy and no second
        // notice.
        if (!_readOnly && !await _alreadyCopied(bytes)) {
          await _setAsideMetadata(keepLiveFile: true);
        }
      }
    }
  }

  /// Where the last copy of a file with bad rows went (prefs key).
  static const _partialCopyKey = 'metadata_partial_copy';

  /// Whether the copy made for a file with bad rows still holds [bytes].
  Future<bool> _alreadyCopied(Uint8List bytes) async {
    final copy = _prefs.getString(_partialCopyKey);
    if (copy == null) return false;
    try {
      final old = await FileStorage.readBytes(copy);
      return old != null && listEquals(old, bytes);
    } catch (_) {
      return false;
    }
  }

  /// Prefs key for the set-aside the family has not been told about yet.
  static const _setAsideNoticeKey = 'metadata_set_aside_notice';

  /// The plain notice for the last set-aside of metadata.json. It stays
  /// recorded until the family taps Dismiss ([dismissSetAsideNotice]), so
  /// an app closed at once tells again at the next start. Null when
  /// nothing was set aside since the last Dismiss.
  String? get setAsideNotice {
    final row = _prefs.getStringList(_setAsideNoticeKey);
    if (row == null || row.length != 2) return null;
    final name = row[1];
    return row[0] == 'part'
        ? 'Part of your journal file couldn’t be read. A copy was kept as '
            '$name beside it. Nothing was deleted.'
        : 'Your journal file couldn’t be read. It was kept as $name '
            'beside the new one. Nothing was deleted.';
  }

  /// The family dismissed [shown]: it is cleared, so it is told once per
  /// set-aside. A newer notice recorded since [shown] was drawn stays.
  Future<void> dismissSetAsideNotice(String shown) async {
    if (setAsideNotice != shown) return;
    await _prefs.remove(_setAsideNoticeKey);
  }

  /// Keeps the bytes of metadata.json under a dated name beside it, so a
  /// file the app cannot read is never lost to the next save. Moves it, or
  /// copies it when the live file must stay until its replacement lands.
  /// Returns whether the old bytes are safe; never throws, because a broken
  /// journal index must not stop the app from opening. On success it
  /// records the notice the app shows the family once.
  Future<bool> _setAsideMetadata({required bool keepLiveFile}) async {
    try {
      final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      String named(String suffix) => _metadataPath.replaceFirst(
          RegExp(r'\.json$'), '.unreadable-$stamp$suffix.json');
      // A rename silently replaces its target, so never reuse a name.
      var aside = named('');
      for (var n = 1; await FileStorage.exists(aside); n++) {
        aside = named('-$n');
      }
      if (keepLiveFile) {
        await FileStorage.copyFile(_metadataPath, aside);
      } else {
        await FileStorage.moveFile(_metadataPath, aside);
      }
      if (!await FileStorage.exists(aside)) {
        throw StateError('The set-aside copy did not appear.');
      }
      final name = aside.split('/').last;
      debugPrint('Set metadata.json aside as $name. '
          'Backup & Restore > Previous snapshots can bring back an index.');
      _setAsidePending = false;
      try {
        await _prefs.setStringList(
            _setAsideNoticeKey, [keepLiveFile ? 'part' : 'whole', name]);
        if (keepLiveFile) await _prefs.setString(_partialCopyKey, aside);
      } catch (e) {
        // The file is safe either way; only the notice is lost.
        debugPrint('Set-aside notice not recorded: ${e.runtimeType}');
      }
      return true;
    } catch (e) {
      debugPrint('Setting metadata.json aside failed: ${e.runtimeType}');
      _setAsidePending = true;
      return false;
    }
  }

  Future<void> _saveMetadata() async {
    if (_readError != null) {
      // The journal in memory is empty because the read failed, not because
      // the file is. Writing it would replace the whole journal.
      throw StateError('metadata.json could not be read, so it was not '
          'overwritten.');
    }
    if (_setAsidePending) {
      if (await FileStorage.exists(_metadataPath) &&
          !await _setAsideMetadata(keepLiveFile: false)) {
        // Same path as a failed write: the caller already handles a save
        // that throws, and the unreadable file stays whole.
        throw StateError('metadata.json could not be set aside, so it was '
            'not overwritten.');
      }
      _setAsidePending = false;
    }
    final data = {
      'clips': _clips.map(
          (key, value) => MapEntry(key, value.map((c) => c.toJson()).toList())),
      'compilations': _compilations.map((e) => e.toJson()).toList(),
      'knownPeople': _knownPeople,
      if (_pending.isNotEmpty)
        pendingDeleteKey: _pending.map((r) => r.toJson()).toList(),
    };
    await FileStorage.writeString(_metadataPath, jsonEncode(data));
  }

  String get clipsPath => _clipsDir;
  String get thumbnailsPath => _thumbnailsDir;
  String get compiledPath => _compiledDir;

  String generateId() => _uuid.v4();

  String getClipPath(String clipId) => '$_clipsDir/$clipId.mp4';
  String getThumbnailPath(String clipId) => '$_thumbnailsDir/$clipId.jpg';

  /// Generate compilation path using date range + timestamp for unique filenames
  String getCompilationPath(String startDate, String endDate) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return '$_compiledDir/${startDate}_to_${endDate}_$timestamp.mp4';
  }

  Map<String, List<Clip>> get clips => Map.unmodifiable(_clips);

  List<Clip> getClipsForDate(String date) => _clips[date] ?? [];

  Clip? getFirstClipForDate(String date) {
    final list = _clips[date];
    return (list != null && list.isNotEmpty) ? list.first : null;
  }

  int clipCountForDate(String date) => _clips[date]?.length ?? 0;

  bool hasClipForDate(String date) => _clips.containsKey(date);

  Future<void> addClip(Clip clip) async {
    _clips.putIfAbsent(clip.date, () => []);
    _clips[clip.date]!.add(clip);
    await _saveMetadata();
    _updateWidget();
  }

  void _updateWidget() {
    if (kIsWeb) return;
    // Fire-and-forget by design — but the plugin calls return futures, so a
    // channel failure surfaces ASYNCHRONOUSLY and sails past a plain
    // try/catch as an unhandled error. Each future needs its own handler.
    try {
      final streak = getCurrentStreak();
      final today = DateFormatUtil.format(DateTime.now(), DateFormatOption.isoDate);
      final capturedToday = _clips.containsKey(today);
      HomeWidget.saveWidgetData<int>('streak', streak).catchError((_) => null);
      HomeWidget.saveWidgetData<bool>('captured_today', capturedToday)
          .catchError((_) => null);
      HomeWidget.updateWidget(
        name: 'OneSecondWidget',
        qualifiedAndroidName: 'com.openhearth.punctumtemporis.OneSecondWidget',
      ).catchError((_) => null);
    } catch (_) {}
  }

  Future<void> updateClip(Clip clip) async {
    final list = _clips[clip.date];
    if (list != null) {
      final index = list.indexWhere((c) => c.id == clip.id);
      if (index >= 0) {
        list[index] = clip;
        await _saveMetadata();
      }
    }
  }

  // ── Soft delete ─────────────────────────────────────────────────────────
  //
  // A deliberate delete does not ask; it happens at once and offers an Undo
  // that never times out (fleet delete ruling).
  //
  // A clip cannot be made again, so a removed clip is never destroyed
  // without its owner's confirm (owner ruling, board-0124), and a montage
  // gets the same protection (owner ruling, board-0138). removeClip and
  // removeCompilation move the row into the "pendingDelete" list of
  // metadata.json, in the same atomic write that takes it off the calendar
  // or the montage list, and leave its files. It stays there across a kill
  // and any number of starts, until a restore (Undo) or deleteForGood
  // (after the confirm). Nothing else destroys it: not a timer, not a
  // start, not a dismissed offer.

  /// Where a build before the rulings listed the files of removals still
  /// on screen, to destroy them at the next start.
  static const _pendingRemovalsKey = 'pending_removal_files';

  /// Clips and montages removed and waiting on Undo or a confirmed delete,
  /// oldest removal first. Kept in metadata.json, not in prefs, so the row
  /// and the move off the calendar land in one atomic write.
  List<Removal> _pending = [];

  /// True when a pending row loaded without a delete time.
  bool _undatedRows = false;

  List<ClipRemoval> get pendingClipRemovals =>
      List.unmodifiable(_pending.whereType<ClipRemoval>());

  /// Everything deleted and still kept: clips, montages and old set-aside
  /// files, oldest delete first.
  List<Removal> get recentlyDeleted => List.unmodifiable(_pending);

  List<CompilationRemoval> get pendingCompilationRemovals =>
      List.unmodifiable(_pending.whereType<CompilationRemoval>());

  /// Notified whenever clips or montages change underneath a screen that
  /// did not make the change (an Undo from the app-wide bar, a removal).
  final ValueNotifier<int> changes = ValueNotifier<int>(0);

  void _changed() => changes.value++;

  /// Moved only by [reload]: a restore or a rollback replaced the journal
  /// and the settings on disk, so every copy of them held in memory outside
  /// this service is old. The app's reset listens here
  /// (`_OneSecondAppState._forgetCachedData` in main.dart), and so does
  /// Settings, which sits under Backup & Restore.
  final ValueNotifier<int> reloads = ValueNotifier<int>(0);

  /// The one reset path after a restore or a rollback. Re-reads
  /// metadata.json, then tells [reloads] (copies of settings, the app-wide
  /// Undo) and [changes] (the calendar and the day view, which sit under
  /// Settings and would otherwise draw the old journal).
  ///
  /// It destroys nothing: the device's pending deletes were written back
  /// by the restore and load again here.
  Future<void> reload() async {
    await initialize();
    reloads.value++;
    _changed();
  }

  List<String> _pendingFiles() =>
      _prefs.getStringList(_pendingRemovalsKey) ?? const [];

  static List<String> _clipFiles(Clip c) =>
      [c.filePath, if (c.thumbnailPath != null) c.thumbnailPath!];

  /// Takes the clip off the calendar and keeps it, row and files, as a
  /// pending delete. Returns null when no clip has [clipId].
  Future<ClipRemoval?> removeClip(String clipId) async {
    for (final date in _clips.keys.toList()) {
      final list = _clips[date]!;
      final index = list.indexWhere((c) => c.id == clipId);
      if (index < 0) continue;
      final clip = list.removeAt(index);
      if (list.isEmpty) _clips.remove(date);
      final removal = ClipRemoval(clip, index, deletedAt: _now());
      _pending.add(removal);
      await _saveMetadata();
      _updateWidget();
      _changed();
      return removal;
    }
    return null;
  }

  /// Puts a removed clip back where it was in its day (a day's first clip is
  /// its thumbnail on the calendar, so the position matters).
  Future<void> restoreClip(ClipRemoval removal) async {
    final id = removal.clip.id;
    _pending.removeWhere((r) => r.id == id);
    final list = _clips.putIfAbsent(removal.clip.date, () => []);
    if (!list.any((c) => c.id == id)) {
      list.insert(removal.index.clamp(0, list.length), removal.clip);
    }
    await _saveMetadata();
    _updateWidget();
    _changed();
  }

  /// Destroys a pending clip's or montage's files and forgets it. Call this
  /// only after the owner confirmed "Delete for good". A file that a live
  /// clip or montage, or another pending row, still names is never touched.
  Future<void> deleteForGood(Removal removal) async {
    final id = removal.id;
    final pending = _pending.where((r) => r.id == id).firstOrNull;
    if (pending == null) return;
    final keep = <String>{
      for (final list in _clips.values)
        for (final c in list) ..._clipFiles(c),
      for (final c in _compilations) c.filePath,
      for (final r in _pending)
        if (r.id != id) ...r.files,
    };
    for (final path in pending.files) {
      if (keep.contains(path)) continue;
      await FileStorage.deleteFile(path);
    }
    _pending.removeWhere((r) => r.id == id);
    await _saveMetadata();
    _changed();
  }

  /// Takes a montage off the list and keeps it, row and file, as a pending
  /// delete. Returns null when no montage has [id].
  Future<CompilationRemoval?> removeCompilation(String id) async {
    final index = _compilations.indexWhere((c) => c.id == id);
    if (index < 0) return null;
    final compilation = _compilations.removeAt(index);
    final removal =
        CompilationRemoval(compilation, index, deletedAt: _now());
    _pending.add(removal);
    await _saveMetadata();
    _changed();
    return removal;
  }

  /// Puts a removed montage back where it was in the list.
  Future<void> restoreCompilation(CompilationRemoval removal) async {
    final id = removal.compilation.id;
    _pending.removeWhere((r) => r.id == id);
    if (!_compilations.any((c) => c.id == id)) {
      _compilations.insert(
          removal.index.clamp(0, _compilations.length), removal.compilation);
    }
    await _saveMetadata();
    _changed();
  }

  /// Old set-aside files: clip and montage files a build before the
  /// rulings listed for purge, whose rows that build had already dropped.
  List<SetAsideFiles> get setAsideFiles =>
      List.unmodifiable(_pending.whereType<SetAsideFiles>());

  /// Turns the files a build before the rulings listed for purge into
  /// entries its owner can see and choose for, and destroys none of them
  /// (owner rulings, board-0124 and board-0138). A clip's video and its
  /// picture share a name, so they make one entry. A file that is gone,
  /// that a live or pending row names, or that lies outside the app's
  /// media folders makes none; it is left where it is.
  Future<void> keepOldPendingFiles() async {
    // A pending row written before rows carried a delete time was dated
    // when it loaded; write that down, so its 30 days count from now and
    // not from every start.
    if (_undatedRows) {
      await _saveMetadata();
      _undatedRows = false;
    }
    final listed = _pendingFiles();
    if (listed.isEmpty) return;
    final named = <String>{
      for (final list in _clips.values)
        for (final c in list) ..._clipFiles(c),
      for (final r in _pending) ...r.files,
      for (final c in _compilations) c.filePath,
    };
    final clipDirs = [_clipsDir, _thumbnailsDir];
    final montageDirs = [_compiledDir, '$_appDocDir/compiled'];
    bool inside(String path, List<String> dirs) => dirs.any((d) {
          if (!path.startsWith('$d/')) return false;
          final rest = path.substring(d.length + 1);
          return rest.isNotEmpty && !rest.contains('/') && rest != '..';
        });
    final groups = <String, SetAsideFiles>{};
    for (final path in listed) {
      if (named.contains(path)) continue;
      final clip = inside(path, clipDirs);
      if (!clip && !inside(path, montageDirs)) continue;
      if (!await FileStorage.exists(path)) continue;
      final base = path.split('/').last;
      final dot = base.lastIndexOf('.');
      final stem = dot > 0 ? base.substring(0, dot) : base;
      final id = '${clip ? 'clip' : 'montage'}-file:$stem';
      final group = groups[id];
      groups[id] = SetAsideFiles(
        id: id,
        files: [...?group?.files, path],
        isMontage: !clip,
        // When this build first saw it: the old delete time is not known.
        deletedAt: group?.deletedAt ?? _now(),
      );
    }
    for (final entry in groups.values) {
      if (_pending.any((r) => r.id == entry.id)) continue;
      _pending.add(entry);
    }
    // The entries land in metadata.json before the old list goes, so a
    // kill between the two loses nothing.
    if (groups.isNotEmpty) await _saveMetadata();
    await _prefs.remove(_pendingRemovalsKey);
    if (groups.isNotEmpty) _changed();
  }

  /// Pending items more than [deletedKeepDays] calendar days past their
  /// delete or their last Keep. Calendar days in local time, so a clock
  /// change between the two dates cannot move the answer.
  List<Removal> get oldRemovals {
    final today = _now();
    return [
      for (final r in _pending)
        if (daysBetweenDates(r.waitingSince.toLocal(), today) > deletedKeepDays)
          r,
    ];
  }

  /// The owner chose Keep: [items] stay, files and entries, and are asked
  /// about again [deletedKeepDays] days from now.
  Future<void> keepForNow(Iterable<Removal> items) async {
    final ids = {for (final r in items) r.id};
    if (ids.isEmpty) return;
    final at = _now();
    _pending = [
      for (final r in _pending) ids.contains(r.id) ? r.withKeep(at) : r,
    ];
    await _saveMetadata();
    _changed();
  }

  /// Destroys [items] after one confirm that named them all, as
  /// [deleteForGood] does for one.
  Future<void> deleteForGoodAll(Iterable<Removal> items) async {
    for (final r in items.toList()) {
      await deleteForGood(r);
    }
  }

  /// Set once the 30-day question has been asked in this run, so it is
  /// asked at most once per start.
  bool oldRemovalsAsked = false;

  List<Clip> getClipsInRange(String startDate, String endDate) {
    return _clips.entries
        .where((e) =>
            e.key.compareTo(startDate) >= 0 && e.key.compareTo(endDate) <= 0)
        .expand((e) => e.value)
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  List<Clip> getClipsForMonth(int year, int month) {
    final monthStr = month.toString().padLeft(2, '0');
    final prefix = '$year-$monthStr';
    return _clips.entries
        .where((e) => e.key.startsWith(prefix))
        .expand((e) => e.value)
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  Set<String> get datesWithClips => _clips.keys.toSet();

  Set<String> get allTags {
    final tags = <String>{};
    for (final list in _clips.values) {
      for (final clip in list) {
        tags.addAll(clip.tags);
      }
    }
    return tags;
  }

  Set<String> get allLocations {
    final locations = <String>{};
    for (final list in _clips.values) {
      for (final clip in list) {
        if (clip.locationLabel != null && clip.locationLabel!.isNotEmpty) {
          locations.add(clip.locationLabel!);
        }
      }
    }
    return locations;
  }

  Set<String> get pinnedTags =>
      Set.unmodifiable(_prefs.getStringList(_pinnedTagsKey)?.toSet() ?? {});

  Set<String> get pinnedLocations =>
      Set.unmodifiable(_prefs.getStringList(_pinnedLocationsKey)?.toSet() ?? {});

  Set<String> get allTagsWithPinned => {...allTags, ...pinnedTags};
  Set<String> get allLocationsWithPinned => {...allLocations, ...pinnedLocations};

  Future<void> pinTag(String tag) async =>
      await _prefs.setStringList(_pinnedTagsKey, [...pinnedTags, tag]);

  Future<void> unpinTag(String tag) async => await _prefs.setStringList(
      _pinnedTagsKey, pinnedTags.where((t) => t != tag).toList());

  Future<void> pinLocation(String location) async =>
      await _prefs.setStringList(_pinnedLocationsKey, [...pinnedLocations, location]);

  Future<void> unpinLocation(String location) async => await _prefs.setStringList(
      _pinnedLocationsKey, pinnedLocations.where((l) => l != location).toList());

  List<Clip> getClipsInRangeFiltered(
    String startDate,
    String endDate, {
    Set<String> tagFilter = const {},
    Set<String> locationFilter = const {},
    Set<int> weekdayFilter = const {},
  }) {
    var clips = _clips.entries
        .where((e) =>
            e.key.compareTo(startDate) >= 0 && e.key.compareTo(endDate) <= 0)
        .expand((e) => e.value);

    if (tagFilter.isNotEmpty) {
      clips = clips.where((c) => c.tags.any((t) => tagFilter.contains(t)));
    }
    if (locationFilter.isNotEmpty) {
      clips = clips.where((c) =>
          c.locationLabel != null && locationFilter.contains(c.locationLabel));
    }
    if (weekdayFilter.isNotEmpty) {
      clips = clips.where((c) {
        final date = DateTime.parse(c.date);
        return weekdayFilter.contains(date.weekday);
      });
    }

    return clips.toList()..sort((a, b) => a.date.compareTo(b.date));
  }

  List<Compilation> get compilations => List.unmodifiable(_compilations);

  Future<void> addCompilation(Compilation compilation) async {
    _compilations.add(compilation);
    await _saveMetadata();
    // Gallery refresh is a courtesy on top of an already-saved row — a
    // scanner hiccup (or a montage restored into the private dir, which
    // the gallery can't index anyway) must never surface as a failure.
    if (!kIsWeb) {
      try {
        await MediaScanner.loadMedia(path: compilation.filePath);
      } catch (_) {}
    }
  }

  Future<void> deleteCompilation(String id) async {
    final index = _compilations.indexWhere((c) => c.id == id);
    if (index >= 0) {
      final compilation = _compilations[index];
      await FileStorage.deleteFile(compilation.filePath);
      _compilations.removeAt(index);
      await _saveMetadata();
    }
  }

  int get totalClips => _clips.values.fold(0, (sum, list) => sum + list.length);

  int getCurrentStreak({DateTime? now}) {
    if (_clips.isEmpty) return 0;
    var streak = 0;
    // Walk backward in UTC-midnight space (see utcMidnight): subtracting
    // 24h from a local DateTime drifts an hour across a DST transition, and
    // the walk can then skip a wall-clock day entirely — silently breaking
    // a real streak. In UTC every step lands exactly one calendar day back,
    // and the formatted day key is unchanged (yyyy-MM-dd reads the fields).
    var date = utcMidnight(now ?? DateTime.now());
    // If today has no clip yet, start counting from yesterday so a
    // multi-day streak is not broken before the day's clip is recorded.
    if (!_clips.containsKey(DateFormatUtil.format(date, DateFormatOption.isoDate))) {
      date = date.subtract(const Duration(days: 1));
    }
    while (true) {
      final dateStr = DateFormatUtil.format(date, DateFormatOption.isoDate);
      if (_clips.containsKey(dateStr)) {
        streak++;
        date = date.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }
    return streak;
  }

  int getLongestStreak() {
    if (_clips.isEmpty) return 0;
    final dates = _clips.keys.toList()..sort();
    var longest = 1;
    var current = 1;
    for (var i = 1; i < dates.length; i++) {
      final prev = DateTime.parse(dates[i - 1]);
      final curr = DateTime.parse(dates[i]);
      // Calendar days, not elapsed-hours/24: parsed local midnights are 23h
      // apart across spring-forward, which a naive inDays truncates to 0
      // and wrongly splits a real streak (same class as getCurrentStreak).
      final diff = daysBetweenDates(prev, curr);
      if (diff == 1) {
        current++;
        if (current > longest) longest = current;
      } else {
        current = 1;
      }
    }
    return longest;
  }

  // Theme: light, dark, or follow the phone; default follow the phone (fleet
  // theme ruling). The stored int keeps its old encoding (0 dark, 1 light,
  // 2 system) because backups and snapshots carry 'theme_mode' as an int.
  // Only the unset default moved, from dark to follow phone. A stored 0 is
  // only ever written from Settings, so it stays the dark its owner sees.

  /// The stored three-way theme mode, in the int encoding above.
  int getThemeMode() => themeModeToInt(getThemePreference());
  Future<void> setThemeMode(int mode) => _prefs.setInt(_themeKey, mode);

  OhThemeModePreference getThemePreference() =>
      themePreferenceFromInt(_prefs.getInt(_themeKey));

  Future<void> setThemePreference(OhThemeModePreference preference) =>
      _prefs.setInt(_themeKey, themeModeToInt(preference));

  static OhThemeModePreference themePreferenceFromInt(int? mode) =>
      switch (mode) {
        0 => OhThemeModePreference.dark,
        1 => OhThemeModePreference.light,
        _ => OhThemeModePreference.system,
      };

  static int themeModeToInt(OhThemeModePreference preference) =>
      switch (preference) {
        OhThemeModePreference.dark => 0,
        OhThemeModePreference.light => 1,
        OhThemeModePreference.system => 2,
      };

  /// The stored accent. The old Coral (0xFFFF6B6B) looked like the error
  /// red in dark themes (C12), so it reads back as the new Coral.
  int getAccentColor() {
    final stored = _prefs.getInt(_accentKey) ?? 0xFF00FF00;
    return stored == 0xFFFF6B6B ? 0xFFFF8C69 : stored;
  }
  Future<void> setAccentColor(int color) => _prefs.setInt(_accentKey, color);

  bool getCrtEffects() => _prefs.getBool(_crtKey) ?? true;
  Future<void> setCrtEffects(bool enabled) => _prefs.setBool(_crtKey, enabled);

  String getDateFormat() => _prefs.getString(_dateFormatKey) ?? 'ddMmmYyyy';
  Future<void> setDateFormat(String key) =>
      _prefs.setString(_dateFormatKey, key);

  bool getCaptureLocation() => _prefs.getBool(_captureLocationKey) ?? true;
  Future<void> setCaptureLocation(bool enabled) =>
      _prefs.setBool(_captureLocationKey, enabled);

  /// Whether the one-time line before the first location prompt has done
  /// its job (the first save that could ask has happened).
  bool getLocationNoticeShown() =>
      _prefs.getBool('location_notice_shown') ?? false;
  Future<void> setLocationNoticeShown() =>
      _prefs.setBool('location_notice_shown', true);

  bool getIncludeLocationOverlay() =>
      _prefs.getBool(_includeLocationOverlayKey) ?? true;
  Future<void> setIncludeLocationOverlay(bool enabled) =>
      _prefs.setBool(_includeLocationOverlayKey, enabled);

  String getVisualStyle() => _prefs.getString(_visualStyleKey) ?? 'hearth';
  Future<void> setVisualStyle(String style) =>
      _prefs.setString(_visualStyleKey, style);

  /// Whether backups carry the montage MP4s themselves (ON by default —
  /// montages are the point of the app; the recipe alone can't reproduce
  /// one whose music file is gone). Device-local, like the migration
  /// flags: deliberately NOT in the settings allowlist that travels.
  bool getIncludeMontagesInBackup() =>
      _prefs.getBool(_includeMontagesInBackupKey) ?? true;
  Future<void> setIncludeMontagesInBackup(bool enabled) =>
      _prefs.setBool(_includeMontagesInBackupKey, enabled);

  Map<String, List<List<double>>> _knownPeople = {};
  Map<String, List<List<double>>> get knownPeople =>
      Map.unmodifiable(_knownPeople);

  Future<void> addPersonEmbedding(String name, List<double> embedding) async {
    _knownPeople.putIfAbsent(name, () => []);
    if (_knownPeople[name]!.length < 5) {
      _knownPeople[name]!.add(embedding);
    }
    await _saveMetadata();
  }

  Future<void> removePerson(String name) async {
    _knownPeople.remove(name);
    await _saveMetadata();
  }

  List<String> get knownPeopleNames => _knownPeople.keys.toList()..sort();

  Set<String> uniqueDatesInRange(String startDate, String endDate) {
    return _clips.keys
        .where((d) => d.compareTo(startDate) >= 0 && d.compareTo(endDate) <= 0)
        .toSet();
  }

  int getStreakInRange(String startDate, String endDate) {
    final dates = _clips.keys
        .where((d) => d.compareTo(startDate) >= 0 && d.compareTo(endDate) <= 0)
        .toList()
      ..sort();
    if (dates.isEmpty) return 0;
    var longest = 1;
    var current = 1;
    for (var i = 1; i < dates.length; i++) {
      final prev = DateTime.parse(dates[i - 1]);
      final curr = DateTime.parse(dates[i]);
      // Calendar days, not elapsed-hours/24: a spring-forward day is 23h
      // long, so inDays reads 0 for a real next day (and 1 for a 2-day gap
      // that includes the short day).
      if (daysBetweenDates(prev, curr) == 1) {
        current++;
        if (current > longest) longest = current;
      } else {
        current = 1;
      }
    }
    return longest;
  }

  Map<String, int> getLocationCountsInRange(String startDate, String endDate) {
    final counts = <String, int>{};
    for (final entry in _clips.entries) {
      if (entry.key.compareTo(startDate) < 0 ||
          entry.key.compareTo(endDate) > 0) {
        continue;
      }
      for (final clip in entry.value) {
        if (clip.locationLabel != null && clip.locationLabel!.isNotEmpty) {
          counts[clip.locationLabel!] = (counts[clip.locationLabel!] ?? 0) + 1;
        }
      }
    }
    return counts;
  }

  Map<String, int> getTagCountsInRange(String startDate, String endDate) {
    final counts = <String, int>{};
    for (final entry in _clips.entries) {
      if (entry.key.compareTo(startDate) < 0 ||
          entry.key.compareTo(endDate) > 0) {
        continue;
      }
      for (final clip in entry.value) {
        for (final tag in clip.tags) {
          counts[tag] = (counts[tag] ?? 0) + 1;
        }
      }
    }
    return counts;
  }

  Map<String, int> getFaceCountsInRange(String startDate, String endDate) {
    final counts = <String, int>{};
    for (final entry in _clips.entries) {
      if (entry.key.compareTo(startDate) < 0 ||
          entry.key.compareTo(endDate) > 0) {
        continue;
      }
      for (final clip in entry.value) {
        for (final face in clip.detectedFaces) {
          counts[face] = (counts[face] ?? 0) + 1;
        }
      }
    }
    return counts;
  }

  static const _reminderEnabledKey = 'reminder_enabled';
  static const _reminderTimeKey = 'reminder_time';

  bool getReminderEnabled() => _prefs.getBool(_reminderEnabledKey) ?? false;
  Future<void> setReminderEnabled(bool enabled) =>
      _prefs.setBool(_reminderEnabledKey, enabled);

  TimeOfDay getReminderTime() {
    final str = _prefs.getString(_reminderTimeKey) ?? '20:00';
    final parts = str.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  Future<void> setReminderTime(TimeOfDay time) {
    final str =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    return _prefs.setString(_reminderTimeKey, str);
  }

  Future<void> replaceClipFile(String clipId, String newFilePath,
      {double? newDuration}) async {
    for (final date in _clips.keys) {
      final list = _clips[date]!;
      final index = list.indexWhere((c) => c.id == clipId);
      if (index >= 0) {
        final clip = list[index];
        if (await FileStorage.exists(newFilePath)) {
          await FileStorage.copyFile(newFilePath, clip.filePath);
          if (newFilePath != clip.filePath) {
            await FileStorage.deleteFile(newFilePath);
          }
          if (newDuration != null) {
            list[index] = clip.copyWith(duration: newDuration);
          }
          await _saveMetadata();
        }
        return;
      }
    }
  }

  Future<void> reorderClips(String date, List<String> clipIdsInOrder) async {
    final list = _clips[date];
    if (list == null) return;
    final reordered = <Clip>[];
    for (final id in clipIdsInOrder) {
      final clip = list.where((c) => c.id == id).firstOrNull;
      if (clip == null) continue; // skip stale IDs rather than duplicating
      reordered.add(clip);
    }
    for (final clip in list) {
      if (!clipIdsInOrder.contains(clip.id)) reordered.add(clip);
    }
    _clips[date] = reordered;
    await _saveMetadata();
  }

  static const _celebratedMilestonesKey = 'celebrated_milestones';
  static const _onboardingCompleteKey = 'onboarding_complete';

  Set<int> getCelebratedMilestones() {
    final list = _prefs.getStringList(_celebratedMilestonesKey) ?? [];
    return list.map((s) => int.tryParse(s) ?? 0).where((v) => v > 0).toSet();
  }

  Future<void> addCelebratedMilestone(int days) async {
    final milestones = getCelebratedMilestones();
    milestones.add(days);
    await _prefs.setStringList(
      _celebratedMilestonesKey,
      milestones.map((m) => m.toString()).toList(),
    );
  }

  bool getOnboardingComplete() =>
      _prefs.getBool(_onboardingCompleteKey) ?? false;
  Future<void> setOnboardingComplete(bool complete) =>
      _prefs.setBool(_onboardingCompleteKey, complete);

  /// Returns the face reference image path, or null if not found.
  String? getFaceImagePath(String name) {
    if (!isSafePersonName(name)) return null; // never resolve outside faces/
    final path = '$_facesDir/$name.jpg';
    if (FileStorage.existsSync(path)) return path;
    return null;
  }

  /// Save a cropped face image as a reference for a named person.
  /// A name that is not a safe basename is refused before any file op —
  /// '$_facesDir/$name.jpg' with a '/' or '..' in the name would write
  /// outside the faces dir.
  Future<void> saveFaceImage(
      String name, String sourceImagePath, Rect boundingBox) async {
    if (!isSafePersonName(name)) {
      debugPrint('Refusing unsafe person name for face image: $name');
      return;
    }
    try {
      await FileStorage.ensureDir(_facesDir);
      final destPath = '$_facesDir/$name.jpg';
      // Store only the detected face, not the whole frame (privacy): crop the
      // source to the bounding box. Fall back to copying if the source can't be
      // read/decoded so a face isn't lost.
      final sourceBytes = await FileStorage.readBytes(sourceImagePath);
      final cropped =
          sourceBytes != null ? cropFaceJpg(sourceBytes, boundingBox) : null;
      if (cropped != null) {
        await FileStorage.writeBytes(destPath, cropped);
      } else {
        await FileStorage.copyFile(sourceImagePath, destPath);
      }
    } catch (e) {
      debugPrint('Failed to save face image: $e');
    }
  }

  /// For tests only — directly seeds the in-memory clip map.
  @visibleForTesting
  void setClipsForTest(Map<String, List<Clip>> clips) {
    _clips = Map.from(clips);
  }
}

/// Something deleted and kept, row and files, until its owner restores it
/// or confirms "Delete for good" (owner rulings, board-0124 and board-0138).
sealed class Removal {
  const Removal({required this.deletedAt, this.keptAt});

  /// The clip's or montage's id: one pending row per id.
  String get id;

  /// The files "Delete for good" destroys.
  List<String> get files;

  /// When it was deleted (or, for an old set-aside file, first seen).
  final DateTime deletedAt;

  /// When its owner last chose Keep in the 30-day question, if ever.
  final DateTime? keptAt;

  /// Where its wait before the 30-day question starts.
  DateTime get waitingSince => keptAt ?? deletedAt;

  /// The same item with Keep chosen at [at].
  Removal withKeep(DateTime at);

  Map<String, dynamic> toJson();

  /// The row's times, written after its other keys.
  Map<String, dynamic> get _times => {
        'deletedAt': deletedAt.toUtc().toIso8601String(),
        if (keptAt != null) 'keptAt': keptAt!.toUtc().toIso8601String(),
      };

  /// A pending row from metadata.json; a row with no delete time is dated
  /// [loadedAt]. Throws on a row this build cannot read, which the loader
  /// counts and skips.
  static Removal fromJson(Map<String, dynamic> json, DateTime loadedAt) {
    final deletedAt =
        DateTime.tryParse(json['deletedAt'] as String? ?? '') ?? loadedAt;
    final keptAt = DateTime.tryParse(json['keptAt'] as String? ?? '');
    if (json['clip'] != null) {
      return ClipRemoval.fromJson(json, deletedAt: deletedAt, keptAt: keptAt);
    }
    if (json['compilation'] != null) {
      return CompilationRemoval.fromJson(json,
          deletedAt: deletedAt, keptAt: keptAt);
    }
    if (json['setAside'] != null) {
      return SetAsideFiles.fromJson(json, deletedAt: deletedAt, keptAt: keptAt);
    }
    throw const FormatException('Unknown pending row');
  }
}

/// A clip taken off the calendar.
class ClipRemoval extends Removal {
  const ClipRemoval(this.clip, this.index,
      {required super.deletedAt, super.keptAt});
  final Clip clip;

  /// Its position in the day's list when it was removed.
  final int index;

  @override
  String get id => clip.id;

  @override
  List<String> get files => StorageService._clipFiles(clip);

  @override
  ClipRemoval withKeep(DateTime at) =>
      ClipRemoval(clip, index, deletedAt: deletedAt, keptAt: at);

  @override
  Map<String, dynamic> toJson() =>
      {'index': index, 'clip': clip.toJson(), ..._times};

  factory ClipRemoval.fromJson(Map<String, dynamic> json,
          {required DateTime deletedAt, DateTime? keptAt}) =>
      ClipRemoval(
        Clip.fromJson(json['clip'] as Map<String, dynamic>),
        (json['index'] as num?)?.toInt() ?? 0,
        deletedAt: deletedAt,
        keptAt: keptAt,
      );
}

/// A montage taken off the list.
class CompilationRemoval extends Removal {
  const CompilationRemoval(this.compilation, this.index,
      {required super.deletedAt, super.keptAt});
  final Compilation compilation;

  /// Its position in the montage list when it was removed.
  final int index;

  @override
  String get id => compilation.id;

  @override
  List<String> get files => [compilation.filePath];

  @override
  CompilationRemoval withKeep(DateTime at) =>
      CompilationRemoval(compilation, index, deletedAt: deletedAt, keptAt: at);

  @override
  Map<String, dynamic> toJson() =>
      {'index': index, 'compilation': compilation.toJson(), ..._times};

  factory CompilationRemoval.fromJson(Map<String, dynamic> json,
          {required DateTime deletedAt, DateTime? keptAt}) =>
      CompilationRemoval(
        Compilation.fromJson(json['compilation'] as Map<String, dynamic>),
        (json['index'] as num?)?.toInt() ?? 0,
        deletedAt: deletedAt,
        keptAt: keptAt,
      );
}

/// Files a build before the rulings listed for purge after their row was
/// already gone. Their day is not known for certain (a clip's file is
/// named by a random id), so they cannot go back on the calendar; their
/// owner keeps them or deletes them for good.
class SetAsideFiles extends Removal {
  const SetAsideFiles({
    required this.id,
    required this.files,
    required this.isMontage,
    required super.deletedAt,
    super.keptAt,
  });

  @override
  final String id;

  @override
  final List<String> files;

  /// A montage's file, not a clip's video and picture.
  final bool isMontage;

  /// The clip's picture, when one was kept.
  String? get thumbnailPath =>
      isMontage ? null : files.where((f) => f.endsWith('.jpg')).firstOrNull;

  @override
  SetAsideFiles withKeep(DateTime at) => SetAsideFiles(
        id: id,
        files: files,
        isMontage: isMontage,
        deletedAt: deletedAt,
        keptAt: at,
      );

  @override
  Map<String, dynamic> toJson() => {
        'setAside': {'id': id, 'files': files, 'isMontage': isMontage},
        ..._times,
      };

  factory SetAsideFiles.fromJson(Map<String, dynamic> json,
      {required DateTime deletedAt, DateTime? keptAt}) {
    final row = json['setAside'] as Map<String, dynamic>;
    return SetAsideFiles(
      id: row['id'] as String,
      files: (row['files'] as List).cast<String>().toList(),
      isMontage: row['isMontage'] as bool? ?? false,
      deletedAt: deletedAt,
      keptAt: keptAt,
    );
  }
}
