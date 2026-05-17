import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

import '../services/compression_service.dart';
import '../services/media_picker_service.dart';
import '../services/media_upload_service.dart';
import '../state/media_upload_state.dart';

/// Formats a [Duration] as mm:ss for durations under 1 hour,
/// or h:mm:ss for durations of 1 hour or longer.
String formatVideoDuration(Duration duration) {
  final totalSeconds = duration.inSeconds;
  if (totalSeconds < 0) return '00:00';

  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;

  if (hours >= 1) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}

/// Returns a display string for the item count, e.g. "1 item selected" or "3 items selected".
String formatItemCount(int count) {
  if (count == 1) return '1 item selected';
  return '$count items selected';
}

/// Tracks compression progress state.
class CompressionProgress {
  final int completed;
  final int total;

  const CompressionProgress({required this.completed, required this.total});
}

/// Result returned when the user minimizes the preview screen.
/// Contains the pending items and caption so the chat screen can
/// show a badge and restore the preview later.
class MinimizedMediaResult {
  final List<AssetEntity> items;
  final String caption;

  const MinimizedMediaResult({required this.items, this.caption = ''});
}

/// Full-screen preview screen displayed after media selection.
/// Shows selected items in a thumbnail strip with options to reorder,
/// remove, add captions, and confirm sending.
class MediaPreviewScreen extends StatefulWidget {
  final List<AssetEntity> selectedAssets;
  final int recipientId;
  final bool fromCamera;
  final MediaUploadState? mediaUploadState;

  const MediaPreviewScreen({
    super.key,
    required this.selectedAssets,
    required this.recipientId,
    this.fromCamera = false,
    this.mediaUploadState,
  });

  @override
  State<MediaPreviewScreen> createState() => _MediaPreviewScreenState();
}

class _MediaPreviewScreenState extends State<MediaPreviewScreen> {
  late List<AssetEntity> _items;
  int _currentIndex = 0;
  bool _isSending = false;
  CompressionProgress? _compressionProgress;
  List<CompressionResult>? _compressedResults;

  final TextEditingController _captionController = TextEditingController();

  /// PageController for swiping between preview items.
  late PageController _pageController;

  /// TransformationController for pinch/double-tap zoom.
  final TransformationController _transformationController =
      TransformationController();

  /// Video player controller for previewing video items.
  VideoPlayerController? _videoController;
  bool _isVideoPlaying = false;
  bool _isVideoInitializing = false;

  @override
  void initState() {
    super.initState();
    _items = List<AssetEntity>.from(widget.selectedAssets);
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _captionController.dispose();
    _pageController.dispose();
    _transformationController.dispose();
    _disposeVideoController();
    super.dispose();
  }

  void _disposeVideoController() {
    _videoController?.dispose();
    _videoController = null;
    _isVideoPlaying = false;
    _isVideoInitializing = false;
  }

  AssetEntity get _currentItem => _items[_currentIndex];

