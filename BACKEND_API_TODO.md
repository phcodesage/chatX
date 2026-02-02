# Backend API TODO - Flask Implementation

This document outlines all the API endpoints required by the Flutter mobile app that need to be implemented in the Flask backend.

## Base URL
```
https://dev.flask-meet.site
```

## Authentication
All endpoints (except register/login) require Bearer token authentication:
```
Authorization: Bearer <token>
```

---

## ✅ Already Implemented (Auth Endpoints)

### POST /api/auth/register
**Status**: Assumed working (login works)

**Request Body**:
```json
{
  "username": "string",
  "email": "string",
  "password": "string",
  "first_name": "string",
  "last_name": "string" // optional
}
```

**Response (201)**:
```json
{
  "token": "string",
  "user": {
    "id": 1,
    "username": "string",
    "email": "string",
    "first_name": "string",
    "last_name": "string",
    "full_name": "string",
    "avatar_url": "string or null",
    "bio": "string or null",
    "timezone": "string",
    "is_admin": false
  }
}
```

### POST /api/auth/login
**Status**: ✅ Working

**Request Body**:
```json
{
  "username": "string",
  "password": "string"
}
```

**Response (200)**: Same as register

### POST /api/auth/logout
**Status**: Assumed working

**Headers**: Requires Bearer token

**Response (200)**:
```json
{
  "message": "Logged out successfully"
}
```

### GET /api/auth/me
**Status**: Unknown

**Headers**: Requires Bearer token

**Response (200)**:
```json
{
  "user": {
    "id": 1,
    "username": "string",
    "email": "string",
    "first_name": "string",
    "last_name": "string",
    "full_name": "string",
    "avatar_url": "string or null",
    "bio": "string or null",
    "timezone": "string",
    "is_admin": false
  }
}
```

---

## ❌ MISSING - Mobile Endpoints (PRIORITY: HIGH)

### GET /api/mobile/lobby
**Status**: ❌ MISSING (Returns HTML, causing FormatException)

**Purpose**: Get list of users to display in the lobby/contact list

**Headers**: Requires Bearer token

**Response (200)**:
```json
{
  "lobby_users": [
    {
      "id": 1,
      "username": "string",
      "email": "string",
      "first_name": "string",
      "last_name": "string",
      "full_name": "string",
      "avatar_url": "string or null",
      "bio": "string or null",
      "status": "online|offline|away",
      "status_message": "string or null",
      "last_seen": "ISO 8601 datetime string or null",
      "is_online": true,
      "is_admin": false,
      "timezone": "string",
      "unread_count": 0,
      "is_contact": true,
      "is_admin_user": false
    }
  ]
}
```

**Implementation Notes**:
- For new users: return all admin users
- For existing users: return their contacts + admin users
- Include unread message count for each user
- Include online status and last seen timestamp

---

### GET /api/mobile/messages/conversation/:userId
**Status**: ❌ MISSING

**Purpose**: Get conversation messages with a specific user

**Headers**: Requires Bearer token

**Query Parameters**:
- `limit` (optional, default: 50) - Number of messages to return
- `before_id` (optional) - Get messages before this message ID (for pagination)

**Response (200)**:
```json
{
  "messages": [
    {
      "id": 1,
      "sender_id": 1,
      "recipient_id": 2,
      "content": "string",
      "message_type": "text",
      "timestamp": "ISO 8601 datetime string",
      "is_read": false,
      "is_delivered": true,
      "reply_to_id": null,
      "reply_to_message": null
    }
  ]
}
```

---

### POST /api/mobile/messages/send
**Status**: ❌ MISSING

**Purpose**: Send a message via REST API (alternative to Socket.IO)

**Headers**: Requires Bearer token

**Request Body**:
```json
{
  "recipient_id": 2,
  "content": "string",
  "message_type": "text",
  "reply_to_id": 1 // optional
}
```

**Response (201)**:
```json
{
  "data": {
    "id": 1,
    "sender_id": 1,
    "recipient_id": 2,
    "content": "string",
    "message_type": "text",
    "timestamp": "ISO 8601 datetime string",
    "is_read": false,
    "is_delivered": false,
    "reply_to_id": null,
    "reply_to_message": null
  }
}
```

---

### POST /api/mobile/messages/mark-read
**Status**: ❌ MISSING

**Purpose**: Mark messages as read

**Headers**: Requires Bearer token

**Request Body**:
```json
{
  "sender_id": 2,
  "last_message_id": 10
}
```

