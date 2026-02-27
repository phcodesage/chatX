# Group Chat Mobile API Documentation

Complete REST API documentation for Flutter mobile app integration with group chat features.

## Authentication

All endpoints require Bearer token authentication:
```
Authorization: Bearer <your_jwt_token>
```

## Base URL
```
https://your-domain.com/api
```

---

## Group Management

### 1. List Groups
Get all groups the current user belongs to.

**Endpoint:** `GET /groups`

**Response:**
```json
{
  "groups": [
    {
      "id": 1,
      "name": "Team Chat",
      "description": "Our team discussion",
      "created_by": 1,
      "avatar_url": "https://...",
      "member_count": 5,
      "is_active": true,
      "created_at": "2024-01-01T00:00:00Z",
      "my_role": "admin",
      "is_muted": false,
      "last_message": {
        "id": 123,
        "content": "Hello everyone",
        "sender_id": 2,
        "sender": {...},
        "timestamp_ms": 1234567890000
      }
    }
  ]
}
```

---

### 2. Create Group
Create a new group chat.

**Endpoint:** `POST /groups`

**Request Body:**
```json
{
  "name": "Team Chat",
  "description": "Our team discussion",
  "member_ids": [2, 3, 4]
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "id": 1,
    "name": "Team Chat",
    "description": "Our team discussion",
    "created_by": 1,
    "member_count": 4,
    "created_at": "2024-01-01T00:00:00Z"
  }
}
```

---

### 3. Get Group Details
Get detailed information about a specific group.

**Endpoint:** `GET /groups/{group_id}`

**Response:**
```json
{
  "group": {
    "id": 1,
    "name": "Team Chat",
    "description": "Our team discussion",
    "created_by": 1,
    "avatar_url": "https://...",
    "member_count": 5,
    "is_active": true,
    "created_at": "2024-01-01T00:00:00Z",
    "members": [
      {
        "user_id": 1,
        "role": "admin",
        "joined_at": "2024-01-01T00:00:00Z",
        "is_muted": false,
        "user": {
          "id": 1,
          "username": "john",
          "first_name": "John",
          "last_name": "Doe",
          "email": "john@example.com"
        }
      }
    ]
  }
}
```

---

### 4. Edit Group
Update group name, description, or avatar (admin only).

**Endpoint:** `PUT /groups/{group_id}` or `PATCH /groups/{group_id}`

**Request Body:**
```json
{
  "name": "Updated Team Chat",
  "description": "New description",
  "avatar_url": "https://..."
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "id": 1,
    "name": "Updated Team Chat",
    "description": "New description",
    "avatar_url": "https://..."
  }
}
```

---

### 5. Add Members
Add new members to the group.

**Endpoint:** `POST /groups/{group_id}/members`

**Request Body:**
```json
{
  "user_ids": [5, 6, 7]
}
```

**Response:**
```json
{
  "success": true,
  "added_count": 3
}
```

---

### 6. Remove Member
Remove a member from the group (admin only) or leave group (if removing self).

**Endpoint:** `DELETE /groups/{group_id}/members/{user_id}`

**Response:**
```json
{
  "success": true,
  "message": "Member removed successfully"
}
```

---

### 7. Leave Group
Leave a group (shortcut for removing yourself).

**Endpoint:** `POST /groups/{group_id}/leave`

**Response:**
```json
{
  "success": true,
  "message": "Left group successfully"
}
```

---

## Messaging

### 8. Get Messages
Get messages for a group with pagination.

**Endpoint:** `GET /groups/{group_id}/messages?limit=50&before_id=123`

**Query Parameters:**
- `limit` (optional): Number of messages to fetch (default: 50)
- `before_id` (optional): Get messages before this message ID (for pagination)

