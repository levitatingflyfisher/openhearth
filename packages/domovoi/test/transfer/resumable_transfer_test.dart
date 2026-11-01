import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
// Direct src import: the barrel exports the STOVE area, which is built by
// another owner and may not exist while CORE is under test.
import 'package:domovoi/src/transfer/resumable_transfer.dart';
import 'package:test/test.dart';

/// Deterministic body — every byte position provable after any resume.
final body = List<int>.generate(4096, (i) => i % 251);

void main() {
  late Directory tmp;
  late File partFile;
  late Dio dio;
  late int promoteCalls;
  HttpServer? server;

  Future<void> promote() async => promoteCalls++;

  String urlOf(HttpServer s) => 'http://127.0.0.1:${s.port}/model.task';

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('domovoi_transfer_');
    partFile = File('${tmp.path}/model.task.part');
    dio = Dio();
    promoteCalls = 0;
  });

  tearDown(() async {
    await server?.close(force: true);
    server = null;
    dio.close(force: true);
    await tmp.delete(recursive: true);
  });

  group('resumableDownload', () {
    test('fresh download sends no Range, promotes exactly once', () async {
      final rangeHeaders = <String?>[];
      final progress = <(int, int?)>[];
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server!.listen((req) async {
        rangeHeaders.add(req.headers.value(HttpHeaders.rangeHeader));
        req.response
          ..statusCode = HttpStatus.ok
          ..contentLength = body.length
          ..add(body);
        await req.response.close();
      });

      await resumableDownload(
        dio: dio,
        url: urlOf(server!),
        partFile: partFile,
        promote: promote,
        onProgress: (received, total) => progress.add((received, total)),
      );

      expect(rangeHeaders, [null]);
      expect(promoteCalls, 1);
      expect(await partFile.readAsBytes(), body);
      expect(progress.last, (body.length, body.length));
    });

    test('resume sends Range from the .part byte offset and completes',
        () async {
      const already = 1000;
      await partFile.writeAsBytes(body.sublist(0, already));
      File('${partFile.path}.validator').writeAsStringSync('"v1"');
      final rangeHeaders = <String?>[];
      final progress = <(int, int?)>[];
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server!.listen((req) async {
        rangeHeaders.add(req.headers.value(HttpHeaders.rangeHeader));
        final rest = body.sublist(already);
        req.response
          ..statusCode = HttpStatus.partialContent
          ..contentLength = rest.length
          ..headers.set(HttpHeaders.contentRangeHeader,
              'bytes $already-${body.length - 1}/${body.length}')
          ..add(rest);
        await req.response.close();
      });

      await resumableDownload(
        dio: dio,
        url: urlOf(server!),
        partFile: partFile,
        promote: promote,
        onProgress: (received, total) => progress.add((received, total)),
      );

      expect(rangeHeaders, ['bytes=$already-']);
      expect(promoteCalls, 1);
      expect(await partFile.readAsBytes(), body);
      // Progress is offset to track the WHOLE file, not just this request.
      expect(progress.last, (body.length, body.length));
      expect(progress.first.$1, greaterThanOrEqualTo(already));
    });

    test('cancel mid-flight is quiet, leaves the .part, never promotes',
        () async {
      final gate = Completer<void>();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server!.listen((req) async {
        req.response
          // dart:io buffers ~8KB by default; the first chunk must actually
          // reach the wire or the client never sees mid-flight progress.
          ..bufferOutput = false
          ..statusCode = HttpStatus.ok
          ..contentLength = body.length
          ..add(body.sublist(0, 1024));
        await req.response.flush();
        try {
          await gate.future;
          await req.response.close();
        } catch (_) {}
      });
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });

      final cancelToken = CancelToken();
      final future = resumableDownload(
        dio: dio,
        url: urlOf(server!),
        partFile: partFile,
        promote: promote,
        cancelToken: cancelToken,
        onProgress: (received, total) {
          if (!cancelToken.isCancelled) cancelToken.cancel();
        },
      );

      // Quiet: completes normally, no error surfaces.
      await future;
      expect(promoteCalls, 0);
      expect(partFile.existsSync(), isTrue);
      expect(partFile.lengthSync(), lessThan(body.length));
    });

    test('a finished run reports the completed outcome', () async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server!.listen((req) async {
        req.response
          ..statusCode = HttpStatus.ok
          ..contentLength = body.length
          ..add(body);
        await req.response.close();
      });

      final outcome = await resumableDownload(
        dio: dio,
        url: urlOf(server!),
        partFile: partFile,
        promote: promote,
      );

      expect(outcome, TransferOutcome.completed);
      expect(promoteCalls, 1);
    });

    test('a cancelled run reports the cancelled outcome, .part intact',
        () async {
      final gate = Completer<void>();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server!.listen((req) async {
        req.response
          ..bufferOutput = false
          ..statusCode = HttpStatus.ok
          ..contentLength = body.length
          ..add(body.sublist(0, 1024));
        await req.response.flush();
        try {
          await gate.future;
          await req.response.close();
        } catch (_) {}
      });
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });

      final cancelToken = CancelToken();
      final outcome = await resumableDownload(
        dio: dio,
        url: urlOf(server!),
        partFile: partFile,
        promote: promote,
        cancelToken: cancelToken,
        onProgress: (received, total) {
          if (!cancelToken.isCancelled) cancelToken.cancel();
        },
      );

      // Awaiting alone used to say nothing: a caller that announced
      // "installed" here would be announcing a half file it never installed.
      expect(outcome, TransferOutcome.cancelled);
      expect(promoteCalls, 0);
      // Resume depends on the partial surviving.
      expect(partFile.existsSync(), isTrue);
      expect(partFile.lengthSync(), lessThan(body.length));
    });

    test('a 200 answering a resume discards the partial and restarts clean',
        () async {
      // Stale bytes that must NOT survive: a host that ignores Range would
      // otherwise have them appended under the real payload.
      await partFile.writeAsBytes(List<int>.filled(1000, 0xFF));
      File('${partFile.path}.validator').writeAsStringSync('"v1"');
      final rangeHeaders = <String?>[];
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server!.listen((req) async {
        rangeHeaders.add(req.headers.value(HttpHeaders.rangeHeader));
        req.response
          ..statusCode = HttpStatus.ok
          ..contentLength = body.length
          ..add(body);
        await req.response.close();
      });

      await resumableDownload(
        dio: dio,
        url: urlOf(server!),
        partFile: partFile,
        promote: promote,
      );

      // The whole body answered the resume, so it is written in place —
      // one request, no second download.
      expect(rangeHeaders, ['bytes=1000-']);
      expect(promoteCalls, 1);
      expect(await partFile.readAsBytes(), body);
    });

    test('a 416 answering a resume discards the partial and restarts clean',
        () async {
      await partFile.writeAsBytes(List<int>.filled(5000, 0xFF));
      File('${partFile.path}.validator').writeAsStringSync('"v1"');
      final rangeHeaders = <String?>[];
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server!.listen((req) async {
        final range = req.headers.value(HttpHeaders.rangeHeader);
        rangeHeaders.add(range);
        if (range != null) {
          req.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          await req.response.close();
          return;
        }
        req.response
          ..statusCode = HttpStatus.ok
          ..contentLength = body.length
          ..add(body);
        await req.response.close();
      });

      await resumableDownload(
        dio: dio,
        url: urlOf(server!),
        partFile: partFile,
        promote: promote,
      );

      expect(rangeHeaders, ['bytes=5000-', null]);
      expect(promoteCalls, 1);
      expect(await partFile.readAsBytes(), body);
    });

    test('a server omitting Content-Length reports null totals', () async {
      final totals = <int?>[];
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server!.listen((req) async {
        // No contentLength set: dart:io answers chunked, dio sees -1.
        req.response
          ..statusCode = HttpStatus.ok
          ..add(body);
        await req.response.close();
      });

      await resumableDownload(
        dio: dio,
        url: urlOf(server!),
        partFile: partFile,
        promote: promote,
        onProgress: (received, total) => totals.add(total),
      );

      expect(totals, isNotEmpty);
      expect(totals, everyElement(isNull));
      expect(await partFile.readAsBytes(), body);
      expect(promoteCalls, 1);
    });

    test('a transfer error surfaces, keeps the .part, never promotes',
        () async {
      final stale = List<int>.filled(1000, 0x42);
      await partFile.writeAsBytes(stale);
      File('${partFile.path}.validator').writeAsStringSync('"v1"');
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server!.listen((req) async {
        req.response.statusCode = HttpStatus.internalServerError;
        await req.response.close();
      });

      await expectLater(
        resumableDownload(
          dio: dio,
          url: urlOf(server!),
          partFile: partFile,
          promote: promote,
        ),
        throwsA(isA<DioException>()),
      );
      expect(promoteCalls, 0);
      // The partial is deliberately KEPT so the next attempt resumes.
      expect(await partFile.readAsBytes(), stale);
    });

    test('a promotion error surfaces to the caller', () async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server!.listen((req) async {
        req.response
          ..statusCode = HttpStatus.ok
          ..contentLength = body.length
          ..add(body);
        await req.response.close();
      });

      await expectLater(
        resumableDownload(
          dio: dio,
          url: urlOf(server!),
          partFile: partFile,
          promote: () async => throw StateError('sha mismatch'),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('same-file resumes', () {
    /// Serves [body] honouring Range only while its ETag matches If-Range,
    /// like a real host; [etag] can change between requests.
    Future<List<Map<String, String?>>> serve(
        {required String Function() etag, int? cutAfter}) async {
      final seen = <Map<String, String?>>[];
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server!.listen((req) async {
        final range = req.headers.value(HttpHeaders.rangeHeader);
        final ifRange = req.headers.value('if-range');
        seen.add({'range': range, 'if-range': ifRange});
        final current = etag();
        req.response.headers.set(HttpHeaders.etagHeader, current);
        if (range != null && ifRange == current) {
          final from = int.parse(range.substring(6, range.length - 1));
          req.response
            ..statusCode = HttpStatus.partialContent
            ..headers.set(HttpHeaders.contentRangeHeader,
                'bytes $from-${body.length - 1}/${body.length}')
            ..contentLength = body.length - from
            ..add(body.sublist(from));
        } else {
          req.response
            ..statusCode = HttpStatus.ok
            ..contentLength = body.length;
          if (cutAfter != null) {
            final socket = await req.response.detachSocket();
            socket.add(body.sublist(0, cutAfter));
            await socket.flush();
            socket.destroy();
            return;
          }
          req.response.add(body);
        }
        await req.response.close();
      });
      return seen;
    }

    test('a partial in a folder that does not exist yet still downloads',
        () async {
      partFile = File('${tmp.path}/nested/dir/model.task.part');
      await serve(etag: () => '"v1"');

      await resumableDownload(
          dio: dio, url: urlOf(server!), partFile: partFile, promote: promote);

      expect(await partFile.readAsBytes(), body);
    });

    test('a promote that discards the partial takes the validator with it',
        () async {
      await serve(etag: () => '"v1"');

      await expectLater(
        resumableDownload(
          dio: dio,
          url: urlOf(server!),
          partFile: partFile,
          promote: () async {
            await partFile.delete();
            throw StateError('sha mismatch');
          },
        ),
        throwsA(isA<StateError>()),
      );
      expect(File('${partFile.path}.validator').existsSync(), isFalse);
    });

    test('a resume sends the saved validator and continues the same file',
        () async {
      await partFile.writeAsBytes(body.sublist(0, 1000));
      File('${partFile.path}.validator').writeAsStringSync('"v1"');
      final seen = await serve(etag: () => '"v1"');

      await resumableDownload(
          dio: dio, url: urlOf(server!), partFile: partFile, promote: promote);

      expect(seen.single, {'range': 'bytes=1000-', 'if-range': '"v1"'});
      expect(await partFile.readAsBytes(), body);
      expect(File('${partFile.path}.validator').existsSync(), isFalse);
    });

    test('a file that changed since the partial restarts instead of splicing',
        () async {
      // Old bytes from a previous version of the enclosure.
      await partFile.writeAsBytes(List<int>.filled(1000, 0xEE));
      File('${partFile.path}.validator').writeAsStringSync('"old"');
      final seen = await serve(etag: () => '"new"');

      await resumableDownload(
          dio: dio, url: urlOf(server!), partFile: partFile, promote: promote);

      expect(seen, hasLength(1));
      expect(await partFile.readAsBytes(), body);
      expect(promoteCalls, 1);
    });

    test('a partial with no saved validator resumes without If-Range',
        () async {
      await partFile.writeAsBytes(body.sublist(0, 1000));
      final seen = await serve(etag: () => '"v1"');

      await resumableDownload(
          dio: dio, url: urlOf(server!), partFile: partFile, promote: promote);

      // No If-Range, so this host answers with the whole file; it is
      // written in place rather than spliced.
      expect(seen.single, {'range': 'bytes=1000-', 'if-range': null});
      expect(await partFile.readAsBytes(), body);
    });

    test('a body cut short is never promoted', () async {
      await serve(etag: () => '"v1"', cutAfter: 1500);

      await expectLater(
        resumableDownload(
            dio: dio,
            url: urlOf(server!),
            partFile: partFile,
            promote: promote),
        throwsA(anything),
      );
      expect(promoteCalls, 0);
    });

    test('an interrupted first attempt keeps its validator for the resume',
        () async {
      var n = 0;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final seen = <String?>[];
      server!.listen((req) async {
        seen.add(req.headers.value('if-range'));
        req.response.headers.set(HttpHeaders.etagHeader, '"v1"');
        if (n++ == 0) {
          req.response
            ..statusCode = HttpStatus.ok
            ..contentLength = body.length;
          final socket = await req.response.detachSocket();
          socket.add(body.sublist(0, 1500));
          await socket.flush();
          socket.destroy();
          return;
        }
        final range = req.headers.value(HttpHeaders.rangeHeader)!;
        final from = int.parse(range.substring(6, range.length - 1));
        req.response
          ..statusCode = HttpStatus.partialContent
          ..headers.set(HttpHeaders.contentRangeHeader,
              'bytes $from-${body.length - 1}/${body.length}')
          ..contentLength = body.length - from
          ..add(body.sublist(from));
        await req.response.close();
      });

      try {
        await resumableDownload(
            dio: dio,
            url: urlOf(server!),
            partFile: partFile,
            promote: promote);
      } catch (_) {}
      expect(partFile.existsSync(), isTrue);

      await resumableDownload(
          dio: dio, url: urlOf(server!), partFile: partFile, promote: promote);
      expect(seen, [null, '"v1"']);
      expect(await partFile.readAsBytes(), body);
      expect(promoteCalls, 1);
    });
  });
}