**Response (200)**:
```json
{
  "message": "Messages marked as read"
}
```

**Implementation Notes**:
- Mark all messages from sender_id up to and including last_message_id as read

---

## ❌ MISSING - Presence Endpoints (PRIORITY: MEDIUM)

### POST /api/mobile/presence/status
**Status**: ❌ MISSING (Likely causing errors)

**Purpose**: Update user's online status

**Headers**: Requires Bearer token

**Request Body**:
```json
{
  "status": "online|offline|away",
  "status_message": "string" // optional
}
```

**Response (200)**:
```json
{
  "message": "Status updated",
  "status": "online"
}
```

---

### POST /api/mobile/presence/heartbeat
**Status**: ❌ MISSING (Likely causing errors)

**Purpose**: Send heartbeat to maintain online status (called every 30 seconds)

**Headers**: Requires Bearer token

**Request Body**: Empty or `{}`

**Response (200)**:
```json
{
  "message": "Heartbeat received"
}
```

**Implementation Notes**:
- Update user's last_seen timestamp
- Automatically set status to online if not already
- Consider users offline if no heartbeat received for 2+ minutes

---

## 🔌 Socket.IO Events (PRIORITY: HIGH)

The app uses Socket.IO for real-time communication. The following events need to be handled:

### Connection
- **Event**: `connect`
- **Auth**: Token passed in query parameter and Authorization header
- **Action**: Join user to their personal room `user_{user_id}`

### Chat Events

#### Client → Server Events:
1. **join_chat** - Join a chat room with another user
   ```json
   { "user_id": 2 }
   ```

2. **leave_chat** - Leave a chat room
   ```json
   { "user_id": 2 }
   ```

3. **send_message** - Send a message
   ```json
   {
     "recipient_id": 2,
     "content": "string",
     "message_type": "text",
     "reply_to_id": 1 // optional
   }
   ```

4. **ring_doorbell** - Ring doorbell to get attention
   ```json
   { "recipient_id": 2 }
   ```

5. **typing_start** - Start typing indicator
   ```json
   { "recipient_id": 2 }
   ```

6. **typing_stop** - Stop typing indicator
   ```json
   { "recipient_id": 2 }
   ```

7. **typing_update** - Send typing preview
   ```json
   {
     "recipient_id": 2,
     "message": "preview text (max 120 chars)"
   }
   ```

8. **confirm_delivery** - Confirm message delivery
   ```json
   { "message_id": 1 }
   ```

9. **confirm_read** - Confirm message read
   ```json
   { "message_id": 1 }
   ```

#### Server → Client Events:
1. **joined_chat** - User joined chat room
2. **left_chat** - User left chat room
3. **new_message** - New message received
4. **doorbell** - Doorbell ring received
5. **user_typing** - User started typing
6. **typing_update** - Typing preview update
7. **presence_update** - User presence changed
8. **message_delivered** - Message delivery confirmation
9. **message_read** - Message read confirmation
10. **color_changed** - Chat color changed
11. **color_reset** - Chat color reset
12. **all_messages_deleted** - All messages deleted

---

## 📋 Implementation Checklist

### High Priority (App Breaking)
- [ ] GET /api/mobile/lobby
- [ ] GET /api/mobile/messages/conversation/:userId
- [ ] POST /api/mobile/messages/send
- [ ] Socket.IO connection handling
- [ ] Socket.IO send_message event
- [ ] Socket.IO new_message event

### Medium Priority (Features Don't Work)
- [ ] POST /api/mobile/presence/status
- [ ] POST /api/mobile/presence/heartbeat
- [ ] POST /api/mobile/messages/mark-read
- [ ] Socket.IO typing events
- [ ] Socket.IO presence events

### Low Priority (Nice to Have)
- [ ] Socket.IO doorbell event
- [ ] Socket.IO message delivery/read confirmations
- [ ] Socket.IO color change events
- [ ] Socket.IO delete messages events

---

## 🚀 Quick Start Implementation Order

1. **First**: Implement `/api/mobile/lobby` to fix the immediate error
2. **Second**: Implement Socket.IO connection and basic message events
3. **Third**: Implement message REST endpoints as fallback
4. **Fourth**: Implement presence/heartbeat endpoints
5. **Last**: Implement advanced features (typing, doorbell, etc.)

---

## 🧪 Testing

After implementing each endpoint, test with:
```bash
curl -X GET https://dev.flask-meet.site/api/mobile/lobby \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json"
```

The Flutter app will automatically work once these endpoints return proper JSON responses.
