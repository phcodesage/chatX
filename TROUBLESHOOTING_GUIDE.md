# Offline Messaging Troubleshooting Guide

## Quick Diagnosis

Run this test to check if caching is working at all:

### Option 1: Add Test Button (Recommended)

Add this to your home screen or settings:

```dart
import 'test_cache.dart';

// In your widget:
ElevatedButton(
  onPressed: () async {
    await testCacheSystem();
  },
  child: Text('Test Cache'),
)
```

Then:
1. Press the "Test Cache" button
2. Check the debug console
3. Look for "✅ CACHE SYSTEM IS WORKING!" or error messages

### Option 2: Check Debug Logs

When you open a conversation, look for these specific logs in order:

## Expected Log Flow

### When Opening Conversation (WiFi ON, First Time):

```
🔍 getConversationMessages called for userId: 2, offlineFirst: true
🔍 Current user ID: 1
🔍 Attempting to load from cache...
🔍 Loading cache for key: conversation_1_2
📦 No cache found for key: conversation_1_2
📦 Cache is empty, will try server
🔍 Fetching from server...
[API call happens]
💾 Saving 10 messages to cache with key: conversation_1_2
✅ Successfully saved 10 messages to cache
✅ Successfully loaded 10 messages
```

### When Opening Conversation (WiFi OFF, After Caching):

```
🔍 getConversationMessages called for userId: 2, offlineFirst: true
🔍 Current user ID: 1
🔍 Attempting to load from cache...
🔍 Loading cache for key: conversation_1_2
📦 Cache data found: {messages, updated_at, message_count}
📦 Cache has 10 messages
📦 Loaded 10 messages from cache
✅ Successfully loaded 10 messages
```

## Common Problems and Solutions

### Problem 1: "Current user ID: null"

**Symptom:**
```
🔍 Current user ID: null
🔍 Skipping cache: offlineFirst=true, currentUserId=null
```

**Cause:** User ID not stored after login

**Solution:**
Check if `StorageService.saveUserId()` is called after login:

```dart
// In your login code, make sure you have:
await StorageService.saveUserId(userId);
```

### Problem 2: "ChatCacheService not initialized"

**Symptom:**
```
⚠️ ChatCacheService not initialized!
⚠️ ChatCacheService not initialized, cannot save!
```

**Cause:** Hive database not initialized

**Solution:**
Check `main.dart` has this BEFORE `runApp()`:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await ChatCacheService.init();  // ← Must be here!
  await StorageService.init();
  
  // ... other initialization ...
  
  runApp(const MessengerApp());
}
```

### Problem 3: Cache saves but doesn't load

**Symptom:**
```
✅ Successfully saved 10 messages to cache
[Later...]
📦 No cache found for key: conversation_1_2
```

**Cause:** Cache key mismatch (user IDs in different order)

**Solution:**
The cache key is automatically sorted, so this shouldn't happen. But check if:
- User IDs are consistent
- You're not clearing cache somewhere
- App data wasn't cleared

### Problem 4: Messages arrive but not cached

**Symptom:**
- Messages appear in UI
- No "💾 Cached incoming message" logs

**Cause:** Socket.IO listener not saving to cache

**Solution:**
This should be fixed in the latest code. Verify you have:

```dart
// In chat_screen.dart, messageReceived listener:
await ChatCacheService.addMessageToCache(
  _currentUserId!,
  widget.otherUser.id,
  message,
);
```

### Problem 5: API fetch doesn't cache

**Symptom:**
```
✅ Successfully loaded 10 messages
[No "💾 Saving" log]
```

**Cause:** currentUserId is null or messages list is empty

**Solution:**
Check the MessageService code has:

```dart
if (currentUserId != null && messages.isNotEmpty) {
  await ChatCacheService.saveConversationMessages(
    currentUserId,
    userId,
    messages,
  );
}
```

## Step-by-Step Debugging

### Step 1: Verify Initialization

Add this to your app startup:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  debugPrint('🔧 Initializing cache...');
  await ChatCacheService.init();
  debugPrint('✅ Cache initialized');
  
  debugPrint('🔧 Initializing storage...');
  await StorageService.init();
  debugPrint('✅ Storage initialized');
  
  runApp(const MessengerApp());
}
```

### Step 2: Verify User ID

After login, add:

```dart
final userId = await StorageService.getUserId();
debugPrint('🔍 Logged in user ID: $userId');
```

### Step 3: Verify Cache Saving

After opening a conversation, check logs for:
- "💾 Saving X messages to cache"
- "✅ Successfully saved X messages to cache"

### Step 4: Verify Cache Loading

Turn off WiFi and reopen conversation, check for:
- "📦 Cache has X messages"
- "📦 Loaded X messages from cache"

## Manual Cache Inspection

Add this temporary code to see what's in the cache:

```dart
// In your chat screen
@override
void initState() {
  super.initState();
  _inspectCache();
}

Future<void> _inspectCache() async {
  final currentUserId = await StorageService.getUserId();
  debugPrint('🔍 Current user: $currentUserId');
  debugPrint('🔍 Other user: ${widget.otherUser.id}');
  
  if (currentUserId != null) {
    final cached = await ChatCacheService.loadConversationMessages(
      currentUserId,
      widget.otherUser.id,
    );
    debugPrint('🔍 Cache inspection: ${cached.length} messages found');
    if (cached.isNotEmpty) {
      debugPrint('🔍 First message: ${cached.first.content}');
      debugPrint('🔍 Last message: ${cached.last.content}');
    }
  }
}
```

## Still Not Working?

If none of the above helps, please provide:

1. **Full debug logs** from app startup to opening a conversation
2. **User ID** (check with `await StorageService.getUserId()`)
3. **Cache initialization status** (check logs for "Cache initialized")
4. **Test cache result** (run `testCacheSystem()` and share output)

With this information, we can pinpoint the exact issue!
