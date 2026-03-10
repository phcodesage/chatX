# Quick Fix Checklist

## ✅ Mobile App (DONE)
- [x] Add renegotiation for video calls
- [x] Add renegotiation when stopping screenshare
- [x] Fix `isScreenShare` flag timing
- [x] Add stream ID tracking
- [x] Add metadata to signals

**Action**: Rebuild and install
```bash
flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

---

## ❌ Web Client (TODO)

### Fix 1: Update ontrack Handler
```javascript
peerConnection.ontrack = (event) => {
  if (event.streams && event.streams[0]) {
    const stream = event.streams[0];
    if (remoteVideo.srcObject !== stream) {
      remoteVideo.srcObject = stream;
      remoteVideo.play().catch(e => console.warn('Play failed:', e));
    }
  }
};
```

### Fix 2: Fix Video Styling
```javascript
socket.on('screen_share_started', (data) => {
  remoteVideo.style.objectFit = 'contain'; // Don't stretch!
});

socket.on('screen_share_stopped', (data) => {
  remoteVideo.style.objectFit = 'cover';
});
```

### Fix 3: Handle Renegotiation (verify existing code)
```javascript
socket.on('signal', async (data) => {
  if (data.signal.type === 'offer') {
    await peerConnection.setRemoteDescription(
      new RTCSessionDescription({ type: 'offer', sdp: data.signal.sdp })
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

---

## ✅ Backend (Should be OK)

Verify signal relay passes through all fields:
```python
@socketio.on('signal')
def handle_signal(data):
    emit('signal', {
        'from': request.sid,
        'signal': data.get('signal')  # Pass everything!
    }, room=data.get('room'), skip_sid=request.sid)
```

---

## Test Checklist

- [ ] Rebuild mobile app
- [ ] Update web client code
- [ ] Clear browser cache
- [ ] Start video call mobile → web
- [ ] Start screenshare on mobile
- [ ] Verify: No freezing
- [ ] Verify: No stretching
- [ ] Stop screenshare
- [ ] Verify: Camera resumes
- [ ] Check logs for `isScreenShare: true`

---

## Expected Result

**Before Fix:**
- ❌ Screenshare freezes on web
- ❌ Screenshare stretches on web
- ❌ `isScreenShare: false` in logs

**After Fix:**
- ✅ Screenshare displays smoothly
- ✅ Correct aspect ratio
- ✅ `isScreenShare: true` in logs

---

## Quick Diagnosis

### Mobile logs show:
```
isScreenShare: false  ← BAD (old code)
isScreenShare: true   ← GOOD (new code)
```

### Web console should show:
```
📥 Received offer: { isRenegotiation: true, isScreenShare: true }
🔄 Updating video element with stream: [id]
```

If you see the offer but no "Updating video element", web client needs Fix 1.

If screenshare displays but stretches, web client needs Fix 2.

---

## Files to Read

1. **WEB_CLIENT_FIX_REQUIRED.md** - Complete web client code
2. **FINAL_FIX_SUMMARY.md** - Overall status
3. **BUILD_AND_TEST.md** - Detailed testing

---

## TL;DR

**Mobile**: ✅ Fixed - rebuild and install
**Web**: ❌ Needs 2 fixes:
1. Update video element on track change
2. Use `object-fit: contain` for screenshare

That's it!
