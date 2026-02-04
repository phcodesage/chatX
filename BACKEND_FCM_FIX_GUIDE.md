# Fix Background Notifications - Backend Implementation Guide

## 🔴 Current Problem
Your Flutter app is properly configured for FCM, but your Flask backend only emits Socket.IO events. When the app is backgrounded, Socket.IO events won't wake it up - you need FCM push notifications.

From your logs:
```
ring_doorbell from 2 to 16
emitting doorbell to personal room user_16
```

This shows Socket.IO events are working for foreground, but no FCM push notifications are sent for background.

## 🔧 Solution Overview
Send **BOTH**:
1. **Socket.IO events** (for real-time when app is foreground)
2. **FCM push notifications** (for when app is backgrounded) ← **MISSING**

## 📋 Implementation Steps

### Step 1: Add FCM Token Field to User Model

Add this field to your User model (database):

```python
# In your User model (e.g., models.py)
class User(db.Model):
    # ... existing fields ...
    fcm_token = db.Column(db.Text, nullable=True)  # Add this field
```

**Database Migration:**
```sql
-- Run this SQL command on your database
ALTER TABLE users ADD COLUMN fcm_token TEXT;
```

### Step 2: Copy FCM Utils to Your Flask Project

Copy these files to your Flask backend directory:
- `backend_fcm_utils.py` (FCM notification functions)
- `backend_socket_integration.py` (example integration code)

### Step 3: Install Firebase Admin SDK

In your Flask project directory:
```bash
pip install firebase-admin
```

### Step 4: Verify Firebase Credentials

Make sure `firebase-credentials.json` exists in your Flask project root directory.

### Step 5: Update Your Socket Event Handlers

In your existing Flask socket handlers file, add FCM notifications:

```python
# Import FCM functions at the top of your socket handlers file
from backend_fcm_utils import (
    send_message_notification,
    send_doorbell_notification, 
    send_call_notification
)

# Example: Update your existing ring_doorbell handler
@socketio.on('ring_doorbell')
def handle_ring_doorbell(data):
    # Your existing code...
    sender_id = session.get('user_id')
    recipient_id = data.get('recipient_id')
    
    # Get users from database
    sender = User.query.get(sender_id)
    recipient = User.query.get(recipient_id)
    
    # Existing Socket.IO emit (keep this)
    socketio.emit('doorbell', {
        'sender_id': sender_id,
        'sender_name': sender.full_name,
        'recipient_id': recipient_id,
        'timestamp_ms': int(time.time() * 1000)
    }, room=f'user_{recipient_id}')
    
    # 🆕 ADD THIS: FCM push notification for background
    if recipient and recipient.fcm_token:
        send_doorbell_notification(
            fcm_token=recipient.fcm_token,
            sender_name=sender.full_name,
            sender_id=sender_id
        )
        print(f"✅ FCM doorbell notification sent to user {recipient_id}")
    else:
        print(f"⚠️ No FCM token for user {recipient_id}")
```

### Step 6: Update ALL Socket Event Handlers

Apply the same pattern to ALL your socket event handlers:
- `send_message` → add `send_message_notification()`
- `ring_doorbell` → add `send_doorbell_notification()`  
- `start_call` → add `send_call_notification()`
- Any other events → add appropriate FCM notifications

## 🧪 Testing

### Test 1: Foreground (Socket.IO)
1. Keep Flutter app open and in foreground
2. Send message/ring doorbell from another device
3. Should see real-time update (Socket.IO working)

### Test 2: Background (FCM) 
1. Put Flutter app in background or close it
2. Send message/ring doorbell from another device  
3. Should see push notification appear (FCM working)

### Test 3: Verify FCM Tokens
Check your database to ensure FCM tokens are being saved:
```sql
SELECT id, username, fcm_token FROM users WHERE fcm_token IS NOT NULL;
```

## 🔍 Debugging

### Check Firebase Admin SDK Initialization
Look for this log in your Flask startup:
```
INFO in fcm: Firebase Admin SDK initialized with service account
```

### Check FCM Token Storage
When users login, verify FCM tokens are saved to database via `/api/user/fcm-token` endpoint.

### Check FCM Sending
Look for these logs when notifications are sent:
```
✅ FCM doorbell notification sent to user 16
✅ Push notification sent: projects/your-project/messages/0:1234567890
```

## ⚠️ Common Issues

**No FCM tokens in database:**
- Ensure users login after FCM implementation
- Check `/api/user/fcm-token` endpoint is working

**Firebase credentials not found:**
- Ensure `firebase-credentials.json` is in Flask project root
- Check file permissions

**Notifications not appearing:**
- Verify Android notification channels are created (already done in Flutter)
- Check device notification settings

## ✅ Success Indicators

When working correctly, you should see both:
1. **Socket.IO logs** (existing): `emitting doorbell to personal room user_16`
2. **FCM logs** (new): `✅ Push notification sent: projects/your-project/messages/...`

The combination ensures notifications work both when app is foreground (Socket.IO) and background (FCM).

## 📁 Files to Copy to Your Flask Backend

1. **`backend_fcm_utils.py`** - Copy to your Flask project root
2. **`backend_socket_integration.py`** - Reference for updating your socket handlers
3. **Database migration** - Add `fcm_token` field to users table

After implementation, your backend will send both Socket.IO events AND FCM push notifications, ensuring users receive notifications whether the app is foreground or background - just like WhatsApp!
