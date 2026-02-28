# Debug Offline Messaging Issue

## Enhanced Debug Logging

I've added extensive debug logging to help us understand what's happening. Here's what to look for:

## Test Steps with Debug Output

### Step 1: First Time Setup (WiFi ON)

1. Open the app with WiFi ON
2. Open a conversation
3. **Look for these logs:**

```
🔍 getConversationMessages called for userId: X, offlineFirst: true
🔍 Current user ID: Y
🔍 Attempting to load from cache...
🔍 Loading cache for key: conversation_X_Y
📦 No cache found for key: conversation_X_Y  (or "Cache has 0 messages")
📦 Cache is empty, will try server
🔍 Fetching from server...
✅ Successfully loaded 15 messages
💾 Saving 15 messages to cache with key: conversation_X_Y
✅ Successfully saved 15 messages to cache
```

### Step 2: Receive Messages (WiFi ON)

3. Send/receive some messages
4. **Look for these logs:**

```
💾 Cached incoming message 123
💾 Cached sent message 124
```

### Step 3: Test Offline (WiFi OFF)

5. Close the app
6. Turn OFF WiFi
7. Reopen the app
8. Open the same conversation
9. **Look for these logs:**

```
🔍 getConversationMessages called for userId: X, offlineFirst: true
🔍 Current user ID: Y
🔍 Attempting to load from cache...
🔍 Loading cache for key: conversation_X_Y
📦 Cache data found: {messages, updated_at, message_count}
📦 Cache has 15 messages
📦 Loaded 15 messages from cache
✅ Successfully loaded 15 messages
```

## What to Check

### If you see "Cache is empty":
- Messages were never cached
- Possible causes:
  1. Messages only arrived via Socket.IO but Socket.IO never connected
  2. Cache service not initialized
  3. User ID is null

### If you see "No cache found for key":
- The cache key doesn't match
- Possible causes:
  1. User IDs are different
  2. Cache was cleared
  3. First time opening this conversation

### If you see "ChatCacheService not initialized":
- The Hive database didn't initialize
- Check if `ChatCacheService.init()` is called in `main.dart`

### If you see "Current user ID: null":
- User ID is not stored
- Check if login saves the user ID properly

## Manual Cache Check

You can also manually check if cache exists by adding this temporary code:

```dart
// Add this in your chat screen's initState or _loadMessages
final currentUserId = await StorageService.getUserId();
if (currentUserId != null) {
  final cached = await ChatCacheService.loadConversationMessages(
    currentUserId,
    widget.otherUser.id,
  );
  debugPrint('🔍 MANUAL CHECK: Cache has ${cached.length} messages');
}
```

## Common Issues and Solutions

### Issue 1: Messages not being cached on first load
**Symptom:** No "💾 Saving X messages to cache" log
**Solution:** Check if API fetch is successful and currentUserId is not null

### Issue 2: Messages not being cached from Socket.IO
**Symptom:** No "💾 Cached incoming message" logs
**Solution:** Check if Socket.IO is connected and messages are arriving

### Issue 3: Cache key mismatch
**Symptom:** Saving with one key, loading with different key
**Solution:** Check if user IDs are consistent

### Issue 4: Hive not initialized
**Symptom:** "ChatCacheService not initialized" warnings
**Solution:** Ensure `await ChatCacheService.init()` is called in main.dart before runApp()

## Next Steps

1. Run the app with WiFi ON
2. Open a conversation
3. Copy ALL the debug logs and share them
4. Then turn WiFi OFF and try again
5. Copy those logs too

This will help us see exactly where the issue is!
