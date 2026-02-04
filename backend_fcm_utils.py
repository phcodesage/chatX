import firebase_admin
from firebase_admin import credentials, messaging
import os
import logging

logger = logging.getLogger(__name__)

# Initialize Firebase Admin SDK (only once)
if not firebase_admin._apps:
    try:
        # Try to find firebase-credentials.json in various locations
        possible_paths = [
            'firebase-credentials.json',
            '../firebase-credentials.json', 
            '../../firebase-credentials.json',
            os.path.join(os.path.dirname(__file__), 'firebase-credentials.json'),
            os.path.join(os.path.dirname(__file__), '../firebase-credentials.json'),
        ]
        
        cred_path = None
        for path in possible_paths:
            if os.path.exists(path):
                cred_path = path
                break
                
        if cred_path:
            cred = credentials.Certificate(cred_path)
            firebase_admin.initialize_app(cred)
            logger.info("Firebase Admin SDK initialized with service account")
        else:
            logger.error("❌ firebase-credentials.json not found in any expected location")
    except Exception as e:
        logger.error(f"❌ Error initializing Firebase Admin SDK: {e}")

def send_push_notification(fcm_token, title, body, data=None):
    """
    Send push notification to a device
    
    Args:
        fcm_token: FCM token of the device
        title: Notification title  
        body: Notification body
        data: Additional data payload (dict)
    
    Returns:
        bool: True if successful, False otherwise
    """
    if not fcm_token:
        logger.warning("❌ No FCM token provided")
        return False
    
    try:
        message = messaging.Message(
            notification=messaging.Notification(
                title=title,
                body=body,
            ),
            data=data or {},
            token=fcm_token,
            android=messaging.AndroidConfig(
                priority='high',
                notification=messaging.AndroidNotification(
                    sound='default',
                    channel_id='chat_messages',
                    click_action='FLUTTER_NOTIFICATION_CLICK',
                ),
            ),
            apns=messaging.APNSConfig(
                payload=messaging.APNSPayload(
                    aps=messaging.Aps(
                        sound='default',
                        badge=1,
                        content_available=True,
                    ),
                ),
            ),
        )
        
        response = messaging.send(message)
        logger.info(f"✅ Push notification sent: {response}")
        return True
        
    except Exception as e:
        logger.error(f"❌ Error sending push notification: {str(e)}")
        return False

def send_message_notification(fcm_token, sender_name, message_content, sender_id):
    """Send notification for new message"""
    return send_push_notification(
        fcm_token=fcm_token,
        title=f"💬 {sender_name}",
        body=message_content[:100],  # Truncate long messages
        data={
            'type': 'message',
            'sender_id': str(sender_id),
            'sender_name': sender_name,
            'click_action': 'FLUTTER_NOTIFICATION_CLICK',
        }
    )

def send_doorbell_notification(fcm_token, sender_name, sender_id):
    """Send notification for doorbell ring"""
    return send_push_notification(
        fcm_token=fcm_token,
        title=f"🔔 {sender_name} rang your doorbell",
        body="Tap to open chat",
        data={
            'type': 'doorbell',
            'sender_id': str(sender_id),
            'sender_name': sender_name,
            'click_action': 'FLUTTER_NOTIFICATION_CLICK',
        }
    )

def send_color_change_notification(fcm_token, sender_name, sender_id, color):
    """Send notification for color change"""
    return send_push_notification(
        fcm_token=fcm_token,
        title=f"🎨 {sender_name}",
        body=f"Changed your chat color to {color}",
        data={
            'type': 'color_change',
            'sender_id': str(sender_id),
            'sender_name': sender_name,
            'color': color,
            'click_action': 'FLUTTER_NOTIFICATION_CLICK',
        }
    )

def send_call_notification(fcm_token, sender_name, sender_id, call_type="voice"):
    """Send notification for incoming call"""
    return send_push_notification(
        fcm_token=fcm_token,
        title=f"📞 {sender_name}",
        body=f"Incoming {call_type} call",
        data={
            'type': 'call',
            'sender_id': str(sender_id),
            'sender_name': sender_name,
            'call_type': call_type,
            'click_action': 'FLUTTER_NOTIFICATION_CLICK',
        }
    )
