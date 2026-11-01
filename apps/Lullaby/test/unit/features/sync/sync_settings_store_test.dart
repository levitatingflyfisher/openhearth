import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lullaby/features/sync/data/sync_settings_store.dart';
import 'package:sanctuary_backup_ui/testing.dart';

void main() {
  final at = DateTime.utc(2026, 11, 10, 12);
  const key = SyncSettingsStore.key;
  final brokenKey = '${key}_broken_2026-11-10T12:00:00.000Z';

  SyncSettingsStore make(InMemorySecretStorage storage, [DateTime? when]) =>
      SyncSettingsStore(storage, clock: () => when ?? at);

  group('SyncSettingsStore.read on saved settings it cannot parse', () {
    test('moves them aside under a dated name and starts fresh', () async {
      const raw = '{"on":true,"relay":"https://relay.example/","la';
      final storage = InMemorySecretStorage({key: raw});

      final settings = await make(storage).read();

      expect(settings.on, isFalse);
      expect(settings.relay, isNull);
      expect(storage.values.containsKey(key), isFalse);
      expect(storage.values[brokenKey], raw);
    });

    test('treats valid JSON of the wrong shape the same way', () async {
      final storage = InMemorySecretStorage({key: '[1,2]'});

      await make(storage).read();

      expect(storage.values[brokenKey], '[1,2]');
    });

    test('the next save does not touch the copy', () async {
      const raw = 'not json';
      final storage = InMemorySecretStorage({key: raw});
      final store = make(storage);

      await store.read();
      await store.write(const SyncSettings(on: true, label: 'Kitchen phone'));

      expect(storage.values[brokenKey], raw);
      expect(jsonDecode(storage.values[key]!), containsPair('label', 'Kitchen phone'));
    });

    test('a second break on another date keeps both copies', () async {
      final storage = InMemorySecretStorage({key: 'first'});
      await make(storage).read();

      storage.values[key] = 'second';
      await make(storage, DateTime.utc(2026, 11, 11, 12)).read();

      expect(storage.values[brokenKey], 'first');
      expect(storage.values['${key}_broken_2026-11-11T12:00:00.000Z'], 'second');
    });
  });

  test('settings that parse are left where they are', () async {
    final raw = jsonEncode(const SyncSettings(on: true, label: 'Hall').toJson());
    final storage = InMemorySecretStorage({key: raw});

    final settings = await make(storage).read();

    expect(settings.label, 'Hall');
    expect(storage.values, {key: raw});
  });
}
