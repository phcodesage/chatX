# FCM Terminated State Navigation Fix

## Problem
When the app was completely closed (terminated state) and a user tapped on a message notification, the app would open but NOT navigate to the chat screen. The notification was being stored as "pending" but never processed.

## Root Causes

### Issue 1: Navigation State Check
The `handleNotificationTap` method in `NotificationHandler` was checking if navigation was in progress using:
```dart
final currentRoute = ModalRoute.of(navigatorKey.currentContext!);
if (currentRoute == null || !currentRoute.isCurrent) {
  // Store as pending
}
```

When the app opens from terminated state, `currentRoute.isCurrent` returns false because the route is still being built, causing the notification to be stored as pending.

### Issue 2: Timing Problem (MAIN ISSUE)
In `AuthCheckScreen`, the notification check was happening AFTER navigation:
```dart
// Navigate to home page
Navigator.pushReplacement(...);

// Check notification with 1000ms delay (TOO LATE!)
Future.delayed(Duration(milliseconds: 1000), () {
  FirebaseMessagingService.instance.checkInitialMessage();
});
```

By the time `checkInitialMessage()` ran (1000ms later), the app had already navigated through `HomePage` → `LobbyScreen`, and `LobbyScreen` had already checked for pending notifications (found none because the notification wasn't stored yet).

## Solution

### Fix 1: Add `fromPending` Parameter
Added a `fromPending` parameter to `handleNotificationTap` that skips the navigation state check when processing pending notifications from `LobbyScreen`.

### Fix 2: Check Notification BEFORE Navigation (CRITICAL)
Moved `checkInitialMessage()` to run BEFORE navigating to `HomePage`:
```dart
// Check notification FIRST (synchronously)
await FirebaseMessagingService.instance.checkInitialMessage();

// THEN navigate
Navigator.pushReplacement(...);
```

This ensures:
1. Notification is detected and stored as pending
2. App navigates to `HomePage` → `LobbyScreen`
3. `LobbyScreen` checks for pending notifications and finds it
4. Navigation to chat happens

## Backend Changes (Python)
The backend now sends **data-only FCM messages** (no `notification` field) to prevent duplicate notifications:

```python
# Data payload includes:
{
  'type': 'message',           # or 'doorbell', 'call', 'color_change'
  'sender_id': str(sender_id), # User ID of sender
  'sender_name': sender_name,  # Display name of sender
  'room_id': str(sender_id),   # Chat room ID (same as sender_id for 1-on-1)
  'title': '💬 {sender_name}', # Notification title
  'body': message_content,     # Notification body
  'click_action': 'FLUTTER_NOTIFICATION_CLICK'
}
```

## Changes Made

### lib/screens/auth_check_screen.dart
- Moved `checkInitialMessage()` to run BEFORE navigation (synchronously with `await`)
- Removed the delayed calls to `processPendingNotification()` and `checkInitialMessage()`
- Removed unused import of `notification_handler.dart`

### lib/utils/notification_handler.dart
- Added `fromPending` parameter to `handleNotificationTap()`
- Skip navigation state check when `fromPending: true`
- Updated `processPendingNotification()` to pass `fromPending: true`
- Added debug logging to `getPendingNotificationData()`

### lib/screens/lobby_screen.dart
- Updated `_checkPendingNotification()` to pass `fromPending: true` when calling `handleNotificationTap()`
- Added debug logging to show when checking for pending notifications

## Testing
1. Completely close the app (swipe away from recent apps)
2. Send a message from another user
3. Tap the notification
4. App should open AND navigate directly to the chat screen with that user

## Expected Logs
```
🔔 App opened from terminated state via LOCAL notification
🔔 NotificationHandler.handleNotificationTap called with: {...} (fromPending: false)
⏳ Navigation in progress, storing pending notification
📱 LobbyScreen: Checking for pending notifications...
🔍 getPendingNotificationData called
🔍 Current pending data: {sender_id: 16, ...}
📱 LobbyScreen: Processing pending notification: {...}
🔔 NotificationHandler.handleNotificationTap called with: {...} (fromPending: true)
✅ Processing from pending queue, skipping navigation check
🚀 Navigating to chat with user: 16 (brave)
```

## Data Flow
1. App is terminated, notification arrives
2. User taps notification → app launches
3. `AuthCheckScreen` initializes
4. Calls `checkInitialMessage()` BEFORE navigation (synchronously)
5. Detects notification, calls `handleNotificationTap()` → stores as pending
6. Navigates to `HomePage` → `LobbyScreen`
7. `LobbyScreen.initState()` → `_checkPendingNotification()`
8. Calls `handleNotificationTap(data, fromPending: true)` → navigates to chat


