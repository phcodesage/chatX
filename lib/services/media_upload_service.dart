import 'dart:math';

import 'package:dio/dio.dart';

import '../config/api_config.dart';
import '../models/message.dart';
import 'compression_service.dart';
import 'storage_service.dart';

/// Status of an individual file upload.
enum UploadStatus { pending, uploading, success, failed, retrying }

/// Strategy for batch uploads.
enum UploadStrategy { parallel, sequential }

/// Tracks progress of a single file within a batch upload.
class UploadProgress {
  /// Zero-based index of the file in the batch.
  final int fileIndex;

  /// Total number of files in the batch.
  final int totalFiles;

  /// Upload progress for this file (0.0 to 1.0).
  final double fileProgress;

  /// Current status of this file's upload.
  final UploadStatus status;

  const UploadProgress({
    required this.fileIndex,
    required this.totalFiles,
    required this.fileProgress,
    required this.status,
  });

  @override
  String toString() =>
      'UploadProgress(file ${fileIndex + 1}/$totalFiles, '
      '${(fileProgress * 100).toStringAsFixed(0)}%, $status)';
}

/// Result of uploading a single file.
class UploadResult {
  /// Whether the upload completed successfully.
  final bool success;

  /// The message created by the backend on success.
  final Message? message;

  /// Error description on failure.
  final String? errorMessage;

  /// Number of retry attempts made before final result.
  final int retryCount;

  /// Whether the failure was due to a temporary network issue
  /// (timeout, connection error, server 5xx). When true, the
  /// upload can be retried later when connectivity is restored.
  final bool isNetworkError;

  const UploadResult({
    required this.success,
    this.message,
    this.errorMessage,
    required this.retryCount,
    this.isNetworkError = false,
  });

  @override
  String toString() =>
      'UploadResult(success: $success, retries: $retryCount'
      '${isNetworkError ? ', networkError' : ''}'
      '${errorMessage != null ? ', error: $errorMessage' : ''})';
}

/// Service responsible for uploading compressed media files to the Flask backend.
///
/// Supports single-file upload with retry logic and batch upload with
/// strategy selection (parallel for ≤5 files, sequential for >5).
class MediaUploadService {
  /// Upload endpoint path.
  static const String _uploadPath = '/api/mobile/messages/upload';

