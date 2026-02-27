# Group Chat Testing Guide

## 🧪 How to Test the Group Chat Implementation

### Current Status
- ✅ Mobile app: **100% complete**
- ⚠️ Backend: **Needs implementation**

---

## 🔍 Testing Without Backend (Current State)

### What You'll See:
1. **Lobby Screen**: Groups button appears in the top right (if groups exist)
2. **Groups List**: Shows empty state with "No groups yet" message
3. **Error Handling**: App gracefully handles 404 errors from missing backend

### How to Test:
```bash
# Run the app
flutter run

# You'll see in the console:
# "Get groups error: Exception: Failed to load groups: <!doctype html>..."
# This is expected - backend endpoints don't exist yet
```

The app won't crash and will show appropriate empty states.

---

## ✅ Testing With Backend (Once Implemented)

### Prerequisites:
1. Backend server running with group endpoints
2. At least 2 user accounts created
3. Mobile app connected to backend

---

### Test Case 1: Create a Group

**Steps:**
1. Open the app and sign in
2. Tap the **Groups icon** (👥) in the top right of lobby screen
3. Tap the **+ FAB button** at bottom right
4. Enter group name: "Test Group"
5. Enter description: "Testing group chat"
6. Search and select 2-3 users
7. Tap **Create Group**

**Expected Result:**
- ✅ Success message appears
- ✅ Redirected to groups list
- ✅ New group appears in the list
- ✅ Group shows "No messages yet" as last message

**Console Logs:**
```
Creating group...
Group created successfully
```

---

### Test Case 2: Send Text Messages

**Steps:**
1. From groups list, tap on a group
2. Type "Hello everyone!" in the input field
3. Tap send button
4. Type another message: "How is everyone?"
5. Tap send

**Expected Result:**
- ✅ Messages appear immediately (optimistic UI)
- ✅ Messages show "sending..." status briefly
- ✅ Messages update to show ✓ (sent)
- ✅ Sender name appears above each message
- ✅ Timestamp shows on the right

**Console Logs:**
```
Sending message: Hello everyone!
Message sent: {message_id: 123, ...}
```

---

### Test Case 3: Real-time Updates (2 Devices)

**Setup:**
- Device A: User 1 signed in
- Device B: User 2 signed in
- Both in the same group chat

**Steps:**
1. Device A: Send message "Hi from Device A"
2. Device B: Observe

**Expected Result:**
- ✅ Message appears on Device B instantly
- ✅ Notification sound plays on Device B
- ✅ Sender name shows "User 1"
- ✅ Message shows at bottom of chat

**Console Logs (Device B):**
```
📨 New group message received: {sender_id: 1, content: "Hi from Device A"}
🔔 Playing notification sound
```

---

### Test Case 4: File Upload

**Steps:**
1. Open a group chat
2. Tap the **📎 attachment button**
3. Select "Gallery"
4. Choose an image
5. Add caption: "Check this out!"
6. Send

**Expected Result:**
- ✅ Upload progress indicator appears
- ✅ Image thumbnail shows in chat
- ✅ Caption appears below image
- ✅ File type icon shows (📷 for images)
- ✅ Other members receive the image

**Console Logs:**
```
Uploading file: photo.jpg (1.2 MB)
Upload progress: 50%
Upload complete: {file_url: "https://...", message_id: 124}
```

---

### Test Case 5: Message Reactions

**Steps:**
1. Long-press on any message
2. Reaction picker appears
3. Tap 👍 emoji
4. Long-press same message again
5. Tap ❤️ emoji

**Expected Result:**
- ✅ 👍 appears below the message
- ✅ Your name shows in reaction tooltip
- ✅ ❤️ replaces 👍 (one reaction per user)
- ✅ Other members see the reaction update

**Console Logs:**
```
Adding reaction: 👍 to message 123
Reaction updated: {reactions: {"👍": ["Your Name"]}}
```

---

### Test Case 6: Reply to Message

**Steps:**
1. Long-press on a message
2. Tap "Reply"
3. Reply banner appears at top of input
4. Type "Great point!"
5. Send

**Expected Result:**
- ✅ Reply banner shows original message preview
- ✅ Sent message shows reply indicator
- ✅ Tapping reply indicator scrolls to original message
- ✅ Reply shows in thread context

---

### Test Case 7: Edit Message

**Steps:**
1. Long-press on your own message
2. Tap "Edit"
3. Change text to "Updated message"
4. Tap save/send

**Expected Result:**
- ✅ Message updates in place
- ✅ "Edited" label appears
- ✅ Other members see the update
- ✅ Timestamp remains original

**Console Logs:**
```
Editing message 123
Message edited successfully
```

---

### Test Case 8: Delete Message

**Steps:**
1. Long-press on your own message
2. Tap "Delete"
3. Confirm deletion

**Expected Result:**
- ✅ Message disappears from chat
- ✅ Shows "Message deleted" placeholder
- ✅ Other members see deletion
- ✅ Cannot be recovered

**Console Logs:**
```
Deleting message 123
Message deleted successfully
```

---

### Test Case 9: Delivery & Read Status

**Setup:**
- Device A: User 1 (sender)
- Device B: User 2 (recipient)

**Steps:**
1. Device A: Send message "Testing status"
2. Device B: App is open but not viewing chat
3. Device B: Open the group chat
4. Device B: Scroll to see the message

