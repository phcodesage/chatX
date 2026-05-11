# Design Document: Inline Message Editing

## Overview

Replace the `AlertDialog`-based edit flow in `ChatScreen` with an inline composer edit flow that mirrors the existing reply-preview pattern. When a user double-taps (or selects "Edit" from the context menu) on a text message they sent, the message text is loaded into the composer input, an "Editing" indicator banner appears above the input (identical in structure to the reply preview banner), and the Send button submits the edit instead of a new message. Cancelling via the banner's close button restores the composer to normal send mode.

No new files are required. All changes are confined to `lib/screens/chat_screen.dart` and `lib/screens/chat/chat_composer_panel.dart`.

---

## Architecture

The feature reuses the existing composer state machine pattern already present for reply mode. The key insight is that `_replyingToMessage` and its associated banner/clear/set helpers are a direct template for `_editingMessage`.

```
┌─────────────────────────────────────────────────────────────┐
│  _ChatScreenState                                           │
│                                                             │
│  State:                                                     │
│    Message? _editingMessage   ← NEW (mirrors _replyingTo)  │
│    Message? _replyingToMessage  (unchanged)                 │
│                                                             │
│  Entry points → _startInlineEdit(message):                  │
│    • onDoubleTap in _buildMessageBubble()                   │
│    • "Edit" in _showMessageContextMenu()                    │
│                                                             │
│  Composer panel receives:                                   │
│    replyPreview: _buildReplyPreview()   (unchanged)         │
│    editPreview:  _buildEditPreview()    ← NEW               │
│                                                             │
│  Send button → _sendMessage() checks _editingMessage first  │
└─────────────────────────────────────────────────────────────┘
```

### State transitions

```
Normal mode
  │
  ├─ double-tap / context "Edit" ──► _startInlineEdit(msg)
  │                                    • guard: draft protection
  │                                    • set _editingMessage = msg
  │                                    • populate messageController
  │                                    • requestFocus
  │
  ▼
Edit mode
  │
  ├─ tap Send ──────────────────────► _sendMessage()
  │                                    • detects _editingMessage != null
  │                                    • calls _editMessage(msg, newContent)
  │                                    • clears _editingMessage
  │                                    • clears messageController
  │
  └─ tap ✕ on banner ──────────────► _clearEdit()
                                       • clears _editingMessage
                                       • clears messageController
                                       • returns to Normal mode
```

---

## Components and Interfaces

### 1. New state field — `_editingMessage`

```dart
// In _ChatScreenState (alongside _replyingToMessage)
Message? _editingMessage;
```

### 2. `_startInlineEdit(Message message)` — replaces `_showEditMessageDialog`

```dart
void _startInlineEdit(Message message) {
  // Draft protection: if composer has unsent text, prompt before overwriting
  final draft = _messageController.text.trim();
  if (draft.isNotEmpty) {
    // Show confirmation dialog; on confirm, proceed with edit
    _confirmDiscardDraftThenEdit(message);
    return;
  }
  setState(() {
    _editingMessage = message;
    // Also clear any active reply so the two modes don't coexist
    _replyingToMessage = null;
  });
  _messageController.text = message.content;
  // Place cursor at end
  _messageController.selection = TextSelection.collapsed(
    offset: message.content.length,
  );
  _inputFocusNode.requestFocus();
}
```

### 3. `_clearEdit()` — mirrors `_clearReply()`

```dart
void _clearEdit() {
  setState(() {
    _editingMessage = null;
  });
  _messageController.clear();
}
```

### 4. `_buildEditPreview()` — mirrors `_buildReplyPreview()`

Renders the "Editing" indicator banner above the composer. Uses the same visual container style (purple left border, dark background) but with an edit icon and "Editing message" label instead of "Replying to".

```dart
Widget _buildEditPreview() {
  if (_editingMessage == null) return const SizedBox.shrink();
  final message = _editingMessage!;
  final preview = message.content.length > 50
      ? '${message.content.substring(0, 50)}...'
      : message.content;

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    margin: const EdgeInsets.only(bottom: 4),
    decoration: BoxDecoration(
      color: const Color(0xFF2D2D44),
      borderRadius: BorderRadius.circular(8),
      border: const Border(
        left: BorderSide(color: Color(0xFF7C3AED), width: 4),
      ),
    ),
    child: Row(
      children: [
        const Icon(Icons.edit_rounded, color: Color(0xFF7C3AED), size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Editing message',
                style: TextStyle(
                  color: Color(0xFF7C3AED),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                preview,
                style: TextStyle(color: Colors.grey[400], fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        GestureDetector(
          onTap: _clearEdit,
          child: Container(
            padding: const EdgeInsets.all(4),
            child: const Icon(Icons.close, color: Colors.grey, size: 18),
          ),
        ),
      ],
    ),
  );
}
```

### 5. `_sendMessage()` — modified to handle edit mode

At the top of `_sendMessage()`, before the normal send path, add an early-return branch:

```dart
Future<void> _sendMessage() async {
  // ── EDIT MODE ──────────────────────────────────────────────
  if (_editingMessage != null) {
    final editTarget = _editingMessage!;
    final newContent = _messageController.text.trim();
    if (newContent.isNotEmpty && newContent != editTarget.content) {
      _editMessage(editTarget, newContent);
    }
    _clearEdit();
    return;
  }
  // ── NORMAL SEND MODE (unchanged below) ────────────────────
  ...
}
```

