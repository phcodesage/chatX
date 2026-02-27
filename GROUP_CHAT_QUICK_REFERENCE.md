# Group Chat Quick Reference Card

## 📱 Mobile App - Quick Access

### Key Files
```
lib/
├── models/group.dart              # Group, GroupMessage, GroupMember models
├── services/group_service.dart    # All API calls
├── screens/
│   ├── groups_list_screen.dart    # Groups list (WhatsApp-like)
│   ├── create_group_screen.dart   # Create new group
│   ├── group_chat_screen.dart     # Group chat interface
│   └── lobby_screen.dart          # Main screen (has groups button)
└── config/api_config.dart         # API endpoints configuration
```

### Quick Commands
```bash
# Run app
flutter run

# Build APK
flutter build apk --release

# Check for errors
flutter analyze

# Format code
flutter format lib/

# Clean and rebuild
flutter clean && flutter pub get && flutter run
```

---

## 🔌 API Endpoints Cheat Sheet

### Base URL
```
https://m.flask-meet.site/api/groups
```

### Groups
```http
GET    /api/groups                    # List all groups
POST   /api/groups                    # Create group
GET    /api/groups/{id}               # Get details
PUT    /api/groups/{id}               # Edit group
POST   /api/groups/{id}/leave         # Leave group
```

### Members
```http
POST   /api/groups/{id}/members              # Add members
DELETE /api/groups/{id}/members/{user_id}    # Remove member
```

### Messages
```http
GET    /api/groups/{id}/messages                      # Get messages
POST   /api/groups/{id}/messages                      # Send message
POST   /api/groups/{id}/messages/upload               # Upload file
PUT    /api/groups/{id}/messages/{msg_id}             # Edit message
DELETE /api/groups/{id}/messages/{msg_id}             # Delete message
```

### Status & Reactions
```http
POST   /api/groups/{id}/messages/{msg_id}/delivered   # Mark delivered
POST   /api/groups/{id}/messages/viewed               # Mark viewed
POST   /api/groups/{id}/messages/{msg_id}/reactions   # Add reaction
DELETE /api/groups/{id}/messages/{msg_id}/reactions   # Remove reaction
```

### Notifications
```http
POST   /api/groups/{id}/doorbell    # Ring doorbell
```

---

## 🔄 Socket.IO Events

### Listen For (Backend → Mobile)
```javascript
'group_new_message'          // New message from another member
'group_message_sent'         // Your message sent confirmation
'group_file_message'         // File message received
'group_doorbell'             // Doorbell notification
'group_message_deleted'      // Message was deleted
'group_message_edited'       // Message was edited
'group_reaction_updated'     // Reaction added/updated
'group_reaction_cleared'     // Reaction removed
'group_member_left'          // Member left the group
'message_status_updated'     // Delivery/read status changed
```

### Emit (Mobile → Backend)
```javascript
'join_group_chat'            // Join group room
'leave_group_chat'           // Leave group room
'group_message_delivered'    // Acknowledge delivery
'group_messages_viewed'      // Mark messages as seen
```

---

## 💾 Data Models

### Group
```dart
{
  id: int,
  name: String,
  description: String?,
  created_by: int,
  avatar_url: String?,
  member_count: int,
  is_active: bool,
  created_at: String,
  my_role: String,  // 'admin' or 'member'
  is_muted: bool,
  last_message: GroupMessage?
}
```

### GroupMessage
```dart
{
  id: int,
  message_id: int,
  group_id: int,
  sender_id: int,
  sender: GroupMessageSender?,
  content: String,
  message_type: String,  // 'text', 'image', 'video', 'file', 'voice', 'doorbell'
  timestamp: String,
  timestamp_ms: int,
  is_deleted: bool,
  file_url: String?,
  file_name: String?,
  file_size: int?,
  file_type: String?,
  reply_to_id: int?,
  reply_preview: String?,
  reactions: Map<String, dynamic>
}
```

### GroupMember
```dart
{
  user_id: int,
  role: String,  // 'admin' or 'member'
  joined_at: String,
  is_muted: bool,
  user: GroupMemberUser
}
```

