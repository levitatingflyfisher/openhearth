import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

/// The largest photo the encrypted backup carries as it is: 1 MiB.
///
/// The whole backup must fit the shared OHBK ceiling of 10 MB, and a photo
/// grows by a third as base64 text. At 1 MiB a household with several
/// babies still leaves most of the 10 MB to the logs.
const maxBackupPhotoBytes = 1024 * 1024;

/// A photo over [maxBackupPhotoBytes] goes into the backup as a smaller
/// copy, this many pixels on its longest side, as PNG. The photo on the
/// phone is not changed.
const backupPhotoSide = 512;

/// A photo as the backup carries it.
typedef BackupPhoto = ({Uint8List bytes, String extension});

/// The photo to put in the backup: [bytes] as they are when within
/// [maxBackupPhotoBytes], else a [backupPhotoSide] copy. Null when the photo
/// cannot be read as an image or the copy is still over the limit; the
/// backup is then made without it, never refused for it.
Future<BackupPhoto?> fitPhotoForBackup(
    Uint8List bytes, String extension) async {
  if (bytes.length <= maxBackupPhotoBytes) {
    return (bytes: bytes, extension: extension);
  }
  try {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final wide = descriptor.width >= descriptor.height;
    final codec = await descriptor.instantiateCodec(
      targetWidth: wide ? backupPhotoSide : null,
      targetHeight: wide ? null : backupPhotoSide,
    );
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
    if (data == null || data.lengthInBytes > maxBackupPhotoBytes) return null;
    return (bytes: data.buffer.asUint8List(), extension: '.png');
  } catch (e) {
    debugPrint('[Backup] baby photo left out, not an image: $e');
    return null;
  }
}

/// A photo file's extension, made safe for a file name: a dot and up to
/// five lowercase letters or digits, else `.img`. A restored backup is
/// untrusted input, so its extension never reaches a path unchecked.
String safePhotoExtension(Object? extension) {
  if (extension is! String) return '.img';
  final lower = extension.toLowerCase();
  return RegExp(r'^\.[a-z0-9]{1,5}$').hasMatch(lower) ? lower : '.img';
}
