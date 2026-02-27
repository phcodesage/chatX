# Group Chat Architecture Diagram

## 🏗️ System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         MOBILE APP (Flutter)                     │
│                          ✅ 100% Complete                        │
└─────────────────────────────────────────────────────────────────┘
                                  │
                                  │ HTTP/REST + Socket.IO
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────┐
│                      BACKEND SERVER (Flask)                      │
│                         ⚠️ Needs Implementation                  │
│                                                                   │
│  ┌─────────────────┐         ┌──────────────────┐              │
│  │   REST API      │         │   Socket.IO      │              │
│  │   /api/groups   │◄───────►│   Real-time      │              │
│  │                 │         │   Events         │              │
│  └────────┬────────┘         └────────┬─────────┘              │
│           │                           │                         │
│           └───────────┬───────────────┘                         │
│                       │                                         │
│                       ▼                                         │
│           ┌───────────────────────┐                            │
│           │   Business Logic      │                            │
│           │   - Auth checks       │                            │
│           │   - Permissions       │                            │
│           │   - Validation        │                            │
│           └───────────┬───────────┘                            │
│                       │                                         │
│                       ▼                                         │
│           ┌───────────────────────┐                            │
│           │   Database (SQLite)   │                            │
│           │   - groups            │                            │
│           │   - group_members     │                            │
│           │   - group_messages    │                            │
│           │   - message_reaction  │                            │
│           └───────────────────────┘                            │
└─────────────────────────────────────────────────────────────────┘
```

---

## 📱 Mobile App Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                           UI LAYER                               │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐         │
│  │ GroupsList   │  │ CreateGroup  │  │ GroupChat    │         │
│  │ Screen       │  │ Screen       │  │ Screen       │         │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘         │
│         │                  │                  │                 │
│         └──────────────────┼──────────────────┘                 │
│                            │                                    │
└────────────────────────────┼────────────────────────────────────┘
                             │
┌────────────────────────────┼────────────────────────────────────┐
│                      SERVICE LAYER                               │
│                            │                                    │
│  ┌─────────────────────────▼──────────────────────────┐        │
│  │           GroupService (API Calls)                  │        │
│  │  - getGroups()                                      │        │
│  │  - createGroup()                                    │        │
│  │  - sendMessage()                                    │        │
│  │  - uploadFile()                                     │        │
│  │  - addReaction()                                    │        │
│  │  - etc...                                           │        │
│  └─────────────────────────┬──────────────────────────┘        │
│                            │                                    │
│  ┌─────────────────────────▼──────────────────────────┐        │
│  │        SocketService (Real-time Events)             │        │
│  │  - Listen: group_new_message                        │        │
│  │  - Listen: group_message_sent                       │        │
│  │  - Listen: group_reaction_updated                   │        │
│  │  - Emit: join_group_chat                            │        │
│  │  - Emit: group_message_delivered                    │        │
│  │  - etc...                                           │        │
│  └─────────────────────────┬──────────────────────────┘        │
│                            │                                    │
└────────────────────────────┼────────────────────────────────────┘
                             │
┌────────────────────────────┼────────────────────────────────────┐
│                       MODEL LAYER                                │
│                            │                                    │
│  ┌─────────────┐  ┌───────▼──────┐  ┌──────────────┐          │
│  │   Group     │  │ GroupMessage │  │ GroupMember  │          │
│  │   Model     │  │    Model     │  │    Model     │          │
│  └─────────────┘  └──────────────┘  └──────────────┘          │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

---

## 🔄 Message Flow

### Sending a Message

```
User Types Message
       │
       ▼
┌──────────────────┐
│ GroupChatScreen  │
│ - Optimistic UI  │
│ - Show "sending" │
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│  GroupService    │
│  sendMessage()   │
└────────┬─────────┘
         │
         │ HTTP POST
         ▼
┌──────────────────┐
│  Backend API     │
│  /api/groups/    │
│  {id}/messages   │
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│  Save to DB      │
└────────┬─────────┘
         │
         ├─────────────────────┐
         │                     │
         ▼                     ▼
┌──────────────────┐  ┌──────────────────┐
│ Socket.IO Emit   │  │ HTTP Response    │
│ to group room    │  │ to sender        │
└────────┬─────────┘  └────────┬─────────┘
         │                     │
         │                     ▼
         │            ┌──────────────────┐
         │            │ Update UI        │
         │            │ - Show "sent" ✓  │
         │            └──────────────────┘
         │
         ▼
