# Group Messages Parsing Error - FIXED

## Issue
Messages were loading from API (50 messages fetched) but not displaying. Console showed:
```
❌ Get group messages error: type '_Map<String, dynamic>' is not a subtype of type 'String?' in type cast
Error loading group messages: type '_Map<String, dynamic>' is not a subtype of type 'String?' in type cast
```

## Root Cause
The `reply_preview` field in the API response can be either:
- `null` (no reply)
- A `String` (simple text preview)
- A `Map<String, dynamic>` (full reply object with content, sender, etc.)

The model was trying to cast it directly as `String?`, which failed when it was a Map.

## Solution
Updated `GroupMessage.fromJson()` in `lib/models/group.dart` to handle all three cases:

```dart
// Handle reply_preview which can be either a String or a Map
String? replyPreviewText;
final replyPreviewData = json['reply_preview'];
if (replyPreviewData != null) {
  if (replyPreviewData is String) {
    replyPreviewText = replyPreviewData;
  } else if (replyPreviewData is Map) {
    // If it's a map, extract the content field
    replyPreviewText = replyPreviewData['content'] as String?;
  }
}
```

## What to Do Now

**Hot restart your Flutter app** (press `R` in terminal):
```bash
R  # Capital R for hot restart
```

Then:
1. Open the app
2. Tap on the "testing group"
3. Messages should now display!

## Expected Result

You should see all 50 messages including:
- Text messages ("hello", "hi", etc.)
- Emoji messages (😃😃😃, etc.)
- Image messages (with thumbnails)
- Voice messages (with audio player)
- Doorbell notifications

## Console Logs After Fix

You should see:
```
💬 Fetching messages from: https://www.flask-call-app.site/api/mobile/groups/1/messages?limit=50
📡 Messages API response status: 200
✅ Loaded 50 messages for group 1
📋 First message: {content: ..., message_type: image, ...}
```

No more error about type casting!

## Files Modified

- `lib/models/group.dart` - Fixed `GroupMessage.fromJson()` to handle `reply_preview` as String or Map

## Message Types in Your Group

Based on the logs, your group has:
1. **Text messages** - Regular chat messages
2. **Image messages** - Screenshots and images
3. **Voice messages** - Audio recordings
4. **Doorbell messages** - Notification alerts
5. **Emoji messages** - Emojis and reactions

All of these should now display correctly!