  /// Uploads a single compressed file to the backend.
  ///
  /// Sends a multipart POST to `/api/mobile/messages/upload` with:
  /// - `file`: the binary file data
  /// - `recipient_id`: the recipient user ID
  /// - `caption`: optional caption text
  ///
  /// On success, parses the response `message` object into a [Message].
  ///
  /// Retries up to [maxRetries] times with exponential backoff (1s, 2s, 4s)
  /// on network errors, timeouts, or server errors (5xx).
  ///
  /// [timeout] defaults to 120 seconds per attempt.
  static Future<UploadResult> uploadSingleFile({
    required CompressionResult file,
    required int recipientId,
    String? caption,
    void Function(double progress)? onProgress,
    int maxRetries = 3,
    Duration timeout = const Duration(seconds: 120),
  }) async {
    int retryCount = 0;

    final dio = Dio(BaseOptions(
      connectTimeout: timeout,
      receiveTimeout: timeout,
      validateStatus: (_) => true,
    ));

    while (true) {
      try {
        // Report upload starting
        onProgress?.call(0.0);

        final token = await StorageService.getToken();
        if (token == null) {
          return const UploadResult(
            success: false,
            errorMessage: 'No authentication token found',
            retryCount: 0,
          );
        }

        final url = '${ApiConfig.baseUrl}$_uploadPath';

        final formData = FormData.fromMap({
          'recipient_id': recipientId.toString(),
          if (caption != null && caption.isNotEmpty) 'caption': caption,
          'file': MultipartFile.fromBytes(
            file.bytes,
            filename: file.fileName,
            contentType: _parseMediaType(file.mimeType),
          ),
        });

        final response = await dio.post(
          url,
          data: formData,
          options: Options(
            headers: {'Authorization': 'Bearer $token'},
          ),
          onSendProgress: (int sent, int total) {
            if (total > 0) {
              onProgress?.call(sent / total);
            }
          },
        );

        // Report upload complete
        onProgress?.call(1.0);

        final statusCode = response.statusCode ?? 0;

        if (statusCode == 200 || statusCode == 201) {
          final data = response.data as Map<String, dynamic>;

          // Parse the message object from the response
          final messageJson = data['message'] as Map<String, dynamic>?;
          if (messageJson != null) {
            final message = Message.fromJson(messageJson);
            return UploadResult(
              success: true,
              message: message,
              retryCount: retryCount,
            );
          }

          // Fallback: response doesn't contain a message object but was successful
          return UploadResult(
            success: true,
            errorMessage: 'Upload succeeded but no message object in response',
            retryCount: retryCount,
          );
        } else if (_isRetryableStatusCode(statusCode)) {
          // Server error (5xx) — retry if attempts remain
          if (retryCount < maxRetries) {
            await _backoff(retryCount);
            retryCount++;
            onProgress?.call(0.0);
            continue;
          }
          return UploadResult(
            success: false,
            errorMessage:
                'Server error $statusCode after $retryCount retries',
            retryCount: retryCount,
            isNetworkError: true,
          );
        } else {
          // Client error (4xx) — don't retry
          String errorMsg = 'Upload failed with status $statusCode';
          try {
            final errorData = response.data;
            if (errorData is Map && errorData['error'] != null) {
              errorMsg = errorData['error'].toString();
            }
          } catch (_) {}
          return UploadResult(
            success: false,
            errorMessage: errorMsg,
            retryCount: retryCount,
          );
        }
      } on DioException catch (e) {
        if (e.type == DioExceptionType.cancel) {
          // Cancellation is non-retryable
          return UploadResult(
            success: false,
            errorMessage: 'Upload cancelled',
            retryCount: retryCount,
          );
        }

        // connectionTimeout, receiveTimeout, connectionError are retryable
        if (e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.connectionError) {
          if (retryCount < maxRetries) {
            await _backoff(retryCount);
            retryCount++;
            onProgress?.call(0.0);
            continue;
          }
          return UploadResult(
            success: false,
            errorMessage: 'Upload timed out after $retryCount retries',
            retryCount: retryCount,
            isNetworkError: true,
          );
        }

        // Other DioException types — retry if attempts remain
        if (retryCount < maxRetries) {
          await _backoff(retryCount);
          retryCount++;
          onProgress?.call(0.0);
          continue;
        }
        return UploadResult(
          success: false,
          errorMessage: 'Upload failed: ${e.message}',
          retryCount: retryCount,
          isNetworkError: true,
        );
      } catch (e) {
        // Other unexpected exceptions — retry if attempts remain
        if (retryCount < maxRetries) {
          await _backoff(retryCount);
          retryCount++;
          onProgress?.call(0.0);
          continue;
        }
        return UploadResult(
          success: false,
          errorMessage: 'Upload failed: ${e.toString()}',
          retryCount: retryCount,
          isNetworkError: true,
        );
      }
    }
  }

  /// Uploads a batch of compressed files.
  ///
  /// Uses parallel upload for ≤5 files, sequential for >5.
  /// Attaches [caption] to the first file only.
  /// Calls [onProgress] after each file status change.
  /// Continues uploading remaining files even if one fails.
  static Future<List<UploadResult>> uploadBatch({
    required List<CompressionResult> files,
    required int recipientId,
    String? caption,
    void Function(UploadProgress)? onProgress,
    int maxRetries = 3,
    Duration timeout = const Duration(seconds: 120),
  }) async {
    final strategy = getStrategy(files.length);
    final totalFiles = files.length;

    if (strategy == UploadStrategy.parallel) {
      return _uploadParallel(
        files: files,
        recipientId: recipientId,
        caption: caption,
        onProgress: onProgress,
        maxRetries: maxRetries,
        timeout: timeout,
        totalFiles: totalFiles,
      );
    } else {
      return _uploadSequential(
        files: files,
        recipientId: recipientId,
        caption: caption,
        onProgress: onProgress,
        maxRetries: maxRetries,
        timeout: timeout,
        totalFiles: totalFiles,
      );
    }
  }

  /// Determines upload strategy based on batch size.
  ///
  /// Returns [UploadStrategy.parallel] for ≤5 files,
  /// [UploadStrategy.sequential] for >5 files.
  static UploadStrategy getStrategy(int batchSize) =>
      batchSize <= 5 ? UploadStrategy.parallel : UploadStrategy.sequential;

  /// Uploads files in parallel (all at once).
  static Future<List<UploadResult>> _uploadParallel({
    required List<CompressionResult> files,
    required int recipientId,
    String? caption,
    void Function(UploadProgress)? onProgress,
    int maxRetries = 3,
    Duration timeout = const Duration(seconds: 120),
    required int totalFiles,
  }) async {
    final futures = <Future<UploadResult>>[];

    for (int i = 0; i < files.length; i++) {
      // Caption only on first file
      final fileCaption = (i == 0) ? caption : null;

      onProgress?.call(UploadProgress(
        fileIndex: i,
        totalFiles: totalFiles,
        fileProgress: 0.0,
        status: UploadStatus.uploading,
      ));

      futures.add(
        uploadSingleFile(
          file: files[i],
          recipientId: recipientId,
          caption: fileCaption,
          onProgress: (progress) {
            onProgress?.call(UploadProgress(
              fileIndex: i,
              totalFiles: totalFiles,
              fileProgress: progress,
              status: UploadStatus.uploading,
            ));
          },
          maxRetries: maxRetries,
          timeout: timeout,
        ).then((result) {
          onProgress?.call(UploadProgress(
            fileIndex: i,
            totalFiles: totalFiles,
            fileProgress: 1.0,
            status: result.success ? UploadStatus.success : UploadStatus.failed,
          ));
          return result;
        }),
      );
    }

    return Future.wait(futures);
  }

  /// Uploads files sequentially (one at a time).
  static Future<List<UploadResult>> _uploadSequential({
    required List<CompressionResult> files,
    required int recipientId,
    String? caption,
    void Function(UploadProgress)? onProgress,
    int maxRetries = 3,
    Duration timeout = const Duration(seconds: 120),
    required int totalFiles,
  }) async {
    final results = <UploadResult>[];

    for (int i = 0; i < files.length; i++) {
      // Caption only on first file
      final fileCaption = (i == 0) ? caption : null;

      onProgress?.call(UploadProgress(
        fileIndex: i,
        totalFiles: totalFiles,
        fileProgress: 0.0,
        status: UploadStatus.uploading,
      ));

      final result = await uploadSingleFile(
        file: files[i],
        recipientId: recipientId,
        caption: fileCaption,
        onProgress: (progress) {
          onProgress?.call(UploadProgress(
            fileIndex: i,
            totalFiles: totalFiles,
            fileProgress: progress,
            status: UploadStatus.uploading,
          ));
        },
        maxRetries: maxRetries,
        timeout: timeout,
      );

      onProgress?.call(UploadProgress(
        fileIndex: i,
        totalFiles: totalFiles,
        fileProgress: 1.0,
        status: result.success ? UploadStatus.success : UploadStatus.failed,
      ));

      results.add(result);
    }

    return results;
  }

  /// Determines if an HTTP status code is retryable (server errors).
  static bool _isRetryableStatusCode(int statusCode) {
    return statusCode >= 500 && statusCode < 600;
  }

  /// Applies exponential backoff delay before a retry attempt.
  ///
  /// Delays: 1s, 2s, 4s for retries 0, 1, 2.
  static Future<void> _backoff(int retryAttempt) async {
    final delaySeconds = pow(2, retryAttempt).toInt(); // 1, 2, 4
    await Future.delayed(Duration(seconds: delaySeconds));
  }

  /// Parses a MIME type string into a [DioMediaType] for the multipart request.
  static DioMediaType _parseMediaType(String mimeType) {
    final parts = mimeType.split('/');
    if (parts.length == 2) {
      return DioMediaType(parts[0], parts[1]);
    }
    return DioMediaType('application', 'octet-stream');
  }
}
