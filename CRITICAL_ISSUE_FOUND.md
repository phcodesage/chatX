# CRITICAL ISSUE: replaceTrack() Doesn't Trigger ontrack

## The Real Problem

Looking at your logs, I found the actual issue:

### What's Happening:
1. ✅ Mobile sends renegotiation offer with `isScreenShare: true` (after our fix)
2. ✅ Web receives offer and sends answer
3. ❌ **NO `ontrack` event fires on web client**
4. ❌ Web keeps displaying old frozen frame

### Why:
**`replaceTrack()` does NOT trigger `ontrack` events!**

When you call `sender.replaceTrack(newTrack)`, it swaps the media source on the EXISTING track, but the web client's `ontrack` handler never fires because no new track is added to the peer connection.

---

## The Solution

The web client needs to listen for track changes in a different way. There are 3 approaches:

### Approach 1: Use Socket Signals (EASIEST - RECOMMENDED)

Since the mobile app already sends `screen_share_started` and `screen_share_stopped` signals, the web client should use these to know when to expect the video to change.

**Web Client Code:**
```javascript
let isRemoteScreenSharing = false;

// Listen for screen share signals
socket.on('screen_share_started', (data) => {
  console.log('🖥️ Remote started screen share');
  isRemoteScreenSharing = true;
  
  // The video track content will change, but no ontrack event fires
  // Just update UI and wait for new frames
  updateVideoStyling();
  showScreenShareIndicator();
  
  // Force video element to refresh
  if (remoteVideo.srcObject) {
    const stream = remoteVideo.srcObject;
    remoteVideo.srcObject = null;
    setTimeout(() => {
      remoteVideo.srcObject = stream;
      remoteVideo.play();
    }, 100);
  }
});

socket.on('screen_share_stopped', (data) => {
  console.log('🎥 Remote stopped screen share');
  isRemoteScreenSharing = false;
  
  // Video track content changed back to camera
  updateVideoStyling();
  hideScreenShareIndicator();
  
  // Force video element to refresh
  if (remoteVideo.srcObject) {
    const stream = remoteVideo.srcObject;
    remoteVideo.srcObject = null;
    setTimeout(() => {
      remoteVideo.srcObject = stream;
      remoteVideo.play();
    }, 100);
  }
});

function updateVideoStyling() {
  if (isRemoteScreenSharing) {
    remoteVideo.style.objectFit = 'contain'; // Don't stretch screen share
  } else {
    remoteVideo.style.objectFit = 'cover'; // Fill for camera
  }
}
```

### Approach 2: Monitor Track Properties

The existing track's properties might change when `replaceTrack()` is called.

```javascript
peerConnection.ontrack = (event) => {
  if (event.streams && event.streams[0]) {
    const stream = event.streams[0];
    const track = event.track;
    
    remoteVideo.srcObject = stream;
    remoteVideo.play();
    
    // Monitor track for changes
    let lastSettings = track.getSettings();
    
    setInterval(() => {
      const currentSettings = track.getSettings();
      
      // Check if resolution changed (screen share usually has different resolution)
      if (currentSettings.width !== lastSettings.width ||
          currentSettings.height !== lastSettings.height) {
        console.log('🔄 Track settings changed:', currentSettings);
        
        // Force refresh
        remoteVideo.srcObject = null;
        setTimeout(() => {
          remoteVideo.srcObject = stream;
          remoteVideo.play();
        }, 50);
      }
      
      lastSettings = currentSettings;
    }, 1000);
  }
};
```

### Approach 3: Use Renegotiation Signal Metadata

Use the `isScreenShare` flag from the renegotiation offer.

```javascript
socket.on('signal', async (data) => {
  const signal = data.signal;
  
  if (signal.type === 'offer') {
    console.log('📥 Received offer:', {
      isRenegotiation: signal.renegotiate,
      reason: signal.reason,
      isScreenShare: signal.isScreenShare
    });
    
    // Check if this is a screen share change
    if (signal.renegotiate && signal.reason) {
      if (signal.reason.includes('screen-share-started')) {
        console.log('🖥️ Screen share starting via renegotiation');
        isRemoteScreenSharing = true;
        updateVideoStyling();
      } else if (signal.reason.includes('screen-share-stopped')) {
        console.log('🎥 Screen share stopping via renegotiation');
        isRemoteScreenSharing = false;
        updateVideoStyling();
      }
    }
    
    await peerConnection.setRemoteDescription(
      new RTCSessionDescription({ type: 'offer', sdp: signal.sdp })
    );
    
    const answer = await peerConnection.createAnswer();
    await peerConnection.setLocalDescription(answer);
    
    socket.emit('signal', {
      room: roomId,
      signal: { type: 'answer', sdp: answer.sdp, renegotiate: signal.renegotiate }
    });
    
    // Force video refresh after renegotiation
    if (signal.renegotiate && remoteVideo.srcObject) {
      setTimeout(() => {
        const stream = remoteVideo.srcObject;
        remoteVideo.srcObject = null;
        setTimeout(() => {
          remoteVideo.srcObject = stream;
          remoteVideo.play();
        }, 100);
      }, 500);
    }
  }
});
```

