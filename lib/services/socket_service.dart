import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'dart:async';
import '../config/api_config.dart';
import 'auth_error_handler.dart';

/// Service for handling Socket.IO real-time communication
class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  IO.Socket? _socket;
  String? _authToken;
  int? _currentUserId;

  // Callbacks for events
  Function(Map<String, dynamic>)? onMessageReceived;
  Function(Map<String, dynamic>)? onDoorbellRing;
  Function(Map<String, dynamic>)? onUserTyping;
  Function(Map<String, dynamic>)? onTypingUpdate;
  Function(Map<String, dynamic>)? onPresenceUpdate;
  Function(Map<String, dynamic>)? onJoinedChat;
  Function(Map<String, dynamic>)? onLeftChat;
  Function(Map<String, dynamic>)? onMessageDelivered;
  Function(Map<String, dynamic>)? onMessageRead;
  Function(Map<String, dynamic>)? onColorChanged;
  Function(Map<String, dynamic>)? onColorReset;
  Function(Map<String, dynamic>)? onAllMessagesDeleted;
  Function(Map<String, dynamic>)? onFileReceived;
  Function(Map<String, dynamic>)? onMessageDeleted;
  Function(Map<String, dynamic>)? onMessageEdited;
  Function(Map<String, dynamic>)? onTaskAdded;
  Function(Map<String, dynamic>)? onTaskCompleted;
  Function(Map<String, dynamic>)? onTaskUncompleted;
  Function(Map<String, dynamic>)? onExcalidrawPinned;
  Function(Map<String, dynamic>)? onExcalidrawUnpinned;
  
  // Call-related callbacks
  Function(Map<String, dynamic>)? onIncomingCall;
  Function(Map<String, dynamic>)? onCrossRoomCallOffer; // For web client calls
  Function(Map<String, dynamic>)? onCallInitiated;
  Function(Map<String, dynamic>)? onCallAnswered;
  Function(Map<String, dynamic>)? onCallDeclined;
  Function(Map<String, dynamic>)? onCallEnded;
  Function(Map<String, dynamic>)? _onSignal;
  
  // Signal buffering for cross-room calls
  final List<Map<String, dynamic>> _signalBuffer = [];
  bool _bufferSignals = false;
  
  // Getter/setter for onSignal with buffer replay
  Function(Map<String, dynamic>)? get onSignal => _onSignal;
  set onSignal(Function(Map<String, dynamic>)? handler) {
    _onSignal = handler;
    // Replay buffered signals when handler is set
    if (handler != null && _signalBuffer.isNotEmpty) {
      debugPrint('📡 Replaying ${_signalBuffer.length} buffered signals');
      for (final signal in _signalBuffer) {
        handler(signal);
      }
      _signalBuffer.clear();
    }
  }
  
  /// Start buffering signals (call before expecting cross-room call)
  void startSignalBuffering() {
    _bufferSignals = true;
    _signalBuffer.clear();
    debugPrint('📡 Started signal buffering');
  }
  
  /// Stop buffering signals
  void stopSignalBuffering() {
    _bufferSignals = false;
    _signalBuffer.clear();
    debugPrint('📡 Stopped signal buffering');
  }

  bool get isConnected => _socket?.connected ?? false;
  int? get currentUserId => _currentUserId;
  
  /// Test connection status
  void testConnection() {
    debugPrint('=== Socket Connection Test ===');
    debugPrint('Socket exists: ${_socket != null}');
    debugPrint('Socket connected: ${_socket?.connected ?? false}');
    debugPrint('Socket ID: ${_socket?.id ?? "null"}');
    debugPrint('Auth token exists: ${_authToken != null}');
    debugPrint('Current user ID: $_currentUserId');
    debugPrint('============================');
  }

  /// Initialize and connect to Socket.IO server
  void initialize(String token, int userId) {
    _authToken = token;
    _currentUserId = userId;
    _connect();
  }

  void _connect() {
    if (_socket != null && _socket!.connected) {
      debugPrint('Socket already connected');
      return;
    }

    // Use the same base URL as the API from centralized config
    final serverUrl = ApiConfig.baseUrl;

    debugPrint('=== Attempting Socket.IO Connection ===');
    debugPrint('Server URL: $serverUrl');
    debugPrint('Token length: ${_authToken?.length ?? 0}');
    debugPrint('User ID: $_currentUserId');

    try {
      // Use older configuration style for better compatibility
      _socket = IO.io(
        serverUrl,
        <String, dynamic>{
          'transports': ['websocket', 'polling'],
          'autoConnect': true,
          'query': {
            'token': _authToken,
          },
          'extraHeaders': {
            'Authorization': 'Bearer $_authToken',
          },
        },
      );

      debugPrint('Socket.IO client created');
      _setupEventListeners();
      
      // Manually connect if not auto-connecting
      if (!(_socket?.connected ?? false)) {
        debugPrint('Manually connecting socket...');
        _socket?.connect();
      }
      
      // Test connection after a short delay
      Future.delayed(const Duration(seconds: 2), () {
        testConnection();
      });
    } catch (e) {
      debugPrint('❌ Error creating socket: $e');
    }
  }

  void _setupEventListeners() {
    if (_socket == null) return;

    // Connection events
    _socket!.on('connect', (_) {
      debugPrint('✅ Socket connected - ID: ${_socket!.id}');
      // Join user's personal room for direct notifications
      if (_currentUserId != null) {
        debugPrint('Joining personal room: user_$_currentUserId');
        _socket!.emit('join_room', {'room': 'user_$_currentUserId'});
      }
    });

    _socket!.on('disconnect', (reason) {
      debugPrint('❌ Socket disconnected - Reason: $reason');
      // If the server explicitly disconnected us (e.g., due to expired token)
      // trigger the auth error handler
      if (reason == 'io server disconnect') {
        debugPrint('🔐 Server disconnected us - likely expired token');
        AuthErrorHandler().handleAuthError(
          message: 'Connection lost. Please sign in again.',
        );
      }
    });

    _socket!.on('connect_error', (error) {
      debugPrint('⚠️ Connection error: $error');
    });

    _socket!.on('error', (error) {
      debugPrint('⚠️ Socket error: $error');
    });

    _socket!.on('reconnect', (attemptNumber) {
      debugPrint('🔄 Socket reconnected after $attemptNumber attempts');
    });

    _socket!.on('reconnect_attempt', (attemptNumber) {
      debugPrint('🔄 Reconnection attempt #$attemptNumber');
    });

    _socket!.on('reconnect_error', (error) {
      debugPrint('⚠️ Reconnection error: $error');
    });

    _socket!.on('reconnect_failed', (_) {
      debugPrint('❌ Reconnection failed');
    });

    // Chat room events
    _socket!.on('joined_chat', (data) {
      debugPrint('📥 Joined chat: $data');
      onJoinedChat?.call(data as Map<String, dynamic>);
    });

    _socket!.on('left_chat', (data) {
      debugPrint('📤 Left chat: $data');
      onLeftChat?.call(data as Map<String, dynamic>);
    });

    // Message events
    _socket!.on('new_message', (data) {
      debugPrint('💬 New message: $data');
      onMessageReceived?.call(data as Map<String, dynamic>);
    });

    // Doorbell event
    _socket!.on('doorbell', (data) {
      debugPrint('🔔 Doorbell ring: $data');
      onDoorbellRing?.call(data as Map<String, dynamic>);
    });

    // Typing events
    _socket!.on('user_typing', (data) {
      debugPrint('⌨️ User typing: $data');
      onUserTyping?.call(data as Map<String, dynamic>);
    });

    _socket!.on('typing_update', (data) {
      debugPrint('📝 Typing update: $data');
      onTypingUpdate?.call(data as Map<String, dynamic>);
    });

    // Presence events
    _socket!.on('user_status_change', (data) {
      debugPrint('👤 Presence update: $data');
      onPresenceUpdate?.call(data as Map<String, dynamic>);
    });

    // Color change event
    _socket!.on('color_changed', (data) {
      debugPrint('🎨 Color changed: $data');
      onColorChanged?.call(data as Map<String, dynamic>);
    });

    // Color reset event
    _socket!.on('color_reset', (data) {
      debugPrint('🔄 Color reset: $data');
      onColorReset?.call(data as Map<String, dynamic>);
    });

    // Message delivery confirmation
    _socket!.on('message_delivered', (data) {
      debugPrint('✓ Message delivered: $data');
      onMessageDelivered?.call(data as Map<String, dynamic>);
    });

    // Message read confirmation
    _socket!.on('message_read', (data) {
      debugPrint('✓✓ Message read: $data');
      onMessageRead?.call(data as Map<String, dynamic>);
    });

    // All messages deleted event
    _socket!.on('all_messages_deleted', (data) {
      debugPrint('📭 All messages deleted: $data');
      onAllMessagesDeleted?.call(data as Map<String, dynamic>);
    });

    // File message event (receiving files from web)
    _socket!.on('file_message', (data) {
      debugPrint('📎 File received: $data');
      onFileReceived?.call(data as Map<String, dynamic>);
    });

    // Message deleted event
    _socket!.on('message_deleted', (data) {
      debugPrint('🗑️ Message deleted: $data');
      onMessageDeleted?.call(data as Map<String, dynamic>);
    });

    // Message edited event
    _socket!.on('message_edited', (data) {
      debugPrint('✏️ Message edited: $data');
      onMessageEdited?.call(data as Map<String, dynamic>);
    });

    // Task added event
    _socket!.on('task_added', (data) {
      debugPrint('📋 Task added: $data');
      onTaskAdded?.call(data as Map<String, dynamic>);
    });

    // Task completed event
    _socket!.on('task_completed', (data) {
      debugPrint('✅ Task completed: $data');
      onTaskCompleted?.call(data as Map<String, dynamic>);
    });

    // Task uncompleted event
    _socket!.on('task_uncompleted', (data) {
      debugPrint('⬜ Task uncompleted: $data');
      onTaskUncompleted?.call(data as Map<String, dynamic>);
    });

    // Excalidraw pinned event
    _socket!.on('excalidraw_pinned', (data) {
      debugPrint('📌 Excalidraw pinned: $data');
      onExcalidrawPinned?.call(data as Map<String, dynamic>);
    });

    // Excalidraw unpinned event
    _socket!.on('excalidraw_unpinned', (data) {
      debugPrint('📌 Excalidraw unpinned: $data');
      onExcalidrawUnpinned?.call(data as Map<String, dynamic>);
    });

    // === Call-related events ===
    
    // Incoming call notification (from initiate_call event)
    _socket!.on('incoming_call', (data) {
      debugPrint('📲 Incoming call: $data');
      onIncomingCall?.call(data as Map<String, dynamic>);
    });
    
    // Cross-room call offer (from web client signaling)
    _socket!.on('cross_room_call_offer', (data) {
      debugPrint('📲 Cross-room call offer: $data');
      // Start buffering signals immediately - they may arrive before handler is set
      startSignalBuffering();
      onCrossRoomCallOffer?.call(data as Map<String, dynamic>);
    });

    // Call initiated confirmation
    _socket!.on('call_initiated', (data) {
      debugPrint('📞 Call initiated: $data');
      onCallInitiated?.call(data as Map<String, dynamic>);
    });

    // Call answered
    _socket!.on('call_answered', (data) {
      debugPrint('✅ Call answered: $data');
      onCallAnswered?.call(data as Map<String, dynamic>);
    });

    // Call declined
    _socket!.on('call_declined', (data) {
      debugPrint('❌ Call declined: $data');
      onCallDeclined?.call(data as Map<String, dynamic>);
    });

    // Call ended
    _socket!.on('call_ended', (data) {
      debugPrint('📴 Call ended: $data');
      onCallEnded?.call(data as Map<String, dynamic>);
    });

    // WebRTC signaling (offer/answer/ICE candidates)
    _socket!.on('signal', (data) {
      debugPrint('📡 Signal received: $data');
      final signalData = data as Map<String, dynamic>;
      if (_bufferSignals && _onSignal == null) {
        // Buffer signal if we're expecting a call but handler not set yet
        _signalBuffer.add(signalData);
        debugPrint('📡 Buffered signal (total: ${_signalBuffer.length})');
      } else {
        _onSignal?.call(signalData);
      }
    });
  }

  /// Disconnect from Socket.IO server
  void disconnect() {
    debugPrint('Disconnecting socket...');
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _authToken = null;
    _currentUserId = null;
  }

  /// Emit an event to the server
  void emit(String event, dynamic data) {
    if (_socket?.connected ?? false) {
      debugPrint('📤 Emitting $event: $data');
      _socket!.emit(event, data);
    } else {
      debugPrint('⚠️ Cannot emit $event - socket not connected');
    }
  }

  /// Join a chat room with another user
  void joinChat(int userId) {
    emit('join_chat', {'user_id': userId});
  }

  /// Leave a chat room with another user
  void leaveChat(int userId) {
    emit('leave_chat', {'user_id': userId});
  }

  /// Send a message via Socket.IO
  void sendMessage({
    required int recipientId,
    required String content,
    String messageType = 'text',
    int? replyToId,
  }) {
    emit('send_message', {
      'recipient_id': recipientId,
      'content': content,
      'message_type': messageType,
      if (replyToId != null) 'reply_to_id': replyToId,
    });
  }

  /// Ring doorbell to get someone's attention
  void ringDoorbell(int recipientId) {
    emit('ring_doorbell', {'recipient_id': recipientId});
  }

  /// Start typing indicator
  void startTyping(int recipientId) {
    emit('typing_start', {'recipient_id': recipientId});
  }

  /// Stop typing indicator
  void stopTyping(int recipientId) {
    emit('typing_stop', {'recipient_id': recipientId});
  }

  /// Send typing update with message preview
  void sendTypingUpdate(int recipientId, String message) {
    final preview = message.length > 120 ? message.substring(0, 120) : message;
    emit('typing_update', {
      'recipient_id': recipientId,
      'message': preview,
    });
  }

  /// Confirm message delivery
  void confirmDelivery(int messageId) {
    emit('confirm_delivery', {'message_id': messageId});
  }

  /// Confirm message read
  void confirmRead(int messageId) {
    emit('confirm_read', {'message_id': messageId});
  }

  /// Delete a message
  void deleteMessage(int messageId) {
    emit('delete_message', {'message_id': messageId});
  }

  /// Edit a message
  void editMessage(int messageId, String newContent) {
    emit('edit_message', {
      'message_id': messageId,
      'content': newContent,
    });
  }

  /// Add message as task
  void addTask(int messageId) {
    emit('add_task', {'message_id': messageId});
  }

  /// Complete a task
  void completeTask(int messageId) {
    emit('complete_task', {'message_id': messageId});
  }

  /// Uncomplete a task
  void uncompleteTask(int messageId) {
    emit('uncomplete_task', {'message_id': messageId});
  }

  /// Pin excalidraw link
  void pinExcalidraw(int messageId) {
    emit('pin_excalidraw', {'message_id': messageId});
  }

  /// Unpin excalidraw link
  void unpinExcalidraw(int messageId) {
    emit('unpin_excalidraw', {'message_id': messageId});
  }

  /// Clear all callbacks
  void clearCallbacks() {
    onMessageReceived = null;
    onDoorbellRing = null;
    onUserTyping = null;
    onTypingUpdate = null;
    onPresenceUpdate = null;
    onJoinedChat = null;
    onLeftChat = null;
    onMessageDelivered = null;
    onMessageRead = null;
    onColorChanged = null;
    onColorReset = null;
    onAllMessagesDeleted = null;
    onFileReceived = null;
    onMessageDeleted = null;
    onMessageEdited = null;
    onTaskAdded = null;
    onTaskCompleted = null;
    onTaskUncompleted = null;
    onExcalidrawPinned = null;
    onExcalidrawUnpinned = null;
    // Call-related
    onIncomingCall = null;
    onCallInitiated = null;
    onCallAnswered = null;
    onCallDeclined = null;
    onCallEnded = null;
    onSignal = null;
  }
}
