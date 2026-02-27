# Backend Group Chat Implementation Checklist

## 🎯 Quick Start Guide for Backend Team

This checklist will help you implement the group chat backend to work with the already-completed mobile app.

---

## ✅ Step 1: Database Setup

### Run Migration Script
```bash
cd backend
python scripts/migrate_message_reactions_for_groups.py
```

This adds:
- `is_group_message` column to `message_reaction` table
- `emoji` column for reactions
- Migrates existing reaction data
- Creates performance indexes

### Verify Tables Exist
```sql
-- Check these tables exist:
SELECT * FROM groups LIMIT 1;
SELECT * FROM group_members LIMIT 1;
SELECT * FROM group_messages LIMIT 1;
SELECT * FROM message_reaction LIMIT 1;
```

---

## ✅ Step 2: REST API Endpoints

Create a new file: `backend/routes/groups.py`

### Group Management Endpoints

```python
from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_jwt_identity
from models import db, Group, GroupMember, GroupMessage, User

groups_bp = Blueprint('groups', __name__)

@groups_bp.route('/api/groups', methods=['GET'])
@jwt_required()
def get_groups():
    """List all groups the current user belongs to"""
    current_user_id = get_jwt_identity()
    
    # Get groups where user is a member
    groups = db.session.query(Group).join(GroupMember).filter(
        GroupMember.user_id == current_user_id,
        Group.is_active == True
    ).all()
    
    return jsonify({
        'groups': [group.to_dict() for group in groups]
    })

@groups_bp.route('/api/groups', methods=['POST'])
@jwt_required()
def create_group():
    """Create a new group"""
    current_user_id = get_jwt_identity()
    data = request.get_json()
    
    # Validate input
    if not data.get('name'):
        return jsonify({'error': 'Group name is required'}), 400
    
    # Create group
    group = Group(
        name=data['name'],
        description=data.get('description'),
        created_by=current_user_id
    )
    db.session.add(group)
    db.session.flush()
    
    # Add creator as admin
    creator_member = GroupMember(
        group_id=group.id,
        user_id=current_user_id,
        role='admin'
    )
    db.session.add(creator_member)
    
    # Add other members
    for user_id in data.get('member_ids', []):
        if user_id != current_user_id:
            member = GroupMember(
                group_id=group.id,
                user_id=user_id,
                role='member'
            )
            db.session.add(member)
    
    db.session.commit()
    
    return jsonify({
        'success': True,
        'data': group.to_dict()
    }), 201

@groups_bp.route('/api/groups/<int:group_id>', methods=['GET'])
@jwt_required()
def get_group_details(group_id):
    """Get group details with members"""
    current_user_id = get_jwt_identity()
    
    # Check membership
    member = GroupMember.query.filter_by(
        group_id=group_id,
        user_id=current_user_id
    ).first()
    
    if not member:
        return jsonify({'error': 'Not a member of this group'}), 403
    
    group = Group.query.get_or_404(group_id)
    
    return jsonify({
        'group': group.to_dict_with_members()
    })

@groups_bp.route('/api/groups/<int:group_id>', methods=['PUT'])
@jwt_required()
def edit_group(group_id):
    """Edit group (admin only)"""
    current_user_id = get_jwt_identity()
    
    # Check admin permission
    member = GroupMember.query.filter_by(
        group_id=group_id,
        user_id=current_user_id,
        role='admin'
    ).first()
    
    if not member:
        return jsonify({'error': 'Admin permission required'}), 403
    
    group = Group.query.get_or_404(group_id)
    data = request.get_json()
    
    if 'name' in data:
        group.name = data['name']
    if 'description' in data:
        group.description = data['description']
    if 'avatar_url' in data:
        group.avatar_url = data['avatar_url']
    
    db.session.commit()
    
    return jsonify({
        'success': True,
        'data': group.to_dict()
    })

# Add more endpoints following the same pattern...
```

### Message Endpoints

```python
@groups_bp.route('/api/groups/<int:group_id>/messages', methods=['GET'])
@jwt_required()
def get_group_messages(group_id):
    """Get messages for a group"""
    current_user_id = get_jwt_identity()
    
    # Check membership
    member = GroupMember.query.filter_by(
        group_id=group_id,
        user_id=current_user_id
    ).first()
    
    if not member:
        return jsonify({'error': 'Not a member of this group'}), 403
    
    limit = request.args.get('limit', 50, type=int)
    before_id = request.args.get('before_id', type=int)
    
    query = GroupMessage.query.filter_by(group_id=group_id)
    
    if before_id:
        query = query.filter(GroupMessage.id < before_id)
    
    messages = query.order_by(GroupMessage.id.desc()).limit(limit).all()
    
    return jsonify({
        'messages': [msg.to_dict() for msg in messages]
    })

@groups_bp.route('/api/groups/<int:group_id>/messages', methods=['POST'])
@jwt_required()
def send_group_message(group_id):
    """Send a message to the group"""
    current_user_id = get_jwt_identity()
    
    # Check membership
    member = GroupMember.query.filter_by(
        group_id=group_id,
        user_id=current_user_id
    ).first()
    
    if not member:
        return jsonify({'error': 'Not a member of this group'}), 403
    
    data = request.get_json()
    
    message = GroupMessage(
        group_id=group_id,
        sender_id=current_user_id,
        content=data['content'],
        message_type=data.get('message_type', 'text'),
        reply_to_id=data.get('reply_to_id')
    )
    
    db.session.add(message)
    db.session.commit()
    
    # Emit Socket.IO event
    from app import socketio
    socketio.emit('group_new_message', 
                  message.to_dict(), 
                  room=f'group_{group_id}')
    
    return jsonify({
        'success': True,
        'data': message.to_dict()
    }), 201

# Continue with other message endpoints...
```