**Response:**
```json
{
  "messages": [
    {
      "id": 123,
      "message_id": 123,
      "group_id": 1,
      "sender_id": 2,
      "sender": {
        "id": 2,
        "username": "jane",
        "first_name": "Jane",
        "full_name": "Jane Smith"
      },
      "content": "Hello everyone!",
      "message_type": "text",
      "timestamp": "2024-01-01T12:00:00Z",
      "timestamp_ms": 1234567890000,
      "is_deleted": false,
      "file_url": null,
      "file_name": null,
      "file_size": null,
      "file_type": null,
      "reply_to_id": null,
      "reply_preview": null
    }
  ]
}
```

**Message Types:**
- `text`: Regular text message
- `image`: Image file
- `video`: Video file
- `voice`: Audio/voice message
- `file`: Other file types
- `system`: System message (member joined, etc.)
- `doorbell`: Notification/doorbell message

---

### 9. Send Message
Send a text message to the group.

**Endpoint:** `POST /groups/{group_id}/messages`

**Request Body:**
```json
{
  "content": "Hello everyone!",
  "message_type": "text",
  "reply_to_id": 122
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "id": 123,
    "group_id": 1,
    "sender_id": 1,
    "sender": {...},
    "content": "Hello everyone!",
    "message_type": "text",
    "timestamp_ms": 1234567890000
  }
}
```

---

### 10. Upload File
Upload a file (image, video, audio, document, etc.) to the group.

**Endpoint:** `POST /groups/{group_id}/messages/upload`

**Content-Type:** `multipart/form-data`

**Form Fields:**
- `file`: The file to upload (required)
- `caption`: Optional caption text

**Supported File Types:**
- Images: png, jpg, jpeg, gif, bmp, svg, webp, etc.
- Videos: mp4, mov, avi, mkv, webm, etc.
- Audio: mp3, wav, ogg, aac, m4a, flac, etc.
- Documents: pdf, doc, docx, txt, xls, xlsx, ppt, pptx, etc.
- Guitar files: gp, gp3, gp4, gp5, gpx, gp7, gtp, ptb, mscz, etc.
- Archives: zip, rar, 7z, tar, gz, etc.
- And many more (see `/api/allowed-extensions` for complete list)

**Response:**
```json
{
  "success": true,
  "data": {
    "id": 124,
    "group_id": 1,
    "sender_id": 1,
    "content": "[image: photo.jpg] - Beautiful sunset",
    "message_type": "image",
    "file_url": "https://.../uploads/messages/abc123.jpg",
    "file_name": "photo.jpg",
    "file_size": 1024000,
    "file_type": "image/jpeg"
  },
  "file_url": "https://.../uploads/messages/abc123.jpg",
  "file_id": "abc123"
}
```

---

### 11. Delete Message
Delete a message (sender or admin only).

**Endpoint:** `DELETE /groups/{group_id}/messages/{message_id}`

**Response:**
```json
{
  "success": true,
  "message": "Message deleted"
}
```

---

### 12. Edit Message
Edit a message (sender only).

**Endpoint:** `PUT /groups/{group_id}/messages/{message_id}` or `PATCH /groups/{group_id}/messages/{message_id}`

**Request Body:**
```json
{
  "content": "Updated message content"
}
```

**Response:**
```json
{
  "success": true,
  "message": "Message edited",
  "data": {
    "id": 123,
    "content": "Updated message content",
    "timestamp_ms": 1234567890000
  }
}
```

---

## Message Status Tracking

### 13. Mark Message as Delivered
Notify the sender that you received their message.

**Endpoint:** `POST /groups/{group_id}/messages/{message_id}/delivered`

**Response:**
```json
{
  "success": true,
  "status": "delivered"
}
```

**When to call:** When your app receives a new message via Socket.IO or when loading messages.

---

### 14. Mark Messages as Viewed
Notify senders that you've viewed their messages.

**Endpoint:** `POST /groups/{group_id}/messages/viewed`

**Request Body:**
```json
{
  "message_ids": [123, 124, 125],
  "sender_id": 2
}
```

**Response:**
```json
{
  "success": true,
  "marked_count": 3
}
```

**When to call:** When messages become visible on screen (user is viewing the chat).