**Expected Result:**
- ✅ Device A sees ✓ (sent) immediately
- ✅ Device A sees ✓✓ (delivered) when Device B receives
- ✅ Device A sees ✓✓ in green (seen) when Device B views
- ✅ Status updates happen in real-time

**Console Logs (Device A):**
```
Message sent: ✓
Message delivered: ✓✓
Message seen: ✓✓ (green)
```

---

### Test Case 10: Ring Doorbell

**Steps:**
1. Open a group chat
2. Tap the **🔔 bell icon** in top right
3. Confirm doorbell

**Expected Result:**
- ✅ All group members receive notification
- ✅ Doorbell message appears in chat
- ✅ Notification sound plays for recipients
- ✅ Shows "🔔 [Your Name] rang the doorbell"

**Console Logs:**
```
Ringing doorbell for group 1
Doorbell sent successfully
```

---

### Test Case 11: Add Members

**Steps:**
1. Open group chat
2. Tap group name/header
3. Tap "Add Members"
4. Select new users
5. Tap "Add"

**Expected Result:**
- ✅ New members added to group
- ✅ Member count updates
- ✅ System message: "[User] added [New Member]"
- ✅ New members can see future messages

---

### Test Case 12: Leave Group

**Steps:**
1. Open group chat
2. Tap group name/header
3. Tap "Leave Group"
4. Confirm

**Expected Result:**
- ✅ You're removed from group
- ✅ Group disappears from your list
- ✅ Other members see "[Your Name] left"
- ✅ Cannot send messages anymore

---

### Test Case 13: Search Groups

**Steps:**
1. Open groups list
2. Type "Test" in search bar
3. Type "xyz" (non-existent)

**Expected Result:**
- ✅ Shows only matching groups
- ✅ Searches name and description
- ✅ Shows "No groups found" for no matches
- ✅ Clears search shows all groups

---

### Test Case 14: Offline Behavior

**Steps:**
1. Turn off WiFi/mobile data
2. Try to send a message
3. Turn on connectivity
4. Observe

**Expected Result:**
- ✅ Shows "Server unavailable" banner
- ✅ Message queues locally (if implemented)
- ✅ Auto-retries when online
- ✅ Shows cached groups list

---

## 🐛 Common Issues & Solutions

### Issue: Groups button doesn't appear
**Cause**: No groups exist yet
**Solution**: Create a group first, or check backend

### Issue: 404 errors in console
**Cause**: Backend endpoints not implemented
**Solution**: Implement backend (see BACKEND_GROUP_CHAT_CHECKLIST.md)

### Issue: Messages don't appear in real-time
**Cause**: Socket.IO not emitting events
**Solution**: Check backend Socket.IO implementation

### Issue: File upload fails
**Cause**: Backend upload endpoint missing or file too large
**Solution**: Check backend logs, increase upload limit

### Issue: Reactions don't work
**Cause**: Database migration not run
**Solution**: Run `migrate_message_reactions_for_groups.py`

---

## 📊 Performance Testing

### Load Test: Large Groups
1. Create group with 50+ members
2. Send 100+ messages
3. Check scroll performance
4. Check memory usage

**Expected:**
- ✅ Smooth scrolling
- ✅ Pagination works
- ✅ Memory stays under 200MB

### Load Test: File Uploads
1. Upload 10 images in sequence
2. Upload 1 large video (50MB+)
3. Check upload progress

**Expected:**
- ✅ Progress indicator accurate
- ✅ No app freeze
- ✅ Thumbnails load quickly

---

## 📝 Test Report Template

```markdown
## Group Chat Test Report

**Date**: YYYY-MM-DD
**Tester**: Your Name
**Backend Version**: v1.0.0
**Mobile App Version**: v1.0.5

### Test Results

| Test Case | Status | Notes |
|-----------|--------|-------|
| Create Group | ✅ Pass | |
| Send Messages | ✅ Pass | |
| Real-time Updates | ✅ Pass | |
| File Upload | ❌ Fail | Upload timeout |
| Reactions | ✅ Pass | |
| Reply | ✅ Pass | |
| Edit Message | ✅ Pass | |
| Delete Message | ✅ Pass | |
| Status Tracking | ⚠️ Partial | Seen status not working |
| Doorbell | ✅ Pass | |
| Add Members | ✅ Pass | |
| Leave Group | ✅ Pass | |
| Search | ✅ Pass | |
| Offline | ✅ Pass | |

### Issues Found
1. File upload times out after 30 seconds
2. Seen status not updating in real-time

### Recommendations
1. Increase upload timeout to 5 minutes
2. Check Socket.IO event for seen status
```

---

## 🎯 Acceptance Criteria

Before marking as "Done", verify:

- [ ] All 14 test cases pass
- [ ] No console errors
- [ ] Real-time updates work on 2+ devices
- [ ] File uploads work for all types
- [ ] Status tracking works (sent/delivered/seen)
- [ ] UI is responsive and smooth
- [ ] No memory leaks
- [ ] Offline mode works gracefully
- [ ] Push notifications work (if implemented)
- [ ] Backend handles 100+ concurrent users

---

## 🚀 Ready to Test!

Once the backend is implemented, follow this guide to thoroughly test all group chat features. Report any issues with detailed steps to reproduce.

Happy testing! 🎉
