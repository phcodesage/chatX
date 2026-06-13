import 'package:flutter/foundation.dart';

import '../services/media_upload_service.dart';

/// Tracks per-file upload progress for media uploads in the chat screen.
///
/// Scoped to the chat screen's lifecycle. Uses ChangeNotifier to notify
/// listeners (the chat message list) when upload progress changes.
class MediaUploadState extends ChangeNotifier {
  final Map<String, _UploadEntry> _uploads = {};

  /// IDs of uploads that have been finalized (completed/removed). A late
  /// progress callback can arrive AFTER an upload is removed on success and
  /// would otherwise re-insert the entry at 100% — leaving the "Send File"
  /// chip stuck showing 100% even though the message was already sent. We
  /// remember finalized IDs and ignore any further updates for them.
  final Set<String> _finalized = {};

  /// Updates the progress for a specific file upload.
  ///
  /// Enforces monotonic progress: ignores stale values where progress
  /// decreases without a retry reset. Allows progress to decrease only
  /// when the status indicates a retry (transitioning to retrying or
  /// uploading from a different status).
  void updateProgress(String fileId, UploadProgress progress) {
    // A finalized upload can only be revived by an explicit retry; ignore any
    // other (late) progress callbacks that would resurrect a finished upload.
    if (_finalized.contains(fileId)) {
      if (progress.status == UploadStatus.retrying) {
        _finalized.remove(fileId);
      } else {
        return;
      }
    }

    // A `success` update means the upload finished — the batch uploader emits a
    // final progress event with status=success at 100%. Storing it would leave
    // the entry sitting in the map (hasActiveUploads stays true, overallProgress
    // = 1.0), so the "Send File" chip would be stuck at 100%. Treat it as a
    // removal/finalize instead.
    if (progress.status == UploadStatus.success) {
      removeUpload(fileId);
      return;
    }

    final existing = _uploads[fileId];

    // Allow progress reset only on retry (status change to retrying/uploading from a different status)
    final isRetryReset = existing != null &&
        progress.fileProgress < existing.progress.fileProgress &&
        (progress.status == UploadStatus.retrying ||
            (progress.status == UploadStatus.uploading &&
                existing.progress.status == UploadStatus.retrying));

    // Ignore stale values (lower progress without a retry reset)
    if (existing != null &&
        progress.fileProgress < existing.progress.fileProgress &&
        !isRetryReset) {
      return;
    }

    _uploads[fileId] = _UploadEntry(progress: progress);
    notifyListeners();
  }

  /// Marks a file upload as failed with an error message.
  void markFailed(String fileId, String errorMessage) {
    // Don't resurrect an already-finalized (successfully removed) upload.
    if (_finalized.contains(fileId)) return;
    final existing = _uploads[fileId]?.progress;
    _uploads[fileId] = _UploadEntry(
      // Force the status to `failed` (preserving the file index/progress).
      // Previously this kept the existing progress as-is, which left the
      // status at `uploading` at ~100% — so failed uploads were neither
      // detected as failed nor cleaned up, and the chip stayed at 100%.
      progress: UploadProgress(
        fileIndex: existing?.fileIndex ?? 0,
        totalFiles: existing?.totalFiles ?? 1,
        fileProgress: existing?.fileProgress ?? 0.0,
        status: UploadStatus.failed,
      ),
      errorMessage: errorMessage,
    );
    notifyListeners();
  }

  /// Removes a completed or cancelled upload from tracking.
  void removeUpload(String fileId) {
    _uploads.remove(fileId);
    _finalized.add(fileId);
    notifyListeners();
  }

  /// Removes an upload only if it's still in a non-terminal in-flight state
  /// (pending/uploading). Used to sweep orphaned entries after an upload flow
  /// concludes without explicitly removing them (e.g. an unexpected exception,
  /// or the message was confirmed via the socket echo instead of the REST
  /// result) — otherwise the "Send File" chip stays stuck at 100%. Intentional
  /// `retrying`/`failed` entries are left untouched.
  void clearIfInFlight(String fileId) {
    final status = _uploads[fileId]?.progress.status;
    if (status == UploadStatus.pending || status == UploadStatus.uploading) {
      removeUpload(fileId);
    }
  }

  /// Clears all tracked uploads.
  void clearAll() {
    _uploads.clear();
    _finalized.clear();
    notifyListeners();
  }

  /// Gets the progress for a specific file upload.
  UploadProgress? getProgress(String fileId) => _uploads[fileId]?.progress;

  /// Gets the error message for a specific file upload.
  String? getError(String fileId) => _uploads[fileId]?.errorMessage;

  /// Returns all active upload entries as a map of fileId to progress.
  Map<String, UploadProgress> get uploads {
    return _uploads.map((key, entry) => MapEntry(key, entry.progress));
  }

  /// Returns all file IDs currently being tracked.
  List<String> get activeUploadIds => _uploads.keys.toList();

  /// Whether there are any active uploads.
  bool get hasActiveUploads => _uploads.isNotEmpty;

  /// Whether there are any failed uploads.
  bool get hasFailedUploads =>
      _uploads.values.any((e) => e.progress.status == UploadStatus.failed);

  /// Returns only the failed upload IDs.
  List<String> get failedUploadIds => _uploads.entries
      .where((e) => e.value.progress.status == UploadStatus.failed)
      .map((e) => e.key)
      .toList();
  /// Returns the overall upload progress across all active uploads (0.0 to 1.0).
  /// Returns null if no uploads are active.
  double? get overallProgress {
    if (_uploads.isEmpty) return null;
    final activeEntries = _uploads.values.toList();
    if (activeEntries.isEmpty) return null;
    final total = activeEntries.fold<double>(
      0.0,
      (sum, entry) => sum + entry.progress.fileProgress,
    );
    return total / activeEntries.length;
  }
}

/// Internal entry tracking both progress and error state.
class _UploadEntry {
  final UploadProgress progress;
  final String? errorMessage;

  const _UploadEntry({
    required this.progress,
    this.errorMessage,
  });
}
