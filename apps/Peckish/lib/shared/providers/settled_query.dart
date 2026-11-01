// lib/shared/providers/settled_query.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The settled (debounced) text of a search field. Each search surface
/// declares its own private autoDispose provider of this, so its query
/// resets to '' when the surface closes. It replaces riverpod 2's
/// `StateProvider.autoDispose((_) => '')`, which riverpod 3 moved to its
/// legacy import.
class SettledQuery extends Notifier<String> {
  @override
  String build() => '';

  void set(String query) => state = query;
}
