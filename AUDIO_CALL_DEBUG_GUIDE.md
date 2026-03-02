# Audio Call UI Debug Guide - Release Build Issue

## Issue Summary
- **Video calls**: Work fine, ConnectedCallScreen appears and stays visible
- **Audio calls**: UI disappears when call connects in release builds
- **Debug builds**: Both audio and video calls work fine

## Enhanced Debugging Added

### 1. **Call Type Logging**
- Added call type to all navigation debug messages
- OutgoingCallModal now logs state changes with call type
- ConnectedCallScreen logs initialization with call type

### 2. **Specific Debug Points**
- Modal state transitions for audio vs video
- Navigation attempts with call type context
- ConnectedCallScreen initialization success/failure

## Testing Steps

### Step 1: Reconnect Device and Install
```bash
# Reconnect your device via wireless ADB or USB
adb connect 192.168.0.101:5555

# Install the updated build with enhanced debugging
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

### Step 2: Test Audio Call with Logging
```bash
# Start logging before making the call
adb logcat -c  # Clear logs
adb logcat -s flutter:V > audio_call_debug.log &

# Make an audio call from mobile to web
# Then stop logging and check the output
```

### Step 3: Compare Video vs Audio Logs
1. Make a **video call** (working) and capture logs
2. Make an **audio call** (broken) and capture logs
3. Compare the differences

## Expected Log Patterns

### **Successful Video Call:**
```
📞 OutgoingCallModal: Call state changed to connected for video call
📞 OutgoingCallModal: Call connected, popping modal for video call
📞 Navigating to ConnectedCallScreen after modal returned: connected (callType: video)
📞 ConnectedCallScreen: Initializing for video call with [Name]
📞 ConnectedCallScreen navigation completed for video call
```

### **Broken Audio Call (Expected):**
```
📞 OutgoingCallModal: Call state changed to connected for audio call
📞 OutgoingCallModal: Call connected, popping modal for audio call
📞 Modal result: [something other than 'connected'], mounted: true, callType: audio - not navigating to ConnectedCallScreen
```

**OR**

```
📞 Navigating to ConnectedCallScreen after modal returned: connected (callType: audio)
❌ Error navigating to ConnectedCallScreen for audio call: [error details]
```

## Potential Root Causes

### 1. **Modal Result Issue**
- OutgoingCallModal might not be returning 'connected' for audio calls
- Timing issue with modal dismissal for audio calls

### 2. **ConnectedCallScreen Constructor Issue**
- Audio-only streams might cause constructor to fail
- Missing video tracks could cause renderer initialization to fail

### 3. **Navigation Context Issue**
- Audio calls might take different timing path
- Context might be invalid when navigation happens

### 4. **Media Stream Issue**
- Audio-only local stream might be null or invalid
- ConnectedCallScreen might expect video tracks

## Quick Test Commands

### Monitor Call State Changes
```bash
adb logcat -s flutter:V | findstr "Call state changed"
```

### Monitor Navigation Attempts
```bash
adb logcat -s flutter:V | findstr "Navigating to ConnectedCallScreen"
```

### Monitor Modal Results
```bash
adb logcat -s flutter:V | findstr "Modal result"
```

## Next Steps Based on Logs

### If Modal Returns Wrong Result:
- Issue is in OutgoingCallModal state handling for audio calls
- Need to investigate CallState transitions for audio calls

### If Navigation Fails:
- Issue is in ConnectedCallScreen constructor for audio calls
- Need to add null safety for audio-only streams

### If No Logs Appear:
- Issue is earlier in the call flow
- Need to check call initiation for audio calls

## Manual Testing Fallback

If logging is difficult, try this manual test:

1. **Video Call Test**: Start video call, verify ConnectedCallScreen appears
2. **Audio Call Test**: Start audio call, note exactly when UI disappears:
   - During "Calling..." phase?
   - During "Ringing..." phase?
   - Right when "Connected!" appears?
   - After "Connected!" shows briefly?

This timing will help pinpoint where the issue occurs in the call flow.

## Files to Check if Issue Persists

1. `lib/widgets/outgoing_call_modal.dart` - Modal state handling
2. `lib/screens/connected_call_screen.dart` - Constructor and initialization
3. `lib/services/call_service.dart` - Call state management for audio calls
4. `lib/widgets/call_setup_modal.dart` - Media constraints for audio calls

The enhanced debugging should help identify exactly where the audio call flow differs from video calls in release builds.