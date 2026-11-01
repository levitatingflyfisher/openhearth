import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

/// How a [resumableDownload] run ended.
///
/// A cancelled run also finishes without error — quietly stopping is not a
/// failure — so "no exception" alone never meant "installed". The two are
/// named apart here because a caller that cannot tell them apart will
/// eventually announce a half-file as a finished install.
enum TransferOutcome {
  /// The last byte arrived and `promote` ran: the artifact is installed.
  completed,

  /// The cancel token fired before the last byte. The partial is kept for
  /// Resume and `promote` never ran.
  cancelled,
}

/// The one resumable-transfer engine behind every big household download
/// (model bundles, data slices — native builds only; web surfaces keep
/// their own inert variants and never compile this file).
///
/// Transfers [url] into [partFile], reporting `(receivedBytes, totalBytes)`
/// through [onProgress] (total is `null` when the server omits
/// Content-Length).
///
/// Resumable: an interrupted attempt's partial is continued with an HTTP
/// Range request instead of restarting from zero (what kept happening
/// when a phone slept mid-download). The partial is deliberately KEPT on
/// error so the next attempt picks up where this one stopped.
///
/// A resume only ever continues the SAME bytes. The first response's
/// validator (a strong ETag, else Last-Modified) is kept beside the
/// partial in `<partFile>.validator` and sent back as `If-Range`; a host
/// whose file changed in between (dynamic ad insertion swaps podcast
/// enclosures between requests) then answers 200 with the whole new file
/// instead of a 206 tail of a different one. A partial with no saved
/// validator (a host that sends neither header) resumes on trust, as
/// before: the length check below and the caller's own hash in [promote]
/// are then the only guards.
/// A 200 to a resume (changed file, or a host that ignores Range)
/// rewrites the partial from the start; a 416 discards and restarts.
///
/// When the host announced a length (Content-Length, or the total in a
/// 206's Content-Range), the finished partial must be exactly that long:
/// a connection that closed cleanly but early is a [TruncatedTransfer],
/// the partial is discarded, and [promote] never runs.
///
/// After the last byte, [promote] runs the caller's own post-transfer
/// step (the model file's atomic rename; a slice's sha check + gunzip +
/// rename) before the future completes — so a caller that hears success
/// knows the artifact is fully installed. An error anywhere (transfer,
/// length check or promotion) reaches the caller as the future's error.
///
/// [cancelToken] is the pause button: cancelling it mid-transfer ends the
/// run quietly — the future completes normally with
/// [TransferOutcome.cancelled], the partial stays for Resume, and
/// [promote] never runs. If the transfer had already completed, the
/// promotion underway is allowed to finish and the run is
/// [TransferOutcome.completed] — the artifact is whole, installing it
/// loses nothing.
Future<TransferOutcome> resumableDownload({
  required Dio dio,
  required String url,
  required File partFile,
  required Future<void> Function() promote,
  CancelToken? cancelToken,
  void Function(int received, int? total)? onProgress,
}) async {
  final validatorFile = File('${partFile.path}.validator');
  try {
    final resumeFrom = partFile.existsSync() ? await partFile.length() : 0;
    final validator =
        validatorFile.existsSync() ? validatorFile.readAsStringSync() : '';

    int? expectedTotal;

    // dio hands the response headers to a savePath callback before it
    // opens the file — the one moment to learn what the host is actually
    // sending and to keep the validator even if the body is cut off.
    Future<Response<dynamic>> fetch({required bool ranged}) {
      final offset = ranged ? resumeFrom : 0;
      var base = offset;
      return dio.download(
        url,
        (Headers headers) {
          final total = _announcedTotal(headers);
          final partial = headers.value(HttpHeaders.contentRangeHeader) != null;
          if (offset > 0 && !partial) {
            // A whole body answered the resume: append mode must not glue
            // it onto the old bytes, so start the file over in place.
            partFile.writeAsBytesSync(const [], flush: true);
            base = 0;
          }
          expectedTotal = total;
          // dio creates the partial's folder only after this returns.
          validatorFile.parent.createSync(recursive: true);
          validatorFile.writeAsStringSync(_validatorOf(headers));
          return partFile.path;
        },
        options: Options(headers: {
          if (offset > 0) ...{
            HttpHeaders.rangeHeader: 'bytes=$offset-',
            if (validator.isNotEmpty) HttpHeaders.ifRangeHeader: validator,
          },
        }),
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          // dio reports progress relative to THIS request; offset it so
          // the caller tracks the whole file when resuming.
          onProgress?.call(base + received, total < 0 ? null : base + total);
        },
        // Keep the partial on error so a later attempt can resume.
        deleteOnError: false,
        fileAccessMode:
            offset > 0 ? FileAccessMode.append : FileAccessMode.write,
      );
    }

    try {
      await fetch(ranged: resumeFrom > 0);
    } on DioException catch (err) {
      if (resumeFrom > 0 &&
          err.response?.statusCode == HttpStatus.requestedRangeNotSatisfiable) {
        if (partFile.existsSync()) await partFile.delete();
        await fetch(ranged: false);
      } else {
        rethrow;
      }
    }

    final want = expectedTotal;
    if (want != null && await partFile.length() != want) {
      final got = await partFile.length();
      await partFile.delete();
      _forget(validatorFile);
      throw TruncatedTransfer(expected: want, received: got);
    }

    await promote();
    _forget(validatorFile);
    return TransferOutcome.completed;
  } on DioException catch (err) {
    // The caller's own cancel ends the run quietly: the kept partial is
    // the whole story, and promote never runs.
    if (err.type == DioExceptionType.cancel) return TransferOutcome.cancelled;
    rethrow;
  } finally {
    // The validator describes the partial; a caller's promote that threw
    // the partial away (failed hash) must not leave it behind.
    if (!partFile.existsSync()) _forget(validatorFile);
  }
}

