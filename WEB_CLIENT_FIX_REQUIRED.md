# Web Client Fix Required for Screenshare

## Problem Confirmed

From your logs, I can see:
1. ✅ Mobile app is sending renegotiation offer: `renegotiate: true, reason: screen-share-started`
2. ✅ Web client is responding with an answer
3. ❌ **BUT** the screenshare is still freezing and stretching on web

This means the **web client is NOT properly handling the renegotiation**.

---

## Root Cause

The web client is likely:
1. Receiving the renegotiation offer
2. Creating an answer (which is why you see the answer in logs)
3. **BUT NOT updating the video element or handling the new track properly**

---

## Required Web Client Fixes

### Fix 1: Handle Renegotiation Offers Properly

The web client must detect renegotiation offers and handle them differently from initial offers.

**Location**: Web client JavaScript (wherever WebRTC signaling is handled)

**Current Code (Likely)**:
```javascript
socket.on('signal', async (data) => {
  const signal = data.signal;
  
  if (signal.type === 'offer') {
    // This probably treats ALL offers the same way
    await peerConnection.setRemoteDescription(
      new RTCSessionDescription({ type: 'offer', sdp: signal.sdp })
    );
    
    const answer = await peerConnection.createAnswer();
    await peerConnection.setLocalDescription(answer);
    
    socket.emit('signal', {
      room: roomId,
      signal: { type: 'answer', sdp: answer.sdp }
    });
  }
});
```

**Fixed Code**:
```javascript
socket.on('signal', async (data) => {
  const signal = data.signal;
  
  if (signal.type === 'offer') {
    console.log('📥 Received offer:', {
      isRenegotiation: signal.renegotiate,
      reason: signal.reason,
      isScreenShare: signal.isScreenShare
    });
    
    // CRITICAL: Set remote description FIRST
    await peerConnection.setRemoteDescription(
      new RTCSessionDescription({ type: 'offer', sdp: signal.sdp })
    );
    
    // Create and send answer
    const answer = await peerConnection.createAnswer();
    await peerConnection.setLocalDescription(answer);
    
    socket.emit('signal', {
      room: roomId,
      signal: { 
        type: 'answer', 
        sdp: answer.sdp,
        renegotiate: signal.renegotiate // Echo back renegotiate flag
      }
    });
    
    console.log('✅ Answer sent for', signal.renegotiate ? 'renegotiation' : 'initial offer');
  }
});
```

### Fix 2: Update ontrack Handler to Handle Track Replacements

**Current Code (Likely)**:
```javascript
peerConnection.ontrack = (event) => {
  console.log('Received track:', event.track.kind);
  
  // This might only set the stream once
  if (event.streams && event.streams[0]) {
    remoteVideo.srcObject = event.streams[0];
  }
};
```

**Fixed Code**:
```javascript
let currentStreamId = null;

peerConnection.ontrack = (event) => {
  console.log('📥 Received track:', {
    kind: event.track.kind,
    trackId: event.track.id,
    streamId: event.streams[0]?.id,
    enabled: event.track.enabled
  });
  
  if (event.streams && event.streams[0]) {
    const stream = event.streams[0];
    
    // CRITICAL: Always update the video element, even for track replacements
    if (remoteVideo.srcObject !== stream) {
      console.log('🔄 Updating video element with new stream:', stream.id);
      remoteVideo.srcObject = stream;
      
      // Force video to play (important for track replacements)
      remoteVideo.play().catch(e => console.warn('Play failed:', e));
    }
    
    // Track stream changes for screen share detection
    if (currentStreamId && currentStreamId !== stream.id) {
      console.log('🖥️ Stream changed - likely screen share');
    }
    currentStreamId = stream.id;
    
    // Listen for track ended
    event.track.onended = () => {
      console.log('📴 Track ended:', event.track.kind);
    };
  }
};
```

### Fix 3: Handle Screen Share Signals

**Add these handlers**:
```javascript
socket.on('screen_share_started', (data) => {
  console.log('🖥️ Remote started screen share:', data);
  
  // Update UI to show screen share indicator
  showScreenShareIndicator();
  
  // Optionally adjust video element styling for screen share
  remoteVideo.style.objectFit = 'contain'; // Don't stretch screen share
});

socket.on('screen_share_stopped', (data) => {
  console.log('🎥 Remote stopped screen share:', data);
  
  // Update UI to hide screen share indicator
  hideScreenShareIndicator();
  
  // Restore video styling for camera
  remoteVideo.style.objectFit = 'cover'; // Or whatever you prefer for camera
});
```

### Fix 4: Fix Video Element Styling (CRITICAL for Stretching Issue)

The stretching issue is likely caused by incorrect CSS on the video element.

**Current CSS (Likely)**:
```css
video {
  width: 100%;
  height: 100%;
  object-fit: cover; /* This stretches screen share! */
}
```

**Fixed CSS**:
```css
video {
  width: 100%;
  height: 100%;
  object-fit: contain; /* This preserves aspect ratio */
  background-color: #000; /* Black background for letterboxing */
}

/* Or dynamically change based on screen share state */
video.camera-view {
  object-fit: cover; /* Fill for camera */
}

video.screenshare-view {
  object-fit: contain; /* Preserve aspect ratio for screen share */
}
```

**JavaScript to toggle**:
```javascript
socket.on('screen_share_started', (data) => {
  remoteVideo.classList.remove('camera-view');
  remoteVideo.classList.add('screenshare-view');
});

socket.on('screen_share_stopped', (data) => {
  remoteVideo.classList.remove('screenshare-view');
  remoteVideo.classList.add('camera-view');
});
```

---

## Complete Web Client Example

Here's a complete example of how the web client should handle everything:

```javascript
// WebRTC Setup
const peerConnection = new RTCPeerConnection(config);
const remoteVideo = document.getElementById('remoteVideo');
let currentStreamId = null;
let isRemoteScreenSharing = false;

// Handle incoming tracks
peerConnection.ontrack = (event) => {
  console.log('📥 Received track:', {
    kind: event.track.kind,
    trackId: event.track.id,
    streamId: event.streams[0]?.id,
    enabled: event.track.enabled
  });
  
  if (event.streams && event.streams[0]) {
    const stream = event.streams[0];
    
    // Always update video element
    if (remoteVideo.srcObject !== stream) {
      console.log('🔄 Updating video element with stream:', stream.id);
      remoteVideo.srcObject = stream;
      remoteVideo.play().catch(e => console.warn('Play failed:', e));
    }
    
    // Detect stream changes
    if (currentStreamId && currentStreamId !== stream.id) {
      console.log('🖥️ Stream changed - likely screen share');
    }
    currentStreamId = stream.id;
    
    event.track.onended = () => {
      console.log('📴 Track ended:', event.track.kind);
      if (isRemoteScreenSharing && event.track.kind === 'video') {
        isRemoteScreenSharing = false;
        updateVideoStyling();
      }
    };
  }
};

// Handle signaling
socket.on('signal', async (data) => {
  const signal = data.signal;
  
  try {
    if (signal.type === 'offer') {
      console.log('📥 Received offer:', {
        isRenegotiation: signal.renegotiate,
        reason: signal.reason,
        isScreenShare: signal.isScreenShare
      });
      
      // Set remote description
      await peerConnection.setRemoteDescription(
        new RTCSessionDescription({ type: 'offer', sdp: signal.sdp })
      );
      
      // Create and send answer
      const answer = await peerConnection.createAnswer();
      await peerConnection.setLocalDescription(answer);
      
      socket.emit('signal', {
        room: roomId,
        signal: { 
          type: 'answer', 
          sdp: answer.sdp,
          renegotiate: signal.renegotiate
        }
      });
      
      console.log('✅ Answer sent');
    }
    else if (signal.type === 'answer') {
      console.log('📥 Received answer');
      await peerConnection.setRemoteDescription(
        new RTCSessionDescription({ type: 'answer', sdp: signal.sdp })
      );
    }
    else if (signal.type === 'ice-candidate') {
      if (signal.candidate) {
        await peerConnection.addIceCandidate(
          new RTCIceCandidate({
            candidate: signal.candidate,
            sdpMid: signal.sdpMid,
            sdpMLineIndex: signal.sdpMLineIndex
          })
        );
      }
    }
  } catch (error) {
    console.error('❌ Error handling signal:', error);
  }
});

// Handle screen share signals
socket.on('screen_share_started', (data) => {
  console.log('🖥️ Remote started screen share:', data);
  isRemoteScreenSharing = true;
  updateVideoStyling();
  showScreenShareIndicator();
});

socket.on('screen_share_stopped', (data) => {
  console.log('🎥 Remote stopped screen share:', data);
  isRemoteScreenSharing = false;
  updateVideoStyling();
  hideScreenShareIndicator();
});

// Update video styling based on screen share state
function updateVideoStyling() {
  if (isRemoteScreenSharing) {
    remoteVideo.style.objectFit = 'contain'; // Preserve aspect ratio
    remoteVideo.classList.add('screenshare-view');
    remoteVideo.classList.remove('camera-view');
  } else {
    remoteVideo.style.objectFit = 'cover'; // Fill for camera
    remoteVideo.classList.add('camera-view');
    remoteVideo.classList.remove('screenshare-view');
  }
}

// UI helpers
function showScreenShareIndicator() {
  const indicator = document.getElementById('screenShareIndicator');
  if (indicator) indicator.style.display = 'block';
}

function hideScreenShareIndicator() {
  const indicator = document.getElementById('screenShareIndicator');
  if (indicator) indicator.style.display = 'none';
}
```

---

## Backend Changes (If Needed)

The Flask backend likely just relays signals, so it should work as-is. However, verify:

### Check Signal Relay

**Location**: Backend signal handler (likely in `socket_events.py` or similar)

**Should look like**:
```python
@socketio.on('signal')
def handle_signal(data):
    room = data.get('room')
    signal = data.get('signal')
    
    # Log for debugging
    if signal.get('renegotiate'):
        print(f"🔄 Relaying renegotiation: {signal.get('reason')}")
    
    # Relay signal to other users in room
    emit('signal', {
        'from': request.sid,
        'signal': signal  # Pass through ALL signal data including renegotiate flag
    }, room=room, skip_sid=request.sid)
```

**CRITICAL**: Make sure the backend is NOT filtering out the `renegotiate`, `reason`, or `isScreenShare` fields!

---

## Testing After Web Client Fix

1. **Clear browser cache** (important!)
2. **Reload web client**
3. **Start video call** from mobile to web
4. **Start screenshare** on mobile
5. **Check browser console** for:
   ```
   📥 Received offer: { isRenegotiation: true, reason: 'screen-share-started', isScreenShare: true }
   🔄 Updating video element with stream: [new-stream-id]
   🖥️ Remote started screen share: { from: '2' }
   ✅ Answer sent
   ```
6. **Verify**: Screen share displays correctly without freezing or stretching

---

## Quick Diagnosis

To confirm the web client is the issue, check browser console:

1. Open browser DevTools (F12)
2. Go to Console tab
3. Look for:
   - ✅ "Received offer" with `renegotiate: true`
   - ✅ "Answer sent"
   - ❌ Missing: "Updating video element" or "Stream changed"

If you see the offer but no video update, the web client needs the fixes above.

---

## Summary

**Mobile App**: ✅ Fixed and working correctly
**Web Client**: ❌ Needs updates to handle renegotiation and track replacements
**Backend**: ✅ Likely working (just relays signals)

The web client needs to:
1. Properly handle renegotiation offers (already partially working)
2. **Update video element when tracks change** (missing)
3. **Fix video styling to prevent stretching** (use `object-fit: contain`)
4. Handle screen share signals for UI updates

Apply the fixes above to your web client code and the screenshare should work correctly!
