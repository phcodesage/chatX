# Group Chat Action Buttons & Keyboard Behavior Fix

## Issues Fixed

### 1. Action Buttons Should Only Show 4 Buttons
**Problem**: Screenshot showed that action buttons should match the 1-on-1 chat style with only essential buttons.

**Solution**: Confirmed that action buttons already contain only the correct 4 buttons:
- Ring Doorbell (purple - #8B5CF6)
- Send File (green - #10B981)
- Camera (blue - #3B82F6)
- Voice Message (red - #EF4444)

**Removed from 1-on-1 chat version**:
- ❌ Change Color (1-on-1 specific)
- ❌ Reset Color (1-on-1 specific)
- ❌ Translate: OFF (1-on-1 specific)
- ❌ Show Timestamps (moved to header menu)
- ❌ Export Chat (not needed in action buttons)
- ❌ Delete All (admin-only, not in action buttons)

### 2. Hide Action Buttons When Keyboard is Active
**Problem**: Action buttons should hide when keyboard is visible.

**Solution**: Already implemented correctly:
```dart
if (!_showEmojiPicker && MediaQuery.of(context).viewInsets.bottom == 0) ...[
  if (_showActionButtons)
    // Action buttons here
]
```

This condition ensures action buttons only show when:
- Emoji picker is closed
- Keyboard is NOT visible (`viewInsets.bottom == 0`)
- Toggle is enabled (`_showActionButtons == true`)

### 3. Tap Outside Input to Dismiss Focus
**Problem**: When input is focused, tapping outside should dismiss the keyboard.

**Solution**: Wrapped body in `GestureDetector`:
```dart
body: GestureDetector(
  onTap: () => FocusScope.of(context).unfocus(),
  behavior: HitTestBehavior.translucent,
  child: Column(
    // ... body content
  ),
),
```

## Changes Made

### 1. Added GestureDetector to Body
```dart
@override
Widget build(BuildContext context) {
  return Scaffold(
    backgroundColor: const Color(0xFF1A1A2E),
    appBar: _buildAppBar(),
    body: GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.translucent,
      child: Column(
        children: [
          // Messages list
          // Reply preview
          // Input area
        ],
      ),
    ),
  );
}
```

### 2. Action Buttons Configuration (Already Correct)
```dart
// Only 4 buttons for group chat
children: [
  // Ring Doorbell (purple)
  ElevatedButton(
    onPressed: _ringDoorbell,
    style: ElevatedButton.styleFrom(
      backgroundColor: const Color(0xFF8B5CF6),
      // ...
    ),
    child: const Text('Ring Doorbell'),
  ),
  // Send File (green)
  ElevatedButton(
    onPressed: _pickFile,
    style: ElevatedButton.styleFrom(
      backgroundColor: const Color(0xFF10B981),
      // ...
    ),
    child: const Text('Send File'),
  ),
  // Camera (blue)
  ElevatedButton(
    onPressed: _takePhoto,
    style: ElevatedButton.styleFrom(
      backgroundColor: const Color(0xFF3B82F6),
      // ...
    ),
    child: const Text('Camera'),
  ),
  // Voice Message (red)
  ElevatedButton(
    onPressed: _showVoiceRecordingModal,
    style: ElevatedButton.styleFrom(
      backgroundColor: const Color(0xFFEF4444),
      // ...
    ),
    child: const Text('Voice Message'),
  ),
],
```

## Behavior Summary

### Action Buttons Visibility Logic
✅ Show when:
- Toggle button is pressed (`_showActionButtons = true`)
- Emoji picker is closed (`!_showEmojiPicker`)
- Keyboard is hidden (`MediaQuery.of(context).viewInsets.bottom == 0`)

✅ Hide when:
- User starts typing (text is not empty)
- User focuses input field
- Keyboard appears
- Emoji picker opens
- Message is sent

### Keyboard Dismissal
✅ Tap anywhere on the message list
✅ Tap on empty space in the screen
✅ Uses `FocusScope.of(context).unfocus()`
✅ `HitTestBehavior.translucent` allows taps to pass through

### Focus Management
✅ Focus listener tracks keyboard visibility
✅ Emoji picker auto-closes when keyboard opens
✅ Action buttons hide when input is focused
✅ Proper state management for all focus changes

## Testing Checklist
- [x] Only 4 action buttons visible (Ring Doorbell, Send File, Camera, Voice Message)
- [x] Action buttons hide when keyboard appears
- [x] Action buttons hide when typing
- [x] Action buttons hide after sending message
- [x] Tap outside input dismisses keyboard
- [x] Tap on message list dismisses keyboard
- [x] Emoji picker closes when keyboard opens
- [x] Toggle button shows/hides action buttons
- [x] Action buttons hide when emoji picker opens

## Files Modified
- `lib/screens/group_chat_screen.dart`

## Notes
- Action buttons already had correct configuration (only 4 buttons)
- Keyboard visibility detection uses `MediaQuery.of(context).viewInsets.bottom`
- GestureDetector with `HitTestBehavior.translucent` allows proper tap detection
- All behavior now matches 1-on-1 chat experience
