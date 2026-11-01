import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A choice made on screen (a period, a filter, a date range): a value with
/// a starting point and a setter. Riverpod 3 moved `StateProvider` to its
/// legacy import; this is the small Notifier that replaces it.
///
/// Not auto-disposed, as the StateProviders it replaces were not: the choice
/// stays while the app runs.
class UiChoice<T> extends Notifier<T> {
  UiChoice(this._initial);

  final T Function() _initial;

  @override
  T build() => _initial();

  void set(T value) => state = value;
}
