import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanctuary_auth_core/sanctuary_auth_core.dart';

import 'package:hatch/core/providers/core_providers.dart';
import 'package:hatch/core/storage/app_database.dart';
import 'package:hatch/main.dart';

/// Hatch's backup overrides, over an in-memory database. Without it the
/// shared key store's vault check opens the real database, which reaches for
/// path_provider and fails whenever that open lands before the test ends.
ProviderContainer _container({required bool web}) {
  final db = AppDatabase(NativeDatabase.memory());
  final container = ProviderContainer(overrides: [
    appDatabaseProvider.overrideWithValue(db),
    ...hatchBackupOverrides(web: web),
  ]);
  addTearDown(db.close);
  addTearDown(container.dispose);
  return container;
}

/// On the web every fleet app is served from one origin, and the key store
/// is that origin's localStorage. Hatch's recovery words must sit under
/// Hatch's own name, or another app in the same browser can overwrite them
/// or read them.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  late Map<String, String> store;
  late List<String> writes;
  late List<String> deletes;

  setUp(() {
    store = {};
    writes = [];
    deletes = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final args = (call.arguments as Map).cast<String, Object?>();
      final key = args['key'] as String?;
      switch (call.method) {
        case 'read':
          return store[key];
        case 'write':
          writes.add(key!);
          store[key] = args['value'] as String;
          return null;
        case 'delete':
          deletes.add(key!);
          store.remove(key);
          return null;
        case 'containsKey':
          return store.containsKey(key);
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('on the web, Hatch keeps its recovery words under its own name',
      () async {
    final container = _container(web: true);

    await container.read(secureKeyStoreProvider).writeMnemonic('words');
    await container.read(secureKeyStoreProvider).writeSeedAcknowledged();

    expect(writes, ['oh_hatch_mnemonic_v1', 'oh_hatch_seed_ack_v1']);
    expect(store.containsKey('oh_mnemonic_v1'), isFalse);
  });

  test('words under the old shared name are never written or deleted',
      () async {
    store['oh_mnemonic_v1'] = 'another app may own these';
    store['oh_seed_ack_v1'] = 'true';
    final container = _container(web: true);
    final keys = container.read(secureKeyStoreProvider);

    // No snapshot in Hatch's vault opens under them, so they are not
    // proved to be Hatch's and are not taken.
    expect(await keys.readMnemonic(), isNull);
    await keys.writeMnemonic('hatch words');
    await keys.clearAuth();

    expect(store['oh_mnemonic_v1'], 'another app may own these');
    expect(store['oh_seed_ack_v1'], 'true');
    expect(writes, isNot(contains('oh_mnemonic_v1')));
    expect(deletes, isNot(contains('oh_mnemonic_v1')));
  });

  test('on a phone, the key store is the platform keychain as before',
      () {
    final container = _container(web: false);

    expect(container.read(secureKeyStoreProvider),
        isA<FlutterSecureKeyStore>());
  });
}
