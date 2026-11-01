import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Photo picking is available here (native, dart:io-backed).
bool get babyPhotoSupported => true;

/// Resolves [photoPath] to a [FileImage], or null when unset or the file has
/// gone missing — callers fall back to the initial-letter avatar.
ImageProvider? babyPhotoImage(String? photoPath) {
  if (photoPath == null) return null;
  final file = File(photoPath);
  if (!file.existsSync()) return null;
  return FileImage(file);
}

/// Copies a freshly picked photo into permanent app storage and returns the
/// stored path. image_picker returns a path in the OS cache/temp dir, which
/// is purged under storage pressure (the avatar would silently vanish), so
/// the path we persist must be one we own.
Future<String?> persistPickedPhoto(XFile picked) async {
  final docsDir = await getApplicationDocumentsDirectory();
  final avatarsDir = Directory(p.join(docsDir.path, 'avatars'));
  await avatarsDir.create(recursive: true);
  final ext = p.extension(picked.path);
  final dest = p.join(avatarsDir.path, '${_uuid.v4()}$ext');
  await File(picked.path).copy(dest);
  return dest;
}

/// The baby photos as files, for the encrypted backup: read one to put it
/// in, save one a restore brings back. [folder] is where restored photos
/// go; null means the app's own `avatars` folder, where picked photos live.
class BabyPhotoFiles {
  const BabyPhotoFiles({this.folder});

  final String? folder;

  /// The photo's bytes, or null when unset or the file is gone.
  Future<Uint8List?> read(String? photoPath) async {
    if (photoPath == null) return null;
    final file = File(photoPath);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  /// Writes [bytes] under a new name in the photo folder and returns the
  /// path. [extension] must already be safe (see `safePhotoExtension`).
  Future<String?> save(Uint8List bytes, String extension) async {
    final dir = folder ??
        p.join((await getApplicationDocumentsDirectory()).path, 'avatars');
    await Directory(dir).create(recursive: true);
    final dest = p.join(dir, '${_uuid.v4()}$extension');
    await File(dest).writeAsBytes(bytes, flush: true);
    return dest;
  }

  /// Removes a photo this restore wrote, when the restore fails after.
  Future<void> remove(String path) async {
    try {
      await File(path).delete();
    } on FileSystemException {
      // Already gone: nothing to undo.
    }
  }
}
