# Screen Sharing UI Debug Guide - Release vs Debug

## What We've Done

1. **Updated Version**: App is now version 1.0.6+6
2. **Added Proguard Rules**: Created `android/app/proguard-rules.pro` to prevent WebRTC class obfuscation
3. **Enabled Minification**: Updated `build.gradle.kts` to use proguard in release builds
4. **Installed Updated APK**: The new release build is now on your device

## Potential Causes of Screen Sharing UI Issues in Release

### 1. **Code Obfuscation (FIXED)**
- **Issue**: WebRTC classes getting obfuscated in release builds
- **Fix Applied**: Added proguard rules to preserve WebRTC classes
- **Files Changed**: 
  - `android/app/proguard-rules.pro` (new)
  - `android/app/build.gradle.kts` (updated)

### 2. **Debug Logging Differences**
- **Issue**: `debugPrint()` statements don't show in release builds
- **Impact**: Harder to track screen sharing state changes
- **Solution**: Use `adb logcat` to see native Android logs

### 3. **Performance Differences**
- **Issue**: Release builds are more optimized, timing-sensitive code may behave differently
- **Potential Areas**: 
  - WebRTC track replacement timing
  - UI state updates during screen share transitions
  - MediaProjection service lifecycle

## Testing Steps

### Step 1: Basic Screen Sharing Test
1. Open the app (version 1.0.6 should show in settings)
2. Start a call between mobile and web
3. Try screen sharing from mobile to web
4. **Look for**: UI breaking, video not displaying, controls not responding

### Step 2: Monitor Logs During Screen Share
Run this command while testing:
```bash
adb logcat -s flutter:V MainActivity:V WebRTC:V MediaProjection:V
```

### Step 3: Compare Behavior
Test the same scenario in debug mode:
```bash
flutter run --debug
```

## Key Areas to Check

### UI State Management
- **File**: `lib/screens/connected_call_screen.dart`
- **Lines**: 183-195 (screen share state handling)
- **Look for**: State not updating properly, UI elements not showing/hiding

### WebRTC Track Replacement
- **File**: `lib/services/call_service.dart`
- **Lines**: 1008-1110 (screen share implementation)
- **Look for**: Track replacement failures, stream disposal issues

### Foreground Service
- **File**: `android/app/src/main/java/com/cloudwebrtc/webrtc/FlutterWebRTCForegroundService.java`
- **Look for**: Service not starting/stopping properly

## Common Release Build Issues

1. **Null Safety**: Release builds are stricter about null checks
2. **Async Timing**: Optimizations can change async operation timing
3. **Memory Management**: More aggressive garbage collection
4. **Native Bridge**: Method channel calls may behave differently

## Debug Commands

### Check App Version
```bash
adb shell dumpsys package com.example.flutter_messenger_v2 | grep versionName
```

### Monitor Screen Share Service
```bash
adb logcat -s FlutterWebRTCForegroundService:V
```

### Check WebRTC Logs
```bash
adb logcat -s org.webrtc:V
```

## Next Steps

1. **Test the updated release build** with the proguard fixes
2. **Compare behavior** between debug and release modes
3. **Capture logs** during the UI breaking scenario
4. **Report specific symptoms**: What exactly breaks in the UI?

The proguard rules should fix the most common cause of WebRTC issues in release builds. If the problem persists, we'll need to investigate the specific UI behavior differences.