import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Riverpod 2's `AsyncValue.value`: the value, or the failure thrown.
///
/// On riverpod 3 `value` gives null on a failure (as `valueOrNull` did), so
/// `value ?? []` draws a failed read as an empty list. Where a null would
/// stand for the household's own records (an item being edited, its tags,
/// the homes), a failure must not pass for "there are none": an empty edit
/// form saves over the item, and "no homes" offers to add one again.
extension ShownValue<T> on AsyncValue<T> {
  /// The value; null while loading with no value yet; the failure, thrown,
  /// when the read failed and there is no value from before.
  T? get shownValue {
    if (hasValue) return requireValue;
    if (hasError) Error.throwWithStackTrace(error!, stackTrace!);
    return null;
  }
}
