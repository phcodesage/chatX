# Group Messages Real-Time Fix

## Issue Description
Mobile users were receiving FCM notifications for group messages sent from web, but the messages were not appearing in real-time within the group chat screen. Users had to refresh or reopen the chat to see new messages.

## Root Cause Analysis

### Event Name Mismatch
**Problem**: The group chat screen was using snake_case event names but the socket service expects camelCase event names.

**Group Chat Screen (Incorrect)**:
```dart
_socketService.addListener('group_new_message', key, (data) { ... });
_socketService.addListener('group_message_sent', key, (data) { ... });
_socketService.addListener('group_file_message', key, (data) { ... });
_socketService.addListener('group_message_deleted', key, (data) { ... });
_socketService.addListener('group_message_edited', key, (data) { ... });
_socketService.addListener('group_reaction_updated', key, (data) { ... });
_socketService.addListener('group_reaction_cleared', key, (data) { ... });
_socketService.addListener('group_doorbell', key, (data) { ... });
_socketService.addListener('group_user_typing', key, (data) { ... });
```

**Socket Service Expected (Correct)**:
```dart
case 'groupNewMessage': // ✅ camelCase
case 'groupMessageSent': // ✅ camelCase  
case 'groupFileMessage': // ✅ camelCase
case 'groupMessageDeleted': // ✅ camelCase
case 'groupMessageEdited': // ✅ camelCase
case 'groupReactionUpdated': // ✅ camelCase
case 'groupReactionCleared': // ✅ camelCase
case 'groupDoorbell': // ✅ camelCase
case 'groupTyping': // ✅ camelCase
```

**Result**: Socket events were being emitted by the backend and received by the socket service, but never delivered to the group chat screen listeners because of the event name mismatch.

## Solution Implemented

### 1. Fixed Event Name Mapping
Updated all group chat screen socket listeners to use correct camelCase event names:

```dart
// BEFORE (snake_case - not working)
_socketService.addListener('group_new_message', key, (data) { ... });

// AFTER (camelCase - working)
_socketService.addListener('groupNewMessage', key, (data) { ... });
```

### 2. Enhanced Debug Logging
Added comprehensive logging to track message reception and processing:

```dart
_socketService.addListener('groupNewMessage', key, (data) {
  debugPrint('💬 [GROUP NEW MESSAGE] Event received for group ${widget.group.id}');
  debugPrint('💬 [GROUP NEW MESSAGE] Full data: $data');
  debugPrint('💬 [GROUP NEW MESSAGE] Data type: ${data.runtimeType}');
  debugPrint('💬 [GROUP NEW MESSAGE] Group ID in data: ${data['group_id']}');
  debugPrint('💬 [GROUP NEW MESSAGE] Current group ID: ${widget.group.id}');
  
  if (data['group_id'] == widget.group.id) {
    debugPrint('💬 [GROUP NEW MESSAGE] Processing message for current group');
    _handleNewMessage(data);
  }
});
```

### 3. Enhanced Message Processing
Improved the `_handleNewMessage` method with better error handling and logging:

```dart
void _handleNewMessage(Map<String, dynamic> data) async {
  debugPrint('📨 [GROUP NEW MESSAGE] Received: data=$data');
  debugPrint('📨 [GROUP NEW MESSAGE] Attempting to parse message...');
  
  try {
    final message = GroupMessage.fromJson(data);
    debugPrint('📨 [GROUP NEW MESSAGE] Successfully parsed message: ${message.id}');
    
    if (mounted) {
      debugPrint('📨 [GROUP NEW MESSAGE] Widget is mounted, adding to messages list');
      setState(() {
        _messages.add(message);
        debugPrint('📨 [GROUP NEW MESSAGE] Messages count: ${_messages.length}');
      });
      
      // Handle auto-scroll, notifications, caching, etc.
    }
  } catch (e, stackTrace) {
    debugPrint('❌ [GROUP NEW MESSAGE] Error parsing message: $e');
    debugPrint('❌ [GROUP NEW MESSAGE] Stack trace: $stackTrace');
  }
}
```

## Complete Event Name Mapping