---

## ✅ Step 3: Socket.IO Integration

### Add Group Room Management

```python
# In your socket.io handlers file

@socketio.on('join_group_chat')
def handle_join_group_chat(data):
    """Join a group chat room"""
    group_id = data.get('group_id')
    user_id = get_jwt_identity()
    
    # Verify membership
    member = GroupMember.query.filter_by(
        group_id=group_id,
        user_id=user_id
    ).first()
    
    if member:
        join_room(f'group_{group_id}')
        emit('joined_group_chat', {'group_id': group_id})

@socketio.on('leave_group_chat')
def handle_leave_group_chat(data):
    """Leave a group chat room"""
    group_id = data.get('group_id')
    leave_room(f'group_{group_id}')
    emit('left_group_chat', {'group_id': group_id})

@socketio.on('group_message_delivered')
def handle_group_message_delivered(data):
    """Mark message as delivered"""
    message_id = data.get('message_id')
    group_id = data.get('group_id')
    user_id = get_jwt_identity()
    
    # Update delivery status in database
    # ...
    
    # Notify sender
    emit('message_status_updated', {
        'message_id': message_id,
        'status': 'delivered',
        'delivered_by': user_id
    }, room=f'group_{group_id}')

@socketio.on('group_messages_viewed')
def handle_group_messages_viewed(data):
    """Mark messages as viewed"""
    message_ids = data.get('message_ids', [])
    group_id = data.get('group_id')
    user_id = get_jwt_identity()
    
    # Update viewed status in database
    # ...
    
    # Notify senders
    emit('message_status_updated', {
        'message_ids': message_ids,
        'status': 'seen',
        'seen_by': user_id
    }, room=f'group_{group_id}')
```

---

## ✅ Step 4: Register Routes

In your main `app.py` or `__init__.py`:

```python
from routes.groups import groups_bp

app.register_blueprint(groups_bp)
```

---

## ✅ Step 5: Test Endpoints

### Using curl:

```bash
# Login first to get token
TOKEN="your_jwt_token"

# List groups
curl -H "Authorization: Bearer $TOKEN" \
     http://localhost:5000/api/groups

# Create group
curl -X POST \
     -H "Authorization: Bearer $TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"name":"Test Group","member_ids":[2,3]}' \
     http://localhost:5000/api/groups

# Get messages
curl -H "Authorization: Bearer $TOKEN" \
     http://localhost:5000/api/groups/1/messages

# Send message
curl -X POST \
     -H "Authorization: Bearer $TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"content":"Hello group!","message_type":"text"}' \
     http://localhost:5000/api/groups/1/messages
```

---

## ✅ Step 6: Deploy

1. Test locally first
2. Run migration on staging database
3. Deploy backend code
4. Test with mobile app
5. Deploy to production

---

## 📋 Complete Endpoint List

Copy this checklist and mark off as you implement:

### Group Management
- [ ] `GET /api/groups` - List groups
- [ ] `POST /api/groups` - Create group
- [ ] `GET /api/groups/{id}` - Get details
- [ ] `PUT /api/groups/{id}` - Edit group
- [ ] `POST /api/groups/{id}/members` - Add members
- [ ] `DELETE /api/groups/{id}/members/{user_id}` - Remove member
- [ ] `POST /api/groups/{id}/leave` - Leave group

### Messaging
- [ ] `GET /api/groups/{id}/messages` - Get messages
- [ ] `POST /api/groups/{id}/messages` - Send message
- [ ] `POST /api/groups/{id}/messages/upload` - Upload file
- [ ] `DELETE /api/groups/{id}/messages/{msg_id}` - Delete message
- [ ] `PUT /api/groups/{id}/messages/{msg_id}` - Edit message

### Status & Reactions
- [ ] `POST /api/groups/{id}/messages/{msg_id}/delivered` - Mark delivered
- [ ] `POST /api/groups/{id}/messages/viewed` - Mark viewed
- [ ] `POST /api/groups/{id}/messages/{msg_id}/reactions` - Add reaction
- [ ] `DELETE /api/groups/{id}/messages/{msg_id}/reactions` - Remove reaction

### Notifications
- [ ] `POST /api/groups/{id}/doorbell` - Ring doorbell

### Socket.IO Events
- [ ] `join_group_chat` - Join room
- [ ] `leave_group_chat` - Leave room
- [ ] `group_message_delivered` - Delivery confirmation
- [ ] `group_messages_viewed` - View confirmation
- [ ] Emit `group_new_message` on new message
- [ ] Emit `group_message_sent` to sender
- [ ] Emit `group_file_message` on file upload
- [ ] Emit `group_message_deleted` on delete
- [ ] Emit `group_message_edited` on edit
- [ ] Emit `group_reaction_updated` on reaction
- [ ] Emit `group_reaction_cleared` on reaction remove
- [ ] Emit `group_member_left` on member leave
- [ ] Emit `message_status_updated` on status change
- [ ] Emit `group_doorbell` on doorbell

---

## 🎉 Done!

Once all endpoints are implemented and tested, the mobile app will work seamlessly with full WhatsApp-like group chat functionality!

For detailed API specifications, see: `GROUP_CHAT_MOBILE_API.md`
