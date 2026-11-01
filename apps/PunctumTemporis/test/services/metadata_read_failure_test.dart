// A read of metadata.json that fails says nothing about the file: a passing
// I/O error must never move the journal aside and start an empty one. Only
// a file that was read and will not parse is set aside, and then the family
// is told plainly, once (board ruling, Banto, 14 Nov 2026).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_second_a_day/main.dart';
import 'package:one_second_a_day/models/clip.dart';
import 'package:one_second_a_day/services/backup_service.dart';
import 'package:one_second_a_day/services/storage_service.dart';
import 'package:openhearth_design/openhearth_design.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';
import 'package:sanctuary_backup_ui/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.base);
  final String base;
  @override
  Future<String?> getApplicationDocumentsPath() async => base;
  @override
  Future<String?> getApplicationSupportPath() async => base;
  @override
  Future<String?> getTemporaryPath() async => '$base/tmp';
}

/// A real file, except that reading metadata.json throws an I/O error.
class _UnreadableFile implements File {
  _UnreadableFile(this._real);
  final File _real;

  bool get _isLive => _real.path.endsWith('/metadata.json');

  @override
  String get path => _real.path;
  @override
  Future<bool> exists() => _real.exists();
  @override
  Future<Uint8List> readAsBytes() async {
    if (_isLive) throw FileSystemException('read failed', path);
    return _real.readAsBytes();
  }

