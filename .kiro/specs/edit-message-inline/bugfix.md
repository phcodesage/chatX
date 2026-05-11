# Bugfix Requirements Document

## Introduction

When a user double-taps a chat bubble for a text message they sent, the app currently opens an `AlertDialog` modal with a separate text field for editing. This is poor UX — especially for long messages — because it pulls the user out of the chat context and requires them to edit in a disconnected popup. The correct behavior (as seen in WhatsApp and similar apps) is to load the message text directly into the composer input at the bottom of the screen, so the user can edit inline without any modal interruption. This fix replaces the modal-based edit flow with an inline edit flow driven by the existing composer input.

## Bug Analysis

### Current Behavior (Defect)

1.1 WHEN the user double-taps a text message bubble they sent THEN the system opens an `AlertDialog` modal with a separate text field pre-filled with the message content

1.2 WHEN the edit modal is open THEN the system requires the user to confirm or cancel via modal action buttons before returning to the chat

1.3 WHEN the user taps "Save" in the edit modal THEN the system dismisses the modal and sends the edit, leaving the composer input unchanged and empty

### Expected Behavior (Correct)

2.1 WHEN the user double-taps a text message bubble they sent THEN the system SHALL load the message text into the composer input field, focus it, and display an "Editing" indicator above the input (similar to the existing reply preview banner) — no modal is shown

2.2 WHEN the editing indicator is visible and the user taps the "Send" button THEN the system SHALL submit the edited content as an edit to the original message and clear the editing state from the composer

2.3 WHEN the editing indicator is visible and the user taps the cancel/close button on the indicator THEN the system SHALL clear the editing state and restore the composer to its normal send mode, discarding any edits

### Unchanged Behavior (Regression Prevention)

3.1 WHEN the user double-taps a text message bubble they sent and the composer already has unsent draft text THEN the system SHALL CONTINUE TO protect that draft (prompt or preserve it) and not silently overwrite it

3.2 WHEN the user is in normal (non-editing) send mode THEN the system SHALL CONTINUE TO send new messages as before, with no change to the send flow

3.3 WHEN the user swipes a message to reply THEN the system SHALL CONTINUE TO show the reply preview banner above the composer and send a reply message, unaffected by the edit flow

3.4 WHEN the user long-presses a message to open the context menu and selects "Edit" THEN the system SHALL CONTINUE TO trigger the same inline edit flow as the double-tap (consistent behavior across both entry points)

3.5 WHEN the message being edited is not a plain text message (e.g. image, audio, file) THEN the system SHALL CONTINUE TO disallow the double-tap edit gesture, as only text messages are editable