### 6. `ChatComposerPanel` — add `editPreview` parameter

`ChatComposerPanel` already accepts a `replyPreview` widget that is rendered at the top of the column. Add a parallel `editPreview` parameter rendered immediately above `replyPreview` (or in the same slot — only one will be non-empty at a time).

```dart
// New parameter in ChatComposerPanel
final Widget editPreview;

// In build(), Column children:
editPreview,      // ← NEW (SizedBox.shrink() when not editing)
replyPreview,     // existing
sendToManyQuickAction,
...
```

Call site in `chat_screen.dart`:

```dart
ChatComposerPanel(
  ...
  editPreview: _buildEditPreview(),   // ← NEW
  replyPreview: _buildReplyPreview(), // existing
  ...
)
```

### 7. Entry point wiring

**Double-tap** (`_buildMessageBubble`):
```dart
onDoubleTap: canDoubleTapEdit
    ? () => _startInlineEdit(message)   // was _showEditMessageDialog
    : null,
```

**Context menu** (`_showMessageContextMenu`):
```dart
() => _startInlineEdit(message)         // was _showEditMessageDialog
```

`_showEditMessageDialog` can be removed entirely once both call sites are updated.

---

## Data Models

No data model changes. The existing `Message` model and `_editMessage()` / `_socketService.editMessage()` pipeline are reused without modification.

---

## Correctness Properties

This feature is a UI interaction replacement (modal → inline composer state). The core logic under test is the state machine governing `_editingMessage`, the draft-protection guard, and the send-path branching. These are pure in-memory state transitions that vary meaningfully with input, making property-based testing applicable for the state logic.

*A property is a characteristic or behavior that should hold true across all valid executions of a system — essentially, a formal statement about what the system should do.*

### Property 1: Edit mode populates composer with original content

*For any* text message sent by the current user, invoking `_startInlineEdit` with an empty composer SHALL result in `messageController.text` equalling the message's original content.

**Validates: Requirements 2.1**

### Property 2: Send in edit mode submits edit, not new message

*For any* active edit session, tapping Send SHALL call `_editMessage` with the edited content and SHALL NOT enqueue a new outbound message.

**Validates: Requirements 2.2**

### Property 3: Cancel restores normal mode

*For any* active edit session, invoking `_clearEdit` SHALL set `_editingMessage` to null and clear `messageController.text`, leaving the composer in normal send mode.

**Validates: Requirements 2.3**

### Property 4: Draft protection — edit does not silently overwrite non-empty draft

*For any* non-empty composer draft, invoking `_startInlineEdit` SHALL NOT silently replace the draft; it SHALL prompt the user before overwriting.

**Validates: Requirements 3.1**

### Property 5: Normal send mode is unaffected when not editing

*For any* `_sendMessage` call where `_editingMessage` is null, the message SHALL be sent as a new message through the existing send path, with no edit side-effects.

**Validates: Requirements 3.2**

### Property 6: Reply mode is unaffected by edit mode

*For any* reply session, entering edit mode SHALL clear the reply state (the two modes are mutually exclusive), and cancelling edit mode SHALL NOT restore a previously active reply.

**Validates: Requirements 3.3**

---

## Error Handling

| Scenario | Handling |
|---|---|
| User double-taps with non-empty draft | `_startInlineEdit` detects `_messageController.text.trim().isNotEmpty` and shows a confirmation dialog before overwriting |
| User edits to empty string | `_sendMessage` edit branch checks `newContent.isNotEmpty`; if empty, calls `_clearEdit()` without submitting |
| User edits to identical content | `_sendMessage` edit branch checks `newContent != editTarget.content`; if unchanged, calls `_clearEdit()` without emitting a socket event |
| Socket/network failure on edit | Handled by existing `_editMessage()` / `_socketService.editMessage()` — no change needed |
| Non-text message double-tap | `canDoubleTapEdit` guard (`messageType == 'text'`) already prevents this; no change needed |

---

## Testing Strategy

This feature does not involve infrastructure, external services, or IaC. The state transitions are pure in-memory logic, making unit tests the primary vehicle. Property-based testing is applicable for the state machine logic but would require a test harness that can drive `_ChatScreenState` methods directly (e.g., via widget tests with `WidgetTester`).

**Unit / widget tests** (example-based):
- Double-tap on own text message → edit banner appears, composer populated
- Double-tap on own text message with draft → confirmation dialog shown
- Tap ✕ on edit banner → banner dismissed, composer cleared
- Tap Send in edit mode → `_editMessage` called, banner dismissed, no new message added
- Tap Send in edit mode with unchanged content → no socket emit, banner dismissed
- Tap Send in edit mode with empty content → no socket emit, banner dismissed
- Double-tap on non-text message → no edit banner (guard respected)
- Reply flow unaffected when edit mode is not active
- Context menu "Edit" triggers same inline flow as double-tap

**Regression tests** (ensure unchanged behavior):
- Normal send flow (no `_editingMessage`) sends new message as before
- Reply preview banner still appears and functions independently
- Long-press context menu still shows "Edit" option for own text messages
