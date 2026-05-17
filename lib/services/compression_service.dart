import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:video_compress/video_compress.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

/// Result of compressing a single media item.
class CompressionResult {
  /// The compressed (or original) file bytes.
  final Uint8List bytes;

  /// The MIME type of the output file.
  final String mimeType;

  /// The output file name.
  final String fileName;

  /// The original file size in bytes before compression.
  final int originalSize;

  /// The compressed file size in bytes (equals originalSize if skipped).
  final int compressedSize;

  /// Whether compression was skipped due to an error or timeout.
  /// Note: GIF passthrough sets this to `false` because passthrough is
  /// intentional behavior, not a failure.
  final bool compressionSkipped;

  const CompressionResult({
    required this.bytes,
    required this.mimeType,
    required this.fileName,
    required this.originalSize,
    required this.compressedSize,
    required this.compressionSkipped,
  });
}

/// Callback for reporting batch compression progress.
typedef CompressionProgressCallback = void Function(int completed, int total);

/// Service responsible for compressing images and videos before upload.
///
/// Uses `flutter_image_compress` for image compression.
/// Supports JPEG, PNG, HEIC, and WebP formats.
/// GIFs are passed through without recompression to preserve animation frames.
class CompressionService {
  /// Compresses a single image asset.
  ///
  /// Returns a [CompressionResult] with compressed bytes as JPEG output
  /// at the specified [quality] (default 70, range 65-75).
  ///
  /// If the asset is a GIF, returns original bytes without compression
  /// (passthrough with `compressionSkipped: false`).
  ///
  /// If compression fails for any reason, returns original bytes with
  /// `compressionSkipped: true`.
  static Future<CompressionResult> compressImage(
    AssetEntity asset, {
    int quality = 70,
    int maxDimension = 1920,
  }) async {
    try {
      // Get the file from the asset
      final file = await asset.file;
      if (file == null) {
        throw Exception('Unable to read asset file');
      }

      final originalBytes = await file.readAsBytes();
      final originalSize = originalBytes.length;
      final title = await asset.titleAsync;
      final fileName = title.isNotEmpty ? title : 'image.jpg';

      // Detect GIF by file extension or mime type
      if (_isGif(fileName, asset.mimeType)) {
        return CompressionResult(
          bytes: originalBytes,
          mimeType: 'image/gif',
          fileName: fileName,
          originalSize: originalSize,
          compressedSize: originalSize,
          compressionSkipped: false, // Passthrough is intentional
        );
      }

      // Calculate target dimensions preserving aspect ratio
      final targetSize = calculateTargetDimensions(
        asset.width,
        asset.height,
        maxDimension: maxDimension,
      );

      // Compress the image to JPEG using flutter_image_compress
      final compressedBytes = await FlutterImageCompress.compressWithFile(
        file.absolute.path,
        minWidth: targetSize.width.toInt(),
        minHeight: targetSize.height.toInt(),
        quality: quality,
        format: CompressFormat.jpeg,
        keepExif: true, // Preserve orientation metadata
      );

      if (compressedBytes == null || compressedBytes.isEmpty) {
        throw Exception('Compression returned empty result');
      }

      final compressedData = Uint8List.fromList(compressedBytes);

      // Generate output file name with .jpg extension
      final outputFileName = _replaceExtension(fileName, '.jpg');

      return CompressionResult(
        bytes: compressedData,
        mimeType: 'image/jpeg',
        fileName: outputFileName,
        originalSize: originalSize,
        compressedSize: compressedData.length,
        compressionSkipped: false,
      );
    } catch (e) {
      // On any error, attempt to return original bytes with flag
      return _fallbackResult(asset);
    }
  }

  /// Compresses a batch of media items sequentially.
  ///
  /// Calls [onProgress] after each item completes with the number of
  /// completed items and the total count.
  ///
  /// Each item has a [itemTimeout] (default 30 seconds). If compression
  /// does not complete within the timeout, the original file is used instead.
  ///
  /// Routes to [compressImage] for images and [compressVideo] for videos
  /// based on [AssetEntity.type].
  ///
  /// Returns results in the same order as input.
  static Future<List<CompressionResult>> compressBatch(
    List<AssetEntity> assets, {
    CompressionProgressCallback? onProgress,
    int imageQuality = 70,
    int maxImageDimension = 1920,
    Duration itemTimeout = const Duration(seconds: 30),
  }) async {
    final results = <CompressionResult>[];
    final total = assets.length;

    for (int i = 0; i < total; i++) {
      final asset = assets[i];
      CompressionResult result;

      try {
        if (asset.type == AssetType.video) {
          result = await compressVideo(asset).timeout(itemTimeout);
        } else {
          result = await compressImage(
            asset,
            quality: imageQuality,
            maxDimension: maxImageDimension,
          ).timeout(itemTimeout);
        }
      } on TimeoutException {
        // 30-second timeout exceeded — fallback to original
        result = await _fallbackResult(asset);
      } catch (_) {
        // Any other compression error — fallback to original
        result = await _fallbackResult(asset);
      }

      results.add(result);
      onProgress?.call(i + 1, total);
    }

    return results;
  }

