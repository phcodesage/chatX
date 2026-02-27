# Groups Visibility Debugging - Changes Made

## Issue
Mobile app (logged in as admin) not seeing groups created from web interface.

## Current Backend
**Base URL**: `https://www.flask-call-app.site`

## Root Causes Identified

### 1. Wrong Base URL (FIXED)
- **Problem**: `baseUrl` was pointing to the wrong server
- **Solution**: Set to `https://www.flask-call-app.site` in `lib/config/api_config.dart`
- **Impact**: All API calls (including groups) now point to the correct backend

### 2. Missing Socket.IO Event Listeners (FIXED)
- **Problem**: No listeners for `group_created`, `group_updated`, `group_member_removed` events
- **Solution**: Added Socket.IO event listeners in `lib/screens/lobby_screen.dart`
- **Impact**: Groups created from web weren't appearing in real-time on mobile

### 3. Insufficient Debugging (FIXED)
- **Problem**: Not enough logging to diagnose API issues
- **Solution**: Enhanced logging in `lib/services/group_service.dart`
- **Impact**: Can now see full API responses and diagnose issues faster

## Changes Made

### 1. `lib/config/api_config.dart`
```dart
// Current backend:
static const String baseUrl = 'https://www.flask-call-app.site';
```

### 2. `lib/services/group_service.dart`
Added enhanced debugging in `getGroups()` method:
- Log full URL being called
- Log token length (for verification)
- Log full response body
- Log first group details when groups are loaded

### 3. `lib/screens/lobby_screen.dart`
Added Socket.IO event listeners in `_setupRealtimeListeners()`:

#### `group_created` Event
- Adds new group to the top of the list
- Shows green snackbar notification
- Refreshes filtered lists

#### `group_updated` Event
- Updates existing group in the list
- Refreshes filtered lists

#### `group_member_removed` Event
- If current user was removed: removes group from list
- If another member was removed: reloads lobby data
- Shows orange snackbar when user is removed

## Testing Instructions

### Step 1: Hot Restart the App
**CRITICAL**: You must hot restart (not hot reload) for the baseUrl change to take effect.

```bash
# In your terminal where Flutter is running, press:
R  # Capital R for hot restart

# Or stop and restart:
Ctrl+C
flutter run
```

### Step 2: Check Console Logs
After restart, look for these log messages:

#### Expected Success Logs:
```
🔍 Fetching groups from: https://www.flask-call-app.site/api/mobile/groups
🔑 Token length: 200+ (should be a long JWT token)
📡 Groups API response status: 200
📡 Groups API response body: {"groups":[...]}
✅ Loaded X groups
📋 First group: {id: 1, name: "...", ...}
```

#### If You See These - There's Still a Problem:
```
❌ Failed to load groups: 404 - <!doctype html>...
❌ Get groups error: TimeoutException...
❌ Failed to load groups: 401 - {"error":"Invalid token"}
```

### Step 3: Test Group Visibility

#### Test A: Existing Groups
1. Open the app (should be on lobby screen)
2. Look at the top of the user list
3. You should see "GROUPS (X)" section header
4. Below it, you should see all groups you're a member of

#### Test B: Real-time Group Creation
1. Keep mobile app open on lobby screen
2. Open web interface in browser
3. Create a new group as admin
4. Mobile app should:
   - Show green snackbar: "New group: [name]"
   - Group appears at top of GROUPS section
   - No need to refresh

#### Test C: Pull to Refresh
1. Pull down on the lobby screen
2. Groups should reload
3. Check console for the fetch logs

### Step 4: Verify Socket.IO Connection
Look for these logs on app start:
```
✅ Socket connected - ID: [socket_id]
Socket exists: true
Socket connected: true
```

If you see:
```
Socket connected: false
❌ Socket disconnected
⚠️ Connection error: timeout
```
Then Socket.IO is not connecting, which means real-time updates won't work.

## Troubleshooting

### Issue: Still No Groups Visible

#### Check 1: Verify Groups Exist in Database
Ask backend developer to run:
```sql
SELECT gc.id, gc.name, gm.user_id, u.username
FROM group_chat gc
JOIN group_member gm ON gc.id = gm.group_id
JOIN user u ON gm.user_id = u.id
WHERE gm.is_active = 1
ORDER BY gc.id;
```

