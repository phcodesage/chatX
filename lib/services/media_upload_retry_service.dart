import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'compression_service.dart';
import 'media_upload_service.dart';

/// Progress update emitted by [MediaUploadRetryService] for a specific upload.
class RetryProgress {
  /// The tracking ID originally passed to [queueUpload].
  final String trackingId;

  /// The current upload progress.
  final UploadProgress progress;

  const RetryProgress({
    required this.trackingId,
    required this.progress,
  });
}

/// A pending media upload that failed due to network issues
/// and is queued for automatic retry when connectivity is restored.
class _PendingUpload {
  /// Path to the temp file containing the upload bytes.
  final String tempFilePath;

  /// Recipient user ID.
  final int recipientId;

  /// Optional caption text.
  final String? caption;

  /// Original file name.
  final String fileName;

  /// MIME type of the file.
  final String mimeType;

  /// Tracking ID used to report progress to [MediaUploadState].
  final String trackingId;

  /// Number of retry attempts already made.
  int retryCount;

  _PendingUpload({
    required this.tempFilePath,
    required this.recipientId,
    this.caption,
    required this.fileName,
    required this.mimeType,
    required this.trackingId,
    this.retryCount = 0,
  });
}

/// Global singleton that manages media uploads which failed due to
/// temporary network issues and automatically retries them when
/// the device comes back online.
///
/// Persists compressed file bytes to the temp directory so that
/// retries can happen even after the caller (e.g. [MediaPreviewScreen])
/// has been disposed.
class MediaUploadRetryService {
  static final MediaUploadRetryService _instance =
      MediaUploadRetryService._internal();
  factory MediaUploadRetryService() => _instance;
  MediaUploadRetryService._internal();

  final List<_PendingUpload> _queue = [];

  final StreamController<RetryProgress> _progressController =
      StreamController<RetryProgress>.broadcast();

  /// Emits progress updates for queued uploads while they are being retried.
  Stream<RetryProgress> get progressStream => _progressController.stream;

  /// Whether there are uploads currently waiting for connectivity.
  bool get hasPendingUploads => _queue.isNotEmpty;

  /// Queues a failed upload for automatic retry.
  ///
  /// Writes [bytes] to a temp file so the data survives the caller's
  /// disposal. The upload will be retried by [retryAll] when the device
  /// regains connectivity.
  Future<void> queueUpload({
    required List<int> bytes,
    required String fileName,
    required String mimeType,
    required int recipientId,
    String? caption,
    required String trackingId,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final safeName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final tempFile = File('${tempDir.path}/retry_${timestamp}_$safeName');
    await tempFile.writeAsBytes(bytes);

    _queue.add(
      _PendingUpload(
        tempFilePath: tempFile.path,
        recipientId: recipientId,
        caption: caption,
        fileName: fileName,
        mimeType: mimeType,
        trackingId: trackingId,
      ),
    );

    debugPrint(
      '📤 Queued upload for retry: $fileName (queue size: ${_queue.length})',
    );
  }

  /// Retries all pending uploads.
  ///
  /// Skips the retry if the device is currently offline.
  /// On network failure, the upload stays in the queue for the next retry.
  /// On non-network failure or success, the temp file is cleaned up.
  Future<void> retryAll() async {
    if (_queue.isEmpty) {
      debugPrint('📤 No pending uploads to retry');
      return;
    }

    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity.contains(ConnectivityResult.none)) {
      debugPrint('📤 Device is offline, skipping retry');
      return;
    }

    final toRetry = List<_PendingUpload>.from(_queue);
    debugPrint('🔄 Retrying ${toRetry.length} pending uploads...');

    for (final job in toRetry) {
      final tempFile = File(job.tempFilePath);
      if (!await tempFile.exists()) {
        debugPrint('⚠️ Temp file missing for ${job.fileName}, removing from queue');
        _queue.remove(job);
        continue;
      }

      // Report retrying state
      _progressController.add(
        RetryProgress(
          trackingId: job.trackingId,
          progress: UploadProgress(
            fileIndex: 0,
            totalFiles: 1,
            fileProgress: 0.0,
            status: UploadStatus.retrying,
          ),
        ),
      );

      try {
        final bytes = await tempFile.readAsBytes();
        final file = CompressionResult(
          bytes: bytes,
          mimeType: job.mimeType,
          fileName: job.fileName,
          originalSize: bytes.length,
          compressedSize: bytes.length,
          compressionSkipped: false,
        );

        final result = await MediaUploadService.uploadSingleFile(
          file: file,
          recipientId: job.recipientId,
          caption: job.caption,
          onProgress: (progress) {
            _progressController.add(
              RetryProgress(
                trackingId: job.trackingId,
                progress: UploadProgress(
                  fileIndex: 0,
                  totalFiles: 1,
                  fileProgress: progress,
                  status: UploadStatus.retrying,
                ),
              ),
            );
          },
        );

        if (result.success) {
          debugPrint('✅ Retry succeeded for ${job.fileName}');
          _progressController.add(
            RetryProgress(
              trackingId: job.trackingId,
              progress: UploadProgress(
                fileIndex: 0,
                totalFiles: 1,
                fileProgress: 1.0,
                status: UploadStatus.success,
              ),
            ),
          );
          _safeDelete(tempFile);
          _queue.remove(job);
        } else if (result.isNetworkError) {
          job.retryCount++;
          debugPrint(
            '⚠️ Retry failed (network) for ${job.fileName} '
            '(attempt ${job.retryCount}), keeping in queue',
          );
          _progressController.add(
            RetryProgress(
              trackingId: job.trackingId,
              progress: UploadProgress(
                fileIndex: 0,
                totalFiles: 1,
                fileProgress: 0.0,
                status: UploadStatus.retrying,
              ),
            ),
          );
        } else {
          debugPrint(
            '❌ Retry failed (permanent) for ${job.fileName}: ${result.errorMessage}',
          );
          _progressController.add(
            RetryProgress(
              trackingId: job.trackingId,
              progress: UploadProgress(
                fileIndex: 0,
                totalFiles: 1,
                fileProgress: 0.0,
                status: UploadStatus.failed,
              ),
            ),
          );
          _safeDelete(tempFile);
          _queue.remove(job);
        }
      } catch (e) {
        debugPrint('❌ Unexpected error during retry for ${job.fileName}: $e');
        job.retryCount++;
        _progressController.add(
          RetryProgress(
            trackingId: job.trackingId,
            progress: UploadProgress(
              fileIndex: 0,
              totalFiles: 1,
              fileProgress: 0.0,
              status: UploadStatus.retrying,
            ),
          ),
        );
      }
    }

    debugPrint('📤 Retry cycle complete. Remaining in queue: ${_queue.length}');
  }

  /// Removes a pending upload by its tracking ID without retrying it.
  /// Cleans up the associated temp file.
  Future<void> cancelUpload(String trackingId) async {
    final job = _queue.cast<_PendingUpload?>().firstWhere(
      (j) => j?.trackingId == trackingId,
      orElse: () => null,
    );
    if (job != null) {
      _safeDelete(File(job.tempFilePath));
      _queue.remove(job);
      debugPrint('🗑️ Cancelled upload $trackingId');
    }
  }

  /// Clears the entire queue and cleans up temp files.
  Future<void> clearQueue() async {
    for (final job in _queue) {
      _safeDelete(File(job.tempFilePath));
    }
    _queue.clear();
    debugPrint('🗑️ Retry queue cleared');
  }

  void _safeDelete(File file) {
    try {
      if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (e) {
      debugPrint('⚠️ Failed to delete temp file: $e');
    }
  }
}
