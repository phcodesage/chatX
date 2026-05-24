import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_view/photo_view.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';

import '../models/message.dart';

/// Formats a timestamp for the gallery viewer metadata overlay.
///
/// Returns relative format (e.g., "2 hours ago") for timestamps less than 24 hours old,
/// and absolute format (e.g., "Jan 5, 2025 3:42 PM") for older timestamps.
String formatGalleryTimestamp(int timestampMs, {DateTime? now}) {
  final messageTime = DateTime.fromMillisecondsSinceEpoch(timestampMs);
  final currentTime = now ?? DateTime.now();
  final difference = currentTime.difference(messageTime);

  if (difference.inHours < 24 && !difference.isNegative) {
    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      final minutes = difference.inMinutes;
      return minutes == 1 ? '1 minute ago' : '$minutes minutes ago';
    } else {
      final hours = difference.inHours;
      return hours == 1 ? '1 hour ago' : '$hours hours ago';
    }
  }

  // Absolute format: "Jan 5, 2025 3:42 PM"
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final month = months[messageTime.month - 1];
  final day = messageTime.day;
  final year = messageTime.year;
  final hour = messageTime.hour;
  final minute = messageTime.minute.toString().padLeft(2, '0');
  final period = hour >= 12 ? 'PM' : 'AM';
  final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);

  return '$month $day, $year $displayHour:$minute $period';
}

/// Returns the display name for a message sender.
///
/// Shows "You" for messages sent by the current user.
/// Shows "Unknown User" for null, empty, or whitespace-only sender names.
/// Otherwise shows the provided sender name.
String getGallerySenderName({
  required int senderId,
  required int currentUserId,
  required String? otherUserName,
}) {
  if (senderId == currentUserId) {
    return 'You';
  }
  if (otherUserName == null || otherUserName.trim().isEmpty) {
    return 'Unknown User';
  }
  return otherUserName;
}

/// Full-screen gallery viewer for browsing conversation media.
///
/// Displays images and videos in a horizontally swipeable PageView,
/// ordered chronologically (oldest first) by timestampMs.
/// Preloads adjacent items (index ± 1) for smooth transitions.
class MediaGalleryViewer extends StatefulWidget {
  /// All media messages in the conversation (images and videos).
  final List<Message> mediaMessages;

  /// The index of the item to display first.
  final int initialIndex;

  /// The current user's ID, used for sender identification.
  final int currentUserId;

  /// The other user's display name in the conversation.
  /// Used to show sender info in the metadata overlay.
  final String? otherUserName;

  const MediaGalleryViewer({
    super.key,
    required this.mediaMessages,
    required this.initialIndex,
    required this.currentUserId,
    this.otherUserName,
  });

  @override
  State<MediaGalleryViewer> createState() => _MediaGalleryViewerState();
}

class _MediaGalleryViewerState extends State<MediaGalleryViewer> {
  late final List<Message> _sortedMessages;
  late final PageController _pageController;
  late int _currentIndex;

  /// Tracks active video controllers by page index for proper disposal.
  final Map<int, _VideoControllerEntry> _videoControllers = {};

  /// Whether the current image is zoomed beyond 1.0x.
  /// When true, PageView swiping is disabled.
  bool _isZoomed = false;

  /// Whether the metadata overlay (sender, timestamp, controls) is visible.
  /// Defaults to true per requirement 9.2.
  bool _overlayVisible = true;

  /// Whether a download is currently in progress.
  bool _isDownloading = false;

  /// Whether a share operation is currently in progress.
  bool _isSharing = false;

