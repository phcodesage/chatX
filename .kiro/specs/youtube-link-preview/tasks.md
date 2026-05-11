# Implementation Tasks

- [x] 1. Create LinkPreview model
  - Create `lib/models/link_preview.dart`
  - Define `LinkPreview` class with fields: `url` (required String), `title` (String?), `description` (String?), `imageUrl` (String?), `siteName` (String?), `faviconUrl` (String?)
  - Implement `const` constructor and `LinkPreview.fromJson` factory that maps `image` → `imageUrl` and `favicon` → `faviconUrl`
  - Add `isYouTube` getter: returns `true` when `siteName == 'youtube'`

- [x] 2. Add linkPreviewUrl to ApiConfig
  - Open `lib/config/api_config.dart`
  - Add a static getter `linkPreviewUrl` that strips a trailing slash from `baseUrl` and appends `/api/link_preview`

- [x] 3. Create LinkPreviewService
  - Create `lib/services/link_preview_service.dart`
  - Implement as a singleton (`factory` constructor returning `_instance`)
  - Add `final Map<String, LinkPreview?> _cache = {}`
  - Add static `RegExp` for URL detection (`https?://[^\s"<>]+`) and YouTube ID extraction
  - Add `_skipExtensions` list: `.jpg .jpeg .png .gif .webp .mp4 .mov .avi .pdf .zip .doc .docx .xls .xlsx`
  - Implement `String? extractFirstUrl(String text)` — returns first URL match or null; returns null if URL ends with a skip extension
  - Implement `String? extractYouTubeId(String url)` — returns 11-char video ID or null
  - Implement `Future<String?> fetchYouTubeTitle(String videoId)` — GET `https://www.youtube.com/oembed?url=...&format=json`, 5s timeout, returns `data['title']` or null on any error
  - Implement `Future<LinkPreview?> fetchLinkPreview(String url)` — POST to `ApiConfig.linkPreviewUrl` with Bearer token from `StorageService.getToken()`, 8s timeout, parses response into `LinkPreview` or returns null on failure
  - Implement `Future<LinkPreview?> getPreview(String text)` — orchestrates: extract URL → check cache → YouTube fast path (synthetic LinkPreview + async oEmbed) → backend call → cache result
  - _Requirements: [1, 2, 3, 4]_

- [x] 4. Create YouTubePreviewCard widget
  - Create `lib/widgets/youtube_preview_card.dart`
  - `YouTubePreviewCard` is a `StatelessWidget` with `videoId` (String) and `title` (String?) parameters
  - Thumbnail: `Image.network('https://img.youtube.com/vi/$videoId/hqdefault.jpg')` with `errorBuilder` falling back to `mqdefault.jpg`
  - Wrap thumbnail in `AspectRatio(aspectRatio: 16/9)` inside `ClipRRect` with top border radius
  - Overlay centered circular play button: 52×52 container, `Colors.black.withValues(alpha: 0.6)`, `Icons.play_arrow` size 32 white
  - Bottom-left YouTube branding: `Row` with `Icons.play_circle_fill` (red `Color(0xFFFF0000)`, size 13) + `Text('YouTube')` (red, 10.5px, bold)
  - If `title != null`, show title text below branding (max 2 lines, white `#e2e8f0`, 12.5px, bold)
  - Container: `maxWidth: 320`, `color: Color(0xFF1a1a2e)`, `BorderRadius.circular(10)`, border `Color(0xFF7c3aed).withValues(alpha: 0.4)`
  - Wrap in `GestureDetector` → `launchUrl(Uri.parse('https://www.youtube.com/watch?v=$videoId'), mode: LaunchMode.externalApplication)` with silent catch
  - _Requirements: [2]_

- [x] 5. Create LinkPreviewCard widget
  - Create `lib/widgets/link_preview_card.dart`
  - `LinkPreviewCard` is a `StatelessWidget` with a `LinkPreview preview` parameter
  - If `preview.imageUrl != null`: render `AspectRatio(aspectRatio: 16/9)` `Image.network` with `ClipRRect` top radius; `errorBuilder` returns `SizedBox.shrink()`
  - Domain row: extract host from `Uri.tryParse(preview.url)`, strip `www.`, uppercase; if `preview.faviconUrl != null` show 14×14 `Image.network` favicon with `errorBuilder: SizedBox.shrink()`; domain text color `Color(0xFFa78bfa)`, 10.5px, bold
  - If `preview.title != null`: title text, max 2 lines, `Color(0xFFe2e8f0)`, 13px, bold, height 1.4
  - If `preview.description != null`: description text, max 3 lines, `Color(0xFF94a3b8)`, 11.5px, height 1.45
  - Container: `maxWidth: 360`, `color: Color(0xFF1a1a2e)`, `BorderRadius.circular(10)`, border `Color(0xFF7c3aed).withValues(alpha: 0.35)`
  - Wrap in `GestureDetector` → `launchUrl(Uri.parse(preview.url), mode: LaunchMode.externalApplication)` with silent catch
  - _Requirements: [3]_

- [x] 6. Wire preview into ChatMessageBubble
  - Open `lib/screens/chat/chat_message_bubble.dart`
  - Add imports: `link_preview_service.dart`, `link_preview.dart`, `youtube_preview_card.dart`, `link_preview_card.dart`, `url_launcher`
  - In `_ChatMessageBubbleState`, add fields: `LinkPreview? _linkPreview` and `bool _previewLoaded = false`
  - Override `initState`: call `_fetchPreview()` only when `widget.message.messageType == 'text'` and `!widget.message.isDeleted`
  - Implement `_fetchPreview()`: call `LinkPreviewService().getPreview(widget.message.content)`, then `if (mounted) setState(...)`
  - In `build`, after the `Builder` row (bubble + emoji reaction button) and before the reactions `Padding`, render the preview card when `_previewLoaded && _linkPreview != null`
  - Add helper `_extractYouTubeId(String thumbnailUrl)` that parses the video ID from the CDN URL path
  - _Requirements: [5]_

- [x] 7. Wire preview into AI chat screen
  - Open `lib/screens/ai_chat_screen.dart`
  - Create a new private `StatefulWidget` class `_AiMessageBubble` at the bottom of the file
  - `_AiMessageBubble` takes: `message` (Map<String, String>), `showTimestamps` (bool), and a `buildBubbleContent` callback `Widget Function()` that returns the existing bubble widget
  - In `_AiMessageBubbleState.initState`, call `_fetchPreview()` using `LinkPreviewService().getPreview(widget.message['content'] ?? '')`
  - Add `LinkPreview? _linkPreview` and `bool _previewLoaded = false` state fields
  - In `build`, call `widget.buildBubbleContent()` then render the preview card below it when `_previewLoaded && _linkPreview != null`
  - In `_AiChatScreenState._buildMessageBubble`, wrap the return value in `_AiMessageBubble`
  - Add required imports: `link_preview_service.dart`, `link_preview.dart`, `youtube_preview_card.dart`, `link_preview_card.dart`, `url_launcher`
  - _Requirements: [5]_