| Backend Event | Socket Service Case | Group Chat Listener |
|---------------|-------------------|-------------------|
| `group_new_message` | `groupNewMessage` | `groupNewMessage` ✅ |
| `group_message_sent` | `groupMessageSent` | `groupMessageSent` ✅ |
| `group_file_message` | `groupFileMessage` | `groupFileMessage` ✅ |
| `group_message_deleted` | `groupMessageDeleted` | `groupMessageDeleted` ✅ |
| `group_message_edited` | `groupMessageEdited` | `groupMessageEdited` ✅ |
| `group_reaction_updated` | `groupReactionUpdated` | `groupReactionUpdated` ✅ |
| `group_reaction_cleared` | `groupReactionCleared` | `groupReactionCleared` ✅ |
| `group_doorbell` | `groupDoorbell` | `groupDoorbell` ✅ |
| `group_typing` | `groupTyping` | `groupTyping` ✅ |

## Expected Behavior After Fix

### Test Scenario: Web User Sends Group Message
1. **Web user sends message** in group chat
2. **Backend emits** `group_new_message` event to group members
3. **Socket service receives** event and broadcasts to `_groupNewMessageListeners`
4. **Group chat screen listener** receives event with correct camelCase name
5. **Message appears immediately** in mobile group chat
6. **Auto-scroll** to bottom if user is at bottom
7. **Notification sound** plays (if from another user)
8. **Message cached** for offline access
9. **FCM notification** also sent as backup (for background users)

### Debug Log Flow (Successful Message Reception)
```
💬 Group new message: {group_id: 6, message_id: 128, content: "Hello from web!", ...}
🔍 [BROADCAST DEBUG] Broadcasting to 1 listeners
🔍 [BROADCAST DEBUG] Listener keys: (group_chat_6)
💬 [GROUP NEW MESSAGE] Event received for group 6
💬 [GROUP NEW MESSAGE] Full data: {group_id: 6, message_id: 128, ...}
💬 [GROUP NEW MESSAGE] Data type: _Map<String, dynamic>
💬 [GROUP NEW MESSAGE] Group ID in data: 6
💬 [GROUP NEW MESSAGE] Current group ID: 6
💬 [GROUP NEW MESSAGE] Processing message for current group
📨 [GROUP NEW MESSAGE] Received: data={group_id: 6, message_id: 128, ...}
📨 [GROUP NEW MESSAGE] Attempting to parse message...
📨 [GROUP NEW MESSAGE] Successfully parsed message: 128
📨 [GROUP NEW MESSAGE] Message content: Hello from web!
📨 [GROUP NEW MESSAGE] Sender ID: 2
📨 [GROUP NEW MESSAGE] Current user ID: 16
📨 [GROUP NEW MESSAGE] Widget is mounted, adding to messages list
📨 [GROUP NEW MESSAGE] Messages count: 5
💾 Cached group message 128
🔊 Playing notification sound for message from other user
📨 [GROUP NEW MESSAGE] At bottom, marking messages as viewed
📨 [GROUP NEW MESSAGE] Scrolling to bottom
```

## Files Modified
- `lib/screens/group_chat_screen.dart` - Fixed event name mapping and enhanced logging

## Testing Checklist
- [ ] Web user sends text message → appears immediately on mobile
- [ ] Web user sends file/image → appears immediately on mobile  
- [ ] Web user edits message → edit appears immediately on mobile
- [ ] Web user deletes message → deletion appears immediately on mobile
- [ ] Web user adds reaction → reaction appears immediately on mobile
- [ ] Multiple messages sent rapidly → all appear in correct order
- [ ] Message sent while mobile app backgrounded → appears when reopened
- [ ] Debug logs show correct event reception and processing

## Troubleshooting
If group messages still don't appear in real-time:

1. **Check event reception at socket level**:
   ```bash
   grep "Group new message:" logs.txt
   ```

2. **Check event broadcasting**:
   ```bash
   grep "Broadcasting to.*listeners" logs.txt
   ```

3. **Check group chat listener registration**:
   ```bash
   grep "GROUP NEW MESSAGE.*Event received" logs.txt
   ```

4. **Check message parsing**:
   ```bash
   grep "Successfully parsed message" logs.txt
   ```

5. **Check UI updates**:
   ```bash
   grep "Messages count:" logs.txt
   ```

6. **Verify group room joining**:
   ```bash
   grep "join_group" logs.txt
   ```

## Notes
- Fix maintains backward compatibility with existing functionality
- Enhanced logging helps with future debugging
- No breaking changes to message handling logic
- Performance impact is minimal (just additional logging)
- FCM notifications still work as backup for background users