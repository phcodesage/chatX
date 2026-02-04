# Backend Socket Events for Tasks & Excalidraw

Add these socket event handlers to your `socket_events.py` file to enable real-time sync between mobile and web for tasks and excalidraw features.

## Add these handlers inside `register_socket_events(socketio)`:

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
    
    message_id = data.get('message_id')
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
    
    message_id = data.get('message_id')
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
    
    message_id = data.get('message_id')
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
    
    message_id = data.get('message_id')
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
    
    message_id = data.get('message_id')
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

## Database Migration Required

Make sure your `Message` model has these fields:

```python
# In app/models/message.py
class Message(db.Model):
    # ... existing fields ...
    
    # Task fields
    is_task = db.Column(db.Boolean, default=False)
    task_created_at = db.Column(db.DateTime, nullable=True)
    task_completed_at = db.Column(db.DateTime, nullable=True)
    
    # Excalidraw fields
    is_excalidraw_link = db.Column(db.Boolean, default=False)
    excalidraw_pinned_at = db.Column(db.DateTime, nullable=True)
```

If these fields don't exist, run a migration:

```bash
flask db migrate -m "Add task and excalidraw fields to Message"
flask db upgrade
```

## Update Message.to_dict() method

Make sure the `to_dict()` method includes these fields:

```python
def to_dict(self):
    return {
        # ... existing fields ...
        'is_task': self.is_task,
        'task_created_at': self.task_created_at.isoformat() if self.task_created_at else None,
        'task_completed_at': self.task_completed_at.isoformat() if self.task_completed_at else None,
        'is_excalidraw_link': self.is_excalidraw_link,
        'excalidraw_pinned_at': self.excalidraw_pinned_at.isoformat() if self.excalidraw_pinned_at else None,
    }
```

## Testing

After adding these handlers:

1. Restart your Flask backend
2. Test from mobile: Long-press a message → "Add to Tasks"
3. Check if web client sees the task appear in real-time
4. Test completing/uncompleting tasks
5. Test pinning/unpinning excalidraw links
