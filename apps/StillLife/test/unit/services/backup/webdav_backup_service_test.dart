import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:still_life/core/errors/failures.dart';
import 'package:still_life/services/backup/webdav_backup_service.dart';

class MockDio extends Mock implements Dio {}

class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

class FakeOptions extends Fake implements Options {}

class FakeRequestOptions extends Fake implements RequestOptions {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(FakeOptions());
    registerFallbackValue(FakeRequestOptions());
  });

  late MockDio mockDio;
  late MockFlutterSecureStorage mockStorage;
  late WebDavBackupService service;

  const testUrl = 'https://cloud.example.com/dav/still-life.ohbk';

  /// The OHBK v2 header the encrypted backup starts with, then made-up
  /// sealed bytes. The service only checks the header.
  final sealed = Uint8List.fromList([
    0x4F, 0x48, 0x42, 0x4B, 0x02, 0x01, //
    ...List<int>.filled(40, 9),
  ]);
  final plainJson = Uint8List.fromList(utf8.encode('{"items":[]}'));
  const testUser = 'alice';
  const testPass = 's3cr3t';

  setUp(() {
    mockDio = MockDio();
    mockStorage = MockFlutterSecureStorage();
    service = WebDavBackupService(dio: mockDio, storage: mockStorage);
  });

  group('WebDavConfig persistence', () {
    test('loadConfig returns null when url is empty', () async {
      when(
        () => mockStorage.read(key: 'webdav_url'),
      ).thenAnswer((_) async => null);

      final cfg = await service.loadConfig();
      expect(cfg, isNull);
    });

    test('loadConfig returns config when url is set', () async {
      when(
        () => mockStorage.read(key: 'webdav_url'),
      ).thenAnswer((_) async => testUrl);
      when(
        () => mockStorage.read(key: 'webdav_user'),
      ).thenAnswer((_) async => testUser);
      when(
        () => mockStorage.read(key: 'webdav_pass'),
      ).thenAnswer((_) async => testPass);

      final cfg = await service.loadConfig();
      expect(cfg, isNotNull);
      expect(cfg!.url, testUrl);
      expect(cfg.username, testUser);
      expect(cfg.password, testPass);
    });

    test('saveConfig writes all fields to secure storage', () async {
      when(
        () => mockStorage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        ),
      ).thenAnswer((_) async {});

      await service.saveConfig(
        const WebDavConfig(
          url: testUrl,
          username: testUser,
          password: testPass,
        ),
      );

      verify(
        () => mockStorage.write(key: 'webdav_url', value: testUrl),
      ).called(1);
      verify(
        () => mockStorage.write(key: 'webdav_user', value: testUser),
      ).called(1);
      verify(
        () => mockStorage.write(key: 'webdav_pass', value: testPass),
      ).called(1);
    });

    test('saveConfig writes empty string for null username/password', () async {
      when(
        () => mockStorage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        ),
      ).thenAnswer((_) async {});

      await service.saveConfig(const WebDavConfig(url: testUrl));

      verify(() => mockStorage.write(key: 'webdav_user', value: '')).called(1);
      verify(() => mockStorage.write(key: 'webdav_pass', value: '')).called(1);
    });

    test('clearConfig deletes all keys', () async {
      when(
        () => mockStorage.delete(key: any(named: 'key')),
      ).thenAnswer((_) async {});

      await service.clearConfig();

      verify(() => mockStorage.delete(key: 'webdav_url')).called(1);
      verify(() => mockStorage.delete(key: 'webdav_user')).called(1);
      verify(() => mockStorage.delete(key: 'webdav_pass')).called(1);
    });
  });

  group('backup', () {
    setUp(() {
      when(
        () => mockStorage.read(key: 'webdav_url'),
      ).thenAnswer((_) async => testUrl);
      when(
        () => mockStorage.read(key: 'webdav_user'),
      ).thenAnswer((_) async => testUser);
      when(
        () => mockStorage.read(key: 'webdav_pass'),
      ).thenAnswer((_) async => testPass);
    });

    test('throws StateError when not configured', () async {
      when(
        () => mockStorage.read(key: 'webdav_url'),
      ).thenAnswer((_) async => null);

      expect(() => service.backup(sealed), throwsA(isA<StateError>()));
    });

    test('PUTs the sealed bytes to the configured URL with Basic Auth', () async {
      when(
        () => mockDio.put<void>(
          any(),
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => Response<void>(
          requestOptions: RequestOptions(path: testUrl),
          statusCode: 201,
        ),
      );

      final result = await service.backup(sealed);
      expect(result.isSuccess, isTrue);

      final captured = verify(
        () => mockDio.put<void>(
          captureAny(),
          data: any(named: 'data'),
          options: captureAny(named: 'options'),
        ),
      ).captured;

      expect(captured[0], testUrl);
      final opts = captured[1] as Options;
      final expectedAuth =
          'Basic ${base64Encode(utf8.encode('$testUser:$testPass'))}';
      expect(opts.headers?['Authorization'], expectedAuth);
      expect(opts.headers?['Content-Type'], 'application/octet-stream');
    });

    test('refuses anything that is not an OHBK envelope, before any request',
        () async {
      final result = await service.backup(plainJson);

      expect(result.isFailure, isTrue);
      expect(result.failure, isA<SecurityFailure>());
      verifyNever(
        () => mockDio.put<void>(
          any(),
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      );
    });
  });

  group('restore', () {
    setUp(() {
      when(
        () => mockStorage.read(key: 'webdav_url'),
      ).thenAnswer((_) async => testUrl);
      when(
        () => mockStorage.read(key: 'webdav_user'),
      ).thenAnswer((_) async => testUser);
      when(
        () => mockStorage.read(key: 'webdav_pass'),
      ).thenAnswer((_) async => testPass);
    });

    test('throws StateError when not configured', () async {
      when(
        () => mockStorage.read(key: 'webdav_url'),
      ).thenAnswer((_) async => null);

      expect(() => service.restore(), throwsA(isA<StateError>()));
    });

    test('GETs the bytes from the configured URL with Basic Auth', () async {
      when(
        () => mockDio.get<List<int>>(any(), options: any(named: 'options')),
      ).thenAnswer(
        (_) async => Response<List<int>>(
          requestOptions: RequestOptions(path: testUrl),
          data: sealed,
          statusCode: 200,
        ),
      );

      final result = await service.restore();
      expect(result.isSuccess, isTrue);
      expect(result.value, sealed);

      final captured = verify(
        () => mockDio.get<List<int>>(
          captureAny(),
          options: captureAny(named: 'options'),
        ),
      ).captured;

      expect(captured[0], testUrl);
      final opts = captured[1] as Options;
      final expectedAuth =
          'Basic ${base64Encode(utf8.encode('$testUser:$testPass'))}';
      expect(opts.headers?['Authorization'], expectedAuth);
      expect(opts.responseType, ResponseType.bytes);
    });

    test('throws StateError when response is null', () async {
      when(
        () => mockDio.get<List<int>>(any(), options: any(named: 'options')),
      ).thenAnswer(
        (_) async => Response<List<int>>(
          requestOptions: RequestOptions(path: testUrl),
          data: null,
          statusCode: 200,
        ),
      );

      expect(() => service.restore(), throwsA(isA<StateError>()));
    });
  });

  group('HTTPS enforcement', () {
    test('backup returns SecurityFailure for http:// URL', () async {
      when(
        () => mockStorage.read(key: 'webdav_url'),
      ).thenAnswer((_) async => 'http://plain.example.com/backup.json');
      when(
        () => mockStorage.read(key: 'webdav_user'),
      ).thenAnswer((_) async => testUser);
      when(
        () => mockStorage.read(key: 'webdav_pass'),
      ).thenAnswer((_) async => testPass);

      final result = await service.backup(sealed);

      expect(result.isFailure, isTrue);
      expect(result.failure, isA<SecurityFailure>());
      expect(result.failure.message, contains('HTTPS'));
      // Critically, Dio must not have been invoked (credentials not leaked).
      verifyNever(
        () => mockDio.put<void>(
          any(),
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      );
    });

    test('restore returns SecurityFailure for http:// URL', () async {
      when(
        () => mockStorage.read(key: 'webdav_url'),
      ).thenAnswer((_) async => 'http://plain.example.com/backup.json');
      when(
        () => mockStorage.read(key: 'webdav_user'),
      ).thenAnswer((_) async => testUser);
      when(
        () => mockStorage.read(key: 'webdav_pass'),
      ).thenAnswer((_) async => testPass);

      final result = await service.restore();

      expect(result.isFailure, isTrue);
      expect(result.failure, isA<SecurityFailure>());
      expect(result.failure.message, contains('HTTPS'));
      verifyNever(
        () => mockDio.get<List<int>>(any(), options: any(named: 'options')),
      );
    });

    test('backup returns SecurityFailure for non-URL schemes', () async {
      when(
        () => mockStorage.read(key: 'webdav_url'),
      ).thenAnswer((_) async => 'ftp://legacy.example.com/backup');
      when(
        () => mockStorage.read(key: 'webdav_user'),
      ).thenAnswer((_) async => testUser);
      when(
        () => mockStorage.read(key: 'webdav_pass'),
      ).thenAnswer((_) async => testPass);

      final result = await service.backup(sealed);

      expect(result.isFailure, isTrue);
      expect(result.failure, isA<SecurityFailure>());
    });
  });
}
