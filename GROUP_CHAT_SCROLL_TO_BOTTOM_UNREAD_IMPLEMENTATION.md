# Group Chat Scroll-to-Bottom Button & Unread Messages Counter

## Implementation Complete ✅

Added the scroll-to-bottom button with unread messages counter to the group chat, copying the exact UI and logic from the 1-on-1 chat.

## Features Implemented

### 1. ✅ Unread Messages Counter
- **State Variable**: `int _unreadCount = 0`
- **Increment Logic**: When new message arrives and user is not at bottom
- **Reset Logic**: When user scrolls to bottom or taps scroll button
- **Display**: Red badge on scroll button showing count (99+ for >99 messages)

### 2. ✅ Scroll-to-Bottom Button
- **Visibility**: Only shows when `!_isAtBottom` (user scrolled up)
- **Design**: Purple circular button with down arrow icon
- **Position**: Centered at bottom of messages area
- **Shadow**: Subtle drop shadow for depth
- **Animation**: Smooth scroll animation when tapped

### 3. ✅ Smart Scroll Detection
- **Threshold**: 100px from bottom (same as 1-on-1 chat)
- **Auto-hide**: Button disappears when user scrolls to bottom
- **State Management**: Updates `_isAtBottom` and resets `_unreadCount`

## Code Implementation

### State Variables Added:
```dart
// Scroll to bottom button state
bool _isAtBottom = true;
int _unreadCount = 0; // ← Added this
```

### Enhanced Scroll Listener:
```dart
void _onScroll() {
  // ... existing logic ...
  if (isAtBottom != _isAtBottom) {
    setState(() {
      _isAtBottom = isAtBottom;
      // Reset unread count when at bottom
      if (isAtBottom) {
        _unreadCount = 0; // ← Added this
      }
    });
    // ... rest of method
  }
}
```

### Unread Count Logic:
```dart
// In _handleNewMessage method
if (message.senderId != _currentUserId) {
  _playNotificationSound();
  
  // Increment unread count if not at bottom (for incoming messages)
  if (!_isAtBottom) {
    _unreadCount++; // ← Added this
  }
}
```

### Scroll-to-Bottom Method:
```dart
Future<void> _scrollToBottomAndMarkRead() async {
  if (_scrollController.hasClients) {
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  // Reset unread count
  setState(() {
    _unreadCount = 0;
    _isAtBottom = true;
  });

  // Mark messages as viewed
  _markMessagesAsViewed();
}
```

### UI Implementation:
```dart
// Messages list wrapped in Stack
Stack(
  children: [
    ListView.builder(...), // Existing messages list
    
    // Scroll to bottom button - positioned inside messages area
    if (!_isAtBottom)
      Positioned(
        bottom: 16,
        left: 0,
        right: 0,
        child: Center(
          child: GestureDetector(
            onTap: _scrollToBottomAndMarkRead,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF7C3AED), // Purple color
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Icon(
                    Icons.keyboard_arrow_down,
                    color: Colors.white,
                    size: 28,
                  ),
                  // Unread count badge
                  if (_unreadCount > 0)
                    Positioned(
                      top: 2,
                      right: 2,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 18,
                          minHeight: 18,
                        ),
                        child: Text(
                          _unreadCount > 99 ? '99+' : _unreadCount.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
  ],
)
```

## Visual Design

### Button Appearance:
- **Size**: 48x48 pixels
- **Color**: Purple (`Color(0xFF7C3AED)`) - matches 1-on-1 chat
- **Shape**: Perfect circle
- **Icon**: Down arrow (`Icons.keyboard_arrow_down`)
- **Shadow**: Subtle drop shadow for floating effect

### Unread Badge:
- **Color**: Red background, white text
- **Position**: Top-right corner of button
- **Size**: Minimum 18x18 pixels
- **Text**: Shows count (1-99) or "99+" for >99 messages
- **Font**: 10px, bold, centered

## Behavior

### When User Scrolls Up:
1. `_isAtBottom` becomes `false`
2. Scroll button appears with smooth animation
3. New messages increment `_unreadCount`
4. Badge shows on button if count > 0

### When User Taps Button:
1. Smooth scroll animation to bottom
2. `_unreadCount` resets to 0
3. `_isAtBottom` becomes `true`
4. Button disappears
5. Messages marked as viewed

### When User Scrolls to Bottom Manually:
1. `_isAtBottom` becomes `true`
2. `_unreadCount` resets to 0
3. Button disappears automatically
4. Messages marked as viewed

## Files Modified
- `lib/screens/group_chat_screen.dart` - Added scroll button, unread counter, and related logic

## Result
The group chat now has the exact same scroll-to-bottom button and unread messages functionality as the 1-on-1 chat, providing a consistent user experience across both chat types. Users can easily navigate back to the latest messages and see how many unread messages they have when scrolled up.