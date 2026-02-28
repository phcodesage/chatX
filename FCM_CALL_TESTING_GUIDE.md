# FCM Call Notification Testing Guide

## Overview
This guide helps test incoming call notifications via FCM (Firebase Cloud Messaging) in different app states.

## Current FCM Implementation Status

### ✅ What's Already Working
1. **FCM Token Management**
   - FCM token is sent to backend after login/registration
   - Token is updated when refreshed
   - Token is removed on logout

2. **FCM Notification Handling**
   - Foreground: Shows notification banner + triggers call handler
   - Background: Shows notification, opens call modal when tapped
   - Terminated: Shows notification, opens app + call modal when tapped

3. **Call Notification Processing**
   - Proper call data extraction from FCM payload
   - Signal buffering for WebRTC offers
   - Call service initialization and state management
   - IncomingCallSetupModal display

4. **🆕 Pending Offer Recovery System**
   - **Primary**: `request_pending_offer` sent when FCM notification is handled
   - **Backup**: `request_call_offer` sent as secondary fallback
   - **Fallback**: `answerCall()` method requests pending offer if none available
   - **Enhanced Logging**: Better debugging for offer reception and processing

5. **🆕 Duplicate Call Prevention System**
   - **Global Flag**: `PresenceService().isHandlingIncomingCall` prevents duplicate setups
   - **FCM Guard**: FCM notification handler checks flag before creating call setup
   - **Socket Guard**: Socket event handlers also check flag to prevent conflicts
   - **Proper Cleanup**: Flag is reset when call setup completes or fails

## Test Scenarios

### Scenario 1: App in Foreground (Lobby Screen)
**Expected Flow:**
1. Web user initiates call
2. Mobile receives Socket.IO event (crossRoomCallOffer)
3. Fallback listener converts to incomingCall format
4. IncomingCallSetupModal appears immediately
5. **Backup:** FCM notification also sent but handled silently

**Test Steps:**
1. Open mobile app, stay on lobby screen
2. Have web user call mobile
3. ✅ **Expected:** Call modal appears immediately
4. ✅ **Expected:** FCM notification may show as banner (optional)

### Scenario 2: App in Foreground (Other Screens)
**Expected Flow:**
1. Web user initiates call
2. Mobile may not receive Socket.IO event (not in lobby)
3. FCM notification received in foreground
4. FCM handler triggers call modal

**Test Steps:**
1. Open mobile app, navigate to chat screen or other screen
2. Have web user call mobile
3. ✅ **Expected:** FCM notification banner appears
4. ✅ **Expected:** Call modal opens automatically
5. ✅ **Expected:** Can answer/decline call normally

### Scenario 3: App in Background
**Expected Flow:**
1. Web user initiates call
2. FCM notification appears in notification tray
3. User taps notification
4. App opens and shows call modal

**Test Steps:**
1. Open mobile app, then press home button (app backgrounded)
2. Have web user call mobile
3. ✅ **Expected:** FCM notification appears in notification tray
4. ✅ **Expected:** Notification shows caller name and "Incoming call"
5. Tap notification
6. ✅ **Expected:** App opens and shows IncomingCallSetupModal
7. ✅ **Expected:** Can answer/decline call normally

### Scenario 4: App Terminated
**Expected Flow:**
1. Web user initiates call
2. FCM notification appears in notification tray
3. User taps notification
4. App launches and shows call modal

**Test Steps:**
1. Force close mobile app completely
2. Have web user call mobile
3. ✅ **Expected:** FCM notification appears in notification tray
4. Tap notification
5. ✅ **Expected:** App launches and shows IncomingCallSetupModal
6. ✅ **Expected:** Can answer/decline call normally

## Backend Requirements

For FCM notifications to work, the backend must:

### 1. Send FCM Notification on Call Initiation
When a web user initiates a call, the backend should send both:
- Socket.IO event: `crossRoomCallOffer` (for real-time delivery)
- FCM notification: Push notification (for background/terminated states)

### 2. FCM Payload Format
The FCM notification should include this data:
```json
{
  "data": {
    "type": "call",
    "sender_id": "2",
    "sender_name": "John Doe",
    "call_type": "video",
    "call_id": "12345",
    "call_room_id": "chat_2_16",
    "title": "Incoming call",
    "body": "John Doe is calling you"
  }
}
```

### 3. FCM Notification Channels
The notification should use the "calls" channel for proper priority:
- Channel ID: `calls`
- Importance: `max`
- Priority: `high`
- Sound: `enabled`
- Vibration: `enabled`

## Debugging FCM Issues

### Check FCM Token
```bash
# Look for FCM token logs during app startup
grep "FCM Token" logs.txt
grep "FCM token sent to backend" logs.txt
```

### Check FCM Message Reception
```bash
# Look for FCM message logs
grep "Foreground message received\|Background message received\|App opened from terminated" logs.txt
```

### Check Call Notification Handling
```bash
# Look for call notification processing
grep "📞 Handling incoming call notification" logs.txt
grep "📞 Call details:" logs.txt
```

### Common Issues & Solutions

#### Issue: No FCM notification received
**Possible Causes:**
1. FCM token not sent to backend
2. Backend not sending FCM notifications
3. App permissions denied

