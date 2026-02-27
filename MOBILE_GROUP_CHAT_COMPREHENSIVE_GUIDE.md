# Mobile Group Chat API - Comprehensive Guide

## Table of Contents
1. [Overview](#overview)
2. [Critical Issue: Mobile Apps Not Seeing Admin-Created Groups](#critical-issue)
3. [Authentication](#authentication)
4. [Group Management Endpoints](#group-management-endpoints)
5. [Messaging Endpoints](#messaging-endpoints)
6. [Real-time Communication (Socket.IO)](#real-time-communication)
7. [Troubleshooting](#troubleshooting)
8. [Implementation Checklist](#implementation-checklist)

---

## Overview

The mobile app uses **token-based authentication** (JWT) to access group chat functionality via REST API endpoints under `/api/mobile`. The web interface uses **session-based authentication** via Flask-Login.

**Base URL**: `https://your-domain.com/api/mobile`

**Authentication**: All mobile endpoints require `Authorization: Bearer <token>` header

---

## Critical Issue: Mobile Apps Not Seeing Admin-Created Groups

### Problem Description
When an admin user creates a group chat from the web interface, mobile apps don't see the newly created group in their group list.

### Root Cause Analysis

#### 1. **Socket.IO Event Broadcasting**
When a group is created via web (`POST /group-chat/api/create`), the system broadcasts a `group_created` event:

```python
# From app/routes/group_chat.py (line ~75)
for uid in added_members + [current_user.id]:
    socketio.emit('group_created', group_data, room=f'user_{uid}')
```

**Issue**: Mobile apps may not be connected to Socket.IO or listening to the `group_created` event.

#### 2. **Mobile API Group List Endpoint**
Mobile apps fetch groups via `GET /api/mobile/groups`:

```python
# From app/routes/mobile_api.py (line ~1065)
@bp.route('/groups', methods=['GET'])
@token_required
def list_groups(current_user):
    memberships = GroupMember.query.filter_by(
        user_id=current_user.id, 
        is_active=True
    ).all()
```

**This endpoint SHOULD work** - it queries `GroupMember` table for all active memberships.


### Possible Causes

#### Cause 1: Mobile App Not Refreshing Group List
**Solution**: Implement periodic polling or pull-to-refresh
```dart
// Flutter example
Future<void> refreshGroups() async {
  final response = await http.get(
    Uri.parse('$baseUrl/api/mobile/groups'),
    headers: {'Authorization': 'Bearer $token'},
  );
  // Update UI with new groups
}
```

#### Cause 2: Socket.IO Not Connected on Mobile
**Solution**: Connect to Socket.IO and listen for `group_created` event
```dart
// Flutter socket_io_client example
import 'package:socket_io_client/socket_io_client.dart' as IO;

IO.Socket socket = IO.io('https://your-domain.com', <String, dynamic>{
  'transports': ['websocket'],
  'extraHeaders': {'Authorization': 'Bearer $token'}
});

socket.on('group_created', (data) {
  // Add new group to local list
  setState(() {
    groups.add(Group.fromJson(data));
  });
});
```

#### Cause 3: Token Authentication Issue
**Solution**: Verify token is valid and not expired
```dart
// Check token expiration before API calls
bool isTokenExpired(String token) {
  try {
    final parts = token.split('.');
    final payload = json.decode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1])))
    );
    final exp = payload['exp'] as int;
    return DateTime.now().millisecondsSinceEpoch > exp * 1000;
  } catch (e) {
    return true;
  }
}
```

#### Cause 4: Database Transaction Not Committed
**Solution**: Verify web group creation commits to database
```python
# Check in app/routes/group_chat.py
db.session.commit()  # Must be called after adding GroupMember records
```

#### Cause 5: User Not Added as Member
**Solution**: Verify `GroupMember` record is created for the user
```sql
-- Check database directly
SELECT * FROM group_member 
WHERE user_id = <mobile_user_id> 
AND is_active = 1;
```

---

## Authentication

### 1. Login and Get Token

**Endpoint**: `POST /api/mobile/login`

**Request**:
```json
{
  "username": "user@example.com",
  "password": "password123"
}
```

**Response**:
```json
{
  "success": true,
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "user": {
    "id": 1,
    "username": "user@example.com",
    "first_name": "John",
    "last_name": "Doe",
    "email": "user@example.com",
    "is_admin": false,
    "status": "online"
  }
}
```

**Token Details**:
- Algorithm: HS256
- Expiration: 24 hours (86400 seconds)
- Payload: `{ exp, iat, sub: user_id }`

### 2. Using the Token

Include in every API request:
```
Authorization: Bearer <token>
```

Or as query parameter (not recommended for production):
```
GET /api/mobile/groups?token=<token>
```

---

## Group Management Endpoints

### 1. List All Groups

**Endpoint**: `GET /api/mobile/groups`

**Headers**:
```
Authorization: Bearer <token>
```

**Response**:
```json
{
  "groups": [
    {
      "id": 1,
      "name": "Team Chat",
      "description": "Our team discussion group",
      "avatar_url": null,
      "created_by": 1,
      "created_at": "2024-01-15T10:30:00",
      "updated_at": "2024-01-15T10:30:00",
      "is_active": true,
      "member_count": 5,
      "my_role": "admin",
      "is_muted": false,
      "members": [
        {
          "id": 1,
          "group_id": 1,
          "user_id": 2,
          "role": "member",
          "joined_at": "2024-01-15T10:30:00",
          "is_active": true,
          "is_muted": false,
          "user": {
            "id": 2,
            "username": "john_doe",
            "first_name": "John",
            "last_name": "Doe",
            "email": "john@example.com",
            "status": "online"
          }
        }
      ],
      "last_message": {
        "id": 100,
        "message_id": 100,
        "group_id": 1,
        "sender_id": 2,
        "content": "Hello everyone!",
        "message_type": "text",
        "timestamp": "2024-01-15T11:00:00",
        "timestamp_ms": 1705318800000,
        "is_deleted": false,
        "sender": {
          "id": 2,
          "username": "john_doe",
          "first_name": "John",
          "last_name": "Doe"
        }
      }
    }
  ]
}
```

**Key Fields**:
- `my_role`: Current user's role in the group (`admin` or `member`)
- `is_muted`: Whether the user has muted notifications for this group
- `timestamp_ms`: Unix timestamp in milliseconds (for mobile convenience)
- Groups are sorted by last message timestamp (most recent first)

### 2. Create a Group

**Endpoint**: `POST /api/mobile/groups`

**Headers**:
```
Authorization: Bearer <token>
Content-Type: application/json
```

**Request**:
```json
{
  "name": "New Team",
  "description": "Optional description",
  "member_ids": [2, 3, 5]
}
```

**Response**:
```json
{
  "success": true,
  "group": {
    "id": 2,
    "name": "New Team",
    "description": "Optional description",
    "avatar_url": null,
    "created_by": 1,
    "created_at": "2024-01-15T12:00:00",
    "updated_at": "2024-01-15T12:00:00",
    "is_active": true,
    "member_count": 4,
    "members": [...]
  }
}
```

**Notes**:
- Creator is automatically added as admin
- System message is created: "{Creator} created the group "{name}""
- Socket.IO `group_created` event is emitted to all members
- FCM push notifications are NOT sent on group creation

### 3. Get Group Details

**Endpoint**: `GET /api/mobile/groups/<group_id>`

**Response**: Same structure as single group in list endpoint

### 4. Edit Group

**Endpoint**: `PUT /api/mobile/groups/<group_id>` or `PATCH /api/mobile/groups/<group_id>`

**Permission**: Only admins and creator can edit

**Request**:
```json
{
  "name": "Updated Name",
  "description": "Updated description",
  "avatar_url": "https://example.com/avatar.jpg"
}
```

**Response**:
```json
{
  "success": true,
  "group": { ... }
}
```

**Notes**:
- If name changes, system message is created
- Socket.IO `group_updated` event is emitted to all members

### 5. Add Members

**Endpoint**: `POST /api/mobile/groups/<group_id>/members`

**Permission**: Only admins can add members

**Request**:
```json
{
  "user_ids": [6, 7, 8]
}
```

**Response**:
```json
{
  "success": true,
  "added": [6, 7, 8],
  "group": { ... }
}
```

**Notes**:
- System message created for each added member
- Socket.IO `group_member_added` event emitted to all members
- New members receive `group_created` event

### 6. Remove Member / Leave Group

**Endpoint**: `DELETE /api/mobile/groups/<group_id>/members/<user_id>`

**Permission**: 
- Admins can remove any member
- Any member can remove themselves (leave)

**Response**:
```json
{
  "success": true,
  "group": { ... }
}
```

**Notes**:
- System message created
- Socket.IO `group_member_removed` event emitted
- Removed user also receives the event

### 7. Leave Group (Alternative)

**Endpoint**: `POST /api/mobile/groups/<group_id>/leave`

**Response**:
```json
{
  "success": true,
  "message": "Left group successfully"
}
```

---

## Messaging Endpoints

### 1. Get Messages (Paginated)

**Endpoint**: `GET /api/mobile/groups/<group_id>/messages`

**Query Parameters**:
- `limit`: Number of messages to fetch (default: 50, max: 200)
- `before_id`: Fetch messages before this message ID (for pagination)

**Example**:
```
GET /api/mobile/groups/1/messages?limit=50&before_id=100
```

**Response**:
```json
{
  "messages": [
    {
      "id": 99,
      "message_id": 99,
      "group_id": 1,
      "sender_id": 2,
      "sender": {
        "id": 2,
        "username": "john_doe",
        "first_name": "John",
        "last_name": "Doe",
        "email": "john@example.com"
      },
      "content": "Hello!",
      "message_type": "text",
      "timestamp": "2024-01-15T10:45:00",
      "timestamp_ms": 1705317900000,
      "is_deleted": false,
      "file_url": null,
      "file_name": null,
      "file_size": null,
      "file_type": null,
      "reply_to_id": null,
      "reply_preview": null
    }
  ],
  "group": { ... },
  "has_more": true
}
```

**Message Types**:
- `text`: Regular text message
- `image`: Image attachment
- `file`: File attachment
- `voice`: Voice message
- `video`: Video attachment
- `system`: System-generated message (member added, group renamed, etc.)
- `doorbell`: Doorbell notification

**Pagination**:
1. First request: `GET /groups/1/messages?limit=50`
2. Get oldest message ID from response (e.g., 50)
3. Next request: `GET /groups/1/messages?limit=50&before_id=50`
4. Continue until `has_more` is `false`

### 2. Send Text Message

**Endpoint**: `POST /api/mobile/groups/<group_id>/messages`

**Request**:
```json
{
  "content": "Hello everyone!",
  "message_type": "text",
  "reply_to_id": 98
}
```

**Response**:
```json
{
  "success": true,
  "data": {
    "id": 101,
    "message_id": 101,
    "group_id": 1,
    "sender_id": 1,
    "sender": { ... },
    "content": "Hello everyone!",
    "message_type": "text",
    "timestamp": "2024-01-15T11:05:00",
    "timestamp_ms": 1705320300000,
    "reply_to_id": 98,
    "reply_preview": {
      "id": 98,
      "sender_id": 2,
      "content": "Previous message...",
      "message_type": "text"
    }
  }
}
```

**Notes**:
- Socket.IO events emitted:
  - `group_message_sent` to sender
  - `group_new_message` to other members
- FCM push notifications sent to offline members

### 3. Upload File/Image

**Endpoint**: `POST /api/mobile/groups/<group_id>/messages/upload`

**Content-Type**: `multipart/form-data`

**Form Fields**:
- `file`: Binary file data (required)
- `caption`: Optional text caption

**Example (Flutter)**:
```dart
var request = http.MultipartRequest(
  'POST',
  Uri.parse('$baseUrl/api/mobile/groups/$groupId/messages/upload'),
);
request.headers['Authorization'] = 'Bearer $token';
request.files.add(await http.MultipartFile.fromPath('file', filePath));
request.fields['caption'] = 'Check this out!';

var response = await request.send();
```

**Response**:
```json
{
  "success": true,
  "data": {
    "id": 102,
    "message_id": 102,
    "group_id": 1,
    "sender_id": 1,
    "content": "[image: photo.jpg] - Check this out!",
    "message_type": "image",
    "file_url": "https://your-domain.com/static/uploads/messages/abc123.jpg",
    "file_name": "photo.jpg",
    "file_size": 245678,
    "file_type": "image/jpeg",
    "timestamp_ms": 1705320400000
  },
  "file_url": "https://your-domain.com/static/uploads/messages/abc123.jpg",
  "file_id": "abc123"
}
```

**Allowed File Types**:
- Images: jpg, jpeg, png, gif, webp
- Videos: mp4, mov, avi, webm
- Audio: mp3, wav, ogg, m4a
- Documents: pdf, doc, docx, txt, csv, xlsx

**File Size Limit**: Check server configuration (typically 16MB)

### 4. Delete Message

**Endpoint**: `DELETE /api/mobile/groups/<group_id>/messages/<message_id>`

**Permission**:
- Message sender can delete their own messages
- Group admins can delete any message

**Response**:
```json
{
  "success": true,
  "message": "Message deleted"
}
```

**Notes**:
- Soft delete (sets `is_deleted=true`)
- Socket.IO `group_message_deleted` event emitted to all members

### 5. Edit Message

**Endpoint**: `PUT /api/mobile/groups/<group_id>/messages/<message_id>` or `PATCH`

**Permission**: Only message sender can edit

**Request**:
```json
{
  "content": "Updated message content"
}
```

**Response**:
```json
{
  "success": true,
  "message": "Message edited",
  "data": { ... }
}
```

**Notes**:
- Socket.IO `group_message_edited` event emitted to all members

### 6. Add Reaction

**Endpoint**: `POST /api/mobile/groups/<group_id>/messages/<message_id>/reactions`

**Request**:
```json
{
  "emoji": "👍"
}
```

**Response**:
```json
{
  "success": true,
  "reactions": {
    "👍": ["John Doe", "Jane Smith"],
    "❤️": ["Alice Johnson"]
  }
}
```

**Notes**:
- If user already reacted with same emoji, it updates (doesn't duplicate)
- Socket.IO `group_reaction_updated` event emitted

### 7. Remove Reaction

**Endpoint**: `DELETE /api/mobile/groups/<group_id>/messages/<message_id>/reactions`

**Request**:
```json
{
  "emoji": "👍"
}
```

**Response**:
```json
{
  "success": true,
  "reactions": {
    "❤️": ["Alice Johnson"]
  }
}
```

### 8. Ring Doorbell

**Endpoint**: `POST /api/mobile/groups/<group_id>/doorbell`

**Response**:
```json
{
  "success": true,
  "message_id": 103,
  "data": {
    "message_id": 103,
    "group_id": 1,
    "group_name": "Team Chat",
    "sender_id": 1,
    "sender_name": "John Doe",
    "timestamp_ms": 1705320500000
  }
}
```

**Notes**:
- Creates a doorbell message in database
- Socket.IO `group_doorbell` event emitted to all members
- FCM push notifications sent to offline members
- Play notification sound on receiving devices

### 9. Mark Message as Delivered

**Endpoint**: `POST /api/mobile/groups/<group_id>/messages/<message_id>/delivered`

**Response**:
```json
{
  "success": true,
  "status": "delivered"
}
```

**Notes**:
- Socket.IO `message_status_updated` event sent to original sender

### 10. Mark Messages as Viewed/Read

**Endpoint**: `POST /api/mobile/groups/<group_id>/messages/viewed`

**Request**:
```json
{
  "message_ids": [100, 101, 102],
  "sender_id": 2
}
```

**Response**:
```json
{
  "success": true,
  "marked_count": 3
}
```

**Notes**:
- Socket.IO `message_status_updated` events sent to sender for each message

---

## Real-time Communication (Socket.IO)

### Connection Setup

**Server URL**: `https://your-domain.com`

**Transport**: WebSocket (preferred) with polling fallback

**Authentication**: Include token in connection headers or query

**Flutter Example**:
```dart
import 'package:socket_io_client/socket_io_client.dart' as IO;

IO.Socket socket = IO.io('https://your-domain.com', 
  IO.OptionBuilder()
    .setTransports(['websocket'])
    .setExtraHeaders({'Authorization': 'Bearer $token'})
    .setAuth({'token': token})
    .enableAutoConnect()
    .build()
);

socket.onConnect((_) {
  print('Connected to Socket.IO');
  // Join user room
  socket.emit('join', {'user_id': currentUserId});
});

socket.onDisconnect((_) => print('Disconnected'));
socket.onConnectError((data) => print('Connection Error: $data'));
```

### Events to Listen For

#### 1. `group_created`
Emitted when a new group is created (to all members)

**Payload**:
```json
{
  "id": 2,
  "name": "New Group",
  "description": "...",
  "created_by": 1,
  "member_count": 3,
  "members": [...],
  "last_message": null
}
```

**Action**: Add group to local list and refresh UI

#### 2. `group_updated`
Emitted when group details are edited (to all members)

**Payload**: Same as `group_created`

**Action**: Update group in local list

#### 3. `group_member_added`
Emitted when members are added (to all members including new ones)

**Payload**:
```json
{
  "group": { ... },
  "added_user_ids": [6, 7]
}
```

**Action**: Update member list in UI

#### 4. `group_member_removed`
Emitted when a member is removed or leaves (to all members including removed one)

**Payload**:
```json
{
  "group": { ... },
  "removed_user_id": 5
}
```

**Action**: 
- If removed user is current user: Remove group from list
- Otherwise: Update member list

#### 5. `group_message_sent`
Confirmation to sender that their message was sent

**Payload**: Full message object

**Action**: Update message status to "sent" in UI

#### 6. `group_new_message`
New message from another member

**Payload**: Full message object with sender details

**Action**: 
- Add message to chat if group is open
- Increment unread count if group is not open
- Show notification
- Play notification sound

#### 7. `group_message_deleted`
Message was deleted

**Payload**:
```json
{
  "message_id": 100,
  "group_id": 1
}
```

**Action**: Remove message from UI or mark as deleted

#### 8. `group_message_edited`
Message was edited

**Payload**:
```json
{
  "message_id": 100,
  "group_id": 1,
  "content": "Updated content"
}
```

**Action**: Update message content in UI

#### 9. `group_doorbell`
Doorbell notification

**Payload**:
```json
{
  "message_id": 103,
  "group_id": 1,
  "group_name": "Team Chat",
  "sender_id": 2,
  "sender_name": "John Doe",
  "timestamp_ms": 1705320500000
}
```

**Action**: 
- Show notification
- Play doorbell sound
- Vibrate device

#### 10. `group_user_typing`
Another member is typing

**Payload**:
```json
{
  "group_id": 1,
  "user_id": 2,
  "username": "john_doe",
  "full_name": "John Doe",
  "message": ""
}
```

**Action**: Show "{full_name} is typing..." indicator

#### 11. `group_reaction_updated`
Reaction added to message

**Payload**:
```json
{
  "message_id": 100,
  "group_id": 1,
  "user_id": 2,
  "user_name": "John Doe",
  "emoji": "👍",
  "reactions": {
    "👍": ["John Doe", "Jane Smith"]
  }
}
```

**Action**: Update reaction display on message

#### 12. `group_reaction_cleared`
Reaction removed from message

**Payload**: Same as `group_reaction_updated`

**Action**: Update reaction display

#### 13. `group_voice_message`
Voice message received

**Payload**:
```json
{
  "group_id": 1,
  "message_id": 104,
  "sender_id": 2,
  "sender_name": "John Doe",
  "audio_url": "/static/audio/voice_123.wav",
  "file_name": "voice_123.wav",
  "file_type": "audio/wav",
  "file_size": 45678,
  "duration": 5.2,
  "timestamp_ms": 1705320600000,
  "message_type": "voice"
}
```

**Action**: Add voice message to chat with audio player

#### 14. `message_status_updated`
Message delivery/read status changed

**Payload**:
```json
{
  "message_id": 100,
  "status": "delivered",
  "delivered_by": 3,
  "delivered_by_name": "Alice"
}
```

**Status values**: `delivered`, `seen`

**Action**: Update message status indicator (checkmarks)

### Events to Emit

#### 1. `group_send_message`
Send a text message

**Payload**:
```json
{
  "group_id": 1,
  "content": "Hello!",
  "message_type": "text",
  "reply_to_id": 99
}
```

#### 2. `group_typing`
Notify others you're typing

**Payload**:
```json
{
  "group_id": 1
}
```

**Note**: Emit this every 2-3 seconds while typing, stop when done

#### 3. `group_message_delivered`
Acknowledge message delivery

**Payload**:
```json
{
  "message_id": 100,
  "group_id": 1
}
```

#### 4. `group_messages_viewed`
Mark messages as read

**Payload**:
```json
{
  "group_id": 1,
  "message_ids": [100, 101, 102],
  "sender_id": 2
}
```

#### 5. `group_ring_doorbell`
Ring doorbell (alternative to REST endpoint)

**Payload**:
```json
{
  "group_id": 1
}
```

#### 6. `group_set_reaction`
Add/toggle reaction (alternative to REST endpoint)

**Payload**:
```json
{
  "group_id": 1,
  "message_id": 100,
  "reaction": "👍"
}
```

#### 7. `group_clear_reaction`
Remove reaction (alternative to REST endpoint)

**Payload**:
```json
{
  "group_id": 1,
  "message_id": 100,
  "reaction": "👍"
}
```

---

## Troubleshooting

### Issue 1: Mobile App Not Seeing Admin-Created Groups

**Symptoms**:
- Admin creates group from web interface
- Mobile app doesn't show the new group
- Other members don't see the group

**Debugging Steps**:

1. **Check Database**:
```sql
-- Verify group was created
SELECT * FROM group_chat WHERE id = <group_id>;

-- Verify members were added
SELECT gm.*, u.username 
FROM group_member gm
JOIN user u ON gm.user_id = u.id
WHERE gm.group_id = <group_id> AND gm.is_active = 1;
```

2. **Test Mobile API Directly**:
```bash
curl -H "Authorization: Bearer <token>" \
  https://your-domain.com/api/mobile/groups
```

Expected: Group should appear in response

3. **Check Socket.IO Connection**:
```dart
socket.onConnect((_) {
  print('Socket connected: ${socket.connected}');
  print('Socket ID: ${socket.id}');
});
```

4. **Verify Token**:
```bash
# Decode JWT token
echo "<token>" | cut -d'.' -f2 | base64 -d | jq
```

Check `exp` (expiration) and `sub` (user_id)

5. **Check Server Logs**:
```bash
tail -f logs/calls.log | grep "GROUP"
```

Look for:
- `[GROUP MESSAGE]` - Message sent
- `[GROUP CREATED]` - Group creation
- `[TOKEN_AUTH]` - Authentication

**Solutions**:

**Solution A: Implement Pull-to-Refresh**
```dart
RefreshIndicator(
  onRefresh: () async {
    await fetchGroups();
  },
  child: ListView.builder(...)
)
```

**Solution B: Connect to Socket.IO**
```dart
socket.on('group_created', (data) {
  setState(() {
    groups.insert(0, Group.fromJson(data));
  });
  showNotification('New group: ${data['name']}');
});
```

**Solution C: Periodic Polling**
```dart
Timer.periodic(Duration(seconds: 30), (timer) {
  if (isAppActive) {
    fetchGroups();
  }
});
```

### Issue 2: Messages Not Appearing in Real-time

**Symptoms**:
- Messages sent but not received immediately
- Need to refresh to see new messages

**Solutions**:

1. **Ensure Socket.IO is connected**:
```dart
if (!socket.connected) {
  socket.connect();
}
```

2. **Listen for `group_new_message` event**:
```dart
socket.on('group_new_message', (data) {
  if (data['group_id'] == currentGroupId) {
    setState(() {
      messages.add(Message.fromJson(data));
    });
    scrollToBottom();
  }
});
```

3. **Send delivery acknowledgment**:
```dart
socket.emit('group_message_delivered', {
  'message_id': message.id,
  'group_id': message.groupId,
});
```

### Issue 3: Token Expired

**Symptoms**:
- API returns 401 Unauthorized
- "Invalid or expired token" error

**Solutions**:

1. **Implement Token Refresh**:
```dart
Future<String> refreshToken() async {
  final response = await http.post(
    Uri.parse('$baseUrl/api/mobile/refresh'),
    headers: {'Authorization': 'Bearer $oldToken'},
  );
  
  if (response.statusCode == 200) {
    final data = json.decode(response.body);
    await storage.write(key: 'token', value: data['token']);
    return data['token'];
  }
  
  // Token refresh failed, re-login required
  navigateToLogin();
  throw Exception('Token refresh failed');
}
```

2. **Intercept 401 Responses**:
```dart
Future<http.Response> authenticatedRequest(
  Future<http.Response> Function() request
) async {
  var response = await request();
  
  if (response.statusCode == 401) {
    // Try to refresh token
    await refreshToken();
    // Retry request
    response = await request();
  }
  
  return response;
}
```

### Issue 4: File Upload Fails

**Symptoms**:
- File upload returns error
- Large files fail to upload

**Solutions**:

1. **Check File Size**:
```dart
if (file.lengthSync() > 16 * 1024 * 1024) {
  showError('File too large. Max 16MB');
  return;
}
```

2. **Verify File Type**:
```dart
final allowedExtensions = [
  'jpg', 'jpeg', 'png', 'gif', 'webp',
  'mp4', 'mov', 'avi', 'webm',
  'mp3', 'wav', 'ogg', 'm4a',
  'pdf', 'doc', 'docx', 'txt'
];

final ext = path.extension(file.path).toLowerCase().substring(1);
if (!allowedExtensions.contains(ext)) {
  showError('File type not allowed');
  return;
}
```

3. **Add Timeout**:
```dart
var request = http.MultipartRequest(...);
var response = await request.send().timeout(
  Duration(seconds: 60),
  onTimeout: () {
    throw TimeoutException('Upload timed out');
  },
);
```

### Issue 5: Notifications Not Working

**Symptoms**:
- No push notifications when app is in background
- Doorbell doesn't ring

**Solutions**:

1. **Verify FCM Token is Registered**:
```dart
final fcmToken = await FirebaseMessaging.instance.getToken();
await http.post(
  Uri.parse('$baseUrl/api/mobile/fcm/register'),
  headers: {
    'Authorization': 'Bearer $token',
    'Content-Type': 'application/json',
  },
  body: json.encode({'fcm_token': fcmToken}),
);
```

2. **Handle Background Messages**:
```dart
FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('Background message: ${message.data}');
  
  if (message.data['type'] == 'group_message') {
    showNotification(
      title: message.data['sender_name'],
      body: message.data['content'],
    );
  }
}
```

3. **Request Notification Permissions**:
```dart
final settings = await FirebaseMessaging.instance.requestPermission(
  alert: true,
  badge: true,
  sound: true,
);

if (settings.authorizationStatus != AuthorizationStatus.authorized) {
  showError('Notification permission denied');
}
```

---

## Implementation Checklist

### Phase 1: Authentication & Basic Setup

- [ ] Implement login endpoint integration
- [ ] Store JWT token securely (flutter_secure_storage)
- [ ] Add token to all API requests
- [ ] Implement token expiration handling
- [ ] Add automatic token refresh
- [ ] Handle 401 responses gracefully

### Phase 2: Group List & Details

- [ ] Fetch groups list on app start
- [ ] Display groups with last message preview
- [ ] Show member count and avatars
- [ ] Implement pull-to-refresh
- [ ] Add search/filter functionality
- [ ] Show online status indicators
- [ ] Display unread message counts

### Phase 3: Socket.IO Integration

- [ ] Install socket_io_client package
- [ ] Connect to Socket.IO server with token
- [ ] Implement reconnection logic
- [ ] Listen for `group_created` event
- [ ] Listen for `group_updated` event
- [ ] Listen for `group_member_added` event
- [ ] Listen for `group_member_removed` event
- [ ] Listen for `group_new_message` event
- [ ] Listen for `group_message_deleted` event
- [ ] Listen for `group_message_edited` event
- [ ] Listen for `group_doorbell` event
- [ ] Listen for `group_user_typing` event
- [ ] Listen for `group_reaction_updated` event
- [ ] Listen for `message_status_updated` event
- [ ] Emit `group_typing` when user types
- [ ] Emit `group_message_delivered` on receive
- [ ] Emit `group_messages_viewed` when messages are read

### Phase 4: Messaging

- [ ] Display messages in chronological order
- [ ] Show sender name and avatar
- [ ] Format timestamps (Today, Yesterday, date)
- [ ] Implement message pagination (load more)
- [ ] Send text messages via REST API
- [ ] Send text messages via Socket.IO (alternative)
- [ ] Show message status (sending, sent, delivered, seen)
- [ ] Implement reply functionality
- [ ] Display reply preview
- [ ] Handle system messages differently
- [ ] Auto-scroll to bottom on new message
- [ ] Maintain scroll position when loading history

### Phase 5: File Uploads

- [ ] Implement image picker
- [ ] Implement file picker
- [ ] Show upload progress
- [ ] Compress images before upload
- [ ] Validate file size and type
- [ ] Display image thumbnails
- [ ] Implement image viewer (full screen)
- [ ] Display file attachments with icons
- [ ] Handle download/open file
- [ ] Add caption support

### Phase 6: Voice Messages

- [ ] Request microphone permission
- [ ] Implement audio recording
- [ ] Show recording duration
- [ ] Cancel recording functionality
- [ ] Send voice message via Socket.IO
- [ ] Display voice message waveform
- [ ] Implement audio playback
- [ ] Show playback progress
- [ ] Pause/resume playback

### Phase 7: Reactions

- [ ] Show reaction picker (emoji selector)
- [ ] Add reaction to message
- [ ] Display reactions on messages
- [ ] Show who reacted (on tap)
- [ ] Remove own reaction
- [ ] Animate reaction changes

### Phase 8: Group Management

- [ ] Create new group
- [ ] Add group name and description
- [ ] Select members from contacts
- [ ] Upload group avatar
- [ ] Edit group details (admin only)
- [ ] Add members (admin only)
- [ ] Remove members (admin only)
- [ ] Leave group
- [ ] Show member list
- [ ] Display member roles (admin/member)
- [ ] Mute/unmute group notifications

### Phase 9: Notifications

- [ ] Integrate Firebase Cloud Messaging
- [ ] Register FCM token with server
- [ ] Handle foreground notifications
- [ ] Handle background notifications
- [ ] Show notification with sender name and message
- [ ] Play notification sound
- [ ] Vibrate on notification
- [ ] Navigate to group on notification tap
- [ ] Badge count for unread messages
- [ ] Respect mute settings

### Phase 10: Doorbell Feature

- [ ] Add doorbell button in group chat
- [ ] Send doorbell via REST API
- [ ] Play doorbell sound on receive
- [ ] Show doorbell notification
- [ ] Vibrate device
- [ ] Display doorbell message in chat

### Phase 11: Advanced Features

- [ ] Typing indicators
- [ ] Online/offline status
- [ ] Last seen timestamp
- [ ] Message search within group
- [ ] Pin important messages
- [ ] Delete messages (own messages)
- [ ] Edit messages (own messages)
- [ ] Forward messages
- [ ] Copy message text
- [ ] Share group invite link
- [ ] Export chat history

### Phase 12: Optimization & Polish

- [ ] Implement local database (SQLite/Hive)
- [ ] Cache messages locally
- [ ] Offline message queue
- [ ] Retry failed messages
- [ ] Image caching
- [ ] Lazy loading for large groups
- [ ] Optimize memory usage
- [ ] Add loading states
- [ ] Add error states
- [ ] Add empty states
- [ ] Implement dark mode
- [ ] Add animations and transitions
- [ ] Accessibility support
- [ ] Localization (i18n)

### Phase 13: Testing

- [ ] Unit tests for API calls
- [ ] Unit tests for Socket.IO events
- [ ] Widget tests for UI components
- [ ] Integration tests for user flows
- [ ] Test token expiration handling
- [ ] Test offline functionality
- [ ] Test notification handling
- [ ] Test file upload/download
- [ ] Test with slow network
- [ ] Test with no network
- [ ] Test on different screen sizes
- [ ] Test on Android and iOS

---

## Quick Start Code Examples

### Complete Flutter Group Chat Service

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as IO;

class GroupChatService {
  final String baseUrl;
  final String token;
  late IO.Socket socket;
  
  GroupChatService({required this.baseUrl, required this.token}) {
    _initSocket();
  }
  
  void _initSocket() {
    socket = IO.io(baseUrl, 
      IO.OptionBuilder()
        .setTransports(['websocket'])
        .setExtraHeaders({'Authorization': 'Bearer $token'})
        .enableAutoConnect()
        .build()
    );
    
    socket.onConnect((_) => print('Socket connected'));
    socket.onDisconnect((_) => print('Socket disconnected'));
  }
  
  // Fetch all groups
  Future<List<Group>> fetchGroups() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/mobile/groups'),
      headers: {'Authorization': 'Bearer $token'},
    );
    
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return (data['groups'] as List)
          .map((g) => Group.fromJson(g))
          .toList();
    }
    throw Exception('Failed to load groups');
  }
  
  // Create group
  Future<Group> createGroup({
    required String name,
    String? description,
    required List<int> memberIds,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/mobile/groups'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: json.encode({
        'name': name,
        'description': description,
        'member_ids': memberIds,
      }),
    );
    
    if (response.statusCode == 201) {
      final data = json.decode(response.body);
      return Group.fromJson(data['group']);
    }
    throw Exception('Failed to create group');
  }
  
  // Fetch messages
  Future<MessageResponse> fetchMessages({
    required int groupId,
    int limit = 50,
    int? beforeId,
  }) async {
    var url = '$baseUrl/api/mobile/groups/$groupId/messages?limit=$limit';
    if (beforeId != null) {
      url += '&before_id=$beforeId';
    }
    
    final response = await http.get(
      Uri.parse(url),
      headers: {'Authorization': 'Bearer $token'},
    );
    
    if (response.statusCode == 200) {
      return MessageResponse.fromJson(json.decode(response.body));
    }
    throw Exception('Failed to load messages');
  }
  
  // Send message
  Future<Message> sendMessage({
    required int groupId,
    required String content,
    int? replyToId,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/mobile/groups/$groupId/messages'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: json.encode({
        'content': content,
        'message_type': 'text',
        'reply_to_id': replyToId,
      }),
    );
    
    if (response.statusCode == 201) {
      final data = json.decode(response.body);
      return Message.fromJson(data['data']);
    }
    throw Exception('Failed to send message');
  }
  
  // Upload file
  Future<Message> uploadFile({
    required int groupId,
    required String filePath,
    String? caption,
  }) async {
    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/mobile/groups/$groupId/messages/upload'),
    );
    
    request.headers['Authorization'] = 'Bearer $token';
    request.files.add(await http.MultipartFile.fromPath('file', filePath));
    
    if (caption != null) {
      request.fields['caption'] = caption;
    }
    
    final response = await request.send();
    final responseBody = await response.stream.bytesToString();
    
    if (response.statusCode == 201) {
      final data = json.decode(responseBody);
      return Message.fromJson(data['data']);
    }
    throw Exception('Failed to upload file');
  }
  
  // Ring doorbell
  Future<void> ringDoorbell(int groupId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/mobile/groups/$groupId/doorbell'),
      headers: {'Authorization': 'Bearer $token'},
    );
    
    if (response.statusCode != 201) {
      throw Exception('Failed to ring doorbell');
    }
  }
  
  // Listen for new messages
  void listenForMessages(Function(Message) onMessage) {
    socket.on('group_new_message', (data) {
      onMessage(Message.fromJson(data));
    });
  }
  
  // Listen for group updates
  void listenForGroupUpdates(Function(Group) onUpdate) {
    socket.on('group_created', (data) => onUpdate(Group.fromJson(data)));
    socket.on('group_updated', (data) => onUpdate(Group.fromJson(data)));
  }
  
  // Send typing indicator
  void sendTyping(int groupId) {
    socket.emit('group_typing', {'group_id': groupId});
  }
  
  // Disconnect
  void dispose() {
    socket.dispose();
  }
}
```

### Model Classes

```dart
class Group {
  final int id;
  final String name;
  final String? description;
  final String? avatarUrl;
  final int createdBy;
  final DateTime createdAt;
  final int memberCount;
  final String myRole;
  final bool isMuted;
  final List<GroupMember> members;
  final Message? lastMessage;
  
