import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../models/message.dart';
import 'chat_cache_service.dart';
import 'compression_service.dart';
import 'media_upload_service.dart';
import 'socket_service.dart';
import 'storage_service.dart';

/// Progress update emitted by [MediaUploadRetryService] for a specific upload.
class RetryProgress {
  /// The tracking ID originally passed to [queueUpload].
  final String trackingId;

  /// The current upload progress.
  final UploadProgress progress;

  /// The created message on successful upload.
  final Message? message;

  const RetryProgress({
    required this.trackingId,
    required this.progress,
    this.message,
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

  Map<String, dynamic> toJson() => {
    'tempFilePath': tempFilePath,
    'recipientId': recipientId,
    'caption': caption,
    'fileName': fileName,
    'mimeType': mimeType,
    'trackingId': trackingId,
    'retryCount': retryCount,
  };

  factory _PendingUpload.fromJson(Map<String, dynamic> json) => _PendingUpload(
    tempFilePath: json['tempFilePath'] as String,
    recipientId: json['recipientId'] as int,
    caption: json['caption'] as String?,
    fileName: json['fileName'] as String,
    mimeType: json['mimeType'] as String,
    trackingId: json['trackingId'] as String,
    retryCount: json['retryCount'] as int? ?? 0,
  );
}

/// Global singleton that manages media uploads which failed due to
/// temporary network issues and automatically retries them when
/// the device comes back online.
class MediaUploadRetryService {
  static final MediaUploadRetryService _instance =
      MediaUploadRetryService._internal();
  factory MediaUploadRetryService() => _instance;
  MediaUploadRetryService._internal();

  final List<_PendingUpload> _queue = [];
  static late Box _retryBox;

  final StreamController<RetryProgress> _progressController =
      StreamController<RetryProgress>.broadcast();

  /// Emits progress updates for queued uploads while they are being retried.
  Stream<RetryProgress> get progressStream => _progressController.stream;

  /// Whether there are uploads currently waiting for connectivity.
  bool get hasPendingUploads => _queue.isNotEmpty;

  /// Initialize the retry box and load any persisted queue items.
  Future<void> initialize() async {
    _retryBox = await Hive.openBox('media_upload_retry_cache');
    final data = _retryBox.get('queue') as List?;
    if (data != null) {
      _queue.clear();
      for (final item in data) {
        if (item is Map) {
          final job = _PendingUpload.fromJson(Map<String, dynamic>.from(item));
          if (File(job.tempFilePath).existsSync()) {
            _queue.add(job);
          }
        }
      }
      debugPrint('📤 Loaded ${_queue.length} pending uploads from cache');
    }

    // Listen for connectivity changes to automatically retry queued uploads,
    // regardless of which screen is currently active. (Previously the only
    // trigger was a chat-screen-scoped socket 'reconnected' listener, so an
    // upload queued offline was never retried after the app was killed or while
    // the user was outside the chat — it sat in the queue, never reaching the
    // socket.)
    Connectivity().onConnectivityChanged.listen((results) {
      if (results.isNotEmpty && results.first != ConnectivityResult.none) {
        if (_queue.isNotEmpty) {
          debugPrint('📡 Connectivity restored, retrying queued uploads...');
          retryAll();
        }
      }
    });

    // Also retry immediately when the socket reconnects.
    SocketService().addListener('reconnected', 'MediaUploadRetryService', () {
      if (_queue.isNotEmpty) {
        debugPrint('🔌 Socket reconnected, retrying queued uploads...');
        retryAll();
      }
    });

    // Kick a retry on startup so uploads queued in a previous (offline) session
    // are sent as soon as the app launches with connectivity. retryAll() itself
    // checks connectivity and auth before doing any work.
    if (_queue.isNotEmpty) {
      retryAll();
    }
  }

  /// Persists the current queue state.
  Future<void> _persistQueue() async {
    final list = _queue.map((job) => job.toJson()).toList();
    await _retryBox.put('queue', list);
  }

  /// Reconstructs the optimistic message ID from tracking ID.
  static int getOptimisticIdFromTrackingId(String trackingId) {
    final parts = trackingId.split('_');
    final baseId = int.tryParse(parts[0]) ?? 0;
    if (parts.length > 1) {
      final index = int.tryParse(parts[1]);
      if (index != null) {
        return baseId + index;
      }
    }
    return baseId;
  }

  /// Queues a failed upload for automatic retry.
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

    await _persistQueue();

    debugPrint(
      '📤 Queued upload for retry: $fileName (queue size: ${_queue.length})',
    );
  }

  bool _isRetrying = false;

  /// Retries all pending uploads.
  Future<void> retryAll() async {
    if (_queue.isEmpty) {
      debugPrint('📤 No pending uploads to retry');
      return;
    }

    // Prevent concurrent retry cycles. retryAll() can now be triggered from
    // several sources (connectivity change, socket reconnect, startup kick, and
    // the chat screen). Without this guard, overlapping cycles would upload the
    // same file twice and deliver duplicate messages to the recipient.
    if (_isRetrying) {
      debugPrint('📤 Retry already in progress, skipping');
      return;
    }

    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity.contains(ConnectivityResult.none)) {
      debugPrint('📤 Device is offline, skipping retry');
      return;
    }

    // Don't attempt (and thus permanently fail/drop) queued uploads before the
    // user is authenticated — keep them in the queue until a token exists.
    final token = await StorageService.getToken();
    if (token == null) {
      debugPrint('📤 No auth token yet, keeping uploads queued');
      return;
    }

    _isRetrying = true;
    try {
      await _runRetryCycle();
    } finally {
      _isRetrying = false;
    }
  }

