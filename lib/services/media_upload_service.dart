import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

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

  const UploadResult({
    required this.success,
    this.message,
    this.errorMessage,
    required this.retryCount,
  });

  @override
  String toString() =>
      'UploadResult(success: $success, retries: $retryCount'
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

        final uri = Uri.parse('${ApiConfig.baseUrl}$_uploadPath');

        final request = http.MultipartRequest('POST', uri);
        request.headers['Authorization'] = 'Bearer $token';
        request.fields['recipient_id'] = recipientId.toString();

        if (caption != null && caption.isNotEmpty) {
          request.fields['caption'] = caption;
        }

        // Parse MIME type for the multipart file
        final mediaType = _parseMediaType(file.mimeType);

        request.files.add(
          http.MultipartFile.fromBytes(
            'file',
            file.bytes,
            filename: file.fileName,
            contentType: mediaType,
          ),
        );

        // Send the request with timeout
        final streamedResponse = await request.send().timeout(timeout);
        final response = await http.Response.fromStream(streamedResponse);

        // Report upload complete (we don't have granular stream progress
        // with the standard http package, so we go 0% → 100%)
        onProgress?.call(1.0);

        if (response.statusCode == 200 || response.statusCode == 201) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;

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
        } else if (_isRetryableStatusCode(response.statusCode)) {
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
                'Server error ${response.statusCode} after $retryCount retries',
            retryCount: retryCount,
          );
        } else {
          // Client error (4xx) — don't retry
          String errorMsg = 'Upload failed with status ${response.statusCode}';
          try {
            final errorData = jsonDecode(response.body);
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
      } on TimeoutException {
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
        );
      } catch (e) {
        // Network error or other exception — retry if attempts remain
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

  /// Parses a MIME type string into a [MediaType] for the multipart request.
  static MediaType _parseMediaType(String mimeType) {
    final parts = mimeType.split('/');
    if (parts.length == 2) {
      return MediaType(parts[0], parts[1]);
    }
    return MediaType('application', 'octet-stream');
  }
}