┌──────────────────┐
│ All Group        │
│ Members Receive  │
│ - Play sound     │
│ - Show message   │
└──────────────────┘
```

---

## 🔔 Real-time Event Flow

### Message Delivery Status

```
Device A (Sender)                    Backend                    Device B (Recipient)
      │                                 │                              │
      │ 1. Send Message                 │                              │
      ├────────────────────────────────►│                              │
      │                                 │                              │
      │ 2. Confirm Sent ✓               │                              │
      │◄────────────────────────────────┤                              │
      │                                 │                              │
      │                                 │ 3. Broadcast Message         │
      │                                 ├─────────────────────────────►│
      │                                 │                              │
      │                                 │ 4. Emit Delivered            │
      │                                 │◄─────────────────────────────┤
      │                                 │                              │
      │ 5. Update Status ✓✓             │                              │
      │◄────────────────────────────────┤                              │
      │                                 │                              │
      │                                 │ 6. User Views Message        │
      │                                 │                              │
      │                                 │ 7. Emit Viewed               │
      │                                 │◄─────────────────────────────┤
      │                                 │                              │
      │ 8. Update Status ✓✓ (green)    │                              │
      │◄────────────────────────────────┤                              │
      │                                 │                              │
```

---

## 📊 Data Flow

### Group Creation

```
┌─────────────────┐
│ User Input      │
│ - Name          │
│ - Description   │
│ - Members       │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Validation      │
│ - Name required │
│ - Min 1 member  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ API Call        │
│ POST /groups    │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Backend         │
│ - Create group  │
│ - Add creator   │
│ - Add members   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Response        │
│ - Group object  │
│ - Success       │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Update UI       │
│ - Show group    │
│ - Navigate      │
└─────────────────┘
```

---

## 🗄️ Database Schema

```
┌─────────────────────────────────────────────────────────────┐
│                          groups                              │
├─────────────────────────────────────────────────────────────┤
│ id (PK)                                                      │
│ name                                                         │
│ description                                                  │
│ created_by (FK → users.id)                                  │
│ avatar_url                                                   │
│ is_active                                                    │
│ created_at                                                   │
└────────────────────┬────────────────────────────────────────┘
                     │
                     │ 1:N
                     │
┌────────────────────▼────────────────────────────────────────┐
│                     group_members                            │
├─────────────────────────────────────────────────────────────┤
│ id (PK)                                                      │
│ group_id (FK → groups.id)                                   │
│ user_id (FK → users.id)                                     │
│ role (admin/member)                                          │
│ joined_at                                                    │
│ is_muted                                                     │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                     group_messages                           │
├─────────────────────────────────────────────────────────────┤
│ id (PK)                                                      │
│ group_id (FK → groups.id)                                   │
│ sender_id (FK → users.id)                                   │
│ content                                                      │
│ message_type                                                 │
│ timestamp                                                    │
│ is_deleted                                                   │
│ file_url                                                     │
│ file_name                                                    │
│ file_size                                                    │
│ file_type                                                    │
│ reply_to_id (FK → group_messages.id)                        │
└────────────────────┬────────────────────────────────────────┘
                     │
                     │ 1:N
                     │
┌────────────────────▼────────────────────────────────────────┐
│                   message_reaction                           │
├─────────────────────────────────────────────────────────────┤
│ id (PK)                                                      │
│ message_id (FK → group_messages.id)                         │
│ user_id (FK → users.id)                                     │
│ emoji                                                        │
│ is_group_message (NEW)                                       │
│ created_at                                                   │
└─────────────────────────────────────────────────────────────┘
```

---

## 🔐 Security Flow

```
┌─────────────────┐
│ Mobile App      │
│ - JWT Token     │
└────────┬────────┘
         │
         │ Authorization: Bearer <token>
         │
         ▼
┌─────────────────┐
│ Backend API     │
│ @jwt_required() │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Verify Token    │
│ - Valid?        │
│ - Expired?      │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Get User ID     │
│ from token      │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Check           │
│ Membership      │
│ - Is member?    │
│ - Is admin?     │
└────────┬────────┘
         │
         ├─── Yes ──►┌─────────────────┐
         │           │ Allow Access    │
         │           └─────────────────┘
         │
         └─── No ───►┌─────────────────┐
                     │ 403 Forbidden   │
                     └─────────────────┘
```

---

## 🎯 Component Interaction

```
┌──────────────────────────────────────────────────────────────┐
│                      User Interface                           │
│                                                                │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐             │
│  │  Groups    │  │  Create    │  │  Group     │             │
│  │  List      │─►│  Group     │─►│  Chat      │             │
│  └────────────┘  └────────────┘  └──────┬─────┘             │
│                                          │                    │
└──────────────────────────────────────────┼────────────────────┘
                                           │
                                           │ Uses
                                           │
┌──────────────────────────────────────────▼────────────────────┐
│                      Services Layer                            │
│                                                                │
│  ┌────────────────────────────────────────────────┐           │
│  │           GroupService                          │           │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐    │           │
│  │  │   API    │  │  Socket  │  │ Storage  │    │           │
│  │  │  Calls   │  │   I/O    │  │  Cache   │    │           │
│  │  └──────────┘  └──────────┘  └──────────┘    │           │
│  └────────────────────────────────────────────────┘           │
│                                                                │
└────────────────────────────────────────────────────────────────┘
                                           │
                                           │ Manages
                                           │
┌──────────────────────────────────────────▼────────────────────┐
│                      Data Models                               │
│                                                                │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐     │
│  │  Group   │  │ Message  │  │  Member  │  │  Sender  │     │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘     │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

---

## 📈 Scalability Considerations

```
┌─────────────────────────────────────────────────────────────┐
│                    Current Architecture                      │
│                    (Single Server)                           │
│                                                              │
│  ┌──────────┐         ┌──────────┐                         │
│  │  Mobile  │────────►│  Backend │                         │
│  │   App    │◄────────│  Server  │                         │
│  └──────────┘         └─────┬────┘                         │
│                             │                               │
│                             ▼                               │
│                      ┌──────────┐                          │
│                      │ Database │                          │
│                      └──────────┘                          │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                    Future Architecture                       │
│                    (Scalable)                                │
│                                                              │
│  ┌──────────┐         ┌──────────────┐                     │
│  │  Mobile  │────────►│ Load         │                     │
│  │   App    │◄────────│ Balancer     │                     │
│  └──────────┘         └──────┬───────┘                     │
│                              │                              │
│                    ┌─────────┼─────────┐                   │
│                    │         │         │                   │
│              ┌─────▼───┐ ┌──▼────┐ ┌──▼────┐             │
│              │ Server  │ │Server │ │Server │             │
│              │    1    │ │   2   │ │   3   │             │
│              └────┬────┘ └───┬───┘ └───┬───┘             │
│                   │          │         │                  │
│                   └──────────┼─────────┘                  │
│                              │                            │
│                    ┌─────────▼─────────┐                 │
│                    │   Redis (Cache)   │                 │
│                    └─────────┬─────────┘                 │
│                              │                            │
│                    ┌─────────▼─────────┐                 │
│                    │  Database Cluster │                 │
│                    └───────────────────┘                 │
└─────────────────────────────────────────────────────────────┘
```

---

## 🎨 UI Component Hierarchy

```
GroupChatScreen
├── AppBar
│   ├── Back Button
│   ├── Group Name
│   ├── Member Count
│   └── Actions
│       ├── Doorbell Button
│       └── Menu Button
├── Message List
│   └── ListView.builder
│       └── For each message:
│           ├── Sender Name (if not me)
│           ├── Message Bubble
│           │   ├── Reply Preview (if reply)
│           │   ├── Content
│           │   │   ├── Text
│           │   │   ├── Image
│           │   │   ├── File
│           │   │   └── Voice
│           │   ├── Reactions Row
│           │   └── Timestamp + Status
│           └── Long Press Menu
│               ├── Reply
│               ├── Edit (if mine)
│               ├── Delete (if mine/admin)
│               └── React
├── Reply Banner (if replying)
│   ├── Original Message Preview
│   └── Cancel Button
├── Input Area
│   ├── Action Buttons
│   │   ├── Camera
│   │   ├── Gallery
│   │   └── Files
│   ├── Text Input
│   └── Send Button
└── Scroll to Bottom FAB
```

---

This architecture provides a clear, scalable foundation for the group chat feature with clean separation of concerns and room for future enhancements.