  /// Runs a single pass over the queue, uploading each pending file.
  Future<void> _runRetryCycle() async {
    final toRetry = List<_PendingUpload>.from(_queue);
    debugPrint('🔄 Retrying ${toRetry.length} pending uploads...');

    for (final job in toRetry) {
      final tempFile = File(job.tempFilePath);
      if (!await tempFile.exists()) {
        debugPrint(
          '⚠️ Temp file missing for ${job.fileName}, removing from queue',
        );
        _queue.remove(job);
        await _persistQueue();
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
              message: result.message,
            ),
          );

          // Update message in cache database
          final currentUserId = await StorageService.getUserId();
          if (currentUserId != null && result.message != null) {
            final optimisticId = getOptimisticIdFromTrackingId(job.trackingId);
            final cachedMessages =
                await ChatCacheService.loadConversationMessages(
                  currentUserId,
                  job.recipientId,
                );
            final index = cachedMessages.indexWhere(
              (m) => m.id == optimisticId,
            );
            if (index != -1) {
              // Preserve the user's caption — the upload echo frequently omits
              // it, which previously made a photo's caption vanish after an
              // offline→online retry.
              cachedMessages[index] =
                  (result.message!.caption?.isNotEmpty == true)
                  ? result.message!
                  : result.message!.copyWith(caption: job.caption);
              await ChatCacheService.saveConversationMessages(
                currentUserId,
                job.recipientId,
                cachedMessages,
              );
              debugPrint(
                '💾 Updated retry-succeeded message in cache database',
              );
            } else {
              // If not found in conversation cache, add it as a new message
              await ChatCacheService.addMessageToCache(
                currentUserId,
                job.recipientId,
                result.message!,
              );
              debugPrint(
                '💾 Saved retry-succeeded message directly to cache database',
              );
            }
          }

          _safeDelete(tempFile);
          _queue.remove(job);
          await _persistQueue();
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
          await _persistQueue();
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
  Future<void> cancelUpload(String trackingId) async {
    final job = _queue.cast<_PendingUpload?>().firstWhere(
      (j) => j?.trackingId == trackingId,
      orElse: () => null,
    );
    if (job != null) {
      _safeDelete(File(job.tempFilePath));
      _queue.remove(job);
      await _persistQueue();
      debugPrint('🗑️ Cancelled upload $trackingId');
    }
  }

  /// Clears the entire queue and cleans up temp files.
  Future<void> clearQueue() async {
    for (final job in _queue) {
      _safeDelete(File(job.tempFilePath));
    }
    _queue.clear();
    await _persistQueue();
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
