# Requirements Document

## Introduction

This feature adds a WhatsApp-style media sharing experience to the Flutter messenger app: (1) a custom gallery picker using `wechat_assets_picker` for multi-select of images and videos with album browsing, (2) a preview screen where users can review, reorder, remove, and caption selected media before sending, (3) image/video compression before upload for faster transfers and reduced storage, (4) a bottom sheet attachment menu for camera, gallery, and document options, and (5) a full-screen swipeable gallery viewer for browsing conversation media.

## Glossary

- **Asset_Picker**: The custom gallery picker component (powered by `wechat_assets_picker`) that provides album browsing, multi-select with badges, lazy-loading thumbnails, and smooth scrolling for images and videos
- **Preview_Screen**: The full-screen preview component displayed after media selection, showing selected items in a grid with options to reorder, remove, add captions, and confirm sending
- **Attachment_Menu**: The WhatsApp-style bottom sheet that slides up from the chat composer, presenting options for Camera, Gallery, and Document
- **Compression_Service**: The component (powered by `flutter_image_compress`) responsible for compressing images and videos before upload to reduce file size and improve transfer speed
- **Gallery_Viewer**: The full-screen overlay component that displays images and videos at full resolution with swipe navigation between them
- **Chat_Screen**: The main messaging interface where users compose and view messages
- **Message_Bubble**: The visual container that renders an individual message (text, image, video, file) in the chat list
- **Upload_Service**: The component responsible for uploading compressed files to the Flask backend via multipart upload and creating corresponding messages
- **Caption**: A text annotation that the user can attach to individual media items or to the entire batch before sending

## Requirements

### Requirement 1: Bottom Sheet Attachment Menu

**User Story:** As a user, I want to tap an attachment icon in the chat composer and see a WhatsApp-style bottom sheet with options for Camera, Gallery, and Document, so that I can quickly choose how to share media.

#### Acceptance Criteria

1. WHEN the user taps the attachment icon in the chat composer, THE Attachment_Menu SHALL slide up as a bottom sheet within 300 milliseconds displaying three options in a fixed order: Camera, Gallery, and Document
2. WHEN the user taps the Camera option, THE Attachment_Menu SHALL dismiss and open the device camera for capturing a photo or video
3. IF the device denies camera permission when the user taps the Camera option, THEN THE Attachment_Menu SHALL dismiss and display an error message indicating that camera access is required
4. WHEN the user taps the Gallery option, THE Attachment_Menu SHALL dismiss and open the Asset_Picker for multi-select browsing
5. WHEN the user taps the Document option, THE Attachment_Menu SHALL dismiss and open the system file picker for selecting documents
6. WHEN the user taps outside the Attachment_Menu or swipes it down, THE Attachment_Menu SHALL dismiss without taking any action
7. THE Attachment_Menu SHALL display each option with a distinct icon and a text label using the app's dark theme background color and white foreground text

### Requirement 2: Custom Gallery Picker (Multi-Select)

**User Story:** As a user, I want a WhatsApp-style gallery picker that lets me browse albums, select multiple images and videos with visual selection badges, so that I can efficiently choose media to send.

#### Acceptance Criteria

