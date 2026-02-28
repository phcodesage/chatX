# How to Test Offline Messaging

## Quick Test (5 minutes)

### Step 1: Setup (WiFi ON)
1. Open your Flutter messenger app
2. Make sure WiFi/mobile data is ON
3. Open a conversation with someone
4. Send and receive a few messages (at least 5-10 messages)
5. Wait for all messages to appear
6. Close the app completely (swipe away from recent apps)

### Step 2: Go Offline
1. Turn OFF WiFi
2. Turn OFF mobile data
3. Make sure you have NO internet connection

### Step 3: Test Offline Reading
1. Open the app again
2. Navigate to the same conversation
3. **Expected Result:** All your messages should appear instantly! ✅

### Step 4: Test Group Chats (Optional)
1. While still offline, open a group chat you've used before
2. **Expected Result:** Group messages should also appear! ✅

## What You Should See

### Success Indicators:
- ✅ Messages load instantly (no loading spinner)
- ✅ All previous messages are visible
- ✅ You can scroll through the conversation
- ✅ Message timestamps and content are correct
- ✅ Works for both direct and group chats

### In Debug Logs (if you're checking):
```
📦 Loaded 15 messages from cache
```

## Troubleshooting

### If messages don't appear offline:

**Problem:** No messages cached yet
- **Solution:** Make sure you opened the conversation while online first
- Messages are only cached after they arrive via Socket.IO

**Problem:** Cache was cleared
- **Solution:** The cache persists, but if you cleared app data, you need to go online once to rebuild the cache

**Problem:** First time opening a conversation
- **Solution:** You need to receive at least one message while online for caching to start

## Advanced Testing

### Test Cache Persistence:
1. Chat while online (messages get cached)
2. Turn off internet
3. Close app
4. Restart phone (optional)
5. Open app
6. Messages should still be there!

### Test Background Sync:
1. Open conversation offline (see cached messages)
2. Turn on internet
3. Stay in the conversation
4. New messages should sync automatically in background

### Test Multiple Conversations:
1. While online, open 3-4 different conversations
2. Send/receive messages in each
3. Go offline
4. All conversations should have cached messages

## Expected Behavior

| Scenario | Expected Result |
|----------|----------------|
| Open conversation online | Messages load from cache instantly, then sync |
| Open conversation offline | Messages load from cache |
| Receive message while online | Message appears AND gets cached |
| Send message while offline | Message queued (not implemented yet) |
| No cache available | Shows empty (need to go online first) |

## Notes

- First-time conversations need at least one online session to build cache
- Cache stores up to 1000 messages per conversation
- Cache is automatic - no manual management needed
- Works exactly like WhatsApp offline mode
