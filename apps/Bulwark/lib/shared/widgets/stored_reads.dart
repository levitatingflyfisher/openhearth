import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderBase;
import 'package:openhearth_design/openhearth_design.dart';

/// What a screen shows until every read of the household's own data in
/// [reads] has a value, or null once they all do.
///
/// A failed read shows [OhReadError] with Try again, which reads again only
/// the providers that failed. It is never drawn as an empty list: an empty
/// wall or shopping list on a failed read tells a parent their data is gone,
/// and they may start over on top of it. While a read is still loading (or
/// reading again after Try again) the screen shows a spinner.
///
/// When this returns null, every read has a value, so the caller can use
/// `requireValue`.
Widget? whileReading(
  WidgetRef ref,
  List<ProviderBase<AsyncValue<Object?>>> reads, {
  required String title,
}) {
  final states = [for (final p in reads) ref.watch(p)];
  final failed = [
    for (var i = 0; i < reads.length; i++)
      if (states[i].hasError && !states[i].isLoading) i,
  ];
  if (failed.isNotEmpty) {
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
  if (states.any((s) => !s.hasValue)) {
    return const Center(child: CircularProgressIndicator());
  }
  return null;
}
