# Task & Excalidraw Socket Event Handlers

Add these handlers to `app/utils/socket_events.py` after the `edit_message` handler (around line 755).

```python
@socketio.on('add_task')
def handle_add_task(data):
    """Handle adding a message as a task.
    Expects: { message_id: number }
    Emits: 'task_added' => { message_id, task_created_at }
    """
    user = get_authenticated_user()
    if not user:
        return
    
    message_id = data.get('message_id') if isinstance(data, dict) else None
    if not message_id:
        emit('error', {'message': 'message_id is required'})
        return
    
    msg = Message.query.get(message_id)
    if not msg:
        return
    
    # Only participants can add tasks
    if user.id not in (msg.sender_id, msg.recipient_id):
        emit('error', {'message': 'Permission denied'})
        return
    
    try:
        from datetime import datetime
        msg.is_task = True
        msg.task_created_at = datetime.utcnow()
        db.session.commit()
        
        payload = {
            'message_id': msg.id,
            'task_created_at': msg.task_created_at.isoformat() if msg.task_created_at else None
        }
        
        # Notify both participants
        emit('task_added', payload, room=f"user_{msg.sender_id}")
        emit('task_added', payload, room=f"user_{msg.recipient_id}")
        
        print(f"[TASK] Message {message_id} added as task by {user.username}")
    except Exception as e:
        db.session.rollback()
        emit('error', {'message': 'Failed to add task'})
        print(f"[ERROR] Failed to add task: {e}")


@socketio.on('complete_task')
def handle_complete_task(data):
    """Handle completing a task.
    Expects: { message_id: number }
    Emits: 'task_completed' => { message_id, completed_at }
    """
    user = get_authenticated_user()
    if not user:
        return
    
    message_id = data.get('message_id') if isinstance(data, dict) else None
    if not message_id:
        emit('error', {'message': 'message_id is required'})
        return
    
    msg = Message.query.get(message_id)
    if not msg:
        return
    
    # Only participants can complete tasks
    if user.id not in (msg.sender_id, msg.recipient_id):
        emit('error', {'message': 'Permission denied'})
        return
    
    if not msg.is_task:
        emit('error', {'message': 'Message is not a task'})
        return
    
    try:
        from datetime import datetime
        msg.task_completed_at = datetime.utcnow()
        db.session.commit()
        
        payload = {
            'message_id': msg.id,
            'completed_at': msg.task_completed_at.isoformat() if msg.task_completed_at else None
        }
        
        # Notify both participants
        emit('task_completed', payload, room=f"user_{msg.sender_id}")
        emit('task_completed', payload, room=f"user_{msg.recipient_id}")
        
        print(f"[TASK] Task {message_id} completed by {user.username}")
    except Exception as e:
        db.session.rollback()
        emit('error', {'message': 'Failed to complete task'})
        print(f"[ERROR] Failed to complete task: {e}")


@socketio.on('uncomplete_task')
def handle_uncomplete_task(data):
    """Handle uncompleting a task.
    Expects: { message_id: number }
    Emits: 'task_uncompleted' => { message_id }
    """
    user = get_authenticated_user()
    if not user:
        return
    
    message_id = data.get('message_id') if isinstance(data, dict) else None
    if not message_id:
        emit('error', {'message': 'message_id is required'})
        return
    
    msg = Message.query.get(message_id)
    if not msg:
        return
    
    # Only participants can uncomplete tasks
    if user.id not in (msg.sender_id, msg.recipient_id):
        emit('error', {'message': 'Permission denied'})
        return
    
    if not msg.is_task:
        emit('error', {'message': 'Message is not a task'})
        return
    
    try:
        msg.task_completed_at = None
        db.session.commit()
        
        payload = {'message_id': msg.id}
        
        # Notify both participants
        emit('task_uncompleted', payload, room=f"user_{msg.sender_id}")
        emit('task_uncompleted', payload, room=f"user_{msg.recipient_id}")
        
        print(f"[TASK] Task {message_id} uncompleted by {user.username}")
    except Exception as e:
        db.session.rollback()
        emit('error', {'message': 'Failed to uncomplete task'})
        print(f"[ERROR] Failed to uncomplete task: {e}")


@socketio.on('pin_excalidraw')
def handle_pin_excalidraw(data):
    """Handle pinning an excalidraw link.
    Expects: { message_id: number }
    Emits: 'excalidraw_pinned' => { message_id, pinned_at }
    """
    user = get_authenticated_user()
    if not user:
        return
    
    message_id = data.get('message_id') if isinstance(data, dict) else None
    if not message_id:
        emit('error', {'message': 'message_id is required'})
        return
    
    msg = Message.query.get(message_id)
    if not msg:
        return
    
    # Only participants can pin excalidraw
    if user.id not in (msg.sender_id, msg.recipient_id):
        emit('error', {'message': 'Permission denied'})
        return
    
    try:
        from datetime import datetime
        msg.is_excalidraw_link = True
        msg.excalidraw_pinned_at = datetime.utcnow()
        db.session.commit()
        
        payload = {
            'message_id': msg.id,
            'pinned_at': msg.excalidraw_pinned_at.isoformat() if msg.excalidraw_pinned_at else None
        }
        
        # Notify both participants
        emit('excalidraw_pinned', payload, room=f"user_{msg.sender_id}")
        emit('excalidraw_pinned', payload, room=f"user_{msg.recipient_id}")
        
        print(f"[EXCALIDRAW] Message {message_id} pinned by {user.username}")
    except Exception as e:
        db.session.rollback()
        emit('error', {'message': 'Failed to pin excalidraw'})
        print(f"[ERROR] Failed to pin excalidraw: {e}")


@socketio.on('unpin_excalidraw')
def handle_unpin_excalidraw(data):
    """Handle unpinning an excalidraw link.
    Expects: { message_id: number }
    Emits: 'excalidraw_unpinned' => { message_id }
    """
    user = get_authenticated_user()
    if not user:
        return
    
    message_id = data.get('message_id') if isinstance(data, dict) else None
    if not message_id:
        emit('error', {'message': 'message_id is required'})
        return
    
    msg = Message.query.get(message_id)
    if not msg:
        return
    
    # Only participants can unpin excalidraw
    if user.id not in (msg.sender_id, msg.recipient_id):
        emit('error', {'message': 'Permission denied'})
        return
    
    try:
        msg.excalidraw_pinned_at = None
        db.session.commit()
        
        payload = {'message_id': msg.id}
        
        # Notify both participants
        emit('excalidraw_unpinned', payload, room=f"user_{msg.sender_id}")
        emit('excalidraw_unpinned', payload, room=f"user_{msg.recipient_id}")
        
        print(f"[EXCALIDRAW] Message {message_id} unpinned by {user.username}")
    except Exception as e:
        db.session.rollback()
        emit('error', {'message': 'Failed to unpin excalidraw'})
        print(f"[ERROR] Failed to unpin excalidraw: {e}")
```

## Required Imports

Make sure these imports are at the top of `socket_events.py`:

```python
from flask import request
from flask_login import current_user
from flask_socketio import emit, join_room, leave_room, disconnect
from app import db
from app.models.user import User
from app.models.message import Message
from app.models.call import Call
from app.models.message_reaction import MessageReaction
from app.utils.socket_auth import get_authenticated_user
```

## After Adding

Restart the Flask backend server to apply the changes.
