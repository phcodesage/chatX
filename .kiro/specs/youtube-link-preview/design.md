# Design Document

## Overview

This feature adds WhatsApp-style link preview cards to the Flutter messenger app. The implementation introduces a shared `LinkPreviewService` singleton, two new card widgets (`YouTubePreviewCard` and `LinkPreviewCard`), and wires them into `ChatMessageBubble` (1-on-1 / self-chat) and the AI chat bubble in `ai_chat_screen.dart`.

No new pub.dev packages are needed — `http` and `url_launcher` are already in `pubspec.yaml`.

---

## Architecture

### New Files

| File | Purpose |
|------|---------|
| `lib/services/link_preview_service.dart` | Singleton service: URL detection, YouTube ID extraction, oEmbed title fetch, backend OG call, in-memory cache |
| `lib/models/link_preview.dart` | `LinkPreview` data model (url, title, description, imageUrl, siteName, faviconUrl) |
| `lib/widgets/youtube_preview_card.dart` | Stateless widget rendering YouTube thumbnail + play overlay + branding |
| `lib/widgets/link_preview_card.dart` | Stateless widget rendering OG image + domain + title + description |

### Modified Files

| File | Change |
|------|--------|
| `lib/screens/chat/chat_message_bubble.dart` | Add `StatefulWidget` preview-fetch logic; render card below bubble |
| `lib/screens/ai_chat_screen.dart` | Add preview-fetch logic inside `_buildMessageBubble`; render card below bubble |
| `lib/config/api_config.dart` | Add `linkPreviewUrl` static getter |

---

## Component Design

### `LinkPreview` Model

```dart
class LinkPreview {
  final String url;
  final String? title;
  final String? description;
  final String? imageUrl;   // maps from backend "image" field
  final String? siteName;
  final String? faviconUrl; // maps from backend "favicon" field

  const LinkPreview({required this.url, ...});

  factory LinkPreview.fromJson(Map<String, dynamic> json);
}
```

### `LinkPreviewService` Singleton

```dart
class LinkPreviewService {
  static final LinkPreviewService _instance = LinkPreviewService._();
  factory LinkPreviewService() => _instance;

  // In-memory cache: null means "fetch attempted, no result"
  final Map<String, LinkPreview?> _cache = {};

  static final _urlRegex = RegExp(r'https?://[^\s"<>]+', caseSensitive: false);
  static final _ytRegex = RegExp(r'(?:youtube\.com/(?:watch\?.*v=|embed/|shorts/)|youtu\.be/)([a-zA-Z0-9_-]{11})', caseSensitive: false);
  static final _skipExtensions = ['.jpg','.jpeg','.png','.gif','.webp','.mp4','.mov','.avi','.pdf','.zip','.doc','.docx','.xls','.xlsx'];

  // Returns null if no previewable URL found
  String? extractFirstUrl(String text);

  // Returns null if URL is a file URL
  String? extractYouTubeId(String url);

  // Fetches oEmbed title (best-effort, 5s timeout)
  Future<String?> fetchYouTubeTitle(String videoId);

  // Fetches OG metadata from backend (8s timeout)
  Future<LinkPreview?> fetchLinkPreview(String url);

  // Main entry: checks cache, routes to YouTube or backend
  Future<LinkPreview?> getPreview(String text);
}
```

**Cache key**: the raw URL string extracted from the message text.

**YouTube fast path**: when `extractYouTubeId` returns non-null, a synthetic `LinkPreview` is constructed with `imageUrl = 'https://img.youtube.com/vi/$id/hqdefault.jpg'` and `siteName = 'youtube'`. The oEmbed title is fetched concurrently and the cache entry is updated when it resolves.

**Backend call**: `POST {ApiConfig.baseUrl}api/link_preview` with `Authorization: Bearer <token>` and `{"url": url}` body. Token is read via `StorageService.getToken()`.

### `YouTubePreviewCard` Widget