  bool get _isCurrentItemVideo => _currentItem.type == AssetType.video;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        title: Row(
          children: [
            // Back button (text only)
            TextButton(
              onPressed: _handleBack,
              child: const Text(
                'Back',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
            const Spacer(),
            // Minimize button (text only)
            TextButton(
              onPressed: _handleMinimize,
              child: const Text(
                'Minimize',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
            // Download button (text only)
            TextButton(
              onPressed: _handleDownload,
              child: const Text(
                'Download',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // Full preview area
              Expanded(
                child: _buildPreviewArea(),
              ),
              // File name and size info
              _buildFileInfo(),
              // Thumbnail strip
              _buildThumbnailStrip(),
              // Caption input and send button
              _buildCaptionAndSend(),
            ],
          ),
          // Compression progress overlay
          if (_compressionProgress != null) _buildCompressionOverlay(),
        ],
      ),
    );
  }

  /// Builds the file name and size info bar for the current item.
  Widget _buildFileInfo() {
    return Container(
      width: double.infinity,
      color: const Color(0xFF1E1E1E),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: FutureBuilder<String>(
        key: ValueKey('fileinfo_${_currentItem.id}_$_currentIndex'),
        future: _getFileInfo(_currentItem),
        builder: (context, snapshot) {
          final info = snapshot.data ?? 'Loading...';
          return Text(
            info,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );
        },
      ),
    );
  }

  /// Gets the file name and size string for a given asset.
  Future<String> _getFileInfo(AssetEntity asset) async {
    final title = asset.title ?? 'Unknown';
    final file = await asset.file;
    if (file == null) return title;

    final bytes = await file.length();
    final sizeStr = _formatFileSize(bytes);
    return '$title • $sizeStr';
  }

  /// Formats a byte count into a human-readable file size string.
  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// Builds the main preview area showing the currently selected item.
  Widget _buildPreviewArea() {
    // If current item is a video and we have an initialized controller, show video player
    if (_isCurrentItemVideo && _videoController != null && _videoController!.value.isInitialized) {
      return _buildVideoPlayer();
    }

    return Container(
      color: Colors.black,
      child: PageView.builder(
        itemCount: _items.length,
        controller: _pageController,
        onPageChanged: (index) {
          setState(() {
            _disposeVideoController();
            _currentIndex = index;
            // Reset zoom when switching pages
            _transformationController.value = Matrix4.identity();
          });
        },
        itemBuilder: (context, index) {
          final item = _items[index];
          return FutureBuilder<Uint8List?>(
            key: ValueKey('preview_${item.id}_$index'),
            future: item.thumbnailDataWithSize(
              const ThumbnailSize(800, 800),
              quality: 90,
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(
                    color: Color(0xFF7C3AED),
                  ),
                );
              }

              if (snapshot.data == null) {
                return const Center(
                  child: Icon(Icons.broken_image, color: Colors.white54, size: 64),
                );
              }

              return Stack(
                fit: StackFit.expand,
                children: [
                  // Double-tap to zoom + pinch-to-zoom image preview
                  GestureDetector(
                    onDoubleTap: _handleDoubleTapZoom,
                    child: InteractiveViewer(
                      transformationController: _transformationController,
                      minScale: 1.0,
                      maxScale: 4.0,
                      child: Image.memory(
                        snapshot.data!,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  // Video overlay (play button + duration) — tap to start playback
                  if (item.type == AssetType.video && index == _currentIndex)
                    _buildVideoOverlay(),
                ],
              );
            },
          );
        },
      ),
    );
  }

  /// Handles double-tap to toggle zoom (1x ↔ 2.5x).
  void _handleDoubleTapZoom() {
    final currentScale = _transformationController.value.getMaxScaleOnAxis();
    if (currentScale > 1.1) {
      // Zoomed in — reset to 1x
      _transformationController.value = Matrix4.identity();
    } else {
      // Zoom to 2.5x centered
      final zoomScale = 2.5;
      final midX = MediaQuery.of(context).size.width / 2;
      final midY = MediaQuery.of(context).size.height / 3;
      _transformationController.value = Matrix4.identity()
        ..translate(midX * (1 - zoomScale), midY * (1 - zoomScale))
        ..scale(zoomScale);
    }
  }

  /// Builds the actual video player widget when video is initialized.
  Widget _buildVideoPlayer() {
    final controller = _videoController!;
    return GestureDetector(
      onTap: _toggleVideoPlayback,
      child: Container(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: controller.value.aspectRatio > 0
                    ? controller.value.aspectRatio
                    : 16 / 9,
                child: VideoPlayer(controller),
              ),
            ),
            // Play/pause overlay
            if (!_isVideoPlaying)
              const Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Icon(
                      Icons.play_arrow,
                      color: Colors.white,
                      size: 48,
                    ),
                  ),
                ),
              ),
            // Progress bar at bottom
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: VideoProgressIndicator(
                controller,
                allowScrubbing: true,
                colors: const VideoProgressColors(
                  playedColor: Color(0xFF7C3AED),
                  bufferedColor: Colors.white24,
                  backgroundColor: Colors.white10,
                ),
              ),
            ),
            // Duration label bottom-right
            Positioned(
              bottom: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  formatVideoDuration(Duration(seconds: _currentItem.duration)),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Initializes the video player for the current video item.
  Future<void> _initializeVideoPlayer() async {
    if (_isVideoInitializing) return;

    setState(() {
      _isVideoInitializing = true;
    });

    _disposeVideoController();

    try {
      final file = await _currentItem.file;
      if (file == null || !mounted) return;

      final controller = VideoPlayerController.file(file);
      await controller.initialize();

      if (!mounted) {
        controller.dispose();
        return;
      }

      controller.addListener(() {
        if (mounted) {
          final isPlaying = controller.value.isPlaying;
          if (isPlaying != _isVideoPlaying) {
            setState(() {
              _isVideoPlaying = isPlaying;
            });
          }
          // When video finishes, reset
          if (controller.value.position >= controller.value.duration) {
            setState(() {
              _isVideoPlaying = false;
            });
            controller.seekTo(Duration.zero);
            controller.pause();
          }
        }
      });

      setState(() {
        _videoController = controller;
        _isVideoInitializing = false;
      });

      // Auto-play after initialization
      controller.play();
      setState(() {
        _isVideoPlaying = true;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isVideoInitializing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to load video preview'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Toggles video playback (play/pause).
  void _toggleVideoPlayback() {
    final controller = _videoController;
    if (controller == null) return;

    if (controller.value.isPlaying) {
      controller.pause();
    } else {
      controller.play();
    }
  }

  /// Builds the play button overlay and duration label for video items.
  /// Tapping the play button initializes and starts video playback.
  Widget _buildVideoOverlay() {
    return GestureDetector(
      onTap: _initializeVideoPlayer,
      child: Stack(
        children: [
          // Play button centered (or loading indicator)
          Center(
            child: _isVideoInitializing
                ? const CircularProgressIndicator(color: Color(0xFF7C3AED))
                : const DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Icon(
                        Icons.play_arrow,
                        color: Colors.white,
                        size: 48,
                      ),
                    ),
                  ),
          ),
          // Duration label bottom-right
          Positioned(
            bottom: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                formatVideoDuration(Duration(seconds: _currentItem.duration)),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Handles removing an item from the selection at the given index.
  /// If all items are removed, dismisses the preview and returns to chat.
  void _removeItem(int index) {
    setState(() {
      _items.removeAt(index);

      if (_items.isEmpty) {
        // Auto-dismiss preview and return to chat if all items removed
        Navigator.of(context).pop(<AssetEntity>[]);
        return;
      }

      // Adjust _currentIndex after removal
      if (_currentIndex >= _items.length) {
        _currentIndex = _items.length - 1;
      } else if (index < _currentIndex) {
        _currentIndex--;
      }
    });
  }

  /// Builds the horizontal thumbnail strip at the bottom showing the selection list.
  Widget _buildThumbnailStrip() {
    return Container(
      height: 80,
      color: const Color(0xFF1E1E1E),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        itemCount: _items.length,
        itemBuilder: (context, index) {
          final asset = _items[index];
          final isSelected = index == _currentIndex;

          return GestureDetector(
            key: ValueKey('thumb_${asset.id}'),
            onTap: () {
              setState(() {
                _disposeVideoController();
                _currentIndex = index;
                _transformationController.value = Matrix4.identity();
              });
              _pageController.jumpToPage(index);
            },
            child: Container(
              width: 64,
              height: 64,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF7C3AED)
                      : Colors.transparent,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildThumbnail(asset),
                    // Video duration on thumbnail
                    if (asset.type == AssetType.video)
                      Positioned(
                        bottom: 2,
                        right: 2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 3,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: Text(
                            formatVideoDuration(
                              Duration(seconds: asset.duration),
                            ),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                            ),
                          ),
                        ),
                      ),
                    // Remove button (X)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: () => _removeItem(index),
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: const BoxDecoration(
                            color: Colors.black87,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Builds a thumbnail widget for a given asset.
  Widget _buildThumbnail(AssetEntity asset) {
    return FutureBuilder<Uint8List?>(
      future: asset.thumbnailDataWithSize(
        const ThumbnailSize(150, 150),
        quality: 80,
      ),
      builder: (context, snapshot) {
        if (snapshot.data != null) {
          return Image.memory(
            snapshot.data!,
            fit: BoxFit.cover,
          );
        }
        return Container(
          color: Colors.grey[800],
          child: const Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF7C3AED),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Builds the caption input field and send button row.
  Widget _buildCaptionAndSend() {
    return Container(
      color: const Color(0xFF1E1E1E),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Caption text field
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF333333),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: _captionController,
                  maxLength: 1024,
                  maxLines: 1,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'Add a caption...',
                    hintStyle: TextStyle(color: Colors.grey),
                    border: InputBorder.none,
                    counterText: '', // Hide the character counter
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Send button with item count badge
            Stack(
              clipBehavior: Clip.none,
              children: [
                GestureDetector(
                  onTap: _isSending ? null : _handleSend,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: _isSending
                          ? Colors.grey[700]
                          : const Color(0xFF7C3AED),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: _isSending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Send',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
                // Badge showing file count
                if (_items.length > 1 && !_isSending)
                  Positioned(
                    top: -6,
                    right: -6,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(
                        minWidth: 20,
                        minHeight: 20,
                      ),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '${_items.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Handles the "Add More" button press for camera capture flow.
  /// Reopens the camera and appends the new capture to the selection.
  /// Shows a SnackBar if the maximum of 20 items has been reached.
  Future<void> _handleAddMore() async {
    if (_items.length >= 20) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Maximum of 20 items reached.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    final newAsset = await MediaPickerService.captureFromCamera(context);

    // If the user cancelled the camera, retain previously captured items
    if (newAsset == null) return;

    if (mounted) {
      setState(() {
        _items.add(newAsset);
        _currentIndex = _items.length - 1;
      });
    }
  }

  /// Downloads the currently previewed media item to the device gallery.
  Future<void> _handleDownload() async {
    try {
      final asset = _currentItem;
      final file = await asset.file;
      if (file == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Unable to access file')),
          );
        }
        return;
      }

      // The file is already on device (from gallery/camera), confirm to user.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('File is already in your gallery'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $e')),
        );
      }
    }
  }

  /// Builds the compression progress overlay shown during the send flow.
  Widget _buildCompressionOverlay() {
    final progress = _compressionProgress!;
    return Container(
      color: Colors.black54,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(
                color: Color(0xFF7C3AED),
              ),
              const SizedBox(height: 16),
              Text(
                'Compressing ${progress.completed + 1} of ${progress.total}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${progress.completed} of ${progress.total} completed',
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Handles the minimize button press.
  /// Pops the preview screen and returns a special result indicating
  /// the files are pending (minimized state). The chat screen will show
  /// a pending files badge on the send/attachment button.
  void _handleMinimize() {
    // Pop with a MinimizedMediaResult so the chat screen knows
    // these are pending files (not a back-to-picker action).
    Navigator.of(context).pop(MinimizedMediaResult(items: _items, caption: _captionController.text));
  }

  /// Handles the back button press.
  void _handleBack() {
    Navigator.of(context).pop(_items);
  }

  /// Handles the send button press.
  /// Disables the button to prevent duplicate submissions,
  /// then triggers the compression → upload pipeline.
  Future<void> _handleSend() async {
    if (_isSending || _items.isEmpty) return;

    setState(() {
      _isSending = true;
    });

    try {
      // Phase 1: Compression
      await _compressItems();

      // Phase 2: Upload
      await _uploadCompressedItems();
    } catch (e) {
      // Handle errors
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send media: ${e.toString()}'),
            backgroundColor: Colors.red[700],
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
          _compressionProgress = null;
          _compressedResults = null;
        });
      }
    }
  }

  /// Compresses all selected media items with progress tracking.
  /// Calls CompressionService.compressBatch and updates progress state.
  Future<void> _compressItems() async {
    setState(() {
      _compressionProgress = CompressionProgress(
        completed: 0,
        total: _items.length,
      );
    });

    _compressedResults = await CompressionService.compressBatch(
      _items,
      onProgress: (completed, total) {
        if (!mounted) return;
        setState(() {
          _compressionProgress = CompressionProgress(
            completed: completed,
            total: total,
          );
        });
      },
    );
  }

  /// Uploads compressed media items with the caption.
  /// Calls MediaUploadService.uploadBatch and reports progress via
  /// the MediaUploadState if provided.
  Future<void> _uploadCompressedItems() async {
    final compressed = _compressedResults;
    if (compressed == null || compressed.isEmpty) {
      if (mounted) Navigator.of(context).pop(null);
      return;
    }

    final caption = _captionController.text.trim();
    final uploadState = widget.mediaUploadState;

    // Generate unique IDs for tracking each file's upload progress
    final batchId = DateTime.now().millisecondsSinceEpoch.toString();
    final fileIds = List.generate(
      compressed.length,
      (i) => '${batchId}_$i',
    );

    // Mark all files as pending in the upload state
    if (uploadState != null) {
      for (int i = 0; i < compressed.length; i++) {
        uploadState.updateProgress(
          fileIds[i],
          UploadProgress(
            fileIndex: i,
            totalFiles: compressed.length,
            fileProgress: 0.0,
            status: UploadStatus.pending,
          ),
        );
      }
    }

    final results = await MediaUploadService.uploadBatch(
      files: compressed,
      recipientId: widget.recipientId,
      caption: caption.isNotEmpty ? caption : null,
      onProgress: (progress) {
        if (uploadState != null && progress.fileIndex < fileIds.length) {
          uploadState.updateProgress(fileIds[progress.fileIndex], progress);
        }
      },
    );

    // Update upload state with final results
    if (uploadState != null) {
      for (int i = 0; i < results.length; i++) {
        if (i < fileIds.length) {
          if (results[i].success) {
            // Remove completed uploads from tracking
            uploadState.removeUpload(fileIds[i]);
          } else {
            // Mark failed uploads with error
            uploadState.markFailed(
              fileIds[i],
              results[i].errorMessage ?? 'Upload failed',
            );
          }
        }
      }
    }

    // After upload completes, navigate back to chat
    if (mounted) {
      Navigator.of(context).pop(null);
    }
  }
}
