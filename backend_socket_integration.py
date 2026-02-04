# Integration code for your Flask Socket.IO event handlers
# Add this to your existing socket event handlers in your Flask backend

from backend_fcm_utils import (
    send_message_notification, 
    send_doorbell_notification, 
    send_call_notification,
    send_color_change_notification
)

# Example integration for your existing socket event handlers:

@socketio.on('send_message')
def handle_send_message(data):
    """Handle message sending - EXISTING CODE + FCM addition"""
    try:
        # Your existing message handling code here...
        sender_id = session.get('user_id')  # or however you get sender ID
        recipient_id = data.get('recipient_id')
        content = data.get('content')
        
        # Get sender info from database
        sender = User.query.get(sender_id)  # Adjust based on your User model
        recipient = User.query.get(recipient_id)
        
        if not sender or not recipient:
            return
            
        # Your existing Socket.IO emit (for real-time when app is foreground)
        socketio.emit('new_message', {
            'sender_id': sender_id,
            'sender_name': sender.full_name,  # Adjust field name
            'content': content,
            'timestamp': datetime.now().isoformat()
        }, room=f'user_{recipient_id}')
        
        # 🆕 NEW: Send FCM push notification (for when app is backgrounded)
        if recipient.fcm_token:  # Adjust field name based on your User model
            send_message_notification(
                fcm_token=recipient.fcm_token,
                sender_name=sender.full_name,  # Adjust field name
                message_content=content,
                sender_id=sender_id
            )
        else:
            print(f"⚠️ No FCM token for user {recipient_id}")
            
    except Exception as e:
        print(f"❌ Error in handle_send_message: {e}")

@socketio.on('ring_doorbell') 
def handle_ring_doorbell(data):
    """Handle doorbell ring - EXISTING CODE + FCM addition"""
    try:
        # Your existing doorbell handling code here...
        sender_id = session.get('user_id')  # or however you get sender ID
        recipient_id = data.get('recipient_id')
        
        # Get sender info from database  
        sender = User.query.get(sender_id)  # Adjust based on your User model
        recipient = User.query.get(recipient_id)
        
        if not sender or not recipient:
            return
            
        # Your existing Socket.IO emit (for real-time when app is foreground)
        socketio.emit('doorbell', {
            'sender_id': sender_id,
            'sender_name': sender.full_name,  # Adjust field name
            'recipient_id': recipient_id,
            'timestamp_ms': int(time.time() * 1000)
        }, room=f'user_{recipient_id}')
        
        # This matches your log: "emitting doorbell to personal room user_16"
        print(f"ring_doorbell from {sender_id} to {recipient_id}")
        print(f"emitting doorbell to personal room user_{recipient_id} {{'sender_id': {sender_id}, 'sender_name': '{sender.full_name}', 'recipient_id': {recipient_id}, 'timestamp_ms': {int(time.time() * 1000)}}}")
        
        # 🆕 NEW: Send FCM push notification (for when app is backgrounded)
        if recipient.fcm_token:  # Adjust field name based on your User model
            send_doorbell_notification(
                fcm_token=recipient.fcm_token,
                sender_name=sender.full_name,  # Adjust field name  
                sender_id=sender_id
            )
        else:
            print(f"⚠️ No FCM token for user {recipient_id}")
            
    except Exception as e:
        print(f"❌ Error in handle_ring_doorbell: {e}")

@socketio.on('start_call')
def handle_start_call(data):
    """Handle call initiation - EXISTING CODE + FCM addition"""
    try:
        # Your existing call handling code here...
        sender_id = session.get('user_id')
        recipient_id = data.get('recipient_id') 
        call_type = data.get('call_type', 'voice')  # 'voice' or 'video'
        
        # Get sender info from database
        sender = User.query.get(sender_id)
        recipient = User.query.get(recipient_id)
        
        if not sender or not recipient:
            return
            
        # Your existing Socket.IO emit (for real-time when app is foreground)
        socketio.emit('incoming_call', {
            'sender_id': sender_id,
            'sender_name': sender.full_name,
            'call_type': call_type,
            'timestamp': datetime.now().isoformat()
        }, room=f'user_{recipient_id}')
        
        # 🆕 NEW: Send FCM push notification (for when app is backgrounded)
        if recipient.fcm_token:
            send_call_notification(
                fcm_token=recipient.fcm_token,
                sender_name=sender.full_name,
                sender_id=sender_id,
                call_type=call_type
            )
        else:
            print(f"⚠️ No FCM token for user {recipient_id}")
            
    except Exception as e:
        print(f"❌ Error in handle_start_call: {e}")

@socketio.on('change_chat_color')
def handle_change_chat_color(data):
    """Handle chat color change - EXISTING CODE + FCM addition"""
    try:
        # Your existing color change handling code here...
        sender_id = session.get('user_id')
        recipient_id = data.get('recipient_id')
        color = data.get('color')
        
        # Get sender info from database
        sender = User.query.get(sender_id)
        recipient = User.query.get(recipient_id)
        
        if not sender or not recipient:
            return
            
        # Your existing Socket.IO emit (for real-time when app is foreground)
        socketio.emit('chat_color_changed', {
            'sender_id': sender_id,
            'sender_name': sender.full_name,
            'color': color,
            'timestamp': datetime.now().isoformat()
        }, room=f'user_{recipient_id}')
        
        # 🆕 NEW: Send FCM push notification (for when app is backgrounded)  
        if recipient.fcm_token:
            send_color_change_notification(
                fcm_token=recipient.fcm_token,
                sender_name=sender.full_name,
                sender_id=sender_id,
                color=color
            )
        else:
            print(f"⚠️ No FCM token for user {recipient_id}")
            
    except Exception as e:
        print(f"❌ Error in handle_change_chat_color: {e}")


# IMPORTANT SETUP NOTES:
# 1. Make sure your User model has an 'fcm_token' field to store FCM tokens
# 2. Update the field names (like 'full_name') to match your actual User model
# 3. Copy the backend_fcm_utils.py file to your Flask project directory
# 4. Install firebase-admin: pip install firebase-admin
# 5. Make sure firebase-credentials.json is in your Flask project root
# 6. Import these functions in your actual socket handlers file
