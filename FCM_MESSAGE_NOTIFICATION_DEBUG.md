# FCM Message Notification Debugging Guide

## Issue
When the app is completely closed and a message notification is tapped, the app opens but does NOT navigate to the specific chat room where the message was sent.

## Required FCM Payload Format

For message notifications to work correctly, the backend MUST send the following data in the FCM notification:

### Minimum Required Fields
```json
{
  "data": {
    "type": "message",
    "sender_id": "123",
    "sender_name": "John Doe",
    "title": "New message from John Doe",
    "body": "Hey, how are you?"
  }
}
```

### Optional But Recommended Fields
```json
{
  "data": {
    "type": "message",
    "sender_id": "123",
    "sender_name": "John Doe",
    "title": "New message from John Doe",
    "body": "Hey, how are you?",
    "message_id": "456",
    "timestamp": "2024-01-15T10:30:00Z"
  }
}
```

### For Group Messages
```json
{
  "data": {
    "type": "message",
    "sender_id": "123",
    "sender_name": "John Doe",
    "group_id": "789",
    "group_name": "Team Chat",
    "title": "New message in Team Chat",
    "body": "John Doe: Hey everyone!"
  }
}
```

## Field Descriptions

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `type` | string | ✅ Yes | Must be "message" for chat messages |
| `sender_id` | string/int | ✅ Yes | User ID of the message sender |
| `sender_name` | string | ✅ Yes | Display name of the sender |
| `title` | string | ✅ Yes | Notification title (shown in notification tray) |
| `body` | string | ✅ Yes | Notification body (message preview) |
| `group_id` | string/int | ❌ No | Group ID if this is a group message |
| `group_name` | string | ❌ No | Group name for display |
| `message_id` | string/int | ❌ No | Unique message identifier |
| `timestamp` | string | ❌ No | Message timestamp |

## How to Debug

### Step 1: Install Debug APK
```bash
adb install build/app/outputs/flutter-apk/app-debug.apk
```

### Step 2: Connect Device and View Logs
```bash
adb logcat | grep -E "🔔|FCM|notification"
```

Or on Windows PowerShell:
```powershell
adb logcat | Select-String "🔔|FCM|notification"
```

### Step 3: Test Notification Flow
1. Completely close the app (swipe away from recent apps)
2. Send a message from another device/web app
3. Wait for notification to appear
4. Tap the notification
5. Watch the logs

### Step 4: Analyze Logs

#### Expected Success Logs:
```
🔔 App opened from terminated state via notification
Initial message notification: {title: New message from John Doe, body: Hey!}
Initial message data: {type: message, sender_id: 123, sender_name: John Doe, ...}
Data keys: [type, sender_id, sender_name, title, body]
Data values: [message, 123, John Doe, New message from John Doe, Hey!]
🔔 NotificationHandler.handleNotificationTap called with: {type: message, ...}
🔔 Data type: message
🔔 Sender ID: 123
🔔 Sender Name: John Doe
🔔 All keys: [type, sender_id, sender_name, title, body]
✅ Parsed senderId: 123, senderName: John Doe, type: message
📱 LobbyScreen: Processing pending notification: {type: message, ...}
🚀 Navigating to chat with user: 123 (John Doe)
```

#### Problem: Missing sender_id
```
🔔 App opened from terminated state via notification
Initial message data: {type: message, title: New message, body: Hey!}
Data keys: [type, title, body]
❌ Invalid sender_id in notification data
❌ Raw sender_id value: null
❌ sender_id type: Null
```
**Solution**: Backend must include `sender_id` in the FCM data payload

#### Problem: Wrong data type
```
🔔 Sender ID: user_123
❌ Invalid sender_id in notification data
❌ Raw sender_id value: user_123
❌ sender_id type: String
```
**Solution**: `sender_id` should be a numeric string or integer, not prefixed with text

#### Problem: Missing sender_name
```
✅ Parsed senderId: 123, senderName: null, type: message
🚀 Navigating to chat with user: 123 (User)
```
**Solution**: Backend should include `sender_name` for better UX (will default to "User" if missing)

## Backend Implementation Checklist

### For Node.js/Express Backend:
```javascript
// When a message is sent, send FCM notification to recipient
const sendMessageNotification = async (recipientFcmToken, message) => {
  const payload = {
    data: {
      type: 'message',
      sender_id: message.sender_id.toString(),
      sender_name: message.sender_name,
      title: `New message from ${message.sender_name}`,
      body: message.content.substring(0, 100), // Truncate long messages
      message_id: message.id.toString(),
      timestamp: message.created_at
    }
  };

  await admin.messaging().send({
    token: recipientFcmToken,
    data: payload.data,
    android: {
      priority: 'high',
      notification: {
        channelId: 'chat_messages',
        sound: 'default'
      }
    },
    apns: {
      payload: {
        aps: {
          sound: 'default',
          badge: 1
        }
      }
    }
  });
};
```

### For Group Messages:
```javascript
const sendGroupMessageNotification = async (recipientFcmTokens, message, group) => {
  const payload = {
    data: {
      type: 'message',
      sender_id: message.sender_id.toString(),
      sender_name: message.sender_name,
      group_id: group.id.toString(),
      group_name: group.name,
      title: `New message in ${group.name}`,
      body: `${message.sender_name}: ${message.content.substring(0, 100)}`,
      message_id: message.id.toString(),
      timestamp: message.created_at
    }
  };

  // Send to all group members except sender
  const tokens = recipientFcmTokens.filter(token => token !== senderToken);
  
  await admin.messaging().sendMulticast({
    tokens: tokens,
    data: payload.data,
    android: {
      priority: 'high',
      notification: {
        channelId: 'chat_messages'
      }
    }
  });
};
```

## Common Backend Mistakes

### ❌ Wrong: Sending notification object instead of data
```javascript
// This won't work for terminated state navigation!
{
  notification: {
    title: "New message",
    body: "Hey!"
  }
  // Missing data payload!
}
```

### ✅ Correct: Send data payload
```javascript
{
  data: {
    type: "message",
    sender_id: "123",
    sender_name: "John Doe",
    title: "New message from John Doe",
    body: "Hey!"
  }
}
```

### ❌ Wrong: Using wrong field names
```javascript
{
  data: {
    type: "message",
    user_id: "123",  // Should be sender_id
    name: "John Doe"  // Should be sender_name
  }
}
```

### ✅ Correct: Use exact field names
```javascript
{
  data: {
    type: "message",
    sender_id: "123",
    sender_name: "John Doe",
    title: "New message from John Doe",
    body: "Hey!"
  }
}
```

## Testing Without Backend Changes

If you can't modify the backend immediately, you can test with Firebase Console:

1. Go to Firebase Console → Cloud Messaging
2. Click "Send test message"
3. Enter your FCM token
4. Click "Add custom data"
5. Add these key-value pairs:
   - `type`: `message`
   - `sender_id`: `123`
   - `sender_name`: `Test User`
   - `title`: `Test Message`
   - `body`: `This is a test`
6. Send the notification
7. Tap it when app is closed

## Next Steps

1. **Install debug APK** and collect logs
2. **Check if backend is sending the correct payload** with all required fields
3. **Verify field names match exactly** (case-sensitive)
4. **Ensure sender_id is numeric** (string or int, not prefixed)
5. **Test with Firebase Console** if backend changes take time

## Files Modified for Enhanced Logging

- `lib/services/firebase_messaging_service.dart` - Added detailed data logging
- `lib/utils/notification_handler.dart` - Added field-by-field logging
- Debug APK location: `build/app/outputs/flutter-apk/app-debug.apk`
