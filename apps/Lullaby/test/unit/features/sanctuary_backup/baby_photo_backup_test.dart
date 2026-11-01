import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lullaby/core/errors/result.dart';
import 'package:lullaby/features/babies/data/repositories/baby_repository_impl.dart';
import 'package:lullaby/features/babies/domain/entities/baby.dart';
import 'package:lullaby/features/babies/presentation/widgets/baby_avatar.dart';
import 'package:lullaby/features/babies/presentation/widgets/baby_photo.dart';
import 'package:lullaby/features/sanctuary_backup/data/backup_photo.dart';
import 'package:lullaby/features/sanctuary_backup/data/backup_serializer.dart';
import 'package:lullaby/services/database/daos/baby_dao.dart';
import 'package:lullaby/services/database/database.dart';
import 'package:sanctuary_auth_core/sanctuary_auth_core.dart';
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';

import '../../../test_setup.dart';

/// The owner's ruling (board-0167): put the baby's photo into the encrypted
/// backup. Before it, the backup held only the photo's path on the old
/// phone, so a restore on a new phone showed the initial letter.
///
/// Every photo here is a made-up image drawn by the test, in a temporary
/// folder.
const _ghostContext = 'ghost-backup/v1';

Uint8List _key(int seed) {
  final rng = Random(seed);
  return Uint8List.fromList(List.generate(32, (_) => rng.nextInt(256)));
}

/// A PNG of random pixels: it does not compress, so its size is close to
/// width x height x 4.
Future<Uint8List> _noisePng(int width, int height, int seed) async {
  final rng = Random(seed);
  final pixels = Uint8List(width * height * 4);
  for (var i = 0; i < pixels.length; i++) {
    pixels[i] = i % 4 == 3 ? 255 : rng.nextInt(256);
  }
  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(
      pixels, width, height, ui.PixelFormat.rgba8888, done.complete);
  final image = await done.future;
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

Future<(int, int)> _size(Uint8List encoded) async {
  final codec = await ui.instantiateImageCodec(encoded);
  final frame = await codec.getNextFrame();
  final size = (frame.image.width, frame.image.height);
  frame.image.dispose();
  codec.dispose();
  return size;
}

bool _containsRun(List<int> haystack, List<int> needle) {
  outer:
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    return true;
  }
  return false;
}

