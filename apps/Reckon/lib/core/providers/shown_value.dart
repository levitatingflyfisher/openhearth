import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Riverpod 2's [AsyncValue.value]: the value, null while loading, and the
/// failure rethrown when there is no value to show.
///
/// Riverpod 3's `value` returns null on a failure instead. Where a null
/// would draw a screen as if the person's own data were simply absent, use
/// this, so the failure still reaches the screen as it did. (The reveal is
/// the case: with the decision unread it would offer to commit option A
/// without showing the options.) Where null honestly means "nothing to
/// show", plain `value` is right.
extension ShownValue<T> on AsyncValue<T> {
  T? get shownValue {
    if (hasError && !hasValue) {
      Error.throwWithStackTrace(error!, stackTrace ?? StackTrace.current);
    }
    return value;
  }
}
