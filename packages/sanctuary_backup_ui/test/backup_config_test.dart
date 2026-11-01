import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';

/// The error a provider threw, as the test sees it. riverpod 3 wraps it in a
/// `ProviderException` (its `exception` field) when the provider is read;
/// riverpod 2 rethrows it as is. This package builds against both, and the
/// wrapper type is not exported from the same library in each.
Object _unwrapped(Object e) {
  try {
    // ignore: avoid_dynamic_calls
    return (e as dynamic).exception as Object;
  } on NoSuchMethodError {
    return e;
  }
}

void main() {
  group('throw-by-default providers give an actionable message', () {
    test('sanctuaryBackupConfigProvider names the override + where', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        () => container.read(sanctuaryBackupConfigProvider),
        throwsA(
          isA<Object>().having(
            _unwrapped,
            'the provider\'s own error',
            isA<UnimplementedError>().having(
              (e) => e.message,
              'message',
              allOf(
                contains('sanctuaryBackupConfigProvider'),
                contains('overrideWithValue'),
                contains('root ProviderScope'),
              ),
            ),
          ),
        ),
      );
    });

    test('backupSerializerProvider names the override + the interface', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        () => container.read(backupSerializerProvider),
        throwsA(
          isA<Object>().having(
            _unwrapped,
            'the provider\'s own error',
            isA<UnimplementedError>().having(
              (e) => e.message,
              'message',
              allOf(
                contains('backupSerializerProvider'),
                contains('overrideWith'),
                contains('BackupSerializer'),
              ),
            ),
          ),
        ),
      );
    });
  });
}