  @override
  void initState() {
    super.initState();

    // Sort media messages chronologically (oldest first) by timestampMs.
    _sortedMessages = List<Message>.from(widget.mediaMessages)
      ..sort((a, b) => a.timestampMs.compareTo(b.timestampMs));

    // Clamp initialIndex to valid range.
    _currentIndex = widget.initialIndex.clamp(0, _sortedMessages.length - 1);

    _pageController = PageController(
      initialPage: _currentIndex,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _disposeAllVideoControllers();
    super.dispose();
  }

  /// Disposes all active video controllers.
  void _disposeAllVideoControllers() {
    for (final entry in _videoControllers.values) {
      entry.chewieController?.dispose();
      entry.videoPlayerController.dispose();
    }
    _videoControllers.clear();
  }

  /// Stops playback and resets position for a video at the given index.
  void _stopAndResetVideo(int index) {
    final entry = _videoControllers[index];
    if (entry != null) {
      entry.chewieController?.pause();
      entry.videoPlayerController.seekTo(Duration.zero);
      entry.videoPlayerController.pause();
    }
  }

  void _onPageChanged(int index) {
    // Stop playback and reset position for the video we're swiping away from.
    if (_currentIndex != index) {
      _stopAndResetVideo(_currentIndex);
    }

    setState(() {
      _currentIndex = index;
      // Reset zoom state when swiping to a new page.
      _isZoomed = false;
    });
  }

  /// Checks if a message is a video type.
  bool _isVideoMessage(Message message) {
    return message.messageType == 'video' ||
        (message.fileType?.startsWith('video/') ?? false);
  }

  /// Called when PhotoView's scale state changes.
  /// Disables swiping when zoomed beyond the initial (contained) scale.
  void _onScaleStateChanged(PhotoViewScaleState scaleState) {
    final zoomed = scaleState != PhotoViewScaleState.initial &&
        scaleState != PhotoViewScaleState.zoomedOut;
    if (zoomed != _isZoomed) {
      setState(() {
        _isZoomed = zoomed;
      });
    }
  }

  /// Downloads the current media file and saves it to the device photo library.
  /// Shows a progress indicator during download and handles 30s timeout.
  Future<void> _downloadMedia() async {
    if (_isDownloading) return;

    final message = _sortedMessages[_currentIndex];
    final fileUrl = message.fileUrl;
    if (fileUrl == null || fileUrl.isEmpty) return;

    setState(() {
      _isDownloading = true;
    });

    try {
      // Request photo library permission
      final permissionState = await PhotoManager.requestPermissionExtend();
      if (!permissionState.isAuth) {
        if (mounted) {
          setState(() => _isDownloading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Photo library permission is required to save media'),
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      // Download file bytes with 30s timeout
      final uri = Uri.parse(fileUrl);
      final response = await http.get(uri).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException('Download timed out after 30 seconds');
        },
      );

      if (!mounted) return;

      if (response.statusCode != 200) {
        throw Exception('Download failed with status ${response.statusCode}');
      }

      final bytes = response.bodyBytes;
      final fileName = message.fileName ??
          'media_${DateTime.now().millisecondsSinceEpoch}';

      // Save to device photo library using photo_manager
      if (_isVideoMessage(message)) {
        // Save video: write to temp file first, then save to gallery
        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/$fileName');
        await tempFile.writeAsBytes(bytes);
        await PhotoManager.editor.saveVideo(tempFile, title: fileName);
        // Clean up temp file
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } else {
        // Save image directly from bytes
        await PhotoManager.editor.saveImage(
          bytes,
          filename: fileName,
          title: fileName,
        );
      }

      if (mounted) {
        setState(() => _isDownloading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Saved to photo library'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } on TimeoutException {
      if (mounted) {
        setState(() => _isDownloading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Download timed out. Please try again.'),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: _downloadMedia,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isDownloading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Download failed: ${e.toString().replaceAll('Exception: ', '')}',
            ),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: _downloadMedia,
            ),
          ),
        );
      }
    }
  }

  /// Shares the current media file using the native share sheet.
  /// Downloads the file to a temp directory first, then shares the file path.
  Future<void> _shareMedia() async {
    if (_isSharing) return;

    final message = _sortedMessages[_currentIndex];
    final fileUrl = message.fileUrl;
    if (fileUrl == null || fileUrl.isEmpty) return;

    setState(() {
      _isSharing = true;
    });

    try {
      // Download file bytes with 30s timeout
      final uri = Uri.parse(fileUrl);
      final response = await http.get(uri).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException('Download timed out');
        },
      );

      if (!mounted) return;

      if (response.statusCode != 200) {
        throw Exception('Failed to download media for sharing');
      }

      final bytes = response.bodyBytes;
      final fileName = message.fileName ??
          'media_${DateTime.now().millisecondsSinceEpoch}';

      // Write to temp directory
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/$fileName');
      await tempFile.writeAsBytes(bytes);

      if (!mounted) return;

      // Invoke native share sheet using share_plus
      await Share.shareXFiles(
        [XFile(tempFile.path, mimeType: message.fileType)],
      );

      if (mounted) {
        setState(() => _isSharing = false);
      }
    } on TimeoutException {
      if (mounted) {
        setState(() => _isSharing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Share failed: download timed out'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSharing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Share failed: ${e.toString().replaceAll('Exception: ', '')}',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: _sortedMessages.isEmpty
              ? const Center(
                  child: Text(
                    'No media available',
                    style: TextStyle(color: Colors.white),
                  ),
                )
              : Stack(
                  children: [
                    // Media content with tap-to-toggle overlay
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _overlayVisible = !_overlayVisible;
                        });
                      },
                      child: PageView.builder(
                        controller: _pageController,
                        itemCount: _sortedMessages.length,
                        onPageChanged: _onPageChanged,
                        allowImplicitScrolling: true,
                        physics: _isZoomed
                            ? const NeverScrollableScrollPhysics()
                            : const BouncingScrollPhysics(
                                parent: PageScrollPhysics(),
                              ),
                        itemBuilder: (context, index) {
                          return _buildMediaPage(index);
                        },
                      ),
                    ),
                    // Top metadata overlay
                    if (_overlayVisible)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: _buildTopOverlay(),
                      ),
                    // Bottom overlay with download/share buttons
                    if (_overlayVisible)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: _buildBottomOverlay(),
                      ),
                  ],
                ),
        ),
      ),
    );
  }

  /// Builds the top overlay bar with close button, sender info, and position indicator.
  Widget _buildTopOverlay() {
    final message = _sortedMessages[_currentIndex];
    final senderName = getGallerySenderName(
      senderId: message.senderId,
      currentUserId: widget.currentUserId,
      otherUserName: widget.otherUserName,
    );
    final timestamp = formatGalleryTimestamp(message.timestampMs);
    final positionText = '${_currentIndex + 1} of ${_sortedMessages.length}';

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Row(
        children: [
          // Close button
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Close',
          ),
          const SizedBox(width: 8),
          // Sender name and timestamp
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  senderName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (timestamp.isNotEmpty)
                  Text(
                    timestamp,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          // Position indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black45,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              positionText,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the bottom overlay with download and share buttons.
  Widget _buildBottomOverlay() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Download button with progress indicator
          _isDownloading
              ? const SizedBox(
                  width: 48,
                  height: 48,
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  ),
                )
              : IconButton(
                  icon: const Icon(
                    Icons.download,
                    color: Colors.white,
                    size: 28,
                  ),
                  onPressed: _downloadMedia,
                  tooltip: 'Download',
                ),
          const SizedBox(width: 32),
          // Share button with progress indicator
          _isSharing
              ? const SizedBox(
                  width: 48,
                  height: 48,
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  ),
                )
              : IconButton(
                  icon: const Icon(
                    Icons.share,
                    color: Colors.white,
                    size: 28,
                  ),
                  onPressed: _shareMedia,
                  tooltip: 'Share',
                ),
        ],
      ),
    );
  }

  /// Builds a single page for the given index.
  Widget _buildMediaPage(int index) {
    final message = _sortedMessages[index];
    final fileUrl = message.fileUrl;

    if (fileUrl == null || fileUrl.isEmpty) {
      return const Center(
        child: Icon(
          Icons.broken_image,
          color: Colors.white54,
          size: 64,
        ),
      );
    }

    if (_isVideoMessage(message)) {
      return _buildVideoPlayer(index, fileUrl);
    }

    return _buildImageView(fileUrl);
  }

  /// Builds the image view for non-video media using PhotoView with zoom.
  Widget _buildImageView(String fileUrl) {
    return _ImagePageView(
      imageUrl: fileUrl,
      onScaleStateChanged: _onScaleStateChanged,
    );
  }

  /// Builds the video player widget using video_player + chewie.
  Widget _buildVideoPlayer(int index, String fileUrl) {
    // Return existing controller if already initialized for this index.
    final existingEntry = _videoControllers[index];
    if (existingEntry != null && existingEntry.chewieController != null) {
      return _VideoPlayerWidget(
        entry: existingEntry,
        onError: () {
          setState(() {
            _videoControllers.remove(index);
          });
        },
      );
    }

    // Initialize a new video controller for this index.
    return _VideoInitializer(
      fileUrl: fileUrl,
      onInitialized: (videoController, chewieController) {
        if (mounted) {
          setState(() {
            _videoControllers[index] = _VideoControllerEntry(
              videoPlayerController: videoController,
              chewieController: chewieController,
            );
          });
        }
      },
      onError: (error) {
        debugPrint('Video initialization error: $error');
      },
    );
  }
}

/// Holds references to video and chewie controllers for a single video.
class _VideoControllerEntry {
  final VideoPlayerController videoPlayerController;
  final ChewieController? chewieController;

  _VideoControllerEntry({
    required this.videoPlayerController,
    this.chewieController,
  });
}

/// Widget that initializes a video player and calls back when ready.
class _VideoInitializer extends StatefulWidget {
  final String fileUrl;
  final void Function(VideoPlayerController, ChewieController) onInitialized;
  final void Function(String error) onError;

  const _VideoInitializer({
    required this.fileUrl,
    required this.onInitialized,
    required this.onError,
  });

  @override
  State<_VideoInitializer> createState() => _VideoInitializerState();
}

class _VideoInitializerState extends State<_VideoInitializer> {
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  bool _isInitializing = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  @override
  void dispose() {
    // Only dispose if we haven't handed off to the parent.
    if (_chewieController == null && _videoController != null) {
      _videoController?.dispose();
    }
    super.dispose();
  }

  Future<void> _initializeVideo() async {
    try {
      VideoPlayerController videoController;
      final cached = await DefaultCacheManager().getFileFromCache(
        widget.fileUrl,
      );
      if (cached != null) {
        videoController = VideoPlayerController.file(cached.file);
      } else {
        videoController = VideoPlayerController.networkUrl(
          Uri.parse(widget.fileUrl),
        );
        unawaited(
          () async {
            try {
              await DefaultCacheManager().downloadFile(widget.fileUrl);
            } catch (_) {}
          }(),
        );
      }

      await videoController.initialize();

      if (!mounted) {
        videoController.dispose();
        return;
      }

      final chewieController = ChewieController(
        videoPlayerController: videoController,
        autoPlay: false,
        looping: false,
        showControls: true,
        allowFullScreen: false,
        allowMuting: true,
        showOptions: false,
        materialProgressColors: ChewieProgressColors(
          playedColor: Colors.white,
          handleColor: Colors.white,
          backgroundColor: Colors.white24,
          bufferedColor: Colors.white54,
        ),
      );

      _videoController = videoController;
      _chewieController = chewieController;

      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
        widget.onInitialized(videoController, chewieController);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _errorMessage = 'Failed to load video';
        });
        widget.onError(e.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.white54, size: 48),
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.white54),
            ),
          ],
        ),
      );
    }

    if (_isInitializing) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text(
              'Loading video...',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

/// Displays the Chewie video player from an already-initialized controller entry.
class _VideoPlayerWidget extends StatelessWidget {
  final _VideoControllerEntry entry;
  final VoidCallback onError;

  const _VideoPlayerWidget({
    required this.entry,
    required this.onError,
  });

  @override
  Widget build(BuildContext context) {
    final chewieController = entry.chewieController;
    if (chewieController == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: Colors.white54, size: 48),
            SizedBox(height: 8),
            Text(
              'Video player not available',
              style: TextStyle(color: Colors.white54),
            ),
          ],
        ),
      );
    }

    return Center(
      child: AspectRatio(
        aspectRatio: entry.videoPlayerController.value.aspectRatio > 0
            ? entry.videoPlayerController.value.aspectRatio
            : 16 / 9,
        child: Chewie(controller: chewieController),
      ),
    );
  }
}