1. WHEN the Asset_Picker opens, THE Asset_Picker SHALL display a grid of device media (images and videos) from the default album with lazy-loading thumbnails, maintaining a frame rate of at least 60fps during scrolling
2. THE Asset_Picker SHALL provide an album/folder selector that allows the user to browse and switch between device albums
3. WHEN the user taps a media item, THE Asset_Picker SHALL mark the item as selected and display a numbered badge (selection counter) on the item indicating its position in the selection order
4. THE Asset_Picker SHALL enforce a maximum selection limit of 20 media items per pick action
5. IF the user has selected 20 items and attempts to select an additional item, THEN THE Asset_Picker SHALL prevent the additional selection and display a temporary notification for 3 seconds indicating the maximum of 20 items has been reached
6. WHILE the Asset_Picker is open, THE Asset_Picker SHALL display a counter showing the number of currently selected items out of the maximum 20 (e.g., "3 / 20")
7. WHEN the user taps a previously selected item, THE Asset_Picker SHALL deselect that item and renumber all remaining badges sequentially to reflect the updated selection order
8. THE Asset_Picker SHALL support selection of both images (JPEG, PNG, GIF, HEIC, WebP) and videos (MP4, MOV)
9. THE Asset_Picker SHALL display a duration label overlay on video thumbnails to visually distinguish them from image thumbnails
10. WHEN the user confirms the selection by tapping the done button in the Asset_Picker, THE Asset_Picker SHALL navigate to the Preview_Screen with all selected items in their selection order
11. IF the user cancels the Asset_Picker without confirming, THEN THE Asset_Picker SHALL return to the Chat_Screen without changes
12. IF the device denies or has not granted photo library permission, THEN THE Asset_Picker SHALL display a message indicating that media access is required and provide an option to open the device settings
13. IF the device media library contains no media items in the selected album, THEN THE Asset_Picker SHALL display an empty state message indicating no media is available

### Requirement 3: Media Preview Screen

**User Story:** As a user, I want to preview all my selected media before sending, so that I can review, reorder, remove items, and add captions — following the WhatsApp flow of Select → Preview → Caption → Send.

#### Acceptance Criteria

1. WHEN the Preview_Screen opens, THE Preview_Screen SHALL display the selected media items as a horizontally scrollable thumbnail strip at the bottom and the first item's full preview in the main area
2. WHEN the user taps a thumbnail in the strip, THE Preview_Screen SHALL display that item's full preview in the main area and visually highlight the selected thumbnail
3. THE Preview_Screen SHALL allow the user to reorder selected items by long-pressing and dragging thumbnails in the strip, updating the displayed order and item count badge positions upon drop
4. THE Preview_Screen SHALL allow the user to remove individual items by tapping a remove button on each thumbnail
5. IF all items are removed from the selection, THEN THE Preview_Screen SHALL dismiss and return to the Chat_Screen
6. THE Preview_Screen SHALL display a text input field for adding a caption to the media batch, limited to a maximum of 1024 characters
7. WHEN the user taps the send button on the Preview_Screen, THE Preview_Screen SHALL disable the send button to prevent duplicate submissions, pass all selected items and the caption to the Compression_Service and then to the Upload_Service for sending
8. THE Preview_Screen SHALL display the total count of selected items (e.g., "3 items selected")
9. WHEN the Preview_Screen displays a video item in the main area, THE Preview_Screen SHALL show a play button overlay and display the video duration in mm:ss format (or h:mm:ss for videos of 1 hour or longer)
10. IF the user presses the back button on the Preview_Screen, THEN THE Preview_Screen SHALL return to the Asset_Picker with the current selection preserved

### Requirement 4: Image and Video Compression Before Upload

**User Story:** As a user, I want my images and videos to be compressed before uploading, so that uploads are faster, use less mobile data, and consume less server storage.

#### Acceptance Criteria

1. WHEN the user confirms sending from the Preview_Screen, THE Compression_Service SHALL compress each image to a JPEG quality level between 65% and 75% before upload
2. THE Compression_Service SHALL preserve the original aspect ratio and orientation of each image during compression, and SHALL scale down images whose longest dimension exceeds 1920 pixels to a maximum of 1920 pixels on the longest side
3. WHEN compressing a video, THE Compression_Service SHALL re-encode the video to produce a file no larger than 50% of the original file size, with a maximum resolution of 720p (1280×720) and a maximum bitrate of 2 Mbps
4. THE Compression_Service SHALL process images using the `flutter_image_compress` package
5. IF compression of an individual item fails, THEN THE Compression_Service SHALL upload the original uncompressed file and notify the user with an inline indicator on the affected item that compression was skipped
6. WHILE compression is in progress, THE Preview_Screen SHALL display a progress indicator showing the number of items completed out of the total (e.g., "Compressing 2 of 5")
7. THE Compression_Service SHALL support compression of JPEG, PNG, HEIC, and WebP image formats
8. WHEN a GIF is selected, THE Compression_Service SHALL pass the GIF through without lossy recompression to preserve animation frames
9. IF compression of a single item does not complete within 30 seconds, THEN THE Compression_Service SHALL cancel the compression for that item, upload the original uncompressed file, and proceed to the next item