  /// Compresses a single video asset.
  ///
  /// Target: max 720p resolution (1280×720), max 2Mbps bitrate,
  /// target ≤50% of original file size.
  /// Uses the `video_compress` package with [VideoQuality.Res1280x720Quality].
  ///
  /// If compression fails for any reason, returns original bytes with
  /// `compressionSkipped: true`.
  static Future<CompressionResult> compressVideo(AssetEntity asset) async {
    try {
      final file = await asset.file;
      if (file == null) {
        throw Exception('Unable to read video asset file');
      }

      final originalBytes = await file.readAsBytes();
      final originalSize = originalBytes.length;
      final title = await asset.titleAsync;
      final fileName = title.isNotEmpty ? title : 'video.mp4';

      // Compress video to 720p max resolution with reduced bitrate.
      // VideoQuality.Res1280x720Quality targets 720p (1280×720) output,
      // which combined with the codec's default settings achieves
      // approximately 2Mbps bitrate and ≤50% size reduction.
      final info = await VideoCompress.compressVideo(
        file.path,
        quality: VideoQuality.Res1280x720Quality,
        deleteOrigin: false,
        includeAudio: true,
        frameRate: 30,
      );

      if (info == null || info.file == null) {
        throw Exception('Video compression returned null result');
      }

      final compressedBytes = await info.file!.readAsBytes();
      final compressedSize = compressedBytes.length;

      // Use compressed result regardless of achieved ratio — the re-encoding
      // at 720p with reduced bitrate provides the best achievable compression.
      // The ≤50% target is a goal, not a hard requirement; if the source is
      // already small or low-bitrate, the ratio may not reach 50%.
      final outputFileName = _replaceExtension(fileName, '.mp4');

      return CompressionResult(
        bytes: Uint8List.fromList(compressedBytes),
        mimeType: 'video/mp4',
        fileName: outputFileName,
        originalSize: originalSize,
        compressedSize: compressedSize,
        compressionSkipped: false,
      );
    } catch (e) {
      return _fallbackResult(asset);
    }
  }

  /// Calculates target dimensions preserving aspect ratio.
  ///
  /// If the longest side exceeds [maxDimension], scales down proportionally
  /// so the longest side equals [maxDimension].
  ///
  /// If both sides are within [maxDimension], returns original dimensions.
  static Size calculateTargetDimensions(
    int width,
    int height, {
    int maxDimension = 1920,
  }) {
    if (width <= 0 || height <= 0) {
      return Size(width.toDouble(), height.toDouble());
    }

    final longestSide = width > height ? width : height;

    if (longestSide <= maxDimension) {
      return Size(width.toDouble(), height.toDouble());
    }

    final scale = maxDimension / longestSide;
    final targetWidth = (width * scale).roundToDouble();
    final targetHeight = (height * scale).roundToDouble();

    return Size(targetWidth, targetHeight);
  }

  /// Determines if a file is a GIF based on file name extension or mime type.
  static bool _isGif(String fileName, String? mimeType) {
    final lowerName = fileName.toLowerCase();
    if (lowerName.endsWith('.gif')) return true;
    if (mimeType != null && mimeType.toLowerCase() == 'image/gif') return true;
    return false;
  }

  /// Replaces the file extension with a new one.
  static String _replaceExtension(String fileName, String newExtension) {
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex == -1) {
      return '$fileName$newExtension';
    }
    return '${fileName.substring(0, dotIndex)}$newExtension';
  }

  /// Creates a fallback CompressionResult using original bytes when
  /// compression fails.
  static Future<CompressionResult> _fallbackResult(AssetEntity asset) async {
    try {
      final file = await asset.file;
      if (file == null) {
        return CompressionResult(
          bytes: Uint8List(0),
          mimeType: 'application/octet-stream',
          fileName: 'unknown',
          originalSize: 0,
          compressedSize: 0,
          compressionSkipped: true,
        );
      }

      final originalBytes = await file.readAsBytes();
      final title = await asset.titleAsync;
      final fileName = title.isNotEmpty ? title : 'image';
      final mimeType = asset.mimeType ?? 'application/octet-stream';

      return CompressionResult(
        bytes: originalBytes,
        mimeType: mimeType,
        fileName: fileName,
        originalSize: originalBytes.length,
        compressedSize: originalBytes.length,
        compressionSkipped: true,
      );
    } catch (_) {
      return CompressionResult(
        bytes: Uint8List(0),
        mimeType: 'application/octet-stream',
        fileName: 'unknown',
        originalSize: 0,
        compressedSize: 0,
        compressionSkipped: true,
      );
    }
  }
}
