import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/errors/failures.dart';
import '../../core/errors/result.dart';

class WebDavConfig {
  final String url;
  final String? username;
  final String? password;

  const WebDavConfig({required this.url, this.username, this.password});
}

/// Moves the encrypted records backup to and from a WebDAV server.
///
/// This class only carries bytes. The sealing is the encrypted backup's own
/// (see `webdav_backup_flow.dart`), and [backup] refuses anything that does
/// not start with the OHBK header, so a plain export cannot be sent by
/// mistake. Uses Dio with Basic Auth. The file is stored at the URL exactly
/// as supplied, for example
/// `https://nextcloud.example.com/remote.php/dav/files/alice/still-life.ohbk`.
class WebDavBackupService {
  /// The OHBK header: magic "OHBK", version 2, ChaCha20-Poly1305. Every blob
  /// the encrypted backup writes today starts with these six bytes.
  static const ohbkHeader = [0x4F, 0x48, 0x42, 0x4B, 0x02, 0x01];

  /// Whether [bytes] start with [ohbkHeader].
  static bool isSealed(List<int> bytes) {
    if (bytes.length < ohbkHeader.length) return false;
    for (var i = 0; i < ohbkHeader.length; i++) {
      if (bytes[i] != ohbkHeader[i]) return false;
    }
    return true;
  }

  static const _urlKey = 'webdav_url';
  static const _userKey = 'webdav_user';
  static const _passKey = 'webdav_pass';

  final Dio _dio;
  final FlutterSecureStorage _storage;

  WebDavBackupService({Dio? dio, FlutterSecureStorage? storage})
    : _dio = dio ?? Dio(),
      _storage = storage ?? const FlutterSecureStorage();

  // ── Config persistence ───────────────────────────────────────────────────

  Future<WebDavConfig?> loadConfig() async {
    final url = await _storage.read(key: _urlKey);
    if (url == null || url.isEmpty) return null;
    return WebDavConfig(
      url: url,
      username: await _storage.read(key: _userKey),
      password: await _storage.read(key: _passKey),
    );
  }

  Future<void> saveConfig(WebDavConfig config) async {
    await _storage.write(key: _urlKey, value: config.url);
    await _storage.write(key: _userKey, value: config.username ?? '');
    await _storage.write(key: _passKey, value: config.password ?? '');
  }

  Future<void> clearConfig() async {
    await _storage.delete(key: _urlKey);
    await _storage.delete(key: _userKey);
    await _storage.delete(key: _passKey);
  }

  // ── Backup / Restore ─────────────────────────────────────────────────────

  /// PUT the [sealed] backup to the configured WebDAV URL.
  ///
  /// Returns [Err] with [SecurityFailure], before any request, if [sealed]
  /// is not an OHBK envelope (the household's data must never reach the
  /// server readable) or if the URL is not HTTPS (Basic Auth over plain
  /// HTTP would leak the login). Throws [StateError] if WebDAV is not
  /// configured.
  Future<Result<void>> backup(Uint8List sealed) async {
    final cfg = await loadConfig();
    if (cfg == null) throw StateError('WebDAV not configured');

    if (!isSealed(sealed)) {
      return const Err(
        SecurityFailure('Refused to send a backup that is not encrypted.'),
      );
    }

    if (!cfg.url.startsWith('https://')) {
      final scheme = cfg.url.contains('://')
          ? cfg.url.split('://').first
          : 'unknown';
      return Err(SecurityFailure('WebDAV URL must use HTTPS (got $scheme).'));
    }

    await _dio.put<void>(
      cfg.url,
      data: Stream.fromIterable([sealed]),
      options: Options(
        headers: {
          'Content-Type': 'application/octet-stream',
          Headers.contentLengthHeader: sealed.length,
          if (cfg.username != null && cfg.username!.isNotEmpty)
            'Authorization': _basicAuth(cfg.username!, cfg.password ?? ''),
        },
        sendTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
      ),
    );
    return const Success(null);
  }

  /// GET the stored backup's bytes from the configured WebDAV URL. They are
  /// returned as they are: opening them is the encrypted backup's job.
  ///
  /// Returns [Err] with [SecurityFailure] if the configured URL is not
  /// HTTPS. Throws [StateError] if WebDAV is not configured or the server
  /// returns an empty body.
  Future<Result<Uint8List>> restore() async {
    final cfg = await loadConfig();
    if (cfg == null) throw StateError('WebDAV not configured');

    if (!cfg.url.startsWith('https://')) {
      final scheme = cfg.url.contains('://')
          ? cfg.url.split('://').first
          : 'unknown';
      return Err(SecurityFailure('WebDAV URL must use HTTPS (got $scheme).'));
    }

    final response = await _dio.get<List<int>>(
      cfg.url,
      options: Options(
        responseType: ResponseType.bytes,
        headers: {
          if (cfg.username != null && cfg.username!.isNotEmpty)
            'Authorization': _basicAuth(cfg.username!, cfg.password ?? ''),
        },
        receiveTimeout: const Duration(seconds: 30),
      ),
    );
    final data = response.data;
    if (data == null) throw StateError('Empty response from server');
    return Success(Uint8List.fromList(data));
  }

  String _basicAuth(String user, String pass) {
    final encoded = base64Encode(utf8.encode('$user:$pass'));
    return 'Basic $encoded';
  }
}
