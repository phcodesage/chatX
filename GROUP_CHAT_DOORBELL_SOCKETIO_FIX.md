# Group Chat Doorbell - Socket.IO Fix ✅

## Issue
The REST API endpoint `/api/mobile/groups/{groupId}/doorbell` was not implemented on the backend, causing doorbell ring attempts to fail with "Failed to ring doorbell" error.

## Solution
Changed from REST API to Socket.IO for ringing the doorbell, since Socket.IO events are already working on the backend.

## Changes Made

### 1. Updated `_ringDoorbell()` Method
**Before:**
```dart
void _ringDoorbell() async {
  try {
    await GroupService.ringDoorbell(widget.group.id);  // REST API call
    // ...
  }
}
```

**After:**
```dart
void _ringDoorbell() async {
  try {
    _socketService.ringGroupDoorbell(widget.group.id);  // Socket.IO emit
    // ...
  }
}
```

### 2. Updated Header Doorbell Button
**Before:**
```dart
onPressed: () async {
  try {
    await GroupService.ringDoorbell(widget.group.id);  // REST API call
    // ...
  }
}
```

**After:**
```dart
onPressed: () {
  try {
    _socketService.ringGroupDoorbell(widget.group.id);  // Socket.IO emit
    // ...
  }
}
```

## How It Works Now

### Sender Side:
1. User taps "Ring Doorbell" button
2. Socket.IO emits `ring_group_doorbell` event with `{group_id: X}`
3. Success snackbar shown immediately
4. No REST API call needed

### Backend Processing:
1. Receives `ring_group_doorbell` event
2. Broadcasts `group_doorbell` event to all group members
3. Includes sender info in the broadcast

### Receiver Side:
1. Receives `group_doorbell` Socket.IO event
2. Plays notification sound
3. Creates system message in chat
4. Shows snackbar notification
5. Scrolls to show the message

## Socket.IO Events

### Emit (Sender):
```javascript
emit('ring_group_doorbell', {
  group_id: 1
});
```

### Receive (All Members):
```javascript
on('group_doorbell', {
  message_id: 64,
  group_id: 1,
  group_name: "testing group",
  sender_id: 2,
  sender_name: "rech Toledo",
  timestamp_ms: 1772220894259
});
```

## Benefits of Socket.IO Approach

1. ✅ **Real-time** - Instant delivery to all members
2. ✅ **No REST API needed** - Works with existing Socket.IO infrastructure
3. ✅ **Already implemented** - Backend already has Socket.IO support
4. ✅ **Consistent** - Matches how other real-time features work
5. ✅ **Reliable** - Socket.IO handles reconnection automatically

## Files Modified
- `lib/screens/group_chat_screen.dart`
  - Updated `_ringDoorbell()` method
  - Updated header doorbell button

## Backend Requirements

### Socket.IO Event Handler:
Backend must listen for `ring_group_doorbell` event:
```javascript
socket.on('ring_group_doorbell', (data) => {
  const { group_id } = data;
  const sender_id = socket.user_id;
  const sender_name = socket.user_name;
  
  // Broadcast to all group members
  io.to(`group_${group_id}`).emit('group_doorbell', {
    message_id: generateId(),
    group_id: group_id,
    group_name: getGroupName(group_id),
    sender_id: sender_id,
    sender_name: sender_name,
    timestamp_ms: Date.now()
  });
});
```

## Testing Results

### Before Fix:
```
I/flutter: Ring group doorbell error: Exception: Failed to ring doorbell
I/flutter: Error ringing doorbell: Exception: Failed to ring doorbell
```

### After Fix:
```
I/flutter: 📤 Emitting ring_group_doorbell: {group_id: 1}
I/flutter: 🔔 Group doorbell: {message_id: 64, group_id: 1, sender_name: rech Toledo...}
I/flutter: [Sound plays]
I/flutter: [System message added to chat]
```

## Notes
- REST API endpoint `/api/mobile/groups/{groupId}/doorbell` is no longer needed
- Socket.IO approach is more efficient for real-time notifications
- Backend already has full Socket.IO support for group doorbell
- No changes needed to backend - already working!
- GroupService.ringDoorbell() method can be removed if not used elsewhere
