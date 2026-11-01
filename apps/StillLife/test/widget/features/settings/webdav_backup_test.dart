import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanctuary_auth_core/sanctuary_auth_core.dart';
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';
import 'package:sanctuary_backup_ui/testing.dart';
import 'package:still_life/core/providers/database_provider.dart';
import 'package:still_life/core/providers/repository_providers.dart';
import 'package:still_life/core/providers/sync_providers.dart';
import 'package:still_life/core/sync/sync_stamp.dart';
import 'package:still_life/features/backup/backup_wiring.dart';
import 'package:still_life/features/backup/webdav_backup_flow.dart';
import 'package:still_life/features/settings/presentation/screens/webdav_settings_screen.dart';
import 'package:still_life/services/backup/still_life_backup_serializer.dart';
import 'package:still_life/services/backup/webdav_backup_service.dart';
import 'package:still_life/services/database/database.dart';
import 'package:still_life/services/export/import_service.dart';
import 'package:still_life/services/export/json_export_service.dart';

import '../../../test_setup.dart';

// Made-up household data. None of it may appear in what leaves the phone.
const _itemName = 'Brass telescope';
const _roomName = 'Sunroom';
const _valueCents = 123456;
const _valueOnWire = '1234.56';

/// The key FakeCryptoService derives for the device's words (fill 7).
final _deviceKey = Uint8List(32)..fillRange(0, 32, 7);

const _phrase =
    'abandon abandon abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon about';

/// Words that are not this household's. [_PhraseKeyedCryptoService] maps
/// them to a different key (fill 9).
const _otherPhrase =
    'legal winner thank year wave sausage worth useful legal winner thank '
    'yellow';

final _otherKey = Uint8List(32)..fillRange(0, 32, 9);

/// The base fake gives every phrase the same key, which would make "wrong
/// words" impossible. This one gives [_phrase] fill 7 and anything else 9.
class _PhraseKeyedCryptoService extends FakeCryptoService {
  @override
  Future<DerivedKeys> deriveKeysFromPhrase(
    String phrase, {
    String? appDomain,
  }) async {
    final fill = phrase == _phrase ? 7 : 9;
    Uint8List filled(int v) => Uint8List(32)..fillRange(0, 32, v);
    return DerivedKeys(
      masterEncryptionKey: filled(fill),
      syncKey: filled(fill + 1),
      authKey: filled(fill + 2),
      recoveryKey: filled(fill + 3),
      syncChannelId: filled(fill + 4),
    );
  }
}

/// A WebDAV server in memory: PUT stores the body, GET returns it.
class _FakeDavServer implements HttpClientAdapter {
  Uint8List? stored;
  int puts = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.method == 'PUT') {
      final body = BytesBuilder();
      if (requestStream != null) {
        await for (final chunk in requestStream) {
          body.add(chunk);
        }
      }
      stored = body.toBytes();
      puts++;
      return ResponseBody.fromBytes(const [], 201);
    }
    if (options.method == 'GET') {
      final held = stored;
      if (held == null) return ResponseBody.fromBytes(const [], 404);
      return ResponseBody.fromBytes(held, 200);
    }
    return ResponseBody.fromBytes(const [], 405);
  }

  @override
  void close({bool force = false}) {}
}

Future<void> _seed(AppDatabase db, {String itemName = _itemName}) async {
  final now = DateTime(2026);
  await db
      .into(db.properties)
      .insertOnConflictUpdate(
        PropertiesCompanion.insert(
          id: 'p1',
          name: 'Home',
          createdAt: now,
          modifiedAt: now,
        ),
      );
  await db
      .into(db.rooms)
      .insertOnConflictUpdate(
        RoomsCompanion.insert(
          id: 'r1',
          propertyId: 'p1',
          name: _roomName,
          createdAt: now,
          modifiedAt: now,
        ),
      );
  await db
      .into(db.categories)
      .insertOnConflictUpdate(
        CategoriesCompanion.insert(
          id: 'c1',
          name: 'Optics',
          createdAt: now,
          modifiedAt: now,
        ),
      );
  await db
      .into(db.items)
      .insertOnConflictUpdate(
        ItemsCompanion.insert(
          id: 'item_1',
          name: itemName,
          categoryId: 'c1',
          roomId: 'r1',
          createdAt: now,
          modifiedAt: now,
          currentValueCents: const Value(_valueCents),
        ),
      );
}

/// The household's records sealed as the encrypted backup seals them,
/// under [key].
Future<Uint8List> _sealedUnder(Uint8List key) async {
  final src = AppDatabase.memory();
  addTearDown(src.close);
  await _seed(src);
  final repo = BackupRepository(
    StillLifeBackupSerializer(
      exportService: JsonExportService(src),
      importService: ImportService(src, photoRootResolver: () async => null),
    ),
    EnvelopeCipher(),
    aadContext: 'stilllife-backup/v1',
  );
  return repo.export(key);
}

/// The plain JSON export an older Still Life put on the server.
Future<Uint8List> _oldPlainFile() async {
  final src = AppDatabase.memory();
  addTearDown(src.close);
  await _seed(src);
  return Uint8List.fromList(
    utf8.encode(await JsonExportService(src).exportToJson()),
  );
}

bool _contains(Uint8List haystack, String needle) {
  final n = utf8.encode(needle);
  outer:
  for (var i = 0; i + n.length <= haystack.length; i++) {
    for (var j = 0; j < n.length; j++) {
      if (haystack[i + j] != n[j]) continue outer;
    }
    return true;
  }
  return false;
}

void main() {
  ensureSqlite3();

  late AppDatabase db;
  late _FakeDavServer server;
  late InMemoryVaultStore vault;

  setUp(() async {
    db = AppDatabase.memory();
    server = _FakeDavServer();
    vault = InMemoryVaultStore();
    FlutterSecureStorage.setMockInitialValues({
      'webdav_url': 'https://dav.example.test/still-life.ohbk',
      'webdav_user': 'household',
      'webdav_pass': 'made-up-password',
    });
    await _seed(db);
  });

  tearDown(() => db.close());

  Future<void> pumpScreen(
    WidgetTester tester, {
    SecureKeyStore? keyStore,
    CryptoService? crypto,
  }) async {
    // Tall enough that the list builds every button.
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dio = Dio()..httpClientAdapter = server;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // StillLife's wiring without its key store: the test brings its
          // own, and riverpod 3 refuses two overrides of one provider.
          ...sanctuaryBackupOverrides(web: false, appKeyStore: false),
          databaseProvider.overrideWithValue(db),
          syncStampProvider.overrideWithValue(SyncStamp.none),
          secureKeyStoreProvider.overrideWithValue(
            keyStore ??
                InMemorySecureKeyStore(mnemonic: _phrase, acknowledged: true),
          ),
          cryptoServiceProvider.overrideWithValue(
            crypto ?? _PhraseKeyedCryptoService(),
          ),
          vaultStoreProvider.overrideWithValue(vault),
          // path_provider never answers inside a widget test.
          importServiceProvider.overrideWith(
            (ref) => ImportService(
              ref.watch(databaseProvider),
              photoRootResolver: () async => null,
            ),
          ),
          webDavServiceProvider.overrideWithValue(
            WebDavBackupService(dio: dio),
          ),
        ],
        child: const MaterialApp(home: WebDavSettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapButton(WidgetTester tester, String label) async {
    // A message from the last action must not cover the next button.
    ScaffoldMessenger.of(
      tester.element(find.byType(WebDavSettingsScreen)),
    ).removeCurrentSnackBar();
    await tester.pumpAndSettle();
    final button = find.text(label);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  Future<String?> itemName() async =>
      (await db.select(db.items).getSingleOrNull())?.name;

  group('Back Up Now', () {
    testWidgets(
      'sends the OHBK envelope the encrypted backup makes, with no plain '
      'item, room or value in it',
      (tester) async {
        await pumpScreen(tester);
        await tapButton(tester, 'Back Up Now');

        final sent = server.stored;
        expect(sent, isNotNull, reason: 'the upload must reach the server');

        // The OHBK v2 header: magic, version 2, ChaCha20-Poly1305.
        expect(sent!.sublist(0, 6), [0x4F, 0x48, 0x42, 0x4B, 0x02, 0x01]);

        expect(_contains(sent, _itemName), isFalse);
        expect(_contains(sent, _roomName), isFalse);
        expect(_contains(sent, _valueOnWire), isFalse);
        expect(_contains(sent, '"app"'), isFalse);

        // Same key and same AAD binding as the encrypted backup: the main
        // backup's own reader opens it with the recovery-words key.
        final container = ProviderScope.containerOf(
          tester.element(find.byType(WebDavSettingsScreen)),
        );
        final plain = await container
            .read(backupRepositoryProvider)
            .open(sent, _deviceKey);
        expect(utf8.decode(plain), contains(_itemName));

        // Bound to StillLife's backup context: another context refuses it.
        await expectLater(
          GhostBackup.import(
            sent,
            _deviceKey,
            EnvelopeCipher(),
            context: defaultGhostBackupContext,
          ),
          throwsA(isA<CryptoException>()),
        );

        expect(find.text('Encrypted backup sent to your server.'), findsOne);
      },
    );

    testWidgets('without recovery words it sends nothing and says why', (
      tester,
    ) async {
      await pumpScreen(tester, keyStore: InMemorySecureKeyStore());
      await tapButton(tester, 'Back Up Now');

      expect(server.puts, 0);
      expect(find.text(webDavNeedsWordsMessage), findsOneWidget);
    });
  });

  group('Restore from WebDAV', () {
    testWidgets('a download made by Back Up Now restores the data', (
      tester,
    ) async {
      await pumpScreen(tester);
      await tapButton(tester, 'Back Up Now');

      // The household changes the item after the backup.
      await _seed(db, itemName: 'Renamed');
      expect(await itemName(), 'Renamed');

      await tapButton(tester, 'Restore from WebDAV');
      // The encrypted backup's own preview and confirm.
      expect(find.text('Merge backup into this device?'), findsOneWidget);
      await tester.tap(find.text('Merge backup'));
      await tester.pumpAndSettle();

      expect(await itemName(), _itemName);
      expect(find.text('Data restored successfully.'), findsOneWidget);
    });

    testWidgets('with the wrong words it fails plainly and writes nothing', (
      tester,
    ) async {
      server.stored = await _sealedUnder(_otherKey);
      await _seed(db, itemName: 'Kept as is');

      await pumpScreen(tester);
      await tapButton(tester, 'Restore from WebDAV');

      // This device's key does not open it, so the words are asked for.
      expect(find.textContaining('different set of words'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, _phrase);
      await tester.pump();
      await tester.tap(find.text('Restore').last);
      await tester.pumpAndSettle();

      expect(find.textContaining("Those words didn't unlock"), findsOneWidget);
      expect(await itemName(), 'Kept as is');
      expect(await vault.list(), isEmpty, reason: 'no snapshot, no write');
    });

    testWidgets(
      'on a device without recovery words, wrong words fail plainly, write '
      'nothing and are not kept',
      (tester) async {
        server.stored = await _sealedUnder(_deviceKey);
        await _seed(db, itemName: 'Kept as is');
        final keyStore = InMemorySecureKeyStore();

        await pumpScreen(tester, keyStore: keyStore);
        await tapButton(tester, 'Restore from WebDAV');

        await tester.enterText(find.byType(TextField).last, _otherPhrase);
        await tester.pump();
        await tester.tap(find.text('Restore').last);
        await tester.pumpAndSettle();

        expect(
          find.textContaining("Those words didn't unlock"),
          findsOneWidget,
        );
        expect(await itemName(), 'Kept as is');
        expect(await vault.list(), isEmpty);
        expect(await keyStore.readMnemonic(), isNull);
      },
    );

    testWidgets(
      'an old plain backup on the server is refused by name and writes '
      'nothing',
      (tester) async {
        server.stored = await _oldPlainFile();
        await _seed(db, itemName: 'Kept as is');

        await pumpScreen(tester);
        await tapButton(tester, 'Restore from WebDAV');

        expect(find.text(webDavOldPlainFileMessage), findsOneWidget);
        expect(find.text('Merge backup into this device?'), findsNothing);
        expect(await itemName(), 'Kept as is');
        expect(await vault.list(), isEmpty);
      },
    );
  });

  group('the words', () {
    testWidgets('the screen says what leaves the phone and what the server '
        'sees', (tester) async {
      await pumpScreen(tester);
      expect(find.text(webDavWhatLeavesText), findsOneWidget);
    });

    test('the screen words are plain', () {
      expect(
        webDavWhatLeavesText,
        'Still Life locks your inventory with your recovery words before it '
        'leaves this phone, the same way as the encrypted backup. Your server '
        'stores a file it cannot read. It can still see the file size, when '
        'it changed, and your login. Photos are not included.',
      );
      expect(
        webDavOldPlainFileMessage,
        'The file on your server is an old unencrypted backup, so Still Life '
        'will not restore it from here. Tap Back Up Now to replace it with an '
        'encrypted one. To bring the old file in, download it and use Import '
        'Data in Settings.',
      );
      expect(
        webDavNeedsWordsMessage,
        'Set up encrypted backup in Settings first. The WebDAV backup is '
        'locked with the same recovery words.',
      );
    });

    test('the privacy model says the WebDAV copy is encrypted', () {
      final doc = File('docs/privacy-model.md').readAsStringSync();
      expect(doc, isNot(contains('WebDAV backup is an unencrypted')));
      expect(
        doc,
        contains(
          'The WebDAV backup is the same encrypted records backup (`.ohbk`), '
          'locked with your recovery words before it leaves the phone.',
        ),
      );
    });

    test('no em dashes in the WebDAV words', () {
      for (final words in [
        webDavWhatLeavesText,
        webDavOldPlainFileMessage,
        webDavNeedsWordsMessage,
      ]) {
        expect(words, isNot(contains('—')), reason: 'no em dashes');
      }
    });
  });
}
