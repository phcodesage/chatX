# Testing FCM Notification Navigation - Terminated State Fix

## Build Information
- Release APK built successfully
- Location: `build/app/outputs/flutter-apk/app-release.apk`
- Size: 87.1MB

## Testing Steps

### Test 1: App Completely Closed (Terminated State)
This is the scenario that was previously broken.

1. Install the release APK on your device
2. Open the app and log in
3. **Completely close the app** (swipe it away from recent apps)
4. From another device, send a message to your account
5. Wait for the notification to appear
6. **Tap the notification**
7. ✅ **Expected Result**: App should open AND navigate directly to the chat room with the sender

### Test 2: App Minimized (Background State)
This scenario was already working, but we should verify it still works.

1. Open the app
2. Press the home button (app goes to background but stays in memory)
3. From another device, send a message
4. Wait for the notification to appear
5. **Tap the notification**
6. ✅ **Expected Result**: App should come to foreground AND navigate to the chat room

### Test 3: App in Foreground
1. Open the app and stay on any screen
2. From another device, send a message
3. Wait for the notification banner to appear
4. **Tap the notification banner**
5. ✅ **Expected Result**: Should navigate to the chat room

### Test 4: Call Notifications (Terminated State)
1. Completely close the app
2. From another device, initiate a call
3. Wait for the call notification
4. **Tap the notification**
5. ✅ **Expected Result**: App should open AND show the incoming call modal

### Test 5: Group Messages (Terminated State)
1. Completely close the app
2. From another device, send a group message
3. Wait for the notification
4. **Tap the notification**
5. ✅ **Expected Result**: App should open AND navigate to the group chat

## Debug Logs to Watch For

When testing, check the logs for these messages:

### Terminated State Success:
```
🔔 App opened from terminated state via notification
Initial message data: {type: message, sender_id: 123, ...}
🔔 NotificationHandler.handleNotificationTap called with: {...}
🚀 Navigating to chat with user: 123 (Username)
```

### Background State Success:
```
🔔 Notification tapped (app in background)
🔔 NotificationHandler.handleNotificationTap called with: {...}
🚀 Navigating to chat with user: 123 (Username)
```

## Common Issues to Check

1. **Navigator not ready**: If you see "⏳ Navigator not ready, storing pending notification", the timing delays may need adjustment
2. **No initial message found**: If you see "ℹ️ No initial message found" when you expect one, the notification may not have been properly delivered
3. **Black screen**: If the app opens to a black screen, check that the navigation stack is being properly cleared and rebuilt

## Installation Command
```bash
adb install build/app/outputs/flutter-apk/app-release.apk
```

Or use the provided batch script:
```bash
./build_and_install.bat
```

## What Changed
- FCM initial message check now happens AFTER navigator is ready
- Added delays to ensure proper navigation stack initialization
- Works for both login and app restart scenarios
- Handles messages, calls, and group notifications