Look for your user_id in the results.

#### Check 2: Test API Directly
```bash
# Get your token from app logs (look for "Token length: XXX")
# Or login via API to get fresh token

curl -H "Authorization: Bearer YOUR_TOKEN_HERE" \
  https://www.flask-call-app.site/api/mobile/groups
```

Expected response:
```json
{
  "groups": [
    {
      "id": 1,
      "name": "Test Group",
      "member_count": 3,
      ...
    }
  ]
}
```

#### Check 3: Verify Token is Valid
```bash
# Decode JWT token (paste your token)
echo "YOUR_TOKEN" | cut -d'.' -f2 | base64 -d | python -m json.tool
```

Check:
- `exp` (expiration): Should be in the future
- `sub` (user_id): Should match your user ID

#### Check 4: Check Server Logs
Ask backend developer to check:
```bash
tail -f logs/calls.log | grep -E "GROUP|/api/mobile/groups"
```

Look for:
- 200 responses (success)
- 401 responses (auth failure)
- 404 responses (endpoint not found)

### Issue: Groups Appear But Not in Real-time

This means Socket.IO is not connected or not receiving events.

#### Solution A: Check Socket Connection
Look for these logs:
```
✅ Socket connected - ID: [socket_id]
```

If not connected, check:
1. Is `https://www.flask-call-app.site` reachable?
2. Does the server support WebSocket connections?
3. Is there a firewall blocking WebSocket?

#### Solution B: Verify Server Emits Events
Ask backend developer to check `app/routes/group_chat.py`:
```python
# After creating group, should emit:
socketio.emit('group_created', group_data, room=f'user_{user_id}')
```

#### Solution C: Use Pull-to-Refresh
If real-time doesn't work, you can manually refresh:
1. Pull down on lobby screen
2. Groups will reload via REST API

## Expected Behavior After Fixes

### On App Start
1. App connects to Socket.IO
2. Fetches groups via REST API
3. Displays groups at top of lobby screen
4. Shows "GROUPS (X)" with count

### When Group Created on Web
1. Server emits `group_created` event
2. Mobile app receives event via Socket.IO
3. Group appears immediately at top
4. Green snackbar shows notification
5. No manual refresh needed

### When Group Updated on Web
1. Server emits `group_updated` event
2. Mobile app updates group in list
3. Changes reflect immediately

### When User Removed from Group
1. Server emits `group_member_removed` event
2. If current user: group disappears from list
3. Orange snackbar shows notification

## Next Steps

1. **Hot restart the app** (press R in terminal)
2. **Check console logs** for the new debug output
3. **Verify groups appear** in the GROUPS section
4. **Test real-time updates** by creating a group on web
5. **Report back** with console logs if still not working

## Files Modified

- `lib/config/api_config.dart` - Fixed baseUrl
- `lib/services/group_service.dart` - Enhanced debugging
- `lib/screens/lobby_screen.dart` - Added Socket.IO listeners

## Console Log Examples

### Success Case
```
🔍 Fetching groups from: https://www.flask-call-app.site/api/mobile/groups
🔑 Token length: 245
📡 Groups API response status: 200
📡 Groups API response body: {"groups":[{"id":1,"name":"Team Chat","member_count":5,...}]}
✅ Loaded 1 groups
📋 First group: {id: 1, name: Team Chat, member_count: 5, ...}
```

### Failure Case (404)
```
🔍 Fetching groups from: https://www.flask-call-app.site/api/mobile/groups
🔑 Token length: 245
📡 Groups API response status: 404
📡 Groups API response body: <!doctype html><html lang=en><title>404 Not Found</title>...
❌ Failed to load groups: 404 - <!doctype html>...
```

### Failure Case (Timeout)
```
🔍 Fetching groups from: https://www.flask-call-app.site/api/mobile/groups
🔑 Token length: 245
❌ Get groups error: TimeoutException after 0:00:30.000000: Future not completed
```

### Failure Case (Auth)
```
🔍 Fetching groups from: https://www.flask-call-app.site/api/mobile/groups
🔑 Token length: 245
📡 Groups API response status: 401
📡 Groups API response body: {"error":"Invalid or expired token"}
❌ Failed to load groups: 401 - {"error":"Invalid or expired token"}
```
