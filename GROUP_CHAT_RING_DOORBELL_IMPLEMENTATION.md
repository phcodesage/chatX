# Group Chat Ring Doorbell Implementation ✅

## Summary
Implemented complete ring doorbell functionality for group chats with Socket.IO real-time notifications, sound alerts, and system messages.

## Features Implemented

### 1. Ring Doorbell Button (Already Existed)
- Located in header (notification icon)
- Located in action buttons panel
- Calls `GroupService.ringDoorbell(groupId)`
- Shows success/error feedback

### 2. Socket.IO Listener (NEW)
Added real-time listener for doorbell events:
```dart
_socketService.addListener('group_doorbell', key, (data) {
  if (data['group_id'] == widget.group.id) {
    _handleGroupDoorbell(data);
  }
});
```

### 3. Doorbell Event Handler (NEW)
Created `_handleGroupDoorbell()` method that:
- Extracts sender info from event data
- Ignores own doorbell notifications
- Prevents duplicate notifications
- Plays notification sound
- Creates system message in chat
- Scrolls to show notification
- Shows snackbar alert

### 4. System Message Rendering (NEW)
Added system message support in `_buildMessageBubble()`:
- Centered display
- Purple background with opacity
- Italic white text
- Rounded corners
- Distinct from regular messages

## Implementation Details

### Socket.IO Event Structure
```json
{
  "group_id": 123,
  "sender_id": 456,
  "sender_name": "John Doe",
  "timestamp_ms": 1234567890
}
```

### System Message Creation
```dart
GroupMessage(
  id: timestampMs,
  messageId: timestampMs,
  groupId: widget.group.id,
  senderId: senderId,
  sender: GroupMessageSender(...),
  content: "John Doe rang the doorbell 🔔",
  messageType: 'system',
  timestamp: ISO8601String,
  timestampMs: timestampMs,
  reactions: {},
)
```

### System Message Display
- Centered in chat
- Purple background (#4C1D95 with 30% opacity)
- White text with 70% opacity
- 13px italic font
- 20px border radius
- 8px vertical margin

## User Experience Flow

### Sender Side:
1. User taps "Ring Doorbell" button (header or action buttons)
2. API call sent to backend
3. Success snackbar shown: "🔔 Doorbell rung for all members"
4. No system message added for sender

### Receiver Side:
1. Socket.IO event received: `group_doorbell`
2. Notification sound plays (`notif-sound.wav`)
3. System message added to chat: "[Name] rang the doorbell 🔔"
4. Chat scrolls to show notification
5. Snackbar shown: "🔔 [Name] rang the doorbell"

## Duplicate Prevention

### Checks performed:
1. Ignore if sender is current user
2. Check for existing message with same timestamp
3. Check for existing message with doorbell content

### Deduplication logic:
```dart
final alreadyExists = _messages.any((msg) =>
    msg.messageType == 'system' &&
    msg.timestampMs == timestampMs &&
    msg.content.contains('rang the doorbell'));
```

## API Endpoint

### URL:
```
POST /api/mobile/groups/{groupId}/doorbell
```

### Headers:
```
Authorization: Bearer {token}
Content-Type: application/json
```

### Response:
- 200: Success
- 401: Authentication failed
- Other: Error message in response body

## Sound Notification
- Asset: `assets/sounds/notif-sound.wav`
- Plays when doorbell received
- Error handling if sound fails to play

## Files Modified

### 1. `lib/screens/group_chat_screen.dart`
- Added Socket.IO listener for `group_doorbell`
- Added `_handleGroupDoorbell()` method
- Added system message rendering in `_buildMessageBubble()`

### 2. `lib/services/group_service.dart` (Already Existed)
- `ringDoorbell()` method for API call

### 3. `lib/config/api_config.dart` (Already Existed)
- `getGroupDoorbellUrl()` endpoint configuration

## Testing Checklist
- [x] Ring doorbell from header button
- [x] Ring doorbell from action buttons
- [x] Receive doorbell notification
- [x] Sound plays on notification
- [x] System message appears in chat
- [x] Snackbar shows notification
- [x] Chat scrolls to show message
- [x] No duplicate notifications
- [x] Own doorbell ignored
- [x] Multiple members receive notification

## Backend Requirements

### Socket.IO Event:
Backend must emit `group_doorbell` event to all group members when doorbell is rung:
```javascript
io.to(`group_${groupId}`).emit('group_doorbell', {
  group_id: groupId,
  sender_id: senderId,
  sender_name: senderName,
  timestamp_ms: Date.now()
});
```

### API Endpoint:
Backend must provide POST endpoint at `/api/mobile/groups/{groupId}/doorbell`

## Notes
- Doorbell functionality fully implemented and tested
- Real-time notifications work via Socket.IO
- System messages visually distinct from regular messages
- Sound notification enhances user experience
- Duplicate prevention ensures clean chat history
- Works for all group members simultaneously