---

## Reactions

### 15. Add Reaction
Add or update your reaction to a message.

**Endpoint:** `POST /groups/{group_id}/messages/{message_id}/reactions`

**Request Body:**
```json
{
  "emoji": "👍"
}
```

**Response:**
```json
{
  "success": true,
  "reactions": {
    "👍": ["John Doe", "Jane Smith"],
    "❤️": ["Alice Johnson"]
  }
}
```

**Common Emojis:** 👍, ❤️, 😂, 😢, 😡, 🎉, 🔥, 👏, 🙏, etc.

---

### 16. Remove Reaction
Remove your reaction from a message.

**Endpoint:** `DELETE /groups/{group_id}/messages/{message_id}/reactions`

**Request Body:**
```json
{
  "emoji": "👍"
}
```

**Response:**
```json
{
  "success": true,
  "reactions": {
    "❤️": ["Alice Johnson"]
  }
}
```

---

## Notifications

### 17. Ring Doorbell
Send a notification/doorbell to all group members.

**Endpoint:** `POST /groups/{group_id}/doorbell`

**Response:**
```json
{
  "success": true,
  "message_id": 126,
  "data": {
    "message_id": 126,
    "group_id": 1,
    "group_name": "Team Chat",
    "sender_id": 1,
    "sender_name": "John Doe",
    "timestamp_ms": 1234567890000
  }
}
```

**Note:** This creates a doorbell message in the database with status tracking (sent/delivered/seen).

---

## Utility Endpoints

### 18. Get Allowed File Extensions
Get the list of allowed file extensions for uploads.

**Endpoint:** `GET /api/allowed-extensions`

**Response:**
```json
{
  "extensions": ["png", "jpg", "pdf", "mp4", "mp3", "gp5", "zip", ...],
  "count": 150
}
```

---

## Socket.IO Events (Real-time)

For real-time updates, connect to Socket.IO with your JWT token:

```dart
socket = io('https://your-domain.com', <String, dynamic>{
  'transports': ['websocket'],
  'auth': {'token': 'your_jwt_token'}
});
```

### Events to Listen For:

1. **group_new_message** - New message from another member
   ```json
   {
     "message_id": 123,
     "group_id": 1,
     "sender_id": 2,
     "content": "Hello!",
     "message_type": "text",
     "timestamp_ms": 1234567890000
   }
   ```

2. **group_message_sent** - Confirmation of your own sent message
   ```json
   {
     "message_id": 123,
     "group_id": 1,
     "sender_id": 1,
     "content": "Hello!",
     "timestamp_ms": 1234567890000
   }
   ```

3. **group_file_message** - File message received
   ```json
   {
     "message_id": 124,
     "group_id": 1,
     "file_url": "https://...",
     "file_name": "photo.jpg",
     "file_type": "image/jpeg"
   }
   ```

4. **group_doorbell** - Doorbell notification received
   ```json
   {
     "message_id": 126,
     "group_id": 1,
     "sender_id": 2,
     "sender_name": "Jane Smith",
     "timestamp_ms": 1234567890000
   }
   ```

5. **message_status_updated** - Message status changed (delivered/seen)
   ```json
   {
     "message_id": 123,
     "status": "delivered",
     "delivered_by": 3,
     "delivered_by_name": "Alice"
   }
   ```

6. **group_message_deleted** - Message was deleted
   ```json
   {
     "message_id": 123,
     "group_id": 1
   }
   ```

7. **group_message_edited** - Message was edited
   ```json
   {
     "message_id": 123,
     "group_id": 1,
     "content": "Updated content"
   }
   ```

8. **group_reaction_updated** - Reaction added/updated
   ```json
   {
     "message_id": 123,
     "group_id": 1,
     "user_id": 2,
     "user_name": "Jane",
     "emoji": "👍",
     "reactions": {"👍": ["Jane", "John"]}
   }
   ```

