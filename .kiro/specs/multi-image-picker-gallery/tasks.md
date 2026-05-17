# Implementation Plan: Multi-Image Picker Gallery

## Overview

This plan implements a WhatsApp-style media sharing experience in the Flutter messenger app. The implementation progresses through dependency setup, UI components (attachment menu, preview screen, gallery viewer), services (media picker, compression, upload), and final integration with the existing chat screen and WebSocket infrastructure.

## Tasks

- [x] 1. Dependencies and project setup
  - [x] 1.1 Add required packages to pubspec.yaml
    - Add `wechat_assets_picker: ^9.0.0`, `flutter_image_compress: ^2.3.0`, `video_compress: ^3.1.3`, `photo_view: ^0.15.0`, `video_player: ^2.9.0`, `chewie: ^1.8.0` to dependencies
    - Run `flutter pub get` to verify resolution
    - _Requirements: 2.1, 4.4, 7.1, 7.2, 7.3_

- [x] 2. Attachment Menu
  - [x] 2.1 Create AttachmentMenuSheet widget
    - Create `lib/widgets/attachment_menu_sheet.dart`
    - Implement modal bottom sheet with Camera, Gallery, Document options in fixed order
    - Use dark theme (`Color(0xFF1E1E1E)`), white text, distinct icons (`Icons.camera_alt`, `Icons.photo_library`, `Icons.insert_drive_file`)
    - Support dismiss on outside tap or swipe down
    - Accept `onCameraTap`, `onGalleryTap`, `onDocumentTap` callbacks
    - _Requirements: 1.1, 1.2, 1.4, 1.5, 1.6, 1.7_

  - [x] 2.2 Integrate AttachmentMenuSheet into ChatScreen
    - Replace or augment existing attachment icon tap handler in `chat_composer_panel.dart` to show `AttachmentMenuSheet`
    - Wire Camera option to open device camera
    - Wire Gallery option to invoke `MediaPickerService.pickAssets`
    - Wire Document option to open system file picker (existing flow)
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5_

- [x] 3. Media Picker Service
  - [x] 3.1 Create MediaPickerService with permission handling
    - Create `lib/services/media_picker_service.dart`
    - Implement `pickAssets` method wrapping `wechat_assets_picker` with config: `maxAssets: 20`, `requestType: RequestType.common`, `themeColor: Color(0xFF25D366)`, dark theme delegate, numbered badges
    - Implement `captureFromCamera` method with max 60s video duration
    - Implement `requestPhotoPermission` and `requestCameraPermission` methods
    - Handle permission denied: show message with "Open Settings" button for photo library, error snackbar for camera
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8, 2.9, 2.10, 2.11, 2.12, 2.13, 1.3, 6.7, 6.8_

- [x] 4. Preview Screen
  - [x] 4.1 Create MediaPreviewScreen widget structure
    - Create `lib/screens/media_preview_screen.dart`
    - Accept `selectedAssets`, `recipientId`, `fromCamera` parameters
    - Implement state: `_items` list, `_currentIndex`, `_caption`, `_isSending`, `_compressionProgress`
    - Build layout: full preview area (top), thumbnail strip (bottom), caption input, send button
    - Display first item's full preview on open
    - _Requirements: 3.1, 3.2, 3.6, 3.7, 3.8, 3.9_

  - [x] 4.2 Implement thumbnail strip with reorder and remove
    - Build horizontal `ReorderableListView` for thumbnail strip
    - Implement long-press drag to reorder items
    - Add remove button (X) on each thumbnail
    - Auto-dismiss preview and return to chat if all items removed
    - Update `_currentIndex` and badge positions on reorder/remove
    - _Requirements: 3.3, 3.4, 3.5_

  - [ ]* 4.3 Write property tests for reorder and remove operations
    - **Property 1: Reorder preserves all items** — verify drag-and-drop reorder produces same items with only positions changed
    - **Property 2: Remove item decreases list size** — verify removing item at index I results in N-1 items without the removed item
    - **Validates: Requirements 3.3, 3.4**

  - [x] 4.4 Implement caption input and send flow
    - Add `TextField` with 1024 character limit for caption
    - Implement send button that disables on tap, triggers compression → upload pipeline
    - Show compression progress indicator ("Compressing 2 of 5")
    - _Requirements: 3.6, 3.7, 4.6_

  - [ ]* 4.5 Write property tests for caption and display formatting
    - **Property 3: Caption length constraint** — verify caption accepts at most 1024 characters, truncates longer strings
    - **Property 4: Video duration formatting** — verify `mm:ss` for < 3600s and `h:mm:ss` for ≥ 3600s
    - **Property 18: Item count display accuracy** — verify "N items selected" / "1 item selected" text
    - **Validates: Requirements 3.6, 3.9, 3.8**

  - [x] 4.6 Implement camera capture flow and "Add More" button
    - When `fromCamera: true`, show "Add More" button
    - "Add More" reopens camera, appends new capture to selection (up to 20)
    - Show notification if max 20 reached
    - Handle cancel: retain previously captured items
    - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5, 6.6_

  - [x] 4.7 Implement back navigation preserving selection
    - Back button returns to Asset_Picker with current selection preserved
    - Pass `selectedAssets` back to picker for continued editing
    - _Requirements: 3.10_

