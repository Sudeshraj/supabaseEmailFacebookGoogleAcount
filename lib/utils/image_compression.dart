// lib/utils/image_compression.dart
//
// Client-side image compression, used before every upload (profile avatar,
// salon logo, salon cover). This is the same approach WhatsApp/Instagram
// use: resize to a sane max dimension, then re-encode as JPEG at a quality
// that keeps the file small without a visible quality drop, trying lower
// quality steps only if still over the size budget.
//
// Add to pubspec.yaml:
//   flutter_image_compress: ^2.3.0

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

/// Compresses [bytes] for upload.
///
/// - Resizes so neither side exceeds [maxDimension] (aspect ratio kept).
/// - Re-encodes as JPEG starting at [startQuality].
/// - If still bigger than [maxSizeKB], retries at progressively lower
///   quality (in steps of 10) down to [minQuality].
/// - Never throws: if compression isn't supported on the current platform
///   or anything goes wrong, the original [bytes] are returned unchanged
///   so the upload still proceeds.
Future<Uint8List> compressImageBytes(
  Uint8List bytes, {
  int maxDimension = 1080,
  int maxSizeKB = 500,
  int startQuality = 85,
  int minQuality = 40,
}) async {
  try {
    var quality = startQuality;

    Uint8List? result = await FlutterImageCompress.compressWithList(
      bytes,
      minWidth: maxDimension,
      minHeight: maxDimension,
      quality: quality,
      format: CompressFormat.jpeg,
    );

    // Progressive quality reduction until under the size budget, or we
    // hit the quality floor (avoids visible artifacting from over-compressing).
    while (result != null &&
        result.lengthInBytes > maxSizeKB * 1024 &&
        quality > minQuality) {
      quality -= 10;
      result = await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: maxDimension,
        minHeight: maxDimension,
        quality: quality,
        format: CompressFormat.jpeg,
      );
    }

    if (result == null || result.isEmpty) {
      debugPrint('⚠️ Compression returned empty result, using original bytes');
      return bytes;
    }

    debugPrint(
      '📦 Image compressed: ${(bytes.lengthInBytes / 1024).toStringAsFixed(0)}KB '
      '-> ${(result.lengthInBytes / 1024).toStringAsFixed(0)}KB (quality=$quality)',
    );
    return result;
  } catch (e) {
    debugPrint('⚠️ Image compression failed, using original bytes: $e');
    return bytes;
  }
}

/// Convenience preset for profile avatars / logos (roughly square, shown small).
Future<Uint8List> compressAvatarBytes(Uint8List bytes) => compressImageBytes(
  bytes,
  maxDimension: 800,
  maxSizeKB: 300,
  startQuality: 85,
);

/// Convenience preset for wide cover/banner photos (shown larger).
Future<Uint8List> compressCoverBytes(Uint8List bytes) => compressImageBytes(
  bytes,
  maxDimension: 1600,
  maxSizeKB: 600,
  startQuality: 85,
);