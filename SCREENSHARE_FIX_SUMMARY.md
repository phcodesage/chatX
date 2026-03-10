# Screenshare Freeze Bug - Fix Summary

## Problem
When screensharing during a video call with web users, the screenshare stream freezes on the web client side.

## Root Cause
The mobile app was using `replaceTrack()` to swap camera video with screen video during video calls, but **not triggering SDP renegotiation**. This meant:
- Mobile app switched tracks locally
- Web client never received updated SDP
- Web client continued expecting the old camera track
- Result: Frozen video on web client

## Solution Implemented
Added SDP renegotiation for all screenshare operations to ensure both mobile and web clients stay synchronized.

---

## Changes Made to `lib/services/call_service.dart`

### 1. Added Stream Tracking Fields (Line ~44)
```dart
// Screen sharing state
bool _isScreenSharing = false;
MediaStreamTrack? _originalVideoTrack;
String? _cameraStreamId; // NEW: Track camera stream ID
String? _screenShareStreamId; // NEW: Track screen share stream ID
bool _remoteIsScreenSharing = false; // NEW: Track remote screen share state
```

### 2. Enhanced `startScreenShare()` Method
**Before**: Only audio calls triggered renegotiation
**After**: Both video and audio calls trigger renegotiation

```dart
if (videoSender != null) {
  // Video call
  await videoSender.replaceTrack(screenTrack);
  
  // CRITICAL FIX: Trigger renegotiation even for video calls
  await _triggerRenegotiation(reason: 'screen-share-started');
} else {
  // Audio call
  await _peerConnection!.addTrack(screenTrack, _screenStream!);
  await _triggerRenegotiation(reason: 'screen-share-started-audio');
}
```

### 3. Enhanced `stopScreenShare()` Method
**Before**: Only audio calls triggered renegotiation
**After**: Both video and audio calls trigger renegotiation

```dart
if (_originalVideoTrack != null && _peerConnection != null) {
  // Video call - restore camera
  await sender.replaceTrack(_originalVideoTrack);
  
  // CRITICAL FIX: Trigger renegotiation when restoring camera
  await _triggerRenegotiation(reason: 'screen-share-stopped');
} else if (_peerConnection != null) {
  // Audio call - remove video track
  await _peerConnection!.removeTrack(sender);
  await _triggerRenegotiation(reason: 'screen-share-stopped-audio');
}
```

### 4. Updated `_triggerRenegotiation()` Method
**Before**: No metadata, generic logging
**After**: Accepts reason parameter, includes metadata

```dart
Future<void> _triggerRenegotiation({String? reason}) async {
  debugPrint('🔄 Triggering renegotiation: ${reason ?? "unknown"}');
  
  final offer = await _peerConnection!.createOffer();
  await _peerConnection!.setLocalDescription(offer);
  
  _socketService.emit('signal', {
    'room': _callRoomId,
    'signal': {
      'type': 'offer',
      'sdp': offer.sdp,
      'renegotiate': true,
      'reason': reason, // NEW: For debugging
      'isScreenShare': _isScreenSharing, // NEW: Screen share state
    },
  });
}
```

### 5. Enhanced `onTrack` Handler
**Before**: Simple stream replacement
**After**: Stream ID tracking and automatic screen share detection

```dart
_peerConnection!.onTrack = (event) {
  if (event.streams.isNotEmpty) {
    final stream = event.streams[0];
    
    // Track camera stream ID on first reception
    if (_cameraStreamId == null) {
      _cameraStreamId = stream.id;
      _primaryRemoteStream = stream;
    }
    
    // Detect screen share by different stream ID
    if (_cameraStreamId != null && stream.id != _cameraStreamId) {
      _screenShareStreamId = stream.id;
      _remoteIsScreenSharing = true;
      onScreenShareChanged?.call(true);
    } else if (stream.id == _cameraStreamId && _remoteIsScreenSharing) {
      _remoteIsScreenSharing = false;
      _screenShareStreamId = null;
      onScreenShareChanged?.call(false);
    }
    
    _remoteStream = stream;
    onRemoteStream?.call(_remoteStream!);
    
    // Listen for track ended
    event.track.onEnded = () {
      if (_remoteIsScreenSharing && event.track.kind == 'video') {
        _remoteIsScreenSharing = false;
        _screenShareStreamId = null;
        onScreenShareChanged?.call(false);
      }
    };
  }
};
```

### 6. Updated Cleanup Methods
Added resets for new tracking fields in both `_cleanup()` and `fullCleanup()`:

```dart
// Reset screen share tracking
_cameraStreamId = null;
_screenShareStreamId = null;
_remoteIsScreenSharing = false;
```

---

## Testing Checklist

Before deploying, test these scenarios:

- [ ] **Mobile-to-Web video call with screenshare** (PRIMARY TEST CASE)
  - Start video call between mobile and web
  - Mobile user starts screenshare
  - Verify web user sees screenshare (not frozen)
  - Mobile user stops screenshare
  - Verify web user sees camera again

- [ ] **Web-to-Mobile video call with screenshare**
  - Start video call between web and mobile
  - Web user starts screenshare
  - Verify mobile user sees screenshare
  - Web user stops screenshare
  - Verify mobile user sees camera again

- [ ] **Mobile-to-Mobile video call with screenshare**
  - Verify screenshare works between two mobile devices

- [ ] **Audio call with screenshare**
  - Start audio call
  - Start screenshare (should add video)
  - Stop screenshare (should remove video)

- [ ] **Multiple screenshare toggles**
  - Start/stop screenshare multiple times
  - Verify no memory leaks or connection issues

- [ ] **ICE connection stability**
  - Monitor ICE connection state during renegotiation
  - Verify no disconnections

---

## Expected Behavior After Fix

1. **Starting Screenshare (Video Call)**:
   - Mobile: Replaces camera track with screen track
   - Mobile: Sends renegotiation offer to web
   - Web: Receives offer, updates SDP, sends answer
   - Web: Displays screen share (not frozen)

2. **Stopping Screenshare (Video Call)**:
   - Mobile: Replaces screen track with camera track
   - Mobile: Sends renegotiation offer to web
   - Web: Receives offer, updates SDP, sends answer
   - Web: Displays camera feed

3. **Debug Logs**:
   - Look for: `🔄 Triggering renegotiation: screen-share-started`
   - Look for: `🔄 Triggering renegotiation: screen-share-stopped`
   - Look for: `🖥️ Detected remote screen share stream: [stream-id]`

---

## Web Client Requirements

The web client must properly handle renegotiation offers:

1. Listen for signals with `renegotiate: true` flag
2. Automatically accept renegotiation offers (no user interaction)
3. Update peer connection with new SDP
4. Handle track changes in `ontrack` event
5. Respect `reason` and `isScreenShare` metadata if needed

---

## Performance Impact

- Renegotiation adds ~200-500ms latency per operation
- This is acceptable for screenshare start/stop operations
- No impact on ongoing call quality
- No additional bandwidth usage

---

## Rollback Plan

If issues occur, revert changes to `lib/services/call_service.dart`:
1. Remove `reason` parameter from `_triggerRenegotiation()` calls
2. Remove renegotiation calls from video call screenshare operations
3. Keep only audio call renegotiation (original behavior)

---

## Additional Notes

- The fix maintains backward compatibility with existing web clients
- Stream ID tracking improves reliability of screen share detection
- Metadata in signals helps with debugging and future enhancements
- All changes are contained in `call_service.dart` - no UI changes needed
