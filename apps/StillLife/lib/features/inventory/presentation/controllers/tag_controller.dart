import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:still_life/core/providers/retry_policy.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../../core/providers/repository_providers.dart';
import '../../../../core/providers/stored_data_caches.dart';
import '../../domain/entities/tag.dart';
import '../../domain/repositories/tag_repository.dart';

/// Watch all tags.
final tagsProvider = StreamProvider<List<Tag>>((ref) {
  return ref.watch(tagRepositoryProvider).watchTags();
},
  retry: noAutoRetry,
);

/// Get tags for a specific item.
final itemTagsProvider = FutureProvider.family<List<Tag>, String>((
  ref,
  itemId,
) async {
  rereadOnDatabaseWrites(ref);
  final result = await ref.watch(tagRepositoryProvider).getItemTags(itemId);
  // A failed read says so (the item page shows it with Try again), never
  // as an item with no tags.
  return result.when(success: (tags) => tags, failure: (f) => throw f);
},
  retry: noAutoRetry,
);

/// Tag CRUD controller.
final tagControllerProvider =
    StateNotifierProvider<TagController, AsyncValue<void>>((ref) {
      return TagController(ref.watch(tagRepositoryProvider));
    });

class TagController extends StateNotifier<AsyncValue<void>> {
  final TagRepository _repo;

  TagController(this._repo) : super(const AsyncData(null));

  Future<bool> createTag(Tag tag) async {
    state = const AsyncLoading();
    final result = await _repo.createTag(tag);
    return result.when(
      success: (_) {
        state = const AsyncData(null);
        return true;
      },
      failure: (f) {
        state = AsyncError(f.message, StackTrace.current);
        return false;
      },
    );
  }

  Future<bool> updateTag(Tag tag) async {
    state = const AsyncLoading();
    final result = await _repo.updateTag(tag);
    return result.when(
      success: (_) {
        state = const AsyncData(null);
        return true;
      },
      failure: (f) {
        state = AsyncError(f.message, StackTrace.current);
        return false;
      },
    );
  }

  Future<bool> deleteTag(String id) async {
    state = const AsyncLoading();
    final result = await _repo.deleteTag(id);
    return result.when(
      success: (_) {
        state = const AsyncData(null);
        return true;
      },
      failure: (f) {
        state = AsyncError(f.message, StackTrace.current);
        return false;
      },
    );
  }

  Future<bool> setItemTags(String itemId, List<String> tagIds) async {
    state = const AsyncLoading();
    final result = await _repo.setItemTags(itemId, tagIds);
    return result.when(
      success: (_) {
        state = const AsyncData(null);
        return true;
      },
      failure: (f) {
        state = AsyncError(f.message, StackTrace.current);
        return false;
      },
    );
  }
}