**Solutions:**
1. Check logs for "FCM token sent to backend successfully"
2. Verify backend FCM integration
3. Check notification permissions in device settings

#### Issue: FCM notification received but call modal doesn't open
**Possible Causes:**
1. Navigation context not available
2. Call data format incorrect
3. Socket connection issues

**Solutions:**
1. Check logs for "No context available for showing call modal"
2. Verify FCM payload format matches expected structure
3. Ensure socket service is properly initialized

#### Issue: Call modal opens but answer/decline doesn't work
**Possible Causes:**
1. Call state not properly set
2. Signal buffering issues
3. WebRTC offer not received

**Solutions:**
1. Check logs for call state transitions
2. Verify signal buffering is started before call setup
3. Check for WebRTC offer reception in logs

#### Issue: "No pending offer to process" when answering FCM call
**Possible Causes:**
1. WebRTC offer sent while app was in background and not stored
2. `request_pending_offer` not working or timing out
3. Backend not storing/returning pending offers correctly

**Solutions:**
1. **Check for offer reception logs:**
   ```bash
   grep "📥 Received WebRTC offer" logs.txt
   grep "📥 Storing offer for incoming call" logs.txt
   grep "📥 Offer SDP length" logs.txt
   ```

2. **Check for pending offer requests:**
   ```bash
   grep "📞 Requesting pending offer" logs.txt
   grep "📞 Pending offer request sent" logs.txt
   grep "📡 Requesting fresh WebRTC offer" logs.txt
   ```

3. **Check answerCall fallback:**
   ```bash
   grep "📞 Requesting pending offer as fallback" logs.txt
   grep "📥 Processing fallback pending offer" logs.txt
   ```

4. **Verify backend `request_pending_offer` functionality:**
   - Backend should store WebRTC offers when calls are initiated
   - Backend should respond to `request_pending_offer` with stored offer
   - Check backend logs for pending offer storage/retrieval

#### Issue: Stuck call offer widget after call ends
**Possible Causes:**
1. Multiple call setups created (socket event + FCM notification)
2. Duplicate prevention not working properly
3. Call cleanup not removing all UI elements

**Solutions:**
1. **Check for duplicate call setup logs:**
   ```bash
   grep "Already handling an incoming call" logs.txt
   grep "📲 Cross-room call offer" logs.txt
   grep "📞 FCM notification tapped" logs.txt
   ```

2. **Verify duplicate prevention is working:**
   - Should see "⚠️ Already handling an incoming call, ignoring FCM duplicate" if both socket and FCM arrive
   - Only one call setup should proceed, the other should be ignored

3. **Check call cleanup:**
   ```bash
   grep "Call ended" logs.txt
   grep "Full cleanup" logs.txt
   grep "isHandlingIncomingCall.*false" logs.txt
   ```

**Expected Fix Flow:**
```
Socket event arrives → Sets isHandlingIncomingCall = true → Shows call modal
FCM notification arrives → Checks flag → Sees already handling → Ignores duplicate
Call ends → Cleanup runs → Resets isHandlingIncomingCall = false
```

## Expected Log Flow (Successful FCM Call)

```
📱 FCM Token: [token]
✅ FCM token sent to backend successfully
📨 Foreground message received: Incoming call
📞 Handling incoming call notification: {type: call, sender_id: 2, ...}
✅ Context available, proceeding with call setup
📞 Call details: senderId=2, senderName=John, callType=video, ...
✅ Call service initialized
📡 Started signal buffering for FCM call
📞 Requesting pending offer for FCM call: chat_2_16
📞 Pending offer request sent for room: chat_2_16
📡 Requesting fresh WebRTC offer for FCM call (backup)
📞 Created call data: {id: ..., call_room_id: ..., ...}
📲 Current call state before: CallState.idle, direction: null
📲 After setting: _callRoomId=chat_2_16, _callId=12345, _callDirection=CallDirection.incoming, _callState=CallState.ringing
📞 Attempting to show IncomingCallSetupModal
📥 Received WebRTC offer (callDirection: CallDirection.incoming, callState: CallState.ringing, remoteDescSet: false)
📥 Storing offer for incoming call - waiting for user to answer
📥 Offer SDP length: 2847 characters
[User presses Answer button]
📞 answerCall called - current state: CallState.ringing, direction: CallDirection.incoming
📞 Call state changed to connecting
📥 Processing pending offer after user answered
📥 Remote description set (offer)
🧊 Processing 0 queued ICE candidates
📤 Sending WebRTC answer to room: chat_2_16
```

## Testing Checklist

- [ ] FCM token sent to backend on login
- [ ] Scenario 1: Foreground (lobby) - Socket.IO + FCM backup
- [ ] Scenario 2: Foreground (other screens) - FCM primary
- [ ] Scenario 3: Background - FCM notification tray
- [ ] Scenario 4: Terminated - FCM launches app
- [ ] Answer button works in all scenarios
- [ ] Decline button works in all scenarios
- [ ] Call quality good in all scenarios
- [ ] Proper cleanup when call ends

## Next Steps

If any test fails:
1. Check the specific logs for that scenario
2. Verify backend is sending FCM notifications
3. Confirm FCM payload format is correct
4. Test notification permissions on device
5. Verify socket connection for signal handling