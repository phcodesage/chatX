import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Renders a WhatsApp-style YouTube video preview card.
/// Shows a 16:9 thumbnail from YouTube's CDN with a play button overlay
/// and YouTube branding. Tapping opens the video in the external browser.
class YouTubePreviewCard extends StatelessWidget {
  final String videoId;
  final String? title;

  const YouTubePreviewCard({
    super.key,
    required this.videoId,
    this.title,
  });

  String get _thumbnailUrl =>
      'https://img.youtube.com/vi/$videoId/hqdefault.jpg';

  String get _fallbackThumbnailUrl =>
      'https://img.youtube.com/vi/$videoId/mqdefault.jpg';

  String get _watchUrl => 'https://www.youtube.com/watch?v=$videoId';

  Future<void> _openVideo() async {
    try {
      final uri = Uri.parse(_watchUrl);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Silently ignore if browser cannot be opened
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _openVideo,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          color: const Color(0xFF1a1a2e),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: const Color(0xFF7c3aed).withValues(alpha: 0.4),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Thumbnail with play button overlay
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10),
              ),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      _thumbnailUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Image.network(
                          _fallbackThumbnailUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: Colors.grey[850],
                              child: const Center(
                                child: Icon(
                                  Icons.play_circle_outline,
                                  color: Colors.white54,
                                  size: 48,
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                    // Centered play button overlay
                    Center(
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.play_arrow,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Meta row: YouTube branding + optional title
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(
                        Icons.play_circle_fill,
                        color: Color(0xFFFF0000),
                        size: 13,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'YouTube',
                        style: TextStyle(
                          color: Color(0xFFFF0000),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  if (title != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      title!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFe2e8f0),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
