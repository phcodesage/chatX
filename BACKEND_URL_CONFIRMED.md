# Backend URL Configuration - Confirmed

## Current Backend
**Base URL**: `https://www.flask-call-app.site`

This is now correctly configured in `lib/config/api_config.dart`.

## All API Endpoints

### Groups
- List groups: `https://www.flask-call-app.site/api/mobile/groups`
- Get group details: `https://www.flask-call-app.site/api/mobile/groups/{id}`
- Get messages: `https://www.flask-call-app.site/api/mobile/groups/{id}/messages`
- Send message: `https://www.flask-call-app.site/api/mobile/groups/{id}/messages`
- Upload file: `https://www.flask-call-app.site/api/mobile/groups/{id}/messages/upload`

### Socket.IO
- Connection URL: `https://www.flask-call-app.site`
- Transport: WebSocket with polling fallback

## What's Been Fixed

1. ✅ API config points to correct backend
2. ✅ Enhanced debugging in group service
3. ✅ Fixed GroupMessageSender model (added lastName field)
4. ✅ Fixed Socket.IO event names (snake_case)
5. ✅ Added Socket.IO listeners for group events in lobby

## Next Steps

**Hot restart your Flutter app** (press `R` in terminal):
```bash
# In your Flutter terminal:
R  # Capital R for hot restart
```

Then check the console logs when:
1. Opening the app (groups should load)
2. Tapping on a group (messages should load)

## Expected Console Output

### On App Start (Loading Groups)
```
🔍 Fetching groups from: https://www.flask-call-app.site/api/mobile/groups
🔑 Token length: 245
📡 Groups API response status: 200
📡 Groups API response body: {"groups":[...]}
✅ Loaded X groups
```

### On Opening Group Chat (Loading Messages)
```
💬 Fetching messages from: https://www.flask-call-app.site/api/mobile/groups/1/messages?limit=50
🔑 Token length: 245
📡 Messages API response status: 200
📡 Messages API response body: {"messages":[...]}
✅ Loaded X messages for group 1
```

### Socket.IO Connection
```
✅ Socket connected - ID: [socket_id]
Socket exists: true
Socket connected: true
```

## If Still Having Issues

Share the console logs showing:
1. The full URL being called
2. The response status code
3. The response body (or error message)

This will help identify if it's:
- Authentication issue (401)
- Endpoint not found (404)
- Server error (500)
- Network/timeout issue
- JSON parsing error

## Testing the Backend Directly

You can test the API endpoints directly using curl:

```bash
# 1. Login to get token
curl -X POST https://www.flask-call-app.site/api/mobile/login \
  -H "Content-Type: application/json" \
  -d '{"username":"your_email","password":"your_password"}'

# 2. Use the token to get groups
curl -H "Authorization: Bearer YOUR_TOKEN" \
  https://www.flask-call-app.site/api/mobile/groups

# 3. Get messages for a specific group
curl -H "Authorization: Bearer YOUR_TOKEN" \
  https://www.flask-call-app.site/api/mobile/groups/1/messages?limit=50
```

This will confirm if the backend endpoints are working correctly.
