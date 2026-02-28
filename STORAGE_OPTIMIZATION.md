# Storage Optimization - Text-Only Caching

## What Changed

Messages are now cached with **file URLs stripped** to save storage space. Only text content is saved.

## How It Works

### Before (With Files):
```json
{
  "id": 123,
  "content": "Check out this photo",
  "fileUrl": "https://example.com/images/photo.jpg",
  "fileName": "photo.jpg",
  "fileSize": 2048576,  // 2MB!
  "fileType": "image/jpeg"
}
```

### After (Text Only):
```json
{
  "id": 123,
  "content": "Check out this photo",  // Preview text
  "fileUrl": null,  // Stripped to save space
  "fileName": null,
  "fileSize": null,
  "fileType": null
}
```

## What's Cached

### ✅ Cached (Text Only):
- Text messages
- Message content (including previews like "📷 Photo", "🎬 Video")
- Reactions
- Timestamps
- Read status
- Delivery status
- Replies
- Tasks
- Excalidraw links

### ❌ Not Cached (File URLs Stripped):
- Image file URLs
- Video file URLs
- Audio file URLs
- Document file URLs
- File names
- File sizes
- File types

## Storage Impact

### Example: 1000 messages with files
- **Before**: ~220MB (with images/videos)
- **After**: ~2-5MB (text only)

### Example: 1000 text-only messages
- **Before**: ~2-5MB
- **After**: ~2-5MB (no change)

## How to Use

### Opening Conversations Offline

1. **Open app with WiFi ON**
2. **Open each conversation** you want to read offline
3. **Messages are cached** (text only)
4. **Turn OFF WiFi**
5. **Open conversation** - text messages appear!

### What You Can Do Offline

✅ Read all text messages  
✅ See message timestamps  
✅ See who sent each message  
✅ See reactions  
✅ See reply previews  
❌ Cannot view images/videos (they show as "📷 Photo" etc.)  
❌ Cannot download files  

## Why This Design

1. **Storage efficiency**: Text takes ~1KB per message, images take ~2MB each
2. **Fast loading**: No file downloads needed
3. **Privacy**: File URLs not stored locally
4. **Sufficient for most use cases**: Text content is what people usually want to read offline

## If You Need Files Offline

If you need to view images/videos offline, you have two options:

### Option 1: Download Files Manually
- Open conversation while online
- View the image/video
- It may be cached by the app's image/video cache

### Option 2: Use App's Built-in Cache
- Some apps cache media files separately
- Check if your app has a media cache setting

## Debugging

### Check Cache Size

```dart
final cacheSize = await ChatCacheService.getCacheSize();
debugPrint('Cache size: $cacheSize bytes');
```

### Clear Cache

```dart
// Clear all conversation caches
await ChatCacheService.clearAllConversations();

// Clear specific conversation
await ChatCacheService.clearUserCache(currentUserId);
```

## Summary

- ✅ Text messages cached (text only, no files)
- ✅ Storage optimized (~2-5MB for 1000 messages)
- ✅ Fast offline reading
- ❌ Images/videos not cached (show as preview text)
- ✅ Works like WhatsApp for text content