---

## RECOMMENDED FIX (Combination)

Use **Approach 1 + Approach 3** together for maximum reliability:

```javascript
let isRemoteScreenSharing = false;
const remoteVideo = document.getElementById('remoteVideo');

// 1. Listen for socket signals (primary method)
socket.on('screen_share_started', (data) => {
  console.log('🖥️ Remote started screen share (socket)');
  handleScreenShareChange(true);
});

socket.on('screen_share_stopped', (data) => {
  console.log('🎥 Remote stopped screen share (socket)');
  handleScreenShareChange(false);
});

// 2. Also check renegotiation signals (backup method)
socket.on('signal', async (data) => {
  const signal = data.signal;
  
  if (signal.type === 'offer') {
    console.log('📥 Received offer:', {
      renegotiate: signal.renegotiate,
      reason: signal.reason,
      isScreenShare: signal.isScreenShare
    });
    
    // Backup detection via renegotiation
    if (signal.renegotiate && signal.reason) {
      if (signal.reason.includes('screen-share-started')) {
        handleScreenShareChange(true);
      } else if (signal.reason.includes('screen-share-stopped')) {
        handleScreenShareChange(false);
      }
    }
    
    await peerConnection.setRemoteDescription(
      new RTCSessionDescription({ type: 'offer', sdp: signal.sdp })
    );
    
    const answer = await peerConnection.createAnswer();
    await peerConnection.setLocalDescription(answer);
    
    socket.emit('signal', {
      room: roomId,
      signal: { type: 'answer', sdp: answer.sdp, renegotiate: signal.renegotiate }
    });
    
    // Force video refresh after renegotiation
    if (signal.renegotiate) {
      forceVideoRefresh();
    }
  }
});

// Handle screen share state change
function handleScreenShareChange(isSharing) {
  if (isRemoteScreenSharing === isSharing) return; // No change
  
  isRemoteScreenSharing = isSharing;
  console.log(`🔄 Screen share state: ${isSharing}`);
  
  // Update video styling
  if (isSharing) {
    remoteVideo.style.objectFit = 'contain'; // Don't stretch
    showScreenShareIndicator();
  } else {
    remoteVideo.style.objectFit = 'cover'; // Fill for camera
    hideScreenShareIndicator();
  }
  
  // Force video refresh
  forceVideoRefresh();
}

// Force video element to refresh
function forceVideoRefresh() {
  if (!remoteVideo.srcObject) return;
  
  console.log('🔄 Forcing video refresh');
  const stream = remoteVideo.srcObject;
  
  // Temporarily remove and re-add stream
  remoteVideo.srcObject = null;
  
  setTimeout(() => {
    remoteVideo.srcObject = stream;
    remoteVideo.play().catch(e => console.warn('Play failed:', e));
  }, 100);
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

## Why This Works

1. **Socket signals** tell the web client when screen share starts/stops
2. **Video refresh** forces the video element to re-render with new frames
3. **CSS changes** prevent stretching
4. **Renegotiation backup** provides redundancy if socket signals fail

The key insight is that `replaceTrack()` changes the media source but doesn't trigger `ontrack`, so we need to:
- Detect the change via signals
- Force the video element to refresh
- Update styling appropriately

---

## Testing

After applying this fix:

1. Start video call mobile → web
2. Start screenshare on mobile
3. Check web console for: `🖥️ Remote started screen share (socket)`
4. Check web console for: `🔄 Forcing video refresh`
5. Verify screenshare displays without freezing
6. Stop screenshare on mobile
7. Check web console for: `🎥 Remote stopped screen share (socket)`
8. Verify camera resumes

---

## Summary

The problem wasn't with the mobile app or the renegotiation - it was that the web client had no way to know the track content changed because `replaceTrack()` doesn't fire `ontrack` events.

The solution is to:
1. Use the existing socket signals (`screen_share_started`/`screen_share_stopped`)
2. Force the video element to refresh when these signals arrive
3. Update CSS to prevent stretching

This is a **web client-only fix** - no more mobile changes needed!
