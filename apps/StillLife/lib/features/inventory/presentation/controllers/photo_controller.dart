import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:still_life/core/providers/retry_policy.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../../core/providers/database_provider.dart';
import '../../../../core/providers/repository_providers.dart';
import '../../../../services/storage/photo_storage_service.dart';
import '../../domain/entities/photo.dart';
import '../../domain/repositories/photo_repository.dart';

/// Photo storage service provider.
final photoStorageServiceProvider = Provider<PhotoStorageService>((ref) {
  return PhotoStorageService();
});

/// Watch primary thumbnail bytes for all items (keyed by itemId).
final primaryThumbnailsProvider =
    StreamProvider<Map<String, Uint8List>>((ref) {
  return ref.watch(databaseProvider).photoDao.watchPrimaryThumbnails();
}, retry: noAutoRetry);

/// Watch photos for an item.
final itemPhotosProvider = StreamProvider.family<List<Photo>, String>((
  ref,
  itemId,
) {
  return ref.watch(photoRepositoryProvider).watchItemPhotos(itemId);
},
  retry: noAutoRetry,
);

/// Photo CRUD controller.
final photoControllerProvider =
    StateNotifierProvider<PhotoController, AsyncValue<void>>((ref) {
      return PhotoController(
        ref.watch(photoRepositoryProvider),
        ref.watch(photoStorageServiceProvider),
      );
    });

class PhotoController extends StateNotifier<AsyncValue<void>> {
  final PhotoRepository _repo;
  final PhotoStorageService _storage;

  PhotoController(this._repo, this._storage) : super(const AsyncData(null));

  /// Add a photo from raw image bytes (camera or gallery).
  ///
  /// Byte-based on purpose: image_picker's `XFile.readAsBytes()` works on
  /// every platform (a web XFile has no usable path), and the bytes are
  /// stored in the database as a BLOB.
  Future<bool> addPhoto({
    required String itemId,
    required Uint8List bytes,
    required PhotoSource source,
    bool setAsPrimary = false,
  }) async {
    state = const AsyncLoading();
    try {
      final now = DateTime.now();
      final cleanBytes = _storage.normalizeForStorage(bytes);
      final photo = Photo(
        id: '',
        itemId: itemId,
        filePath: '',
        bytes: cleanBytes,
        thumbBytes: _storage.thumbnailFor(cleanBytes),
        isPrimary: setAsPrimary,
        source: source,
        capturedAt: now,
        createdAt: now,
        modifiedAt: now,
      );

      final result = await _repo.addPhoto(photo);
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
    } catch (e) {
      state = AsyncError(e, StackTrace.current);
      return false;
    }
  }

  /// Delete a photo (the DB record, plus the legacy file for pre-v12 rows).
  Future<bool> deletePhoto(String photoId, String filePath) async {
    state = const AsyncLoading();
    try {
      await _storage.deletePhoto(filePath);
      final result = await _repo.deletePhoto(photoId);
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
    } catch (e) {
      state = AsyncError(e, StackTrace.current);
      return false;
    }
  }

  /// Set a photo as the primary photo for an item.
  Future<bool> setPrimary(String itemId, String photoId) async {
    state = const AsyncLoading();
    final result = await _repo.setPrimaryPhoto(itemId, photoId);
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