  Group({
    required this.id,
    required this.name,
    this.description,
    this.avatarUrl,
    required this.createdBy,
    required this.createdAt,
    required this.memberCount,
    required this.myRole,
    required this.isMuted,
    required this.members,
    this.lastMessage,
  });
  
  factory Group.fromJson(Map<String, dynamic> json) {
    return Group(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      avatarUrl: json['avatar_url'],
      createdBy: json['created_by'],
      createdAt: DateTime.parse(json['created_at']),
      memberCount: json['member_count'],
      myRole: json['my_role'] ?? 'member',
      isMuted: json['is_muted'] ?? false,
      members: (json['members'] as List?)
          ?.map((m) => GroupMember.fromJson(m))
          .toList() ?? [],
      lastMessage: json['last_message'] != null
          ? Message.fromJson(json['last_message'])
          : null,
    );
  }
}

class Message {
  final int id;
  final int groupId;
  final int senderId;
  final User? sender;
  final String content;
  final String messageType;
  final DateTime timestamp;
  final bool isDeleted;
  final String? fileUrl;
  final String? fileName;
  final int? replyToId;
  
  Message({
    required this.id,
    required this.groupId,
    required this.senderId,
    this.sender,
    required this.content,
    required this.messageType,
    required this.timestamp,
    required this.isDeleted,
    this.fileUrl,
    this.fileName,
    this.replyToId,
  });
  
  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] ?? json['message_id'],
      groupId: json['group_id'],
      senderId: json['sender_id'],
      sender: json['sender'] != null ? User.fromJson(json['sender']) : null,
      content: json['content'],
      messageType: json['message_type'],
      timestamp: DateTime.parse(json['timestamp']),
      isDeleted: json['is_deleted'] ?? false,
      fileUrl: json['file_url'],
      fileName: json['file_name'],
      replyToId: json['reply_to_id'],
    );
  }
}
```

---

## Summary

This guide covers the complete mobile API for group chat functionality. The key points to remember:

1. **Authentication**: Use JWT tokens with `Authorization: Bearer <token>` header
2. **REST API**: Use `/api/mobile/groups/*` endpoints for CRUD operations
3. **Socket.IO**: Connect for real-time updates and listen for events
4. **Sync Strategy**: Combine REST API (initial load) + Socket.IO (real-time) + periodic polling (backup)
5. **Error Handling**: Implement token refresh, retry logic, and offline support
6. **Notifications**: Register FCM token and handle push notifications

For the specific issue of mobile apps not seeing admin-created groups, ensure:
- Socket.IO is connected and listening for `group_created` event
- Implement pull-to-refresh to manually fetch groups
- Verify token is valid and user is added as a member in the database
- Check server logs for any errors during group creation

