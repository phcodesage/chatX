# Requirements Document

## Introduction

This feature adds WhatsApp-style link preview cards to the Flutter messenger app. When a user sends a message containing a URL in any supported chat area (1-on-1 chat, self-chat, or AI chat), the app detects the URL and renders a rich preview card below the message bubble. YouTube URLs are handled entirely client-side using YouTube's free thumbnail CDN. All other URLs are previewed via a backend Open Graph metadata endpoint. Tapping a card opens the URL in an external browser. Results are cached in-memory per session to avoid redundant network calls.

## Glossary

- **LinkPreviewService**: The Dart service class responsible for URL detection, YouTube identification, backend API calls, and in-memory caching.
- **YouTubePreviewCard**: The Flutter widget that renders a YouTube video preview with a 16:9 thumbnail, play button overlay, and YouTube branding.
- **LinkPreviewCard**: The Flutter widget that renders a general URL preview using Open Graph metadata (image, domain, title, description).
- **LinkPreview**: The Dart data model holding Open Graph metadata returned by the backend (title, description, imageUrl, siteName, faviconUrl, url).
- **MessageBubble**: The `ChatMessageBubble` StatefulWidget used in 1-on-1 and self-chat screens.
- **AIChatBubble**: The inline bubble-building logic in `ai_chat_screen.dart` used for AI chat messages.
- **OG Metadata**: Open Graph protocol metadata tags (`og:title`, `og:description`, `og:image`, `og:site_name`) embedded in web page HTML.
- **oEmbed**: A standard for embedding representations of URLs; used here to optionally fetch a YouTube video title.
- **Preview Cache**: An in-memory `Map<String, LinkPreview?>` keyed by URL, scoped to the app session.
- **File URL**: A URL whose path ends with a known file extension (`.jpg`, `.jpeg`, `.png`, `.gif`, `.webp`, `.mp4`, `.mov`, `.avi`, `.pdf`, `.zip`, `.doc`, `.docx`, `.xls`, `.xlsx`).

## Requirements

### Requirement 1: URL Detection in Messages

**User Story:** As a user, I want the app to automatically detect URLs in my messages, so that preview cards can be shown without any manual action.

#### Acceptance Criteria

1. WHEN a message is rendered, THE LinkPreviewService SHALL scan the message text for URLs using a regex that matches `http://` and `https://` schemes.
2. WHEN multiple URLs are present in a message, THE LinkPreviewService SHALL select only the first detected URL for preview.
3. WHEN the detected URL's path ends with a known file extension (`.jpg`, `.jpeg`, `.png`, `.gif`, `.webp`, `.mp4`, `.mov`, `.avi`, `.pdf`, `.zip`, `.doc`, `.docx`, `.xls`, `.xlsx`), THE LinkPreviewService SHALL skip preview generation for that URL.
4. WHEN a message contains no URL, THE LinkPreviewService SHALL not initiate any network request.
5. WHEN a message contains only whitespace or is empty, THE LinkPreviewService SHALL not initiate any network request.

---

### Requirement 2: YouTube URL Preview

**User Story:** As a user, I want YouTube links to show a video thumbnail with a play button, so that I can visually identify the video before opening it.

#### Acceptance Criteria

1. WHEN the detected URL matches a YouTube domain (`youtube.com/watch`, `youtu.be/`, `youtube.com/shorts/`, `youtube.com/embed/`), THE LinkPreviewService SHALL classify it as a YouTube URL.
2. WHEN a YouTube URL is classified, THE LinkPreviewService SHALL extract the video ID from the URL.
3. WHEN a video ID is extracted, THE LinkPreviewService SHALL construct the thumbnail URL as `https://img.youtube.com/vi/{videoId}/hqdefault.jpg` without making any API call.
4. WHEN a YouTube URL is detected, THE YouTubePreviewCard SHALL render a 16:9 aspect-ratio thumbnail image using the constructed CDN URL.
5. WHEN the thumbnail is displayed, THE YouTubePreviewCard SHALL overlay a circular play button icon centered on the thumbnail.
6. WHEN the thumbnail is displayed, THE YouTubePreviewCard SHALL display a YouTube branding label (red background, white "YouTube" text) in the bottom-left corner of the thumbnail.
7. WHERE an oEmbed title fetch succeeds within 8 seconds, THE YouTubePreviewCard SHALL display the video title below the thumbnail.
8. IF the oEmbed title fetch fails or times out, THE YouTubePreviewCard SHALL render without a title, showing only the thumbnail and branding.
9. THE YouTubePreviewCard SHALL have a maximum width of 320 logical pixels and be centered below the message bubble.
10. WHEN a user taps the YouTubePreviewCard, THE YouTubePreviewCard SHALL open the original YouTube URL in the device's external browser.

