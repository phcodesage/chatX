import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/link_preview.dart';
import 'storage_service.dart';

/// Singleton service for detecting URLs in messages and fetching link previews.
/// YouTube URLs are handled client-side (CDN thumbnail + optional oEmbed title).
/// All other URLs are previewed via the backend /api/link_preview endpoint.
/// Results are cached in-memory for the app session.
class LinkPreviewService {
  static final LinkPreviewService _instance = LinkPreviewService._internal();
  factory LinkPreviewService() => _instance;
  LinkPreviewService._internal();

  /// In-memory cache: null means "fetch attempted, no result available".
  final Map<String, LinkPreview?> _cache = {};

  static final RegExp _urlRegex = RegExp(
    r'https?://[^\s"<>]+',
    caseSensitive: false,
  );

  static final RegExp _ytRegex = RegExp(
    r'(?:youtube\.com/(?:watch\?(?:[^#&?]*&)*v=|embed/|shorts/)|youtu\.be/)([a-zA-Z0-9_-]{11})',
    caseSensitive: false,
  );

  static const List<String> _skipExtensions = [
    '.jpg', '.jpeg', '.png', '.gif', '.webp',
    '.mp4', '.mov', '.avi',
    '.pdf', '.zip', '.doc', '.docx', '.xls', '.xlsx',
  ];

  /// Extracts the first previewable URL from [text].
  /// Returns null if no URL is found or the URL ends with a skip extension.
  String? extractFirstUrl(String text) {
    final match = _urlRegex.firstMatch(text);
    if (match == null) return null;
    final url = match.group(0)!;
    final lower = url.toLowerCase();
    if (_skipExtensions.any((ext) => lower.endsWith(ext))) return null;
    return url;
  }

  /// Extracts the YouTube video ID from [url].
  /// Returns null if the URL is not a YouTube URL.
  String? extractYouTubeId(String url) {
    final match = _ytRegex.firstMatch(url);
    return match?.group(1);
  }

  /// Fetches the YouTube video title via oEmbed (no API key required).
  /// Returns null on any error or timeout.
  Future<String?> fetchYouTubeTitle(String videoId) async {
    try {
      final encodedUrl = Uri.encodeComponent(
        'https://www.youtube.com/watch?v=$videoId',
      );
      final uri = Uri.parse(
        'https://www.youtube.com/oembed?url=$encodedUrl&format=json',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['title'] as String?;
      }
    } catch (_) {
      // Silently ignore — title is optional
    }
    return null;
  }

  /// Fetches Open Graph metadata from the backend for [url].
  /// Returns null on failure, timeout, or non-200 response.
  Future<LinkPreview?> fetchLinkPreview(String url) async {
    try {
      final token = await StorageService.getToken();
      final response = await http
          .post(
            Uri.parse(ApiConfig.linkPreviewUrl),
            headers: {
              'Content-Type': 'application/json',
              if (token != null && token.isNotEmpty)
                'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'url': url}),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['success'] == true && data['preview'] != null) {
          return LinkPreview.fromJson(
            data['preview'] as Map<String, dynamic>,
          );
        }
      }
    } catch (_) {
      // Silently ignore network errors
    }
    return null;
  }

  /// Main entry point. Detects a URL in [text], checks the cache, then
  /// routes to the YouTube fast path or the backend OG endpoint.
  /// Returns null if no previewable URL is found or the fetch fails.
  Future<LinkPreview?> getPreview(String text) async {
    final url = extractFirstUrl(text);
    if (url == null) return null;

    // Return cached result immediately (including null = "already tried, failed")
    if (_cache.containsKey(url)) return _cache[url];

    final videoId = extractYouTubeId(url);
    if (videoId != null) {
      // YouTube fast path: build synthetic preview from CDN thumbnail
      final preview = LinkPreview(
        url: 'https://www.youtube.com/watch?v=$videoId',
        imageUrl: 'https://img.youtube.com/vi/$videoId/hqdefault.jpg',
        siteName: 'youtube',
      );
      _cache[url] = preview;

      // Fetch title asynchronously and update cache when it arrives
      fetchYouTubeTitle(videoId).then((title) {
        if (title != null && _cache[url] != null) {
          _cache[url] = LinkPreview(
            url: preview.url,
            title: title,
            imageUrl: preview.imageUrl,
            siteName: preview.siteName,
          );
        }
      });

      return preview;
    }

    // General link preview via backend
    final preview = await fetchLinkPreview(url);
    _cache[url] = preview; // cache null on failure to prevent retries
    return preview;
  }
}
