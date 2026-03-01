# Group Removal Real-Time Fix

## Issue Description
Group removal from web interface was not working in real-time on mobile app. Users had to manually refresh to see that they were removed from groups.

## Root Cause Analysis

### 1. Event Data Structure Mismatch
**Problem**: The backend emits different data structures for different group member removal scenarios.

**Backend Event Structures**:

1. **`group_member_left`** (simple structure):
```javascript
socket.to(`group_${groupId}`).emit('group_member_left', {group_id, user_id});
```

2. **`group_member_removed`** (complex structure):
```javascript
socket.to(`group_${groupId}`).emit('group_member_removed', {
  group: {
    id: 6,
    name: "test", 
    members: [...], // Updated member list without removed user
    member_count: 1
  }
});
```

**Mobile App Original Expectation**:
```dart
final removedUserId = data['user_id'] as int?; // Only worked for group_member_left
```

**Issue**: The `group_member_removed` event doesn't have a direct `user_id` field - it contains the updated group object with the remaining members.

### 2. Missing Alternative Event Handler
The backend might emit either `group_member_left` or `group_member_removed` depending on the context, but the socket service only handled one variant.

## Solution Implemented

### 1. Dual Data Structure Support
Updated listeners to handle both event data structures:

```dart
// Handle different event data structures
if (data.containsKey('group_id') && data.containsKey('user_id')) {
  // Structure: {group_id: 6, user_id: 16} - from group_member_left
  groupId = data['group_id'] as int?;
  removedUserId = data['user_id'] as int?;
} else if (data.containsKey('group')) {
  // Structure: {group: {...}} - from group_member_removed
  final groupData = data['group'] as Map<String, dynamic>?;
  if (groupData != null) {
    groupId = groupData['id'] as int?;
    // Check if current user is still in the members list
    final members = groupData['members'] as List?;
    if (members != null) {
      final isCurrentUserInGroup = members.any((member) {
        final memberData = member as Map<String, dynamic>;
        final memberUserId = memberData['user_id'] as int?;
        return memberUserId == userId;
      });
      
      if (!isCurrentUserInGroup) {
        // Current user was removed - remove group from list
        // Show notification and update UI
      }
    }
  }
}
```

### 2. Smart Member List Comparison
For `group_member_removed` events, the app now:
1. **Extracts the updated member list** from the group object
2. **Checks if current user is still in the list**
3. **If not found**: User was removed → remove group from UI
4. **If found**: Another member was removed → reload group data

### 2. Added Alternative Event Handler
Added support for both event names in socket service:

```dart
// Primary event (from backend implementation)
_socket!.on('group_member_left', (data) {
  debugPrint('👋 [SOCKET] Group member left event received: $data');
  _broadcast(_groupMemberLeftListeners, data as Map<String, dynamic>);
});

// Alternative event (for compatibility)
_socket!.on('group_member_removed', (data) {
  debugPrint('👋 [SOCKET] Group member removed event received: $data');
  _broadcast(_groupMemberLeftListeners, data as Map<String, dynamic>);
});
```

### 3. Enhanced Debug Logging
Added comprehensive logging to troubleshoot future issues:

**Socket Service Level**:
```dart
debugPrint('👋 [SOCKET] Group member left event received: $data');
debugPrint('👋 [SOCKET] Broadcasting to ${_groupMemberLeftListeners.length} listeners');
debugPrint('👋 [SOCKET] Listener keys: ${_groupMemberLeftListeners.keys}');
```

**Lobby Screen Level**:
```dart
debugPrint('👋 Event data type: ${data.runtimeType}');
debugPrint('👋 Parsed groupId: $groupId, removedUserId: $removedUserId');
debugPrint('👋 Current userId: $userId, comparing with removedUserId: $removedUserId');
debugPrint('👋 Current user was removed from group $groupId, removing from list');
debugPrint('👋 Groups count: $initialCount → $finalCount');
```

**Groups List Screen Level**:
```dart
debugPrint('👋 [GROUPS LIST] Group member left event received: $data');
debugPrint('👋 [GROUPS LIST] Parsed groupId: $groupId, userId: $userId, currentUserId: $_currentUserId');
debugPrint('👋 [GROUPS LIST] Current user was removed from group $groupId');
debugPrint('👋 [GROUPS LIST] Groups count: $initialCount → $finalCount');
```

## Expected Behavior After Fix

### Test Scenario: User Removed from Group
1. **Admin removes mobile user** from group via web interface
2. **Backend emits** `group_member_left` event with `{group_id: 123, user_id: 456}`
3. **Socket service receives** event and broadcasts to registered listeners
4. **Lobby screen listener** receives event, compares `user_id` with current user ID
5. **If match**: Group is immediately removed from `_groups` list
6. **UI updates** instantly without refresh
7. **Notification shown**: "You were removed from a group"
8. **Groups list screen** also removes group if currently viewing groups

### Debug Log Flow (Successful Removal)
```
👋 [SOCKET] Group member removed event received: {group: {id: 6, members: [...]}}
👋 [SOCKET] Broadcasting to 2 listeners
👋 Event data type: _Map<String, dynamic>
👋 Using group_member_removed structure
👋 Current user (16) in group: false
👋 Current user (16) not found in member list, was removed from group 6
👋 Groups count: 1 → 0
👋 [GROUPS LIST] Group member left event received: {group: {id: 6, members: [...]}}
👋 [GROUPS LIST] Using group_member_removed structure
👋 [GROUPS LIST] Current user was removed from group 6
👋 [GROUPS LIST] Groups count: 1 → 0
```

## Files Modified
- `lib/services/socket_service.dart` - Added alternative event handler and debug logging
- `lib/screens/lobby_screen.dart` - Fixed field name mapping and added debug logging  
- `lib/screens/groups_list_screen.dart` - Fixed field name mapping and added debug logging

## Testing Checklist
- [ ] User removed from group via web → group disappears immediately on mobile
- [ ] User removed from group via mobile → group disappears immediately  
- [ ] Multiple users removed simultaneously → all see updates correctly
- [ ] Debug logs show correct event reception and processing
- [ ] Notification appears when user is removed
- [ ] Groups list screen also updates when viewing groups
- [ ] No duplicate removal attempts or errors

## Troubleshooting
If group removal still doesn't work in real-time:

1. **Check debug logs** for event reception:
   ```bash
   grep "Group member left event received" logs.txt
   ```

2. **Verify event data structure**:
   ```bash
   grep "Parsed groupId.*removedUserId" logs.txt
   ```

3. **Check user ID comparison**:
   ```bash
   grep "Current userId.*comparing with removedUserId" logs.txt
   ```

4. **Verify group removal**:
   ```bash
   grep "Groups count.*→" logs.txt
   ```

5. **Check socket connection**:
   ```bash
   grep "Socket connected" logs.txt
   ```

## Notes
- Fix maintains backward compatibility with both event names
- Enhanced logging helps with future debugging
- No breaking changes to existing functionality
- Performance impact is minimal (just additional logging)