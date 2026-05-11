# Implementation Plan: Inline Message Editing

## Overview

Replace the `AlertDialog` edit modal with an inline composer edit flow. All changes are in `chat_screen.dart` and `chat_composer_panel.dart`. The implementation follows the existing reply-preview pattern exactly.

## Tasks

- [x] 1. Add `_editingMessage` state and core edit helpers to `_ChatScreenState`
  - Declare `Message? _editingMessage;` alongside `_replyingToMessage` in the state fields
  - Implement `_clearEdit()`: sets `_editingMessage = null` and calls `_messageController.clear()`
  - Implement `_startInlineEdit(Message message)`:
    - If `_messageController.text.trim()` is non-empty, call `_confirmDiscardDraftThenEdit(message)` and return (draft protection)
    - Otherwise: `setState` to set `_editingMessage = message` and clear `_replyingToMessage`
    - Set `_messageController.text = message.content` and move cursor to end
    - Call `_inputFocusNode.requestFocus()`
  - Implement `_confirmDiscardDraftThenEdit(Message message)`: show an `AlertDialog` asking the user to confirm discarding the draft; on confirm, clear the controller and call `_startInlineEdit(message)` again
  - _Requirements: 2.1, 3.1_

- [x] 2. Implement `_buildEditPreview()` widget
  - Mirror the structure of `_buildReplyPreview()` exactly
  - Return `const SizedBox.shrink()` when `_editingMessage == null`
  - When non-null: render a `Container` with the same dark background (`0xFF2D2D44`), purple left border (`0xFF7C3AED`, width 4), and `BorderRadius.circular(8)` as the reply banner
  - Row contents: `Icons.edit_rounded` icon (purple, size 18), `SizedBox(width: 8)`, `Expanded` column with "Editing message" label (purple, 12px, w600) and truncated original content preview (grey, 13px, maxLines 1), `GestureDetector` with `Icons.close` that calls `_clearEdit`
  - _Requirements: 2.1, 2.3_

- [x] 3. Wire edit mode into `_sendMessage()`
  - At the very top of `_sendMessage()`, before any existing logic, add an edit-mode branch:
    - `if (_editingMessage != null)` → capture `editTarget = _editingMessage!`, compute `newContent = _messageController.text.trim()`
    - If `newContent.isNotEmpty && newContent != editTarget.content`: call `_editMessage(editTarget, newContent)`
    - Always call `_clearEdit()` and `return` from this branch (no new message is enqueued)
  - The remainder of `_sendMessage()` is unchanged and handles normal send mode
  - _Requirements: 2.2, 3.2_

- [x] 4. Replace `_showEditMessageDialog` call sites with `_startInlineEdit`
  - In `_buildMessageBubble()`: change `onDoubleTap` callback from `() => _showEditMessageDialog(message)` to `() => _startInlineEdit(message)`
  - In `_showMessageContextMenu()`: change the "Edit" action's `onTap` from `() => _showEditMessageDialog(message)` to `() => _startInlineEdit(message)`
  - Delete the `_showEditMessageDialog` method entirely (it is no longer referenced)
  - _Requirements: 2.1, 3.4_

- [x] 5. Add `editPreview` parameter to `ChatComposerPanel` and pass `_buildEditPreview()`
  - In `chat_composer_panel.dart`: add `required this.editPreview` (`Widget`) to the constructor and field list
  - In the `Column` children inside `build()`, insert `editPreview` as the first child (above the existing `replyPreview` child)
  - In `chat_screen.dart` at the `ChatComposerPanel(...)` call site: add `editPreview: _buildEditPreview()`
  - _Requirements: 2.1, 2.3_

- [x] 6. Checkpoint — verify the full edit flow end-to-end
  - Ensure all existing tests pass, ask the user if questions arise
  - Manually verify: double-tap own text message → banner appears, composer populated, Send submits edit, ✕ cancels
  - Manually verify: context menu "Edit" triggers same flow
  - Manually verify: reply flow is unaffected
  - Manually verify: double-tap with draft text shows confirmation dialog

- [ ]* 7. Write widget tests for the inline edit state machine
  - Test: double-tap own text message with empty composer → `_editingMessage` set, controller text equals message content
    - _Requirements: 2.1_
  - Test: `_clearEdit()` → `_editingMessage` null, controller empty
    - _Requirements: 2.3_
  - Test: `_sendMessage()` in edit mode with changed content → `_editMessage` called, `_editingMessage` cleared, no new message inserted
    - _Requirements: 2.2_
  - Test: `_sendMessage()` in edit mode with unchanged content → no socket emit, `_editingMessage` cleared
    - _Requirements: 2.2_
  - Test: `_sendMessage()` in edit mode with empty content → no socket emit, `_editingMessage` cleared
    - _Requirements: 2.2_
  - Test: double-tap with non-empty draft → confirmation dialog shown, draft not overwritten
    - _Requirements: 3.1_
  - Test: `_sendMessage()` with `_editingMessage == null` → normal send path executes, no edit side-effects
    - _Requirements: 3.2_
  - Test: entering edit mode clears `_replyingToMessage`
    - _Requirements: 3.3_
  - Test: double-tap on non-text message → `_startInlineEdit` not called (guard in `_buildMessageBubble`)
    - _Requirements: 3.5_

## Notes

- Tasks marked with `*` are optional and can be skipped for a faster fix
- `_showEditMessageDialog` is deleted in task 4 — do not leave it as dead code
- Edit mode and reply mode are mutually exclusive: `_startInlineEdit` clears `_replyingToMessage`, and `_setReplyTo` does not need to clear `_editingMessage` (reply is only triggered by swipe, which is a separate gesture path)
- The `_editMessage()` method and `_socketService.editMessage()` are unchanged — only the entry point changes