/// A stateful widget that displays an image with PhotoView zoom capabilities
/// and handles load timeout (15s) with error placeholder and retry.
class _ImagePageView extends StatefulWidget {
  final String imageUrl;
  final ValueChanged<PhotoViewScaleState> onScaleStateChanged;

  const _ImagePageView({
    required this.imageUrl,
    required this.onScaleStateChanged,
  });

  @override
  State<_ImagePageView> createState() => _ImagePageViewState();
}

class _ImagePageViewState extends State<_ImagePageView> {
  late PhotoViewScaleStateController _scaleStateController;
  StreamSubscription<PhotoViewScaleState>? _scaleStateSubscription;

  /// Tracks the loading state of the image.
  _ImageLoadState _loadState = _ImageLoadState.loading;

  /// Timer for the 15-second load timeout (covers swipe navigation per requirement 8.7).
  Timer? _loadTimeoutTimer;

  /// Key to force rebuild of the image on retry.
  UniqueKey _imageKey = UniqueKey();

  @override
  void initState() {
    super.initState();
    _scaleStateController = PhotoViewScaleStateController();
    _scaleStateSubscription =
        _scaleStateController.outputScaleStateStream.listen((scaleState) {
      widget.onScaleStateChanged(scaleState);
    });
    _startLoadTimeout();
    _resolveImage();
  }

  @override
  void dispose() {
    _loadTimeoutTimer?.cancel();
    _scaleStateSubscription?.cancel();
    _scaleStateController.dispose();
    super.dispose();
  }

  /// Resolves the image to detect load success/failure independently of PhotoView.
  void _resolveImage() {
    final imageProvider = CachedNetworkImageProvider(widget.imageUrl);
    final stream = imageProvider.resolve(const ImageConfiguration());
    stream.addListener(ImageStreamListener(
      (info, synchronousCall) {
        _onImageLoaded();
      },
      onError: (exception, stackTrace) {
        _onImageError();
      },
    ));
  }

  void _startLoadTimeout() {
    _loadTimeoutTimer?.cancel();
    _loadTimeoutTimer = Timer(const Duration(seconds: 15), () {
      if (_loadState == _ImageLoadState.loading && mounted) {
        setState(() {
          _loadState = _ImageLoadState.error;
        });
      }
    });
  }

  void _onImageLoaded() {
    _loadTimeoutTimer?.cancel();
    if (mounted && _loadState == _ImageLoadState.loading) {
      setState(() {
        _loadState = _ImageLoadState.loaded;
      });
    }
  }

  void _onImageError() {
    _loadTimeoutTimer?.cancel();
    if (mounted && _loadState != _ImageLoadState.error) {
      setState(() {
        _loadState = _ImageLoadState.error;
      });
    }
  }

  void _retry() {
    setState(() {
      _loadState = _ImageLoadState.loading;
      _imageKey = UniqueKey();
    });
    // Evict any cached entries so retry fetches fresh from the network.
    imageCache.evict(CachedNetworkImageProvider(widget.imageUrl));
    unawaited(
      () async {
        try {
          await DefaultCacheManager().removeFile(widget.imageUrl);
        } catch (_) {}
      }(),
    );
    _startLoadTimeout();
    _resolveImage();
  }

  @override
  Widget build(BuildContext context) {
    if (_loadState == _ImageLoadState.error) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.white54, size: 48),
            const SizedBox(height: 8),
            const Text(
              'Failed to load media',
              style: TextStyle(color: Colors.white54),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: _retry,
              icon: const Icon(Icons.refresh, color: Colors.white70),
              label: const Text(
                'Retry',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ],
        ),
      );
    }

    return PhotoView(
      key: _imageKey,
      imageProvider: CachedNetworkImageProvider(widget.imageUrl),
      minScale: PhotoViewComputedScale.contained,
      maxScale: PhotoViewComputedScale.contained * 5,
      initialScale: PhotoViewComputedScale.contained,
      scaleStateController: _scaleStateController,
      backgroundDecoration: const BoxDecoration(color: Colors.black),
      loadingBuilder: (context, event) {
        return Center(
          child: CircularProgressIndicator(
            value: event != null && event.expectedTotalBytes != null
                ? event.cumulativeBytesLoaded / event.expectedTotalBytes!
                : null,
            color: Colors.white,
          ),
        );
      },
    );
  }
}

/// Tracks the loading state of an image in the gallery viewer.
enum _ImageLoadState {
  loading,
  loaded,
  error,
}