9. **group_reaction_cleared** - Reaction removed
   ```json
   {
     "message_id": 123,
     "group_id": 1,
     "user_id": 2,
     "emoji": "👍",
     "reactions": {"❤️": ["Alice"]}
   }
   ```

10. **group_member_left** - Member left the group
    ```json
    {
      "group_id": 1,
      "user_id": 3,
      "user_name": "Bob"
    }
    ```

### Events to Emit:

When you receive messages via Socket.IO, emit these events:

1. **group_message_delivered** - Acknowledge message delivery
   ```json
   {
     "message_id": 123,
     "group_id": 1
   }
   ```

2. **group_messages_viewed** - Mark messages as seen
   ```json
   {
     "group_id": 1,
     "message_ids": [123, 124],
     "sender_id": 2
   }
   ```

---

## Error Responses

All endpoints return standard error responses:

```json
{
  "error": "Error message",
  "details": "Detailed error information"
}
```

**Common HTTP Status Codes:**
- `200` - Success
- `201` - Created
- `400` - Bad Request (invalid input)
- `403` - Forbidden (not authorized)
- `404` - Not Found
- `500` - Internal Server Error

---

## Implementation Notes for Flutter

### 1. Message Status Flow
```
Send Message → Optimistic UI (sending)
  ↓
Receive group_message_sent → Update to "sent" ✓
  ↓
Other users receive → They emit group_message_delivered
  ↓
Receive message_status_updated (delivered) → Update to "delivered" ✓✓
  ↓
Other users view → They emit group_messages_viewed
  ↓
Receive message_status_updated (seen) → Update to "seen" ✓✓ (green)
```

### 2. File Upload Flow
```
1. Select file
2. Validate extension (call /api/allowed-extensions)
3. Upload via POST /groups/{id}/messages/upload
4. Receive response with file_url and message_id
5. Display file message in chat
```

### 3. Real-time Updates
- Connect to Socket.IO on app start
- Listen for all group events
- Emit delivery/viewed events when appropriate
- Handle reconnection gracefully

### 4. Offline Support
- Queue messages locally when offline
- Send via REST API when connection restored
- Sync message status on reconnect

---

## Database Schema Changes Required

To support the new features, run the migration script:

```bash
# Run the migration
python scripts/migrate_message_reactions_for_groups.py

# Or verify without making changes
python scripts/migrate_message_reactions_for_groups.py --verify

# Or rollback if needed (requires SQLite 3.35.0+)
python scripts/migrate_message_reactions_for_groups.py --rollback
```

The migration script will:
1. Add `is_group_message` column (BOOLEAN, default FALSE)
2. Add `emoji` column (VARCHAR(32), nullable)
3. Migrate existing `reaction` data to `emoji` field
4. Create index on `is_group_message` for performance
5. Note: The unique constraint update will be handled by SQLAlchemy automatically

**Manual SQL (if needed):**
```sql
-- Add columns
ALTER TABLE message_reaction ADD COLUMN is_group_message BOOLEAN DEFAULT 0 NOT NULL;
ALTER TABLE message_reaction ADD COLUMN emoji VARCHAR(32);

-- Migrate existing data
UPDATE message_reaction SET emoji = reaction WHERE emoji IS NULL AND reaction IS NOT NULL;

-- Create index
CREATE INDEX idx_message_reaction_group ON message_reaction(is_group_message);
```

---

## Testing Checklist

- [ ] Create group
- [ ] Add members
- [ ] Send text message
- [ ] Upload file (image, video, audio, document, guitar file)
- [ ] Reply to message
- [ ] Edit message
- [ ] Delete message
- [ ] Add reaction
- [ ] Remove reaction
- [ ] Ring doorbell
- [ ] Mark messages as delivered
- [ ] Mark messages as viewed
- [ ] Leave group
- [ ] Remove member (admin)
- [ ] Real-time message updates via Socket.IO
- [ ] Message status updates (sent/delivered/seen)
- [ ] Offline message queueing

---

## Support

For issues or questions, contact the backend team or refer to the main API documentation.