---

### Requirement 3: General Link Preview

**User Story:** As a user, I want non-YouTube links to show a rich preview card with the page title, description, and image, so that I can understand the content before opening it.

#### Acceptance Criteria

1. WHEN the detected URL is not a YouTube URL and not a file URL, THE LinkPreviewService SHALL send a `POST` request to `{ApiConfig.baseUrl}api/link_preview` with a JSON body `{"url": "<detected_url>"}` and a `Bearer` JWT token in the `Authorization` header.
2. WHEN the backend responds with HTTP 200 and a valid JSON body, THE LinkPreviewService SHALL parse the response into a `LinkPreview` model containing `title`, `description`, `imageUrl`, `siteName`, `faviconUrl`, and `url` fields.
3. WHEN the backend call exceeds 8 seconds without a response, THE LinkPreviewService SHALL cancel the request and treat the result as a failed preview.
4. IF the backend returns a non-200 status code or a network error occurs, THE LinkPreviewService SHALL treat the result as a failed preview and not render a card.
5. WHEN a valid `LinkPreview` is available, THE LinkPreviewCard SHALL render the OG image (if present) at the top of the card.
6. WHEN a valid `LinkPreview` is available, THE LinkPreviewCard SHALL display the domain name extracted from the URL below the image.
7. WHEN a valid `LinkPreview` is available and `title` is non-empty, THE LinkPreviewCard SHALL display the title text.
8. WHEN a valid `LinkPreview` is available and `description` is non-empty, THE LinkPreviewCard SHALL display the description text, truncated to a maximum of 3 lines.
9. WHERE a `faviconUrl` is present in the `LinkPreview`, THE LinkPreviewCard SHALL display the favicon image alongside the domain name.
10. THE LinkPreviewCard SHALL have a maximum width of 360 logical pixels and be centered below the message bubble.
11. WHEN a user taps the LinkPreviewCard, THE LinkPreviewCard SHALL open the original URL in the device's external browser.

---

### Requirement 4: In-Memory Preview Cache

**User Story:** As a user, I want the app to avoid re-fetching previews for URLs I have already seen, so that the chat remains fast and does not make redundant network calls.

#### Acceptance Criteria

1. THE LinkPreviewService SHALL maintain a single in-memory `Map<String, LinkPreview?>` cache keyed by the normalized URL string, shared across all chat screens within the same app session.
2. WHEN a preview is successfully fetched (YouTube or general), THE LinkPreviewService SHALL store the result in the cache under the URL key.
3. WHEN a preview fetch fails, THE LinkPreviewService SHALL store a `null` value in the cache under the URL key to prevent repeated failed requests.
4. WHEN a URL is requested for preview and the cache already contains an entry for that URL (including `null`), THE LinkPreviewService SHALL return the cached value immediately without making any network request.
5. WHEN the app is restarted, THE LinkPreviewService SHALL start with an empty cache (cache is not persisted to disk).

---

### Requirement 5: Preview Card Integration in Chat Screens

**User Story:** As a user, I want preview cards to appear below message bubbles in all supported chat areas, so that the experience is consistent across 1-on-1, self, and AI chat.

#### Acceptance Criteria

1. WHEN a `ChatMessageBubble` is built and the message content contains a previewable URL, THE MessageBubble SHALL display the appropriate preview card (YouTubePreviewCard or LinkPreviewCard) centered below the bubble widget.
2. WHEN an AI chat message is built and the message content contains a previewable URL, THE AIChatBubble SHALL display the appropriate preview card centered below the bubble widget.
3. WHILE a preview is being fetched asynchronously, THE MessageBubble SHALL render the bubble without a preview card (no loading spinner is required).
4. WHEN a preview fetch completes, THE MessageBubble SHALL update its state to display the preview card without rebuilding the entire message list.
5. WHEN a message does not contain a previewable URL or the preview fetch fails, THE MessageBubble SHALL render the bubble without any preview card.
6. THE preview card SHALL be rendered outside the bubble's `Container` decoration, appearing as a separate widget below the bubble.

---

### Requirement 6: External Browser Navigation

**User Story:** As a user, I want to open the previewed URL in my device's browser by tapping the card, so that I can view the full content.

#### Acceptance Criteria

1. WHEN a user taps a YouTubePreviewCard or LinkPreviewCard, THE app SHALL invoke `url_launcher` to open the URL in the device's default external browser.
2. IF `url_launcher` cannot launch the URL (e.g., no browser installed), THE app SHALL silently fail without crashing or showing an error dialog.
