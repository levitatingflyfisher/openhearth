import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:image_picker/image_picker.dart';

/// Photo picking is hidden on web: baby photos are stored as device file
/// paths, and a browser has no file system to resolve them against.
bool get babyPhotoSupported => false;

/// Always null on web — a stored photoPath is a path on some device's disk,
/// unreachable from a browser; callers fall back to the initial-letter
/// avatar instead of hitting dart:io's throwing File stub.
ImageProvider? babyPhotoImage(String? photoPath) => null;

/// Unreachable on web ([babyPhotoSupported] hides the affordance). Returns
/// null — photo unchanged — rather than throwing, so a regression that
/// re-exposes the button degrades to a no-op instead of a crash.
Future<String?> persistPickedPhoto(XFile picked) async => null;

/// No photo files on web: a backup made here carries no photo, and a
/// restore here keeps the row's path, which the avatar never resolves.
class BabyPhotoFiles {
  const BabyPhotoFiles({this.folder});

  final String? folder;

  Future<Uint8List?> read(String? photoPath) async => null;

  Future<String?> save(Uint8List bytes, String extension) async => null;

  Future<void> remove(String path) async {}
}