void main() {
  ensureSqlite3();
  TestWidgetsFlutterBinding.ensureInitialized();

  final cipher = EnvelopeCipher();
  final key = _key(7);
  final now = DateTime(2026, 11, 12);

  late Directory tmp;
  late String oldPhone;
  late String newPhone;
  late AppDatabase db;
  late AppDatabase fresh;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('lullaby_photo_backup_');
    oldPhone = '${tmp.path}/old/avatars';
    newPhone = '${tmp.path}/new/avatars';
    await Directory(oldPhone).create(recursive: true);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    fresh = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
    await fresh.close();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  BackupRepository repoFor(AppDatabase d, String folder) => BackupRepository(
      LullabyBackupSerializer(d, photos: BabyPhotoFiles(folder: folder)),
      cipher,
      aadContext: _ghostContext);

  Future<void> seedBaby({String? photoPath}) async {
    await db.into(db.babies).insert(BabiesCompanion.insert(
          id: 'b1',
          name: 'Alice',
          dateOfBirth: DateTime(2026, 6, 1),
          photoPath: Value(photoPath),
          createdAt: now,
          modifiedAt: now,
        ));
  }

  Future<File> writePhoto(Uint8List bytes, [String name = 'face.png']) async {
    final file = File('$oldPhone/$name');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Map<String, dynamic> tablesOf(Uint8List plaintext) =>
      (jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>)['tables']
          as Map<String, dynamic>;

  test('the backup of a household with a photo carries the photo', () async {
    final photo = await _noisePng(64, 48, 1);
    final file = await writePhoto(photo);
    await seedBaby(photoPath: file.path);

    final plain = await LullabyBackupSerializer(db,
            photos: BabyPhotoFiles(folder: oldPhone))
        .dumpAll();

    final photos = tablesOf(plain)['babyPhotos'] as List<dynamic>;
    expect(photos, hasLength(1));
    final entry = photos.single as Map<String, dynamic>;
    expect(entry['babyId'], 'b1');
    expect(entry['extension'], '.png');
    expect(base64Decode(entry['data'] as String), photo);
  });

  test('the photo is encrypted: its bytes are not visible in the backup',
      () async {
    final photo = await _noisePng(64, 48, 2);
    final file = await writePhoto(photo);
    await seedBaby(photoPath: file.path);

    final blob = await repoFor(db, oldPhone).export(key);

    // A run from the middle of the picture, raw and as base64 text.
    final run = photo.sublist(200, 264);
    expect(_containsRun(blob, run), isFalse);
    final asText = utf8.encode(base64Encode(photo).substring(400, 480));
    expect(_containsRun(blob, asText), isFalse);
    expect(_containsRun(blob, utf8.encode('babyPhotos')), isFalse);
  });

  testWidgets(
      'a restore on a fresh install brings the photo back byte for byte, '
      'and the app shows it', (tester) async {
    late Uint8List photo;
    late BabyEntity restored;
    await tester.runAsync(() async {
      photo = await _noisePng(64, 48, 3);
      final file = await writePhoto(photo, 'a.jpg');
      await seedBaby(photoPath: file.path);
      final blob = await repoFor(db, oldPhone).export(key);
      // The old phone is gone.
      await Directory('${tmp.path}/old').delete(recursive: true);

      await repoFor(fresh, newPhone).restore(blob, key);

      final result = await BabyRepositoryImpl(BabyDao(fresh)).getBabyById('b1');
      restored = (result as Success<BabyEntity>).value;
    });

    expect(restored.photoPath, isNotNull);
    expect(restored.photoPath, startsWith('$newPhone/'));
    expect(restored.photoPath, endsWith('.jpg'));
    expect(File(restored.photoPath!).readAsBytesSync(), photo);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: BabyAvatar(baby: restored)),
    ));
    final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
    expect(avatar.backgroundImage, isA<FileImage>());
    expect((avatar.backgroundImage! as FileImage).file.path,
        restored.photoPath);
    expect(find.text('A'), findsNothing, reason: 'the photo, not the letter');
  });

  test('a backup without a photo still works', () async {
    await seedBaby();
    final blob = await repoFor(db, oldPhone).export(key);
    await repoFor(fresh, newPhone).restore(blob, key);

    final rows = await fresh.select(fresh.babies).get();
    expect(rows.single.name, 'Alice');
    expect(rows.single.photoPath, isNull);
    expect(Directory(newPhone).existsSync() &&
        Directory(newPhone).listSync().isNotEmpty, isFalse);
  });

  test('a photo whose file is gone leaves the rest of the backup whole',
      () async {
    await seedBaby(photoPath: '$oldPhone/gone.jpg');
    final plain = await LullabyBackupSerializer(db,
            photos: BabyPhotoFiles(folder: oldPhone))
        .dumpAll();
    expect(tablesOf(plain)['babyPhotos'], isEmpty);
    expect(tablesOf(plain)['babies'], hasLength(1));
  });

  test('an older backup without photos still restores', () async {
    // As the build before this one wrote it: a path, no babyPhotos table.
    final old = utf8.encode(jsonEncode({
      'schemaVersion': db.schemaVersion,
      'exportedAt': now.toUtc().toIso8601String(),
      'tables': {
        'babies': [
          {
            'id': 'b1',
            'name': 'Alice',
            'dateOfBirth': DateTime(2026, 6, 1).millisecondsSinceEpoch,
            'gender': null,
            'photoPath': '/data/user/0/old/app_flutter/avatars/x.jpg',
            'isActive': true,
            'createdAt': now.millisecondsSinceEpoch,
            'modifiedAt': now.millisecondsSinceEpoch,
          }
        ],
      },
    }));

    await LullabyBackupSerializer(fresh,
            photos: BabyPhotoFiles(folder: newPhone))
        .restoreAll(Uint8List.fromList(old));

    final rows = await fresh.select(fresh.babies).get();
    expect(rows.single.name, 'Alice');
    expect(rows.single.photoPath,
        '/data/user/0/old/app_flutter/avatars/x.jpg',
        reason: 'unchanged from before: the app shows the letter when the '
            'path is not on this phone');
  });

  group('the photo size is bounded at $maxBackupPhotoBytes bytes', () {
    test('a photo at the limit goes in as it is', () async {
      final png = await _noisePng(16, 16, 4);
      // Pad to exactly the limit; the bytes are carried, never decoded.
      final atLimit = Uint8List(maxBackupPhotoBytes)
        ..setRange(0, png.length, png);
      final file = await writePhoto(atLimit, 'big.png');
      await seedBaby(photoPath: file.path);

      final plain = await LullabyBackupSerializer(db,
              photos: BabyPhotoFiles(folder: oldPhone))
          .dumpAll();
      final entry = (tablesOf(plain)['babyPhotos'] as List).single as Map;
      expect(base64Decode(entry['data'] as String), atLimit);
    });

    test(
        'a larger photo goes in as a smaller copy, $backupPhotoSide pixels '
        'on its longest side; the photo on the phone is not changed',
        () async {
      final big = await _noisePng(1200, 600, 5);
      expect(big.length, greaterThan(maxBackupPhotoBytes));
      final file = await writePhoto(big, 'big.jpg');
      await seedBaby(photoPath: file.path);

      final plain = await LullabyBackupSerializer(db,
              photos: BabyPhotoFiles(folder: oldPhone))
          .dumpAll();
      final entry = (tablesOf(plain)['babyPhotos'] as List).single as Map;
      final copy = base64Decode(entry['data'] as String);

      expect(copy.length, lessThanOrEqualTo(maxBackupPhotoBytes));
      expect(entry['extension'], '.png');
      expect(await _size(copy), (backupPhotoSide, backupPhotoSide ~/ 2));
      expect(file.readAsBytesSync(), big);
    });

    test('a restore skips a photo over the limit and keeps the rest',
        () async {
      await seedBaby();
      final plain = await LullabyBackupSerializer(db).dumpAll();
      final payload = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
      (payload['tables'] as Map<String, dynamic>)['babyPhotos'] = [
        {
          'babyId': 'b1',
          'extension': '.png',
          'data': base64Encode(Uint8List(maxBackupPhotoBytes + 1)),
        }
      ];

      await LullabyBackupSerializer(fresh,
              photos: BabyPhotoFiles(folder: newPhone))
          .restoreAll(Uint8List.fromList(utf8.encode(jsonEncode(payload))));

      final rows = await fresh.select(fresh.babies).get();
      expect(rows.single.photoPath, isNull);
    });
  });

  test('a restored photo gets a name of its own inside the photo folder',
      () async {
    await seedBaby();
    final plain = await LullabyBackupSerializer(db).dumpAll();
    final payload = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
    final png = await _noisePng(8, 8, 6);
    (payload['tables'] as Map<String, dynamic>)['babyPhotos'] = [
      {
        'babyId': 'b1',
        'extension': '/../../evil.sh',
        'data': base64Encode(png),
      }
    ];

    await LullabyBackupSerializer(fresh,
            photos: BabyPhotoFiles(folder: newPhone))
        .restoreAll(Uint8List.fromList(utf8.encode(jsonEncode(payload))));

    final path = (await fresh.select(fresh.babies).get()).single.photoPath!;
    expect(File(path).parent.path, newPhone);
    expect(path, isNot(contains('..')));
    expect(path, isNot(contains('evil')));
    expect(File(path).readAsBytesSync(), png);
  });

  test('a restore that fails leaves no restored photo behind', () async {
    final photo = await _noisePng(8, 8, 8);
    final file = await writePhoto(photo);
    await seedBaby(photoPath: file.path);
    final plain = await LullabyBackupSerializer(db,
            photos: BabyPhotoFiles(folder: oldPhone))
        .dumpAll();
    final payload = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
    // A feed with no type cannot be inserted, so the restore fails after
    // the photo was written.
    (payload['tables'] as Map<String, dynamic>)['feedingLogs'] = [
      {
        'id': 'f1',
        'babyId': 'b1',
        'startTime': now.millisecondsSinceEpoch,
        'createdAt': now.millisecondsSinceEpoch,
        'modifiedAt': now.millisecondsSinceEpoch,
      }
    ];

    await expectLater(
        LullabyBackupSerializer(fresh,
                photos: BabyPhotoFiles(folder: newPhone))
            .restoreAll(Uint8List.fromList(utf8.encode(jsonEncode(payload)))),
        throwsA(anything));

    expect(Directory(newPhone).existsSync() &&
        Directory(newPhone).listSync().isNotEmpty, isFalse);
  });
}