### Requirement 5: Upload and Message Creation

**User Story:** As a user, I want my compressed media to be uploaded to the server and appear as messages in the conversation, so that the recipient can view them.

#### Acceptance Criteria

1. WHEN compressed files are ready, THE Upload_Service SHALL upload each file individually to the Flask backend via multipart HTTP upload with a timeout of 120 seconds per file
2. WHEN a file upload completes successfully, THE Upload_Service SHALL create a separate message for each uploaded file in the conversation containing the file URL, file name, MIME type, and file size returned by the backend
3. WHEN a caption is provided, THE Upload_Service SHALL attach the caption text (maximum 1024 characters) to the first message in the batch
4. WHILE files are being uploaded, THE Chat_Screen SHALL display a progress indicator for each file showing the upload percentage, updated at least every 500 milliseconds or on each progress event from the HTTP client, whichever is less frequent
5. IF a file upload fails due to network error, server error, or timeout, THEN THE Upload_Service SHALL continue uploading remaining files, display an error indicator on the failed message, and provide a retry option allowing up to 3 retry attempts per failed file
6. WHEN the backend returns a successful upload response, THE Upload_Service SHALL treat the file message as sent and expect the backend to emit a websocket event so the receiver can download and display the media
7. THE Upload_Service SHALL use parallel upload for batches of 5 or fewer files and sequential upload for batches of more than 5 files

### Requirement 6: Camera Capture Flow

**User Story:** As a user, I want to take a photo or video from the camera and preview it before sending, so that I can verify the capture and optionally add a caption.

#### Acceptance Criteria

1. WHEN the user captures a photo or video via the camera, THE Preview_Screen SHALL open displaying the captured media with a text input field for adding a caption (maximum 1024 characters) and a send button
2. WHEN the Preview_Screen is showing a camera capture, THE Preview_Screen SHALL offer an "Add More" option to reopen the camera for additional captures
3. WHEN the user taps "Add More" and the current selection contains fewer than 20 items, THE Preview_Screen SHALL reopen the camera for another capture and append the new item to the selection
4. IF the user taps "Add More" and the current selection has reached 20 items, THEN THE Preview_Screen SHALL display a notification indicating the maximum selection limit of 20 has been reached, visible for at least 3 seconds
5. IF the user cancels the camera after tapping "Add More", THEN THE Preview_Screen SHALL retain all previously captured items and return to the preview state
6. IF the user cancels or dismisses the camera before any item has been captured, THEN THE Preview_Screen SHALL not open and the system SHALL return to the Chat_Screen
7. IF the device camera fails to open or camera permission is denied, THEN THE system SHALL display an error message indicating the camera is unavailable and return to the Chat_Screen
8. THE camera SHALL enforce a maximum video recording duration of 60 seconds per capture

### Requirement 7: Full-Screen Gallery Viewer

**User Story:** As a user, I want to open a full-screen gallery when I tap an image or video in the chat, so that I can view media at full resolution.

#### Acceptance Criteria

1. WHEN the user taps an image in a Message_Bubble, THE Gallery_Viewer SHALL open in full-screen mode displaying that image fitted to the screen dimensions while maintaining its original aspect ratio
2. WHEN the user taps a video in a Message_Bubble, THE Gallery_Viewer SHALL open in full-screen mode and begin playing the video with playback controls including a play/pause button, a seek bar showing current position and total duration, and a mute/unmute button
3. THE Gallery_Viewer SHALL support pinch-to-zoom with a minimum zoom level of 1x (fit-to-screen) and a maximum zoom level of 5x, and double-tap-to-zoom that toggles between 1x and 2x zoom levels
4. THE Gallery_Viewer SHALL display a close button in the top-right corner that returns the user to the Chat_Screen, and SHALL also dismiss when the user performs the system back gesture or presses the hardware back button
5. WHEN the Gallery_Viewer is open, THE Gallery_Viewer SHALL display the current media position indicator showing the format "N of M" where N is the current index and M is the total number of media items in the conversation
6. IF the full-resolution media fails to load within 10 seconds, THEN THE Gallery_Viewer SHALL display an error message indicating the media could not be loaded, provide a retry option, and preserve the user's ability to swipe to other items or dismiss the viewer
7. WHILE the Gallery_Viewer is loading a full-resolution image, THE Gallery_Viewer SHALL display the message thumbnail as a placeholder and show a loading indicator until the full-resolution image is rendered

### Requirement 8: Swipe Navigation Between Media

**User Story:** As a user, I want to swipe left and right through all images and videos in the conversation while in the gallery viewer, so that I can browse media without going back to the chat.

#### Acceptance Criteria

1. WHILE the Gallery_Viewer is open and the current media item is at default zoom level (1.0x scale), THE Gallery_Viewer SHALL allow horizontal swipe gestures of at least 50 density-independent pixels to navigate to the next or previous media item in the conversation
2. THE Gallery_Viewer SHALL collect all image and video messages from the current conversation and order them from oldest to newest (ascending chronological order), where swiping left navigates to the next newer item and swiping right navigates to the next older item
3. WHEN the user swipes to the next item, THE Gallery_Viewer SHALL update the position indicator to reflect the new position in "N of M" format, where N is the current item index and M is the total media count
4. IF the user is viewing the first (oldest) item and swipes right, THEN THE Gallery_Viewer SHALL display a boundary indication (e.g., bounce effect) and remain on the current item
5. IF the user is viewing the last (newest) item and swipes left, THEN THE Gallery_Viewer SHALL display a boundary indication (e.g., bounce effect) and remain on the current item
6. THE Gallery_Viewer SHALL preload adjacent items (one before and one after the current item) so that the transition to the next item completes within 300 milliseconds when the adjacent item is already cached
7. IF a media item fails to load within 15 seconds during swipe navigation, THEN THE Gallery_Viewer SHALL display an error placeholder in place of the item and allow the user to continue swiping to other items
8. WHEN the user swipes away from a video item that is currently playing, THE Gallery_Viewer SHALL stop playback of that video and reset its playback position to the beginning

### Requirement 9: Gallery Viewer Metadata

**User Story:** As a user, I want to see information about the media I'm viewing in the gallery, so that I know who sent it and when.

#### Acceptance Criteria

1. WHILE the Gallery_Viewer is open, THE Gallery_Viewer SHALL display the sender name and timestamp (in relative format for messages less than 24 hours old, e.g., "2 hours ago", and in absolute date-time format for older messages, e.g., "Jan 5, 2025 3:42 PM") for the currently viewed item
2. WHEN the Gallery_Viewer opens, THE Gallery_Viewer SHALL display the metadata overlay and navigation controls as visible by default
3. WHEN the user taps the media area outside of interactive controls, THE Gallery_Viewer SHALL toggle the visibility of the metadata overlay and navigation controls
4. WHILE the Gallery_Viewer is open, THE Gallery_Viewer SHALL display a share button that, when tapped, invokes the device's native share sheet for the currently viewed media
5. WHILE the Gallery_Viewer is open, THE Gallery_Viewer SHALL display a download button that, when tapped, shows a progress indicator and saves the media to the device's photo library upon completion
6. IF the media download does not complete within 30 seconds or a network error occurs, THEN THE Gallery_Viewer SHALL display an error message indicating the download could not be completed, remove the progress indicator, and present a retry button that re-initiates the download
7. IF the sender account has been deleted or the sender name is unavailable, THEN THE Gallery_Viewer SHALL display a placeholder label (e.g., "Unknown User") in place of the sender name
