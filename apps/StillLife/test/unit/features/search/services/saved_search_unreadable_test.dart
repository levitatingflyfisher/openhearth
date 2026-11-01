import 'package:clock/clock.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:still_life/features/search/data/services/saved_search_service.dart';

class _FakeStorage extends Fake implements FlutterSecureStorage {
  final Map<String, String> data = {};

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => data[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      data.remove(key);
    } else {
      data[key] = value;
    }
  }
}

// Reading a list we cannot parse used to return empty, and the next save
// wrote its one new search over the old text, so what could have been
// recovered was gone. The rule: move it aside under a dated name, start
// fresh, never delete.
void main() {
  test('an unreadable list is kept under a dated name, not overwritten', () async {
    final storage = _FakeStorage()..data['saved_searches_v1'] = '[{"label": "cam';
    final service = SavedSearchService(storage: storage);

    await withClock(Clock.fixed(DateTime(2026, 11, 10, 9, 30, 5)), () async {
      expect(await service.load(), isEmpty);
      await service.save(const SavedSearch(label: 'tv', query: 'tv'));
    });

    expect(
      storage.data['saved_searches_v1.unreadable-20261110T093005'],
      '[{"label": "cam',
    );
    expect((await service.load()).map((s) => s.label), ['tv']);
  });

  test('a readable list is not moved', () async {
    final storage = _FakeStorage();
    final service = SavedSearchService(storage: storage);
    await service.save(const SavedSearch(label: 'tv', query: 'tv'));
    await service.load();
    expect(storage.data.keys, ['saved_searches_v1']);
  });

  test('a list of the wrong shape is kept aside too', () async {
    final storage = _FakeStorage()..data['saved_searches_v1'] = '{"a": 1}';
    final service = SavedSearchService(storage: storage);
    await withClock(Clock.fixed(DateTime(2026, 11, 10, 9, 30, 5)), () async {
      expect(await service.load(), isEmpty);
    });
    expect(
      storage.data['saved_searches_v1.unreadable-20261110T093005'],
      '{"a": 1}',
    );
    expect(storage.data.containsKey('saved_searches_v1'), isFalse);
  });
}
