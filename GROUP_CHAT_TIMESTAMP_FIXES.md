# Group Chat Timestamp Issues & Show Timestamps Feature

## Issues Addressed ✅

### 1. Show Timestamps Feature Implementation
Added the conditional timestamp display feature to match the 1-on-1 chat functionality.

#### Changes Made:

**Added to GroupMessage model (`lib/models/group.dart`):**
```dart
/// Format timestamp for full display with square brackets and timezone
/// Format: [MM/DD/YYYY, HH:MM:SS GMT+offset]
String get formattedTimestampFull {
  try {
    final dateTime = DateTime.parse(timestamp).toLocal();

    // Format date parts
    final month = dateTime.month.toString().padLeft(2, '0');
    final day = dateTime.day.toString().padLeft(2, '0');
    final year = dateTime.year;

    // Format time parts
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final second = dateTime.second.toString().padLeft(2, '0');

    // Get timezone offset
    final offset = dateTime.timeZoneOffset;
    final offsetHours = offset.inHours.abs();
    final offsetSign = offset.isNegative ? '-' : '+';

    return '[$month/$day/$year, $hour:$minute:$second GMT$offsetSign$offsetHours]';
  } catch (e) {
    debugPrint('🕐 [GROUP TIMESTAMP DEBUG] Error parsing timestamp "$timestamp": $e');
    return '';
  }
}
```

**Added to Group Chat UI (`lib/screens/group_chat_screen.dart`):**
```dart
// Full timestamp - only visible when _showTimestamps is true
if (_showTimestamps)
  Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    child: Text(
      message.formattedTimestampFull,
      style: const TextStyle(
        color: Color(0xFFFF69B4), // Hot pink
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
    ),
  ),
```

#### How It Works:
- **Toggle Button**: "Show Timestamps" / "Hide Timestamps" button in action menu
- **Conditional Display**: Full timestamps only appear when `_showTimestamps = true`
- **Format**: `[MM/DD/YYYY, HH:MM:SS GMT+offset]` in hot pink color
- **Position**: Below each message bubble, same as 1-on-1 chat

### 2. Timestamp Date Change Issue 🔍

**Problem Reported**: When leaving and rejoining group chat, outgoing message dates are changed.

**Potential Causes**:

1. **Backend Timestamp Handling**:
   - Backend might be updating timestamps when messages are re-fetched
   - Server-side timezone conversion issues
   - Database timestamp updates on query

2. **Frontend Timestamp Parsing**:
   - Client-side timezone conversion differences
   - Timestamp format inconsistencies between optimistic and real messages
   - Local vs UTC timestamp handling

3. **Message Caching Issues**:
   - Cached messages have different timestamps than fresh API responses
   - Optimistic message timestamps vs backend-confirmed timestamps

**Debug Information Added**:
The `formattedTime` method already has extensive debug logging:
```dart
debugPrint('🕐 [TIMESTAMP DEBUG] Raw timestamp: "$timestamp"');
debugPrint('🕐 [TIMESTAMP DEBUG] Parsed dateTime: $dateTime');
debugPrint('🕐 [TIMESTAMP DEBUG] Current time: $now');
debugPrint('🕐 [TIMESTAMP DEBUG] Formatted result: "$result"');
```

**Recommended Investigation Steps**:

1. **Check Backend Logs**: Look for timestamp modifications in backend when fetching messages
2. **Compare API Responses**: Check if timestamps differ between:
   - Initial message send response
   - Message list fetch response after rejoining
3. **Verify Timezone Handling**: Ensure consistent UTC/local timezone handling
4. **Check Database**: Verify if message timestamps are being updated in database

**Temporary Workaround**:
The new `formattedTimestampFull` method shows the exact timestamp with timezone info, which can help identify if the issue is:
- Backend changing timestamps
- Frontend parsing differently
- Timezone conversion problems

## Features Now Working ✅

### Show Timestamps Toggle:
- ✅ Button toggles between "Show Timestamps" and "Hide Timestamps"
- ✅ Full timestamps appear/disappear based on toggle state
- ✅ Timestamps show in hot pink color with timezone info
- ✅ Format matches 1-on-1 chat exactly: `[MM/DD/YYYY, HH:MM:SS GMT+offset]`

### Timestamp Display:
- ✅ Regular timestamps (time only) always visible on sent messages
- ✅ Full timestamps (date + time + timezone) conditionally visible
- ✅ Consistent formatting between group chat and 1-on-1 chat

## Files Modified
- `lib/models/group.dart` - Added `formattedTimestampFull` method
- `lib/screens/group_chat_screen.dart` - Added conditional timestamp display

## Next Steps for Timestamp Issue
1. Enable debug logging and check timestamp values before/after rejoining
2. Compare backend API responses for the same messages
3. Verify if the issue is backend or frontend related
4. Check if optimistic messages have different timestamps than confirmed messages