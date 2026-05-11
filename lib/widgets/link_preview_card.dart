import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/link_preview.dart';

/// Renders a WhatsApp-style link preview card for general (non-YouTube) URLs.
/// Shows the OG image, domain, title, and description.
/// Tapping opens the URL in the external browser.
class LinkPreviewCard extends StatelessWidget {
  final LinkPreview preview;

  const LinkPreviewCard({
    super.key,
    required this.preview,
  });

  String get _domain {
    final host = Uri.tryParse(preview.url)?.host ?? preview.url;
    return host.replaceFirst('www.', '').toUpperCase();
  }

  Future<void> _openUrl() async {
    try {
      final uri = Uri.parse(preview.url);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Silently ignore if browser cannot be opened
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _openUrl,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 360),
        decoration: BoxDecoration(
          color: const Color(0xFF1a1a2e),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: const Color(0xFF7c3aed).withValues(alpha: 0.35),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // OG image (optional)
            if (preview.imageUrl != null)
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(10),
                ),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Image.network(
                    preview.imageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        const SizedBox.shrink(),
                  ),
                ),
              ),
            // Text metadata
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Domain row with optional favicon
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (preview.faviconUrl != null) ...[
                        Image.network(
                          preview.faviconUrl!,
                          width: 14,
                          height: 14,
                          errorBuilder: (context, error, stackTrace) =>
                              const SizedBox.shrink(),
                        ),
                        const SizedBox(width: 5),
                      ],
                      Flexible(
                        child: Text(
                          _domain,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFa78bfa),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.04,
                          ),
                        ),
                      ),
                    ],
                  ),
                  // Title (optional)
                  if (preview.title != null && preview.title!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      preview.title!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFe2e8f0),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                  ],
                  // Description (optional)
                  if (preview.description != null &&
                      preview.description!.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      preview.description!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF94a3b8),
                        fontSize: 11.5,
                        height: 1.45,
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
