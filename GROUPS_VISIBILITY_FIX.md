# Groups Button Visibility Fix

## Changes Made

### 1. Groups Button Always Visible
**File**: `lib/screens/lobby_screen.dart`

**Before**: Groups button only showed if `_groups.isNotEmpty`
```dart
if (_groups.isNotEmpty)
  IconButton(...)
```

**After**: Groups button always visible
```dart
IconButton(
  icon: Stack(
    children: [
      const Icon(Icons.group, color: Colors.white70),
      if (_groups.isNotEmpty)  // Badge only shows if groups exist
        Positioned(...)
    ],
  ),
  ...
)
```

**Result**: You can now always tap the groups icon to see your groups, even if the list is empty or still loading.

---

### 2. Enhanced Debug Logging
**File**: `lib/services/group_service.dart`

Added detailed logging to help debug API calls:
```dart
debugPrint('🔍 Fetching groups from: $url');
debugPrint('📡 Groups API response status: ${response.statusCode}');
debugPrint('✅ Loaded ${groupsList.length} groups');
debugPrint('❌ Failed to load groups: ${response.statusCode}');
```

**Result**: You can now see exactly what's happening in the console when fetching groups.

---

## How to Test

### 1. Run the App
```bash
flutter run
```

### 2. Check the Console
Look for these log messages:
```
🔍 Fetching groups from: https://app.flask-meet.site/api/groups
📡 Groups API response status: 200
✅ Loaded 1 groups
```

### 3. Check the Lobby Screen
- Look for the **groups icon** (👥) in the top right of the AppBar
- If you have groups, you'll see a purple badge with the count
- Tap the icon to open the groups list

---

## Expected Behavior

### If Backend Has Groups:
1. ✅ Groups icon appears in lobby
2. ✅ Purple badge shows group count (e.g., "1", "2", "3")
3. ✅ Tapping icon opens groups list
4. ✅ Your web-created group appears in the list
5. ✅ Tapping group opens chat screen

### If Backend Returns Empty:
1. ✅ Groups icon still appears
2. ✅ No badge (since count is 0)
3. ✅ Tapping icon shows "No groups yet" message
4. ✅ Can tap + FAB to create new group

### If Backend API Fails:
1. ✅ Groups icon still appears
2. ✅ Error logged in console
3. ✅ Tapping icon shows error message
4. ✅ Can retry by tapping refresh

---

## Troubleshooting

### Groups Icon Not Appearing
**Check**: Make sure you're on the lobby screen (main chat list)
**Fix**: Restart the app

### No Groups Showing
**Check Console For**:
```
❌ Get groups error: Exception: Failed to load groups: <!doctype html>
```
**Meaning**: Backend endpoint doesn't exist yet
**Solution**: Backend needs to implement `/api/groups` endpoint

**Check Console For**:
```
📡 Groups API response status: 200
✅ Loaded 0 groups
```
**Meaning**: API works but you're not a member of any groups
**Solution**: 
1. Check if you're logged in as the same user who created the group on web
2. Create a new group from mobile
3. Check backend database to verify group membership

**Check Console For**:
```
📡 Groups API response status: 401
```
**Meaning**: Authentication token expired or invalid
**Solution**: Log out and log back in

### Groups List Empty But Should Have Groups
**Check**:
1. Are you logged in as the same user who created the group on web?
2. Does the backend `/api/groups` endpoint return your groups?
3. Check console logs for the API response

**Test Backend Directly**:
```bash
# Get your auth token from the app logs or login response
TOKEN="your_jwt_token_here"

# Test the API
curl -H "Authorization: Bearer $TOKEN" \
     https://app.flask-meet.site/api/groups
```

Expected response:
```json
{
  "groups": [
    {
      "id": 1,
      "name": "Your Group Name",
      "member_count": 2,
      ...
    }
  ]
}
```

---

## API Configuration

Current configuration in `lib/config/api_config.dart`:
```dart
static const String baseUrl = 'https://app.flask-meet.site';
static String get groupsUrl => '$baseUrl/api/groups';
```

Full URL being called: `https://app.flask-meet.site/api/groups`

---

## Next Steps

1. **Run the app** and check if the groups icon appears
2. **Tap the groups icon** to see if your web-created group shows up
3. **Check the console logs** to see what the API returns
4. **If groups don't appear**, check the troubleshooting section above

---

## Summary

✅ Groups button now always visible in lobby  
✅ Enhanced debug logging added  
✅ API URL: `https://app.flask-meet.site/api/groups`  
✅ Ready to test with your web-created group  

The app is now ready to display groups created from the web interface!