/// The finished file was shorter (or longer) than the host announced.
class TruncatedTransfer implements Exception {
  /// A transfer that ended at [received] bytes of an announced [expected].
  const TruncatedTransfer({required this.expected, required this.received});

  /// The length the host announced.
  final int expected;

  /// The length that actually landed on disk.
  final int received;

  @override
  String toString() =>
      'TruncatedTransfer: expected $expected bytes, received $received';
}

/// The whole file's length: a 206's Content-Range total, else a 200's
/// Content-Length. Null when the host didn't say, or the body is
/// compressed in transit (Content-Length then counts wire bytes).
int? _announcedTotal(Headers headers) {
  final range = headers.value(HttpHeaders.contentRangeHeader);
  if (range != null) {
    final slash = range.lastIndexOf('/');
    return slash < 0 ? null : int.tryParse(range.substring(slash + 1));
  }
  final encoding = headers.value(HttpHeaders.contentEncodingHeader);
  if (encoding != null && encoding != 'identity') return null;
  return int.tryParse(headers.value(HttpHeaders.contentLengthHeader) ?? '');
}

/// If-Range accepts only a strong ETag or an HTTP date; a weak ETag
/// would make every resume restart, so fall through to Last-Modified.
String _validatorOf(Headers headers) {
  final etag = headers.value(HttpHeaders.etagHeader);
  if (etag != null && !etag.startsWith('W/')) return etag;
  return headers.value(HttpHeaders.lastModifiedHeader) ?? '';
}

void _forget(File f) {
  if (f.existsSync()) f.deleteSync();
}

/// [resumableDownload] in the dialect the download screens already speak:
/// progress as `(receivedBytes, totalBytes)` events, `-1` for a total the
/// server never sent, and the listener leaving as the pause button.
///
/// The engine's laws are unchanged — this only changes who does the
/// asking. Every argument means what it means above.
///
/// **Cold.** Nothing hits the wire until something subscribes. An eager
/// start would leave a stream nobody listened to downloading *and
/// promoting* an artifact with no reachable cancel — a transfer running
/// on behalf of no one. Cancelling the subscription is therefore always
/// enough to stop the work, because the subscription is what started it.
/// (One listener, once: the transfer is a real thing happening, not a
/// value to be replayed.)
///
/// **Cancellation is not silence.** [onOutcome] fires exactly once, just
/// BEFORE the stream closes, so a consumer that merely awaits the stream
/// can read the outcome immediately after and know whether it may say
/// "installed". It reports [TransferOutcome.completed] or
/// [TransferOutcome.cancelled] only; a transfer or promotion error rides
/// the stream's error channel instead. Pass [cancelToken] to hold the
/// pause button somewhere other than the subscription — the stream then
/// closes normally on cancel, and [onOutcome] is the only thing that
/// tells you it was not a finish.
///
/// Note that `await subscription.cancel()` returns once the token is
/// cancelled, not once the transfer has wound down; a promotion already
/// underway is still allowed to finish.
Stream<(int, int)> resumableDownloadStream({
  required Dio dio,
  required String url,
  required File partFile,
  required Future<void> Function() promote,
  CancelToken? cancelToken,
  void Function(TransferOutcome outcome)? onOutcome,
}) {
  final token = cancelToken ?? CancelToken();
  late final StreamController<(int, int)> controller;
  controller = StreamController<(int, int)>(
    onListen: () {
      unawaited(resumableDownload(
        dio: dio,
        url: url,
        partFile: partFile,
        promote: promote,
        cancelToken: token,
        onProgress: (received, total) {
          // The listener can leave mid-byte; the engine finds out one
          // chunk later, and a closed controller refuses events.
          if (!controller.isClosed) controller.add((received, total ?? -1));
        },
      ).then((outcome) {
        onOutcome?.call(outcome);
        return controller.close();
      }, onError: (Object err, StackTrace stack) {
        if (!controller.isClosed) controller.addError(err, stack);
        return controller.close();
      }));
    },
    // A transfer that already finished shrugs this off: cancel() is a
    // no-op once there is nothing left in flight.
    onCancel: () {
      if (!token.isCancelled) token.cancel();
    },
  );
  return controller.stream;
}
