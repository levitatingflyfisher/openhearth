import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderBase;
import 'package:openhearth_design/openhearth_design.dart';

/// What a screen shows in place of its content when a read of the
/// household's own data in [reads] has failed, or null when none has.
///
/// A failed read shows [OhReadError] with Try again, which reads again only
/// the providers that failed. While they read again it shows a spinner.
/// The failure is never drawn as an empty list (an empty grocery list reads
/// "my list is gone") and never reaches Flutter's grey error box.
///
/// It matches `shownValue`: a read "failed" when it has an error and no
/// value to show. So once this returns null, `shownValue` on these reads
/// does not throw, and `shownValue` stays the backstop for any read a
/// screen forgot to list here.
Widget? readFailure(
  WidgetRef ref,
  List<ProviderBase<AsyncValue<Object?>>> reads, {
  required String title,
}) {
  final states = [for (final p in reads) ref.watch(p)];
  final failed = [
    for (var i = 0; i < reads.length; i++)
      if (states[i].hasError && !states[i].hasValue) i,
  ];
  if (failed.isEmpty) return null;
  if (failed.any((i) => states[i].isLoading)) {
    return const Center(child: CircularProgressIndicator());
  }
  final first = states[failed.first];
  return OhReadError(
    title: title,
    error: first.error,
    stackTrace: first.stackTrace,
    onRetry: () {
      for (final i in failed) {
        ref.invalidate(reads[i]);
      }
    },
  );
}
