# Group Messages Not Loading - Fix Applied

## Issue
Group is visible in lobby, but when tapping on it, no messages are displayed even though messages exist on the web interface.

**Current Backend**: `https://www.flask-call-app.site`

## Root Causes & Fixes

### 1. GroupMessageSender Model Missing lastName Field (FIXED)
**Problem**: The API returns `last_name` in the sender object, but the `GroupMessageSender` model didn't have this field, causing JSON parsing to fail.

**Solution**: Updated `lib/models/group.dart` to include `lastName` field in `GroupMessageSender` class with proper fallback logic.

```dart
class GroupMessageSender {
  final int id;
  final String username;
  final String firstName;
  final String lastName;  // ← Added this
  final String fullName;
  
  // Added smart parsing logic to build fullName from firstName + lastName
}
```

### 2. Wrong Socket.IO Event Names (FIXED)
**Problem**: Socket.IO event listeners were using camelCase names (`groupNewMessage`) but the server emits snake_case names (`group_new_message`).

**Solution**: Updated all event names in `lib/screens/group_chat_screen.dart`:
- `groupNewMessage` → `group_new_message`
- `groupMessageSent` → `group_message_sent`
- `groupFileMessage` → `group_file_message`
- `groupMessageDeleted` → `group_message_deleted`
- `groupMessageEdited` → `group_message_edited`
- `groupReactionUpdated` → `group_reaction_updated`
- `groupReactionCleared` → `group_reaction_cleared`

### 3. Enhanced Debugging (ADDED)
**Added comprehensive logging** in `lib/services/group_service.dart` for the `getMessages()` method:
- Logs the full URL being called
- Logs token length
- Logs full API response body
- Logs message count and first message details

## Testing Instructions

### Step 1: Hot Restart the App
```bash
# Press R (capital R) in terminal, or:
Ctrl+C
flutter run
```

### Step 2: Check Console Logs
When you tap on a group, look for these logs:

#### Expected Success:
```
💬 Fetching messages from: https://www.flask-call-app.site/api/mobile/groups/1/messages?limit=50
🔑 Token length: 245
📡 Messages API response status: 200
📡 Messages API response body: {"messages":[...], "group":{...}, "has_more":false}
✅ Loaded 5 messages for group 1
📋 First message: {id: 1, content: "Hello", sender_id: 2, ...}
```

#### If Still Failing:
```
❌ Failed to load messages: 404
❌ Get group messages error: FormatException: Unexpected character...
```

### Step 3: Verify Messages Display
1. Open the app
2. Tap on a group from the lobby
3. Messages should load and display
4. You should see the message history from the web interface

### Step 4: Test Real-time Messages
1. Keep mobile app open in a group chat
2. Send a message from web interface
3. Message should appear immediately on mobile (via Socket.IO)

## What to Check If Still Not Working

### Check 1: API Response Structure
The console logs will now show the full API response. Look for:
```json
{
  "messages": [
    {
      "id": 1,
      "message_id": 1,
      "group_id": 1,
      "sender_id": 2,
      "sender": {
        "id": 2,
        "username": "john",
        "first_name": "John",
        "last_name": "Doe",  ← Must be present
        "email": "john@example.com"
      },
      "content": "Hello",
      "message_type": "text",
      "timestamp": "2024-01-15T10:00:00",
      "timestamp_ms": 1705320000000,  ← Must be present
      ...
    }
  ]
}
```

### Check 2: Model Parsing Errors
If you see errors like:
```
type 'Null' is not a subtype of type 'String'
FormatException: Unexpected character
```

This means the API response structure doesn't match the model. Check the console logs for the actual response structure.

### Check 3: Empty Messages Array
If the API returns `{"messages": []}`, then:
1. Verify messages exist in the database for this group
2. Check if the user is actually a member of the group
3. Verify the backend endpoint is working correctly

### Check 4: Socket.IO Events
For real-time messages, verify Socket.IO is connected:
```
✅ Socket connected - ID: [socket_id]
```

If not connected, messages won't appear in real-time (but should still load via REST API).

## Files Modified

1. **lib/models/group.dart**
   - Added `lastName` field to `GroupMessageSender`
   - Improved `fromJson` parsing with fallback logic

2. **lib/services/group_service.dart**
   - Enhanced debugging in `getMessages()` method
   - Logs full URL, token length, response body, and message details

3. **lib/screens/group_chat_screen.dart**
   - Fixed Socket.IO event names (camelCase → snake_case)
   - Removed non-existent `_handleDoorbell` listener

## Expected Behavior After Fix

### On Opening Group Chat
1. Shows loading indicator
2. Fetches messages via REST API
3. Displays messages in chronological order
4. Scrolls to bottom automatically
5. Marks messages as viewed

### When New Message Arrives
1. Receives `group_new_message` event via Socket.IO
2. Adds message to chat immediately
3. Scrolls to bottom if already at bottom
4. Shows notification if not at bottom

### Message Display
- Sender name and avatar
- Message content
- Timestamp (formatted: "10:30 AM", "Yesterday", etc.)
- Message type indicator (text, image, file, etc.)
- Reactions (if any)
- Reply preview (if replying to another message)

## Troubleshooting Commands

### Test API Directly
```bash
# Replace GROUP_ID and TOKEN with actual values
curl -H "Authorization: Bearer YOUR_TOKEN" \
  "https://www.flask-call-app.site/api/mobile/groups/GROUP_ID/messages?limit=50"
```

### Check Database
Ask backend developer to run:
```sql
SELECT gm.id, gm.content, gm.message_type, gm.timestamp, 
       u.username, u.first_name, u.last_name
FROM group_message gm
JOIN user u ON gm.sender_id = u.id
WHERE gm.group_id = YOUR_GROUP_ID
  AND gm.is_deleted = 0
ORDER BY gm.timestamp DESC
LIMIT 10;
```

### Verify User is Group Member
```sql
SELECT * FROM group_member
WHERE group_id = YOUR_GROUP_ID
  AND user_id = YOUR_USER_ID
  AND is_active = 1;
```

## Next Steps

1. **Hot restart the app**
2. **Tap on a group**
3. **Check console logs** for the new debug output
4. **Verify messages appear**
5. **Test sending a message** from mobile
6. **Test real-time updates** by sending from web

If messages still don't appear, share the console logs (especially the "Messages API response body" line) for further debugging.