---

## 🎨 UI Components

### Colors
```dart
Background:     Color(0xFF0F172A)  // Dark blue-gray
Card:           Color(0xFF1E293B)  // Lighter blue-gray
Input:          Color(0xFF334155)  // Medium gray
Primary:        Color(0xFF8B5CF6)  // Purple
Accent:         Color(0xFF00D9FF)  // Cyan
```

### Common Widgets
```dart
// Loading shimmer
Shimmer.fromColors(
  baseColor: Color(0xFF1E293B),
  highlightColor: Color(0xFF334155),
  child: Container(...)
)

// Group avatar
CircleAvatar(
  radius: 28,
  backgroundColor: Color(0xFF8B5CF6),
  child: Text(initials)
)

// Message bubble
Container(
  decoration: BoxDecoration(
    color: isSentByMe ? Color(0xFF8B5CF6) : Color(0xFF1E293B),
    borderRadius: BorderRadius.circular(12)
  )
)
```

---

## 🔧 Common Code Snippets

### Call API
```dart
final groups = await GroupService.getGroups();
```

### Send Message
```dart
await GroupService.sendMessage(
  groupId: groupId,
  content: 'Hello!',
  messageType: 'text',
);
```

### Upload File
```dart
await GroupService.uploadFile(
  groupId: groupId,
  file: File(path),
  caption: 'Check this out',
);
```

### Add Reaction
```dart
await GroupService.addReaction(
  groupId: groupId,
  messageId: messageId,
  emoji: '👍',
);
```

### Listen to Socket Event
```dart
_socketService.addListener('groupNewMessage', 'my_key', (data) {
  final message = GroupMessage.fromJson(data);
  setState(() => _messages.add(message));
});
```

### Remove Listener
```dart
_socketService.removeListener('groupNewMessage', 'my_key');
```

---

## 🐛 Debug Commands

### Check Socket Connection
```dart
print('Socket connected: ${_socketService.isConnected}');
print('Socket ID: ${_socketService.socket?.id}');
```

### Log API Response
```dart
debugPrint('API Response: ${response.body}');
```

### Check Current User
```dart
final userId = await StorageService.getUserId();
print('Current user ID: $userId');
```

---

## ⚡ Performance Tips

1. **Pagination**: Load 50 messages at a time
2. **Image Caching**: Use `CachedNetworkImage` for avatars
3. **Lazy Loading**: Only render visible messages
4. **Debounce**: Throttle typing indicators
5. **Optimize Builds**: Use `const` constructors

---

## 🔐 Security Notes

- All endpoints require JWT authentication
- Check membership before showing group data
- Validate file types before upload
- Sanitize user input
- Rate limit API calls

---

## 📊 Status Indicators

```
✓     = Sent (gray)
✓✓    = Delivered (gray)
✓✓    = Seen (green)
```

---

## 🎯 Feature Flags

```dart
// In group_service.dart
static const bool enableReactions = true;
static const bool enableFileUpload = true;
static const bool enableVoiceMessages = true;
static const int maxFileSize = 50 * 1024 * 1024; // 50MB
```

---

## 📞 Support

- **API Docs**: `GROUP_CHAT_MOBILE_API.md`
- **Implementation**: `GROUP_CHAT_IMPLEMENTATION_SUMMARY.md`
- **Backend Guide**: `BACKEND_GROUP_CHAT_CHECKLIST.md`
- **Testing**: `GROUP_CHAT_TESTING_GUIDE.md`

---

## 🚀 Deployment Checklist

- [ ] Update `baseUrl` in `api_config.dart`
- [ ] Test all endpoints
- [ ] Verify Socket.IO connection
- [ ] Test on real devices
- [ ] Check push notifications
- [ ] Build release APK
- [ ] Test release build
- [ ] Upload to Play Store

---

**Last Updated**: 2026-02-27
**Version**: 1.0.5
**Status**: ✅ Mobile Complete | ⚠️ Backend Pending
