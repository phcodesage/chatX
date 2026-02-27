# Group Chat Input Behavior Fix

## Issues Fixed

### 1. Send Button Not Working
**Problem**: Send button wasn't properly sending messages or clearing state.

**Solution**: Updated `_sendMessage()` method to:
- Capture reply ID before clearing state
- Clear input and reply state immediately for better UX
- Hide action buttons after sending
- Properly handle async message sending
- Scroll to bottom after message is sent

### 2. Missing Input Behavior
**Problem**: Input area wasn't responding to focus changes and keyboard visibility.

**Solution**: Added proper focus and keyboard management:
- Added `_isKeyboardVisible` state variable
- Added `_onFocusChange()` method to track keyboard visibility
- Auto-close emoji picker when keyboard opens
- Hide action buttons when user starts typing
- Added focus listener in `initState()`

## Changes Made

### State Variables Added
```dart
// Keyboard visibility state
bool _isKeyboardVisible = false;
```

### Methods Added/Updated

#### 1. `initState()` - Added Focus Listener
```dart
@override
void initState() {
  super.initState();
  _inputFocusNode.addListener(_onFocusChange);  // NEW
  _scrollController.addListener(_onScroll);
  _initialize();
}
```

#### 2. `_onFocusChange()` - NEW Method
```dart
void _onFocusChange() {
  // Only update if keyboard visibility actually changed
  final isVisible = _inputFocusNode.hasFocus;
  if (_isKeyboardVisible != isVisible) {
    setState(() {
      _isKeyboardVisible = isVisible;
      // Auto-close emoji picker when keyboard opens (user tapped text field)
      if (isVisible && _showEmojiPicker) {
        _showEmojiPicker = false;
      }
    });
  }
}
```

#### 3. `_sendMessage()` - Updated
```dart
Future<void> _sendMessage() async {
  final content = _messageController.text.trim();
  if (content.isEmpty) return;

  // Capture reply info before clearing
  final replyToId = _replyingToMessage?.id;

  // Clear input and reply state immediately for better UX
  _messageController.clear();
  setState(() {
    _replyingToMessage = null;
    _showActionButtons = false; // Hide action buttons after sending
  });

  // ... rest of send logic
}
```

#### 4. TextField `onChanged` - Updated
```dart
onChanged: (text) {
  setState(() {
    // Hide action buttons when typing
    if (text.isNotEmpty && _showActionButtons) {
      _showActionButtons = false;
    }
  });
},
```

#### 5. Clear Button - Updated
```dart
onPressed: () {
  _messageController.clear();
  setState(() {
    _replyingToMessage = null;  // Also clear reply state
  });
},
```

## Behavior Now Matches 1-on-1 Chat

### Input Focus Behavior
✅ Emoji picker auto-closes when keyboard opens
✅ Action buttons hide when input is focused
✅ Action buttons hide when text is entered
✅ Keyboard visibility is tracked

### Send Behavior
✅ Message sends immediately when Send button pressed
✅ Input clears immediately after sending
✅ Reply state clears after sending
✅ Action buttons hide after sending
✅ Scrolls to bottom after sending

### Clear Behavior
✅ Clears text input
✅ Clears reply state
✅ Maintains proper UI state

### Action Buttons Behavior
✅ Toggle button shows/hides action buttons
✅ Hidden when input is focused
✅ Hidden when text is entered
✅ Hidden after sending message
✅ Only visible when emoji picker is closed and keyboard is hidden

## Testing Checklist
- [x] Send button sends messages
- [x] Input clears after sending
- [x] Reply state clears after sending
- [x] Action buttons hide when typing
- [x] Action buttons hide after sending
- [x] Emoji picker closes when keyboard opens
- [x] Clear button clears input and reply
- [x] Focus changes are tracked
- [x] Keyboard visibility is tracked

## Files Modified
- `lib/screens/group_chat_screen.dart`

## Notes
- Group chat uses normal list order (not reversed like 1-on-1 chat)
- Scroll behavior adjusted accordingly (scrolls to maxScrollExtent, not 0)
- All input behaviors now match 1-on-1 chat experience