- Stateless, takes `videoId` and optional `title`
- 16:9 `AspectRatio` with `Image.network` for thumbnail
- `hqdefault.jpg` primary, `mqdefault.jpg` error fallback
- Centered circular play button overlay (52×52, black 60% opacity)
- Bottom-left YouTube branding pill (red `#FF0000`, white text "YouTube", play icon)
- Max width 320px, `BorderRadius.circular(10)`, dark background `#1a1a2e`, purple border
- `GestureDetector` → `launchUrl` with `LaunchMode.externalApplication`

### `LinkPreviewCard` Widget

- Stateless, takes `LinkPreview`
- Optional OG image at top (16:9 `AspectRatio`, `ClipRRect`)
- Domain row: optional favicon (14×14) + uppercase domain text (purple `#a78bfa`)
- Title text (max 2 lines, white `#e2e8f0`, 13px bold)
- Description text (max 3 lines, grey `#94a3b8`, 11.5px)
- Max width 360px, same border/background style as YouTube card
- `GestureDetector` → `launchUrl` with `LaunchMode.externalApplication`

### Integration in `ChatMessageBubble`

`ChatMessageBubble` is already a `StatefulWidget`. The state class gains:

```dart
LinkPreview? _linkPreview;
bool _previewLoaded = false;
```

In `initState`, call `_fetchPreview()`:

```dart
Future<void> _fetchPreview() async {
  final preview = await LinkPreviewService().getPreview(widget.message.content);
  if (mounted) setState(() { _linkPreview = preview; _previewLoaded = true; });
}
```

In `build`, the outer `AnimatedContainer` → `Align` → `Column` already wraps the bubble. After the `Builder` row (bubble + emoji button), add:

```dart
if (_previewLoaded && _linkPreview != null)
  Padding(
    padding: const EdgeInsets.only(top: 4),
    child: _buildPreviewCard(_linkPreview!),
  ),
```

`_buildPreviewCard` checks `_linkPreview!.siteName == 'youtube'` to decide which card widget to render.

### Integration in `ai_chat_screen.dart`

`_buildMessageBubble` is a plain method returning a widget. Convert the `Align` wrapper to a `StatefulBuilder` or — simpler — extract the bubble into a new private `_AiMessageBubble` `StatefulWidget` that owns the preview state. This avoids touching the large `_AiChatScreenState`.

```dart
class _AiMessageBubble extends StatefulWidget {
  final Map<String, String> message;
  final bool showTimestamps;
  // ... other display params passed in
}
```

The `StatefulWidget` fetches the preview in `initState` and renders the card below the bubble using the same pattern as `ChatMessageBubble`.

---

## Data Flow

```
Message rendered
      │
      ▼
LinkPreviewService.getPreview(text)
      │
      ├─ No URL found ──────────────────────► render bubble only
      │
      ├─ URL is file extension ─────────────► render bubble only
      │
      ├─ Cache hit (including null) ────────► use cached value
      │
      ├─ YouTube URL
      │     ├─ Build synthetic LinkPreview (imageUrl from CDN)
      │     ├─ Store in cache
      │     ├─ Fetch oEmbed title async (update cache + setState)
      │     └─ Render YouTubePreviewCard
      │
      └─ General URL
            ├─ POST /api/link_preview (8s timeout)
            ├─ Store result (or null) in cache
            └─ Render LinkPreviewCard (or nothing on failure)
```

---

## API Config Addition

```dart
static String get linkPreviewUrl {
  final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
  return '$base/api/link_preview';
}
```

---

## Error Handling

- oEmbed fetch failure: silently ignored, card renders without title
- Backend OG fetch failure / timeout: `null` stored in cache, no card rendered
- `url_launcher` failure: silently caught, no crash
- Image load failure: `errorBuilder` returns `SizedBox.shrink()` for OG images; YouTube falls back to `mqdefault.jpg`

---

## Constraints

- No new pub.dev packages required
- No changes to `Message` model or backend message schema
- Preview cards do not appear for deleted messages (`message.isDeleted == true`)
- Preview cards do not appear for media/file/audio/contact message types — only `text` type messages
- Cache is in-memory only; cleared on app restart
