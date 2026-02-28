# Incoming Call Issue Fix

## Problem
When a web user calls the mobile app, the call offer appears in logs but:
- No incoming call widget shows up
- No FCM notification is received

## Root Causes Found & Fixed

### 1. ✅ FCM Token Already Being Sent
- **Status**: Already working correctly
- **Location**: `lib/services/auth_service.dart` (lines 60-65, 120-125)
- **Fix**: FCM token is sent to backend after both login and registration

### 2. ✅ Fixed Signal Buffering Issue
- **Problem**: WebRTC signals were lost during FCM call setup
- **Location**: `lib/utils/notification_handler.dart` (lines 85-95)
- **Fix**: Now calls `socketService.startSignalBuffering()` BEFORE `callService.handleIncomingCall()`
- **Impact**: Prevents loss of WebRTC offer/ICE candidates during call setup

### 3. ✅ Added Fallback for Cross-Room Call Offers
- **Problem**: Mobile only listened to 'incomingCall' events, not 'crossRoomCallOffer'
- **Locations**: 
  - `lib/screens/lobby_screen.dart` (lines 160-180)
  - `lib/screens/chat_screen.dart` (lines 905-925)
- **Fix**: Added fallback listeners for 'crossRoomCallOffer' that convert to 'incomingCall' format
- **Impact**: Handles cases where backend only sends cross-room events

### 4. ✅ Enhanced Debug Logging
- **Location**: `lib/utils/notification_handler.dart`
- **Fix**: Added detailed logging to track call setup process
- **Impact**: Better debugging for future issues

## Testing Instructions

### Test 1: Foreground Call (App Open)
1. Open mobile app and stay on lobby or chat screen
2. Have web user initiate call to mobile
3. **Expected**: Incoming call modal should appear immediately
4. **Check logs for**: 
   - `📲 Fallback: Received crossRoomCallOffer` (if backend sends this event)
   - `📞 Handling incoming call notification`
   - `✅ Context available, proceeding with call setup`
   - `📞 Attempting to show IncomingCallSetupModal`

### Test 2: Background Call (App Backgrounded)
1. Put mobile app in background
2. Have web user initiate call to mobile
3. **Expected**: FCM notification should appear
4. Tap notification
5. **Expected**: Incoming call modal should appear
6. **Check logs for**:
   - `📱 Background message received` (in background handler)
   - `🔔 Notification tapped` (when tapped)
   - Same call setup logs as Test 1

### Test 3: Terminated Call (App Closed)
1. Force close mobile app
2. Have web user initiate call to mobile
3. **Expected**: FCM notification should appear
4. Tap notification to open app
5. **Expected**: App opens and shows incoming call modal
6. **Check logs for**:
   - `🔔 App opened from terminated state via notification`
   - Same call setup logs as Test 1

## Debug Commands

### Check FCM Token Status
```bash
# Look for these logs during app startup:
grep "FCM Token" logs.txt
grep "FCM token sent to backend" logs.txt
```

### Check Socket Events
```bash
# Look for incoming call events:
grep "Incoming call\|crossRoomCallOffer" logs.txt
grep "📲" logs.txt
```

### Check Call Setup Process
```bash
# Look for call setup logs:
grep "📞" logs.txt
grep "Call service initialized" logs.txt
grep "Started signal buffering" logs.txt
```

## Potential Remaining Issues

If calls still don't work after these fixes, check:

1. **Backend Event Sending**: Verify backend is actually sending either 'incomingCall' or 'crossRoomCallOffer' events
2. **FCM Backend Integration**: Verify backend is sending FCM notifications with correct payload format
3. **Network Connectivity**: Ensure mobile device can reach both Socket.IO and FCM services
4. **Permissions**: Verify notification permissions are granted on mobile device

## Event Flow Diagram

```
Web User Initiates Call
         ↓
Backend receives call request
         ↓
Backend sends TWO events:
├── Socket.IO: 'incomingCall' OR 'crossRoomCallOffer' → Mobile (if app open)
└── FCM: Push notification → Mobile (if app background/closed)
         ↓
Mobile receives event
         ↓
├── If Socket.IO: lobby_screen.dart or chat_screen.dart handles
└── If FCM: notification_handler.dart handles
         ↓
Both paths lead to: IncomingCallSetupModal
         ↓
User accepts → ConnectedCallScreen
```

## Files Modified

1. `lib/utils/notification_handler.dart` - Fixed signal buffering, added debug logs
2. `lib/screens/lobby_screen.dart` - Added crossRoomCallOffer fallback listener  
3. `lib/screens/chat_screen.dart` - Added crossRoomCallOffer fallback listener

## Next Steps

1. Test all three scenarios above
2. Check logs for any remaining issues
3. If problems persist, investigate backend event sending
4. Consider adding call timeout handling for better UX