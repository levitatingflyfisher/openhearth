import 'package:flutter/material.dart';

import 'error_state.dart';

/// What a screen shows in place of its content when reading its own data
/// failed: a plain line that the app could not read this part of the data on
/// this device, that a failed read deletes nothing, and one "Try again".
///
/// Use it for the error branch of a read. Show an empty list only when the
/// read worked and found nothing: an empty list on a failed read tells the
/// household their data is gone when it is not.
///
/// ```dart
/// switch (ref.watch(shoppingProvider)) {
///   AsyncData(:final value) => ShoppingList(value),
///   AsyncError(:final error, :final stackTrace) => OhReadError(
///       onRetry: () => ref.invalidate(shoppingProvider),
///       error: error,
///       stackTrace: stackTrace,
///     ),
///   _ => const Center(child: CircularProgressIndicator()),
/// }
/// ```
///
/// Built on [OhErrorState], so it looks and behaves like every other failure
/// state in the fleet. The words are [OhErrorMessages.readFailedTitle] and
/// [OhErrorMessages.readFailed].
class OhReadError extends StatelessWidget {
  const OhReadError({
    super.key,
    required this.onRetry,
    this.title = OhErrorMessages.readFailedTitle,
    this.detail,
    this.error,
    this.stackTrace,
  });

  /// Reads again. Usually `ref.invalidate(theProvider)`. Required: a failed
  /// read with no way to try again strands the person.
  final VoidCallback onRetry;

  /// Defaults to "Couldn't read this". An app may name the part
  /// ("Couldn't read your shopping list").
  final String title;

  /// An optional quieter line the app writes for a person, such as which
  /// list. Never the exception text.
  final String? detail;

  /// The technical error, kept behind Details for a bug report. Null hides
  /// Details, so by default no technical text reaches the screen.
  final Object? error;
  final StackTrace? stackTrace;

  @override
  Widget build(BuildContext context) => OhErrorState(
        title: title,
        message: OhErrorMessages.readFailed,
        detail: detail,
        onRetry: onRetry,
        error: error,
        stackTrace: stackTrace,
        // A local read, not the network: the cloud icon OhErrorState uses
        // by default would point the person at their connection.
        icon: Icons.folder_off_outlined,
      );
}