  @override
  Future<String> readAsString({Encoding encoding = utf8}) async {
    if (_isLive) throw FileSystemException('read failed', path);
    return _real.readAsString(encoding: encoding);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

final class _UnreadableOverrides extends IOOverrides {
  @override
  File createFile(String path) => _UnreadableFile(super.createFile(path));
}

Map<String, dynamic> _row(String id, String date) => {
      'id': id,
      'date': date,
      'filePath': '/clips/$id.mp4',
      'type': 'video',
      'createdAt': '${date}T12:00:00.000',
    };

final _journal = jsonEncode({
  'clips': {
    '2026-11-01': [_row('kept', '2026-11-01')],
  },
  'compilations': <dynamic>[],
});

const _torn = '{"clips":{"2026-11-01":[{"id":"a","date":"2026-11-0';

final _someBad = jsonEncode({
  'clips': {
    '2026-11-01': [
      _row('good', '2026-11-01'),
      {'id': 'no-date-or-path'},
    ],
  },
  'compilations': <dynamic>[],
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late File live;
  late SharedPreferences prefs;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('pt_read_failure_');
    live = File('${tmp.path}/metadata.json');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    SharedPreferences.setMockInitialValues({
      'onboarding_complete': true,
      'crt_effects': false,
    });
    prefs = await SharedPreferences.getInstance();
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  List<File> setAsideFiles() => tmp
      .listSync()
      .whereType<File>()
      .where((f) => f.path.split('/').last.startsWith('metadata.unreadable-'))
      .toList();

  group('a read that throws an I/O error', () {
    test('leaves metadata.json in place and sets nothing aside', () async {
      await live.writeAsString(_journal);
      final storage = StorageService(prefs);

      await IOOverrides.runWithIOOverrides(
          () => storage.initialize(), _UnreadableOverrides());

      expect(storage.readFailed, isTrue);
      expect(storage.readError, isA<FileSystemException>());
      expect(live.readAsStringSync(), _journal);
      expect(setAsideFiles(), isEmpty);
      expect(storage.setAsideNotice, isNull,
          reason: 'nothing was set aside, so there is nothing to tell');
    });

    test('a save refuses and the journal stays whole', () async {
      await live.writeAsString(_journal);
      final storage = StorageService(prefs);
      await IOOverrides.runWithIOOverrides(
          () => storage.initialize(), _UnreadableOverrides());

      await expectLater(
          storage.addClip(Clip.fromJson(_row('new', '2026-11-10'))),
          throwsStateError);

      expect(live.readAsStringSync(), _journal);
    });

    test('Try again reads the journal once the read works', () async {
      await live.writeAsString(_journal);
      final storage = StorageService(prefs);
      await IOOverrides.runWithIOOverrides(
          () => storage.initialize(), _UnreadableOverrides());

      await storage.retryRead();

      expect(storage.readFailed, isFalse);
      expect(storage.getClipsForDate('2026-11-01').map((c) => c.id), ['kept']);
    });
  });

  group('the notice', () {
    test('a file that will not parse is set aside and told once', () async {
      await live.writeAsString(_torn);
      final storage = StorageService(prefs);
      await storage.initialize();

      final name = setAsideFiles().single.path.split('/').last;
      final told = 'Your journal file couldn’t be read. It was kept as $name '
          'beside the new one. Nothing was deleted.';
      expect(storage.setAsideNotice, told);

      await storage.dismissSetAsideNotice(told);
      expect(storage.setAsideNotice, isNull);

      // The next start has a good (new) journal and says nothing.
      final again = StorageService(prefs);
      await again.initialize();
      expect(again.setAsideNotice, isNull);
    });

    test('the notice stays recorded until the family dismisses it', () async {
      await live.writeAsString(_torn);
      final storage = StorageService(prefs);
      await storage.initialize();
      final told = storage.setAsideNotice;
      expect(told, isNotNull);

      // Shown, then the app is closed at once: the next start tells again.
      final next = StorageService(prefs);
      await next.initialize();
      expect(next.setAsideNotice, told);

      await next.dismissSetAsideNotice(told!);

      final third = StorageService(prefs);
      await third.initialize();
      expect(third.setAsideNotice, isNull);
    });

    test('dismissing an older notice keeps a newer one recorded', () async {
      await live.writeAsString(_torn);
      final storage = StorageService(prefs);
      await storage.initialize();
      final older = storage.setAsideNotice!;

      // A second set-aside lands before the family taps Dismiss.
      await live.writeAsString(_torn);
      final next = StorageService(prefs);
      await next.initialize();
      final newer = next.setAsideNotice!;
      expect(newer, isNot(older));

      await storage.dismissSetAsideNotice(older);
      expect(next.setAsideNotice, newer);
    });

    test('a file with some bad rows keeps the good ones and tells of the copy',
        () async {
      await live.writeAsString(_someBad);
      final storage = StorageService(prefs);
      await storage.initialize();

      expect(storage.getClipsForDate('2026-11-01').map((c) => c.id), ['good']);
      final name = setAsideFiles().single.path.split('/').last;
      final told = 'Part of your journal file couldn’t be read. A copy was '
          'kept as $name beside it. Nothing was deleted.';
      expect(storage.setAsideNotice, told);
      await storage.dismissSetAsideNotice(told);

      // The same file at the next start: no second copy, no second notice.
      final again = StorageService(prefs);
      await again.initialize();
      expect(setAsideFiles(), hasLength(1));
      expect(again.setAsideNotice, isNull);
    });
  });

  group('on screen', () {
    // Real file work runs in runAsync; a widget test's own zone never
    // finishes real I/O (old_deletes_prompt_test has the same settle).
    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 400));
      }
    }

    Future<void> pumpApp(
        WidgetTester tester, Future<void> Function(StorageService) init) async {
      final storage = StorageService(prefs);
      await tester.runAsync(() => init(storage));
      await tester.pumpWidget(OneSecondApp(
        storageService: storage,
        backupServiceFactory: () => BackupService(storage,
            vault: BackupVault(InMemoryVaultStore(),
                appId: 'punctum', extension: 'json'),
            prefs: prefs),
      ));
      await settle(tester);
    }

    testWidgets('a failed read shows the read error with Try again',
        (tester) async {
      live.writeAsStringSync(_journal);
      await pumpApp(
          tester,
          (s) => IOOverrides.runWithIOOverrides(
              () => s.initialize(), _UnreadableOverrides()));

      expect(find.byType(OhReadError), findsOneWidget);
      expect(find.text('Couldn’t read your journal'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(live.readAsStringSync(), _journal);

      await tester.tap(find.text('Try again'));
      // The read again is real file work, one step per round here.
      for (var i = 0; i < 10 && find.byType(OhReadError).evaluate().isNotEmpty;
          i++) {
        await settle(tester);
      }
      expect(find.byType(OhReadError), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    });

    testWidgets('a set-aside shows one notice the family can dismiss',
        (tester) async {
      live.writeAsStringSync(_torn);
      await pumpApp(tester, (s) => s.initialize());

      final notice = find.textContaining('Your journal file couldn’t be read');
      expect(notice, findsOneWidget);
      expect(find.textContaining('Nothing was deleted.'), findsOneWidget);

      await tester.tap(find.text('Dismiss'));
      await tester.pump();
      expect(notice, findsNothing);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    });

    testWidgets('an app closed before Dismiss shows the notice at next start',
        (tester) async {
      live.writeAsStringSync(_torn);
      await pumpApp(tester, (s) => s.initialize());
      final notice = find.textContaining('Your journal file couldn’t be read');
      expect(notice, findsOneWidget);

      // Closed at once, without Dismiss.
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
      await pumpApp(tester, (s) => s.initialize());
      expect(notice, findsOneWidget);

      await tester.tap(find.text('Dismiss'));
      await tester.pump();
      await settle(tester);
      expect(notice, findsNothing);

      // Dismissed: the next start says nothing.
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
      await pumpApp(tester, (s) => s.initialize());
      expect(notice, findsNothing);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    });
  });
}
