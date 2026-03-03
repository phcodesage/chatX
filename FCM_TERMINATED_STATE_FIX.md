# FCM Notification Navigation Fix - Terminated State (Black Screen Fix)

## Problem
When the app was completely closed (terminated state) and a user tapped on a notification:
1. The app would open but show a BLACK SCREEN
2. The app would not navigate to the chat room
3. However, when the app was only minimized (background state), tapping notifications worked correctly

## Root Cause
The issue had multiple layers:

1. **Timing Issue**: `getInitialMessage()` was called too early during app initialization, before the Flutter navigator was ready
2. **Navigation Conflict**: HomePage immediately redirects to LobbyScreen, causing navigation conflicts when trying to handle notifications during this transition
3. **Missing Context**: The navigator context wasn't fully established when notification navigation was attempted

## Solution
We implemented a two-phase approach:

### Phase 1: Delay Initial Message Check
- Removed `getInitialMessage()` from the FCM `initialize()` method
- Created new `checkInitialMessage()` method called AFTER navigator is ready
- Added proper delays (1000ms) to ensure HomePage → LobbyScreen transition completes

### Phase 2: LobbyScreen Coordination
- Added `getPendingNotificationData()` method to retrieve stored notification data
- LobbyScreen now checks for pending notifications in `initState()` using `addPostFrameCallback`
- This ensures navigation happens only after LobbyScreen is fully rendered

### Changes Made

1. **firebase_messaging_service.dart**
   - Removed `getInitialMessage()` call from `initialize()` method
   - Added `checkInitialMessage()` method to be called after navigator is ready

2. **notification_handler.dart**
   - Added `hasPendingNavigation` getter to check if notification is pending
   - Added `getPendingNotificationData()` to retrieve and clear pending data
   - Improved navigation checks to detect mid-transition states
   - Simplified `_navigateToChat()` to directly push chat screen (no stack manipulation)

3. **lobby_screen.dart**
   - Added import for `NotificationHandler`
   - Added `_checkPendingNotification()` method in `initState()`
   - Uses `addPostFrameCallback` to ensure lobby is rendered before navigation

4. **auth_check_screen.dart**
   - Increased delay for `checkInitialMessage()` to 1000ms (from 500ms)
   - Ensures HomePage → LobbyScreen transition completes

5. **auth_service.dart**
   - Increased delay for `checkInitialMessage()` to 1000ms in both login and register
   - Ensures navigation is complete before checking notifications

## How It Works Now

### Terminated State Flow:
1. User taps notification → App launches
2. Firebase initializes (WITHOUT checking initial message)
3. Auth check completes → Navigate to HomePage
4. HomePage redirects to LobbyScreen
5. After 1000ms delay → `checkInitialMessage()` is called
6. Notification data is stored as pending
7. LobbyScreen finishes rendering → `_checkPendingNotification()` is called
8. After 500ms delay → Navigation to chat room happens successfully

### Background State Flow:
1. User taps notification → App comes to foreground
2. `onMessageOpenedApp` listener fires immediately
3. LobbyScreen is already loaded
4. Navigation happens directly (no delays needed)

## Testing
To test this fix on a release build:

1. Completely close the app (swipe away from recent apps)
2. Send a message from another device
3. Tap the notification
4. App should open, show LobbyScreen briefly, then navigate to chat room (NO BLACK SCREEN)

## Key Points
- The navigator must be ready AND the current route must be stable before navigation
- HomePage → LobbyScreen transition takes time and must complete first
- Different delays ensure proper timing: 500ms for pending check, 1000ms for initial message
- LobbyScreen coordination prevents black screen by ensuring UI is rendered
- This fix works for both message and call notifications

## Debug Logs to Watch For

### Success Flow:
```
🔔 App opened from terminated state via notification
Initial message data: {type: message, sender_id: 123, ...}
⏳ Navigation in progress, storing pending notification
📱 LobbyScreen: Processing pending notification: {...}
🔔 NotificationHandler.handleNotificationTap called with: {...}
🚀 Navigating to chat with user: 123 (Username)
```
