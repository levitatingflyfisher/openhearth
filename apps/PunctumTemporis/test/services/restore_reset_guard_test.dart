// The guard for the restore reset (fleet erase and restore audit,
// 12 November 2026).
//
// PT keeps state in plain StatefulWidgets and one StorageService, so a
// copy of stored data can hide in three places that live across a
// restore: a State that read from storage, a mutable static, and a
// singleton. This test finds every one of them in lib/ and fails until
// each has a ruling below: it follows StorageService.reload (and the test
// checks that it really listens), or it says why a restore cannot leave
// it old. It also pins that both restore paths go through reload() and
// that no Undo carries an onCommit, which an ordinary dismissal would run.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// How a State that touches storage follows a restore.
sealed class _Ruling {
  const _Ruling();
}

/// Listens to `reloads` or `changes` and re-reads from storage.
class _Listens extends _Ruling {
  const _Listens();
}

/// Holds nothing a restore can leave old, for the reason given.
class _Exempt extends _Ruling {
  const _Exempt(this.why);
  final String why;
}

/// A restore runs from Backup & Restore, opened from Settings, opened from
/// the calendar. Only those three, and the app around them, are alive
/// during a restore.
const _notUnderRestore =
    'Never on the stack under Backup & Restore (calendar, Settings, '
    'Backup & Restore), so it is built fresh after any restore.';

/// Every State class in lib/ that names the storage service.
const _states = <String, _Ruling>{
  'lib/main.dart _OneSecondAppState': _Listens(),
  'lib/screens/calendar_screen.dart _CalendarScreenState': _Listens(),
  'lib/screens/settings_screen.dart _SettingsScreenState': _Listens(),
  'lib/screens/day_view_screen.dart _DayViewScreenState': _Listens(),
  'lib/screens/compilation_screen.dart _CompilationScreenState': _Listens(),
  'lib/screens/recently_deleted_screen.dart _RecentlyDeletedScreenState':
      _Listens(),
  'lib/screens/backup_restore_screen.dart _BackupRestoreScreenState':
      _Exempt('The restore runs here; it reads its size estimate again '
          'when the restore ends.'),
  'lib/screens/clip_preview_screen.dart _ClipPreviewScreenState':
      _Exempt(_notUnderRestore),
  'lib/screens/gallery_import_screen_native.dart _GalleryImportScreenState':
      _Exempt(_notUnderRestore),
  'lib/screens/gallery_import_screen_web.dart _GalleryImportScreenState':
      _Exempt(_notUnderRestore),
  'lib/screens/onboarding_screen.dart _OnboardingScreenState':
      _Exempt('Holds only its page and the reminder choice, and reads the '
          'reminder time when it finishes. On the web its moved-here offer '
          'can open Backup & Restore over it, and nothing it holds can go '
          'old.'),
  'lib/move/move_page.dart _MovedHereOfferSlotState': _Listens(),
  'lib/screens/photo_capture_screen.dart _PhotoCaptureScreenState':
      _Exempt(_notUnderRestore),
  'lib/screens/video_capture_screen.dart _VideoCaptureScreenState':
      _Exempt(_notUnderRestore),
  'lib/screens/year_review_screen.dart _YearReviewScreenState':
      _Exempt('Opened on top of the calendar or Settings, never under '
          'Backup & Restore.'),
};

/// Every mutable static field in lib/, and why it is safe or how it is
/// reset.
const _statics = <String, String>{
  'lib/theme/app_theme.dart visualStyle':
      'A stored setting: _forgetCachedData in main.dart sets it again.',
  'lib/platform/face_service_impl.dart _instance':
      'The face model, loaded from the app bundle; no stored data.',
  'lib/platform/face_service_stub.dart _instance':
      'The web stand-in for the face model; no stored data.',
  'lib/platform/file_storage_native.dart _tempWrites':
      'A counter that makes temporary file names unique.',
  'lib/services/offline_geocoder.dart _instance':
      'The bundled place list; no stored data.',
};

/// Every app-wide singleton (`static final ... instance`) in lib/.
const _singletons = <String, String>{
  'lib/platform/notification_service_impl.dart':
      'The phone holds the daily reminder: _forgetCachedData sets it to '
          'the restored setting.',
  'lib/platform/notification_service_stub.dart':
      'The web stand-in for reminders; it schedules nothing.',
};

List<File> _libFiles() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList()
  ..sort((a, b) => a.path.compareTo(b.path));

String _rel(File f) => f.path.replaceAll('\\', '/');

/// Each `class X extends State<...>` with its source, up to the next class.
Map<String, String> _stateClasses() {
  final out = <String, String>{};
  final classStart = RegExp(r'^class (\w+) extends State<', multiLine: true);
  final nextClass = RegExp(r'^class ', multiLine: true);
  for (final f in _libFiles()) {
    final text = f.readAsStringSync();
    for (final m in classStart.allMatches(text)) {
      final rest = text.substring(m.end);
      final end = nextClass.firstMatch(rest);
      out['${_rel(f)} ${m.group(1)}'] =
          text.substring(m.start, m.end + (end?.start ?? rest.length));
    }
  }
  return out;
}

void main() {
  test('every State that touches storage has a ruling', () {
    final names = RegExp(r'\bstorage(Service)?\b');
    final found = {
      for (final MapEntry(:key, :value) in _stateClasses().entries)
        if (names.hasMatch(value)) key,
    };
    expect(found, isNotEmpty, reason: 'the scan found nothing: fix the scan');
    expect(found.difference(_states.keys.toSet()), isEmpty,
        reason: 'a new State reads storage: make it listen to '
            'StorageService.reloads (or changes), or rule why a restore '
            'cannot leave it old');
    expect(_states.keys.toSet().difference(found), isEmpty,
        reason: 'a ruling names a State that no longer exists');
  });

  test('a State ruled as listening really listens', () {
    final classes = _stateClasses();
    final listens = RegExp(r'\.(reloads|changes)\.addListener\(');
    for (final MapEntry(:key, :value) in _states.entries) {
      if (value is! _Listens) continue;
      expect(listens.hasMatch(classes[key]!), isTrue,
          reason: '$key is ruled as listening but adds no listener');
    }
  });

  test('every mutable static has a ruling', () {
    // `static` not followed by const or final, a type, a name, then = or ;.
    // A getter's `=>` and a method's `(` do not count.
    final mutable = RegExp(
        r'^\s*static\s+(?!const\b|final\b)[\w<>?, ]+?\s(\w+)\s*(=(?!>)|;)',
        multiLine: true);
    final found = {
      for (final f in _libFiles())
        for (final m in mutable.allMatches(f.readAsStringSync()))
          '${_rel(f)} ${m.group(1)}',
    };
    expect(found, contains('lib/theme/app_theme.dart visualStyle'),
        reason: 'the scan missed a known static: fix the scan');
    expect(found, _statics.keys.toSet(),
        reason: 'a mutable static lives across a restore: reset it in '
            '_forgetCachedData or rule why it holds no stored data');
  });

  test('every app-wide singleton has a ruling', () {
    final singleton = RegExp(r'static final \w+ instance\b');
    final found = {
      for (final f in _libFiles())
        if (singleton.hasMatch(f.readAsStringSync())) _rel(f),
    };
    expect(found, _singletons.keys.toSet());
  });

  test('the app reset resets each long-lived copy it is ruled to', () {
    final main = File('lib/main.dart').readAsStringSync();
    final start = main.indexOf('void _forgetCachedData()');
    expect(start, isNot(-1));
    final body = main.substring(start, main.indexOf('\n  }\n', start));
    expect(body, contains('_undo.cancel()'));
    expect(body, contains('AppTheme.visualStyle ='));
    expect(body, contains('_themeMode ='));
    expect(body, contains('_accentColor ='));
    expect(body, contains('getReminderEnabled()'));
    expect(main, contains('reloads.addListener(_forgetCachedData)'));
  });

  test('both restore paths go through StorageService.reload', () {
    final backup = File('lib/services/backup_service.dart').readAsStringSync();
    expect(backup, isNot(contains('storageService.initialize(')),
        reason: 'initialize() re-reads the journal but tells no one');
    expect('storageService.reload()'.allMatches(backup), hasLength(2),
        reason: 'restoreBackup and restoreMetadataSnapshot');
  });

  test('no Undo carries an onCommit', () {
    // The reset cancels, which runs no onCommit, so it does not need this.
    // An ordinary dismissal (the close button, a newer delete) does run the
    // entry's onCommit, and nothing in PT needs one.
    final passed = RegExp(r'onCommit\s*:');
    for (final f in _libFiles()) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final code = lines[i].split('//').first;
        expect(passed.hasMatch(code), isFalse,
            reason: '${_rel(f)}:${i + 1} passes onCommit; none in PT needs one');
      }
    }
  });
}
