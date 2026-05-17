import 'package:flutter/material.dart';

import '../services/media_upload_service.dart';
import '../state/media_upload_state.dart';

/// Displays per-file upload progress indicators in the chat message list.
///
/// Shows a compact card with:
/// - A progress bar for each uploading file
/// - Error indicators on failed uploads with a retry button
/// - Automatically removed on completion
class UploadProgressIndicator extends StatelessWidget {
  final MediaUploadState uploadState;
  final VoidCallback? onRetry;

  const UploadProgressIndicator({
    super.key,
    required this.uploadState,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: uploadState,
      builder: (context, _) {
        if (!uploadState.hasActiveUploads) {
          return const SizedBox.shrink();
        }

        final uploadIds = uploadState.activeUploadIds;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: uploadIds.map((fileId) {
              final progress = uploadState.getProgress(fileId);
              final error = uploadState.getError(fileId);

              if (progress == null) return const SizedBox.shrink();

              return _buildFileProgressCard(
                fileId: fileId,
                progress: progress,
                error: error,
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Widget _buildFileProgressCard({
    required String fileId,
    required UploadProgress progress,
    String? error,
  }) {
    final isFailed = progress.status == UploadStatus.failed;
    final isUploading = progress.status == UploadStatus.uploading;
    final isPending = progress.status == UploadStatus.pending;
    final isRetrying = progress.status == UploadStatus.retrying;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      constraints: const BoxConstraints(maxWidth: 260),
      decoration: BoxDecoration(
        color: isFailed
            ? const Color(0xFF3D1F1F)
            : const Color(0xFF1E2A1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isFailed
              ? const Color(0xFF7F2D2D)
              : const Color(0xFF2D5A2D),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header row: file info + status
          Row(
            children: [
              Icon(
                isFailed ? Icons.error_outline : Icons.upload_file,
                color: isFailed ? const Color(0xFFEF4444) : const Color(0xFF25D366),
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _statusLabel(progress, error),
                  style: TextStyle(
                    color: isFailed ? const Color(0xFFEF4444) : Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isFailed && onRetry != null)
                GestureDetector(
                  onTap: onRetry,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF25D366).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Retry',
                      style: TextStyle(
                        color: Color(0xFF25D366),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          // Progress bar (only for uploading/pending/retrying states)
          if (isUploading || isPending || isRetrying) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress.fileProgress,
                backgroundColor: Colors.white.withValues(alpha: 0.1),
                valueColor: AlwaysStoppedAnimation<Color>(
                  isRetrying
                      ? const Color(0xFFF59E0B)
                      : const Color(0xFF25D366),
                ),
                minHeight: 3,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${(progress.fileProgress * 100).toInt()}%',
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 10,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _statusLabel(UploadProgress progress, String? error) {
    switch (progress.status) {
      case UploadStatus.pending:
        return 'Waiting to upload (${progress.fileIndex + 1}/${progress.totalFiles})';
      case UploadStatus.uploading:
        return 'Uploading file ${progress.fileIndex + 1} of ${progress.totalFiles}';
      case UploadStatus.retrying:
        return 'Retrying upload...';
      case UploadStatus.failed:
        return error ?? 'Upload failed';
      case UploadStatus.success:
        return 'Upload complete';
    }
  }
}