- [x] 5. Checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 6. Compression Service
  - [x] 6.1 Create CompressionService with image compression
    - Create `lib/services/compression_service.dart`
    - Define `CompressionResult` class with `bytes`, `mimeType`, `fileName`, `originalSize`, `compressedSize`, `compressionSkipped`
    - Implement `compressImage`: JPEG output at 65-75% quality, max 1920px longest side, preserve aspect ratio and orientation
    - Use `flutter_image_compress` package
    - Support JPEG, PNG, HEIC, WebP formats
    - GIF passthrough (no recompression)
    - _Requirements: 4.1, 4.2, 4.4, 4.7, 4.8_

  - [x] 6.2 Implement video compression
    - Implement `compressVideo`: 720p max, 2Mbps bitrate, target ≤50% original size
    - Use `video_compress` package
    - _Requirements: 4.3_

  - [x] 6.3 Implement batch compression with progress and error handling
    - Implement `compressBatch`: process items sequentially, call `onProgress` after each
    - 30-second timeout per item — fallback to original on timeout
    - On any compression error — return original with `compressionSkipped: true`
    - Implement `calculateTargetDimensions` for aspect-ratio-preserving scaling
    - _Requirements: 4.5, 4.6, 4.9_

  - [ ]* 6.4 Write property tests for compression logic
    - **Property 5: Image dimension scaling preserves aspect ratio** — verify target dimensions maintain aspect ratio within floating-point tolerance
    - **Property 6: GIF passthrough preserves bytes** — verify GIF input returns identical output bytes
    - **Property 7: Compression failure returns original with flag** — verify exception produces original bytes with `compressionSkipped: true`
    - **Validates: Requirements 4.2, 4.8, 4.5**

- [x] 7. Upload Service
  - [x] 7.1 Create MediaUploadService with single file upload
    - Create `lib/services/media_upload_service.dart`
    - Define `UploadProgress`, `UploadStatus`, `UploadResult` classes
    - Implement `uploadSingleFile`: multipart POST to `/api/mobile/messages/upload`, parse response into `Message` object
    - 120-second timeout, retry up to 3 times with exponential backoff (1s, 2s, 4s)
    - _Requirements: 5.1, 5.2, 5.5_

  - [x] 7.2 Implement batch upload with strategy selection
    - Implement `uploadBatch`: parallel for ≤5 files, sequential for >5
    - Implement `getStrategy` method
    - Caption attached only to first file's upload request
    - Report progress via callback
    - Continue uploading remaining files on individual failure
    - _Requirements: 5.3, 5.4, 5.5, 5.7_

  - [ ]* 7.3 Write property tests for upload logic
    - **Property 8: Upload response maps to complete message** — verify successful response fields map to Message object
    - **Property 9: Caption attached only to first message in batch** — verify only first upload includes caption
    - **Property 10: Upload strategy determined by batch size** — verify ≤5 → parallel, >5 → sequential
    - **Property 11: Upload retry continues remaining files** — verify failed file doesn't block subsequent uploads
    - **Validates: Requirements 5.2, 5.3, 5.7, 5.5**

- [x] 8. Checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 9. Gallery Viewer
  - [x] 9.1 Create MediaGalleryViewer widget structure
    - Create `lib/screens/media_gallery_viewer.dart`
    - Accept `mediaMessages`, `initialIndex`, `currentUserId` parameters
    - Implement `PageView` for horizontal swipe navigation between media items
    - Order media messages chronologically (oldest first)
    - Preload adjacent items (index ± 1)
    - _Requirements: 7.1, 8.1, 8.2, 8.6_

  - [x] 9.2 Implement image viewing with PhotoView zoom
    - Integrate `photo_view` for pinch-to-zoom (1x–5x) and double-tap toggle (1x/2x)
    - Disable swipe navigation when zoomed beyond 1.0x
    - Show message thumbnail as placeholder while loading full-resolution
    - Handle load timeout (10s) with error placeholder and retry
    - _Requirements: 7.1, 7.3, 7.6, 7.7_

  - [x] 9.3 Implement video playback in gallery viewer
    - Integrate `video_player` + `chewie` for video playback
    - Show play/pause button, seek bar with position/duration, mute/unmute
    - Stop playback and reset position when swiping away from video
    - _Requirements: 7.2, 8.8_

  - [x] 9.4 Implement metadata overlay and controls
    - Display sender name and timestamp (relative < 24h, absolute ≥ 24h)
    - Display position indicator "N of M"
    - Show close button (top-right), share button, download button
    - Tap media area to toggle overlay visibility (visible by default)
    - Handle system back gesture to dismiss
    - Handle unknown sender: display "Unknown User"
    - _Requirements: 9.1, 9.2, 9.3, 9.4, 9.5, 9.6, 9.7, 7.4, 7.5_

  - [x] 9.5 Implement swipe boundary behavior
    - Bounce effect at first (oldest) and last (newest) items
    - Swipe threshold: 50 density-independent pixels
    - Transition within 300ms for cached adjacent items
    - Error placeholder for items failing to load within 15s
    - _Requirements: 8.1, 8.3, 8.4, 8.5, 8.7_

  - [x] 9.6 Implement download and share functionality
    - Download button: show progress indicator, save to device photo library
    - Handle download timeout (30s) with error message and retry button
    - Share button: invoke native share sheet for current media
    - _Requirements: 9.4, 9.5, 9.6_

  - [ ]* 9.7 Write property tests for gallery viewer logic
    - **Property 12: Gallery media ordered chronologically** — verify ascending timestampMs order
    - **Property 13: Position indicator format** — verify "N of M" string for valid indices
    - **Property 14: Zoom level clamping** — verify zoom clamped to [1.0, 5.0]
    - **Property 15: Timestamp formatting** — verify relative (< 24h) vs absolute (≥ 24h) format
    - **Property 16: Overlay visibility toggle** — verify tap produces opposite state
    - **Property 17: Unknown user fallback** — verify null/empty/whitespace sender shows "Unknown User"
    - **Validates: Requirements 8.2, 7.5, 8.3, 7.3, 9.1, 9.3, 9.7**

- [x] 10. Integration and wiring
  - [x] 10.1 Wire ChatScreen to open Gallery Viewer on media tap
    - Add tap handler on image/video message bubbles to open `MediaGalleryViewer`
    - Collect all media messages from conversation, determine initial index
    - Pass `currentUserId` for sender identification
    - _Requirements: 7.1, 7.2, 8.2_

  - [x] 10.2 Implement MediaUploadState and progress indicators in ChatScreen
    - Create `MediaUploadState` (ChangeNotifier) in chat screen
    - Display per-file upload progress indicators in message list
    - Show error indicators on failed uploads with retry button
    - Remove progress indicators on completion
    - _Requirements: 5.4, 5.5_

  - [x] 10.3 Handle WebSocket file_received events for received media
    - Verify existing `file_received` listener in `SocketService` handles batch media messages
    - Ensure received media messages render correctly in message bubbles with thumbnails
    - Test that multiple rapid `file_received` events (batch) are handled without duplicates
    - _Requirements: 5.6_

  - [ ]* 10.4 Write integration tests for end-to-end media flow
    - Test: select → preview → compress → upload → message appears in chat
    - Test: WebSocket `file_received` creates message in receiver's chat
    - Test: permission denial flows (camera, photo library)
    - _Requirements: 1.1, 2.10, 5.6_

- [x] 11. Final checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation
- Property tests validate universal correctness properties from the design document (18 properties total)
- Unit tests validate specific examples and edge cases
- The implementation uses Dart/Flutter with existing app patterns (ChangeNotifier, setState)
- No new state management libraries are introduced (no Bloc/Riverpod)
- The existing `SocketService` file_received event handler is reused — no new WebSocket events needed

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1"] },
    { "id": 1, "tasks": ["2.1", "3.1"] },
    { "id": 2, "tasks": ["2.2", "4.1"] },
    { "id": 3, "tasks": ["4.2", "4.4", "4.6", "4.7"] },
    { "id": 4, "tasks": ["4.3", "4.5", "6.1"] },
    { "id": 5, "tasks": ["6.2", "6.3"] },
    { "id": 6, "tasks": ["6.4", "7.1"] },
    { "id": 7, "tasks": ["7.2"] },
    { "id": 8, "tasks": ["7.3", "9.1"] },
    { "id": 9, "tasks": ["9.2", "9.3"] },
    { "id": 10, "tasks": ["9.4", "9.5", "9.6"] },
    { "id": 11, "tasks": ["9.7", "10.1", "10.2"] },
    { "id": 12, "tasks": ["10.3"] },
    { "id": 13, "tasks": ["10.4"] }
  ]
}
```
