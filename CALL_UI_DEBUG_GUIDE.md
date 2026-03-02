# Call UI Disappearing Issue - Debug Guide

## Issue Description
The call UI disappears when the call connects in release builds, but works fine in debug builds.

## Root Cause Analysis
This is likely a **navigation timing issue** where the modal dismissal and ConnectedCallScreen navigation happen too quickly in optimized release builds, causing a race condition.

## Fixes Applied

### 1. **Added Navigation Delays**
- **Files Changed**: 
  - `lib/widgets/outgoing_call_modal.dart`
  - `lib/widgets/incoming_call_modal.dart`
- **Fix**: Added 100ms delay before popping modal when call connects
- **Reason**: Gives UI time to stabilize before navigation in release builds

### 2. **Enhanced Error Handling**
- **File Changed**: `lib/screens/chat_screen.dart`
- **Fix**: Added try-catch around ConnectedCallScreen navigation with debug logging
- **Reason**: Better error detection and debugging information

## Testing Steps

### Step 1: Test Call Connection
1. Open the updated app (should still be version 1.0.6)
2. Start a call from mobile to web
3. **Look for**: ConnectedCallScreen should now appear and stay visible

### Step 2: Monitor Debug Logs
Run this command while testing:
```bash
adb logcat -s flutter:V | grep -E "📞|ConnectedCallScreen|Modal result"
```

### Step 3: Test Both Directions
- Mobile → Web call
- Web → Mobile call (incoming)
- Both should show the ConnectedCallScreen properly

## Expected Log Output

**Successful Connection:**
```
📞 Call connected!
📞 Navigating to ConnectedCallScreen after modal returned: connected
📞 ConnectedCallScreen navigation completed
```

**If Still Failing:**
```
📞 Modal result: [something other than 'connected'], mounted: [true/false] - not navigating to ConnectedCallScreen
```
or
```
❌ Error navigating to ConnectedCallScreen: [error details]
```

## Additional Debug Commands

### Check Call State Transitions
```bash
adb logcat -s flutter:V | grep -E "CallState|_callState"
```

### Monitor Navigation Events
```bash
adb logcat -s flutter:V | grep -E "Navigator|Route|Modal"
```

### Full Call Flow Monitoring
```bash
adb logcat -s flutter:V | grep -E "📞|🎥|CallState|ConnectedCallScreen"
```

## Fallback Solutions

If the issue persists, we can try:

1. **Increase Delay**: Change 100ms to 200ms or 300ms
2. **Use SchedulerBinding**: Use `WidgetsBinding.instance.addPostFrameCallback`
3. **Alternative Navigation**: Use `pushReplacement` instead of `pop` + `push`
4. **State Management**: Move navigation logic to a state manager

## Technical Details

**Why This Happens in Release:**
- Release builds have aggressive optimizations
- Async operations can complete faster
- UI frame timing is different
- Navigator state changes happen more rapidly

**The Fix:**
- Small delay ensures modal is fully dismissed before new navigation
- Error handling catches any remaining edge cases
- Debug logging helps identify specific failure points

Test the updated build and let me know if the ConnectedCallScreen now appears and stays visible when the call connects!