// lib/core/providers/shown_value.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Riverpod 2's [AsyncValue.value]: the value, null while loading, and the
/// failure rethrown when there is no value to show.
///
/// Riverpod 3's `value` returns null on a failure instead. Peckish's screens
/// draw `value ?? empty`, so on riverpod 3 a failed read of the grocery
/// list, the plan or the day's log would be drawn as an empty list: "your
/// list is gone". Rethrowing keeps the failure on screen, as it was.
extension ShownValue<T> on AsyncValue<T> {
  T? get shownValue {
    if (hasError && !hasValue) {
      Error.throwWithStackTrace(error!, stackTrace ?? StackTrace.current);
    }
    return value;
  }
}
