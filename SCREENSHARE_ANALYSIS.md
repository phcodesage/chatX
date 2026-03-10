# Screenshare Stream Analysis - Video Call Freeze Bug

## Overview
This document analyzes how screenshare streams are sent and received during video and audio calls in the Flutter WebRTC messenger app, with focus on the bug where screenshare freezes during video calls with web users.

---

## 1. How Screenshare is Initiated and Sent

### Location: `lib/services/call_service.dart` - `startScreenShare()` method (lines 1106-1230)

### Flow:

1. **Foreground Service (Android Only)**
   - Starts foreground service via method channel for Android 10+ media projection requirements
   - Channel: `com.example.flutter_messenger_v2/screen_share`

2. **Capture Screen Stream**
   ```dart
   _screenStream = await navigator.mediaDevices.getDisplayMedia({
     'video': true,
     'audio': true, // Include system audio if available
   });
   ```

3. **Store Original Video Track**
   ```dart
   if (_localStream != null) {
     _originalVideoTrack = _localStream!.getVideoTracks().firstOrNull;
   }
   ```

4. **Disable Original Camera Track**
   ```dart
   if (_originalVideoTrack != null) {
     _originalVideoTrack!.enabled = false;
   }
   ```

5. **Replace Video Track in Peer Connection**
   - **For Video Calls**: Uses `replaceTrack()` on existing video sender
   ```dart
   await videoSender.replaceTrack(screenTrack);
   ```
   - **For Audio Calls**: Adds new video track and triggers renegotiation
   ```dart
   await _peerConnection!.addTrack(screenTrack, _screenStream!);
   await _triggerRenegotiation();
   ```

6. **Notify Remote Peer**
   - Via signal: `{'type': 'screen-share-started'}`
   - Via socket event: `screen_share_started`

---

## 2. How Screenshare is Stopped

### Location: `lib/services/call_service.dart` - `stopScreenShare()` method (lines 1233-1330)

### Flow:

1. **Re-enable Original Camera Track**
   ```dart
   _originalVideoTrack!.enabled = true;
   ```

2. **Restore Original Video Track**
   - **For Video Calls**: Replace screen track back to camera track
   ```dart
   await sender.replaceTrack(_originalVideoTrack);
   ```
   - **For Audio Calls**: Remove video sender and trigger renegotiation
   ```dart
   await _peerConnection!.removeTrack(sender);
   await _triggerRenegotiation();
   ```

3. **Stop and Dispose Screen Stream**
   ```dart
   for (var track in _screenStream!.getTracks()) {
     track.stop();
   }
   await _screenStream!.dispose();
   ```

4. **Notify Remote Peer**
   - Via signal: `{'type': 'screen-share-stopped'}`
   - Via socket event: `screen_share_stopped`

---

## 3. How Screenshare is Received

### Location: `lib/services/call_service.dart` - `_createPeerConnection()` method (lines 323-410)

### Remote Track Handler:

```dart
_peerConnection!.onTrack = (event) {
  if (event.streams.isNotEmpty) {
    final stream = event.streams[0];
    
    // Save the very first remote stream as primary (camera) stream
    _primaryRemoteStream ??= stream;
    
    // Always update remote stream - handles both camera and screen share
    _remoteStream = stream;
    onRemoteStream?.call(_remoteStream!);
  }
};
```

### Key Points:
- First stream received is saved as `_primaryRemoteStream` (camera)
- `_remoteStream` is updated whenever a new track arrives
- No explicit differentiation between camera and screenshare streams
- Relies on track replacement mechanism

---

## 4. Renegotiation Handling

### Location: `lib/services/call_service.dart`

### Trigger Renegotiation (lines 1330-1380):
```dart
Future<void> _triggerRenegotiation() async {
  final offer = await _peerConnection!.createOffer();
  await _peerConnection!.setLocalDescription(offer);
  
  _socketService.emit('signal', {
    'room': _callRoomId,
    'signal': {
      'type': 'offer',
      'sdp': offer.sdp,
      'renegotiate': true, // Mark as renegotiation
    },
  });
}
```

### Process Renegotiation Offer (lines 600-650):
```dart
Future<void> _processRenegotiationOffer(Map<String, dynamic> signal) async {
  // Reset remote description flag
  _remoteDescriptionSet = false;
  
  await _peerConnection!.setRemoteDescription(
    RTCSessionDescription(sdp, 'offer'),
  );
  
  _remoteDescriptionSet = true;
  
  // Process queued ICE candidates
  await _processQueuedCandidates();
  
  // Create and send answer (do NOT re-add local tracks)
  final answer = await _peerConnection!.createAnswer();
  await _peerConnection!.setLocalDescription(answer);
  
  _socketService.emit('signal', {
    'room': _callRoomId,
    'signal': {'type': 'answer', 'sdp': answer.sdp, 'renegotiate': true},
  });
}
```

---

## 5. UI Display Logic

### Location: `lib/screens/connected_call_screen.dart` (lines 807-880)

```dart
Widget _buildRemoteVideo() {
  // For audio calls, show video only if remote is screen sharing
  if (widget.callType == 'audio' && !_remoteIsScreenSharing) {
    return _buildAvatarView();
  }
  
  return Stack(
    children: [
      Container(
        child: RTCVideoView(
          _remoteRenderer,
          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
        ),
      ),
      // Screen share indicator
      if (_remoteIsScreenSharing)
        _buildScreenShareIndicator(),
    ],
  );
}
```

---

## 6. IDENTIFIED BUG: Frozen Screenshare During Video Calls with Web Users

### Root Cause Analysis:

#### Problem 1: No Renegotiation for Video Call Screenshare
When screenshare starts during a **video call**, the code uses `replaceTrack()`:

```dart
if (videoSender != null) {
  await videoSender.replaceTrack(screenTrack);
  debugPrint('🖥️ Replaced existing video track with screen share');
} else {
  // Only audio calls reach here and trigger renegotiation
  await _peerConnection!.addTrack(screenTrack, _screenStream!);
  await _triggerRenegotiation();
}
```

**Issue**: `replaceTrack()` does NOT trigger renegotiation automatically. The web client may not be notified about the track change through SDP, causing it to continue expecting the old camera track.

#### Problem 2: Track Replacement Without SDP Update
- Mobile app replaces the video track locally
- No new SDP offer/answer exchange occurs
- Web client's peer connection still references the old track in its SDP
- Result: Web client displays frozen/stale video

#### Problem 3: Inconsistent Stream Handling
```dart
_remoteStream = stream;
onRemoteStream?.call(_remoteStream!);
```
- Remote stream is replaced entirely when new tracks arrive
- No mechanism to distinguish between camera and screenshare streams
- UI state (`_remoteIsScreenSharing`) relies on socket events, not actual stream state

#### Problem 4: Missing Renegotiation Detection
The signal handler checks for renegotiation flag:
```dart
final isRenegotiation = signal['renegotiate'] == true;
```
But when mobile sends `screen-share-started` signal, it doesn't include renegotiation offer for video calls.

---

## 7. RECOMMENDED FIXES

### Fix 1: Always Trigger Renegotiation for Screenshare (CRITICAL)

**Location**: `lib/services/call_service.dart` - `startScreenShare()` method

**Change**:
```dart
if (videoSender != null) {
  // Replace existing video track (video calls)
  try {
    await videoSender.replaceTrack(screenTrack);
    debugPrint('🖥️ Replaced existing video track with screen share');
    
    // CRITICAL FIX: Trigger renegotiation even for video calls
    // This ensures web clients receive updated SDP with new track
    await _triggerRenegotiation();
    
  } catch (e) {
    debugPrint('❌ Failed to replace video track with screen share: $e');
    await _peerConnection!.addTrack(screenTrack, _screenStream!);
    debugPrint('🖥️ Fallback: added screen track as new sender');
    await _triggerRenegotiation();
  }
}
```

**Rationale**: 
- `replaceTrack()` changes the media source but doesn't update SDP
- Web clients need SDP renegotiation to properly handle the new track
- This ensures both mobile and web clients stay synchronized

### Fix 2: Trigger Renegotiation When Stopping Screenshare

**Location**: `lib/services/call_service.dart` - `stopScreenShare()` method

**Change**:
```dart
if (_originalVideoTrack != null && _peerConnection != null) {
  // Video call - restore original camera track
  try {
    _originalVideoTrack!.enabled = true;
    debugPrint('🖥️ Re-enabled original camera track before restore');
  } catch (e) {
    debugPrint('⚠️ Could not re-enable original camera track: $e');
  }

  final senders = await _peerConnection!.getSenders();
  for (final sender in senders) {
    if (sender.track?.kind == 'video') {
      try {
        await sender.replaceTrack(_originalVideoTrack);
        debugPrint('🖥️ Restored original video track');
        
        // CRITICAL FIX: Trigger renegotiation when restoring camera
        await _triggerRenegotiation();
        
      } catch (e) {
        debugPrint('❌ Failed to restore original video track: $e');
      }
      break;
    }
  }
}
```

### Fix 3: Add Stream ID Tracking for Better Differentiation

**Location**: `lib/services/call_service.dart` - Add new fields

**Change**:
```dart
// Add to class fields
String? _cameraStreamId;
String? _screenShareStreamId;
bool _remoteIsScreenSharing = false;

// Update onTrack handler
_peerConnection!.onTrack = (event) {
  if (event.streams.isNotEmpty) {
    final stream = event.streams[0];
    
    // Track camera stream ID
    if (_cameraStreamId == null) {
      _cameraStreamId = stream.id;
      _primaryRemoteStream = stream;
    }
    
    // Detect screen share by different stream ID
    if (_cameraStreamId != null && stream.id != _cameraStreamId) {
      _screenShareStreamId = stream.id;
      _remoteIsScreenSharing = true;
      debugPrint('🖥️ Detected remote screen share stream: ${stream.id}');
    } else if (stream.id == _cameraStreamId) {
      _remoteIsScreenSharing = false;
      debugPrint('🎥 Back to camera stream: ${stream.id}');
    }
    
    _remoteStream = stream;
    onRemoteStream?.call(_remoteStream!);
    onScreenShareChanged?.call(_remoteIsScreenSharing);
  }
};
```

### Fix 4: Add Explicit Screen Share Metadata in Signals

**Location**: `lib/services/call_service.dart` - `_triggerRenegotiation()` method

**Change**:
```dart
Future<void> _triggerRenegotiation({String? reason}) async {
  if (_peerConnection == null || _callRoomId == null) {
    debugPrint('❌ Cannot trigger renegotiation - no peer connection or room ID');
    return;
  }

  try {
    debugPrint('🔄 Triggering renegotiation: $reason');

    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);

    _socketService.emit('signal', {
      'room': _callRoomId,
      'signal': {
        'type': 'offer',
        'sdp': offer.sdp,
        'renegotiate': true,
        'reason': reason, // Add reason for debugging
        'isScreenShare': _isScreenSharing, // Add screen share state
      },
    });

    debugPrint('✅ Renegotiation offer sent: $reason');
  } catch (e) {
    debugPrint('❌ Error triggering renegotiation: $e');
  }
}
```

Then update calls:
```dart
await _triggerRenegotiation(reason: 'screen-share-started');
await _triggerRenegotiation(reason: 'screen-share-stopped');
```

### Fix 5: Ensure Web Client Handles Renegotiation

**Note**: This requires checking the web client code (not in this repository)

The web client must:
1. Listen for renegotiation offers with `renegotiate: true` flag
2. Automatically accept renegotiation offers without user interaction
3. Update video track references when new tracks arrive
4. Handle `screen-share-started` and `screen-share-stopped` signals

---

## 8. Testing Checklist

After implementing fixes:

- [ ] Mobile-to-Mobile video call with screenshare
- [ ] Mobile-to-Web video call with screenshare (PRIMARY TEST CASE)
- [ ] Web-to-Mobile video call with screenshare
- [ ] Mobile-to-Mobile audio call with screenshare
- [ ] Mobile-to-Web audio call with screenshare
- [ ] Verify screenshare stops and camera resumes correctly
- [ ] Test with multiple renegotiations (start/stop screenshare multiple times)
- [ ] Check ICE connection stability during renegotiation
- [ ] Verify no memory leaks from unreleased streams

---

## 9. Additional Observations

### Potential Issues:

1. **ICE Candidate Timing**: ICE candidates may arrive before renegotiation completes
2. **Track Disposal**: Original video track is disabled but not disposed, may cause issues
3. **Error Handling**: Fallback to `addTrack()` may create duplicate video senders
4. **State Synchronization**: UI state depends on socket events, not actual WebRTC state

### Performance Considerations:

- Renegotiation adds ~200-500ms latency
- Multiple renegotiations in quick succession may cause issues
- Consider debouncing screenshare toggle

---

## Summary

The frozen screenshare bug during video calls with web users is caused by:
1. **Missing renegotiation** when using `replaceTrack()` for video calls
2. **No SDP update** sent to web client about track changes
3. **Inconsistent stream handling** between mobile and web

The primary fix is to **always trigger renegotiation** when starting or stopping screenshare, regardless of call type (video or audio). This ensures both peers have synchronized SDP and track information.

---

## IMPLEMENTATION STATUS: ✅ COMPLETED

All critical fixes have been implemented in `lib/services/call_service.dart`:

### ✅ Fix 1: Renegotiation for Video Call Screenshare (CRITICAL)
- Added `await _triggerRenegotiation(reason: 'screen-share-started')` after `replaceTrack()` in video calls
- Added renegotiation for fallback case when `replaceTrack()` fails
- Updated audio call renegotiation to include reason parameter

### ✅ Fix 2: Renegotiation When Stopping Screenshare
- Added `await _triggerRenegotiation(reason: 'screen-share-stopped')` when restoring camera track
- Ensures web clients receive SDP update when returning to camera

### ✅ Fix 3: Stream ID Tracking for Better Differentiation
- Added `_cameraStreamId`, `_screenShareStreamId`, and `_remoteIsScreenSharing` fields
- Updated `onTrack` handler to detect screen share by stream ID changes
- Automatically triggers `onScreenShareChanged` callback based on stream detection
- Properly resets tracking fields in cleanup methods

### ✅ Fix 4: Explicit Screen Share Metadata in Signals
- Updated `_triggerRenegotiation()` to accept optional `reason` parameter
- Added `reason` and `isScreenShare` metadata to renegotiation signals
- Improves debugging and allows web client to handle screen share explicitly

### Changes Made:
1. **startScreenShare()**: Now triggers renegotiation for both video and audio calls
2. **stopScreenShare()**: Now triggers renegotiation when restoring camera track
3. **_triggerRenegotiation()**: Accepts reason parameter and includes metadata
4. **onTrack handler**: Enhanced with stream ID tracking and automatic screen share detection
5. **_cleanup() and fullCleanup()**: Reset new tracking fields

These fixes ensure proper SDP synchronization between mobile and web clients during screenshare operations.
