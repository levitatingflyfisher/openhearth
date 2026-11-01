import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Width of generated photo thumbnails, in pixels.
const int kThumbnailWidth = 200;

/// Maximum pixel dimension (width or height) for stored full-size photos.
const int kMaxPhotoDimension = 2048;

/// Re-encodes [bytes] as a clean JPEG with orientation baked in, max dimension
/// capped at [maxDimension], and all EXIF/GPS metadata stripped.
///
/// Pure Dart (`package:image`), so it runs identically on native and web.
/// Returns [bytes] unchanged when [bytes] cannot be decoded (e.g. synthetic
/// bytes in unit tests) so storage never silently drops data.
Uint8List normalizePhotoBytes(
  Uint8List bytes, {
  int maxDimension = kMaxPhotoDimension,
  int quality = 85,
}) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;
    var processed = img.bakeOrientation(decoded);
    if (processed.width > maxDimension || processed.height > maxDimension) {
      if (processed.width >= processed.height) {
        processed = img.copyResize(processed, width: maxDimension);
      } else {
        processed = img.copyResize(processed, height: maxDimension);
      }
    }
    // Clear EXIF (GPS, camera serial, device model) before re-encoding JPEG.
    processed.exif.clear();
    return Uint8List.fromList(img.encodeJpg(processed, quality: quality));
  } catch (_) {
    return bytes;
  }
}

/// Builds a JPEG thumbnail from full-size image [bytes].
///
/// Pure Dart (package:image), so it runs identically on native and web.
/// Returns null when [bytes] is not a decodable image — thumbnails are
/// best-effort and must never fail a save or a migration.
Uint8List? buildThumbnailBytes(
  Uint8List bytes, {
  int width = kThumbnailWidth,
  int quality = 80,
}) {
  try {
    final image = img.decodeImage(bytes);
    if (image == null) return null;
    final thumbnail = img.copyResize(image, width: width);
    return Uint8List.fromList(img.encodeJpg(thumbnail, quality: quality));
  } catch (_) {
    return null;
  }
}
