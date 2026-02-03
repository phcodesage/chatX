import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mime/mime.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import '../models/lobby_user.dart';
import '../models/message.dart';
import '../services/message_service.dart';
import '../services/socket_service.dart';
import '../services/storage_service.dart';
import '../widgets/color_picker_modal.dart';
import '../config/api_config.dart';

/// Chat screen for messaging with a specific user
class ChatScreen extends StatefulWidget {
  final LobbyUser otherUser;
  
  const ChatScreen({super.key, required this.otherUser});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final SocketService _socketService = SocketService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final FocusNode _inputFocusNode = FocusNode();
  
  List<Message> _messages = [];
  bool _isLoading = true;
  bool _isTyping = false;
  bool _isKeyboardVisible = false;
  bool _otherUserTyping = false;
  String _typingPreview = '';
  int? _currentUserId;
  Timer? _typingTimer;
  Timer? _typingUpdateThrottle;
  DateTime? _lastTypingUpdate;
  Color _headerColor = const Color(0xFF4C1D95); // Default purple color
  bool _showResetButton = false;
  
  // Voice recording state
  bool _isRecording = false;
  bool _isPaused = false;
  String? _recordingPath;
  Duration _recordingDuration = Duration.zero;
  Timer? _recordingTimer;
  List<double> _waveformData = [];

  @override
  void initState() {
    super.initState();
    _inputFocusNode.addListener(_onFocusChange);
    _initialize();
  }

  void _onFocusChange() {
    // Only update if keyboard visibility actually changed
    final isVisible = _inputFocusNode.hasFocus;
    if (_isKeyboardVisible != isVisible) {
      setState(() {
        _isKeyboardVisible = isVisible;
      });
    }
  }

  Future<void> _initialize() async {
    _currentUserId = await StorageService.getUserId();
    await _loadMessages();
    _joinChatRoom();
    _setupRealtimeListeners();
  }

  void _joinChatRoom() {
    // Test connection status first
    _socketService.testConnection();
    
    // Try to join chat room
    _socketService.joinChat(widget.otherUser.id);
  }

  void _setupRealtimeListeners() {
    // Listen for new messages
    _socketService.onMessageReceived = (data) {
      final message = Message.fromJson(data);
      
      // Only add if it's from the current conversation
      if (message.senderId == widget.otherUser.id || 
          message.recipientId == widget.otherUser.id) {
        setState(() {
          _messages.insert(0, message);
          // Clear typing preview when message is received
          _otherUserTyping = false;
          _typingPreview = '';
        });
        
        // Play message sound for incoming messages
        if (message.senderId == widget.otherUser.id) {
          try {
            _audioPlayer.play(AssetSource('sounds/splat2.m4a'));
          } catch (e) {
            debugPrint('Error playing message sound: $e');
          }
        }
        
        // Confirm delivery and read
        _socketService.confirmDelivery(message.id);
        _socketService.confirmRead(message.id);
        
        // Mark as read via API
        MessageService.markAsRead(
          senderId: widget.otherUser.id,
          lastMessageId: message.id,
        );
        
        // Scroll to bottom
        _scrollToBottom();
      }
    };

    // Listen for typing indicator (includes live typing preview)
    _socketService.onUserTyping = (data) {
      if (data['user_id'] == widget.otherUser.id) {
        setState(() {
          final isTyping = data['is_typing'] ?? false;
          final message = data['message'] as String? ?? '';
          
          if (isTyping) {
            _otherUserTyping = true;
            // Update preview if message is provided
            if (message.isNotEmpty) {
              _typingPreview = message;
            }
          } else {
            _otherUserTyping = false;
            _typingPreview = '';
          }
        });
      }
    };

    // Listen for live typing preview (separate event if used)
    _socketService.onTypingUpdate = (data) {
      if (data['user_id'] == widget.otherUser.id || 
          data['sender_id'] == widget.otherUser.id) {
        final preview = data['message'] ?? '';
        setState(() {
          _otherUserTyping = preview.isNotEmpty;
          _typingPreview = preview;
        });
      }
    };

    // Listen for joined chat confirmation
    _socketService.onJoinedChat = (data) {
      debugPrint('Successfully joined chat with ${widget.otherUser.fullName}');
    };

    // Listen for doorbell rings
    _socketService.onDoorbellRing = (data) {
      if (data['sender_id'] == widget.otherUser.id) {
        _handleIncomingDoorbell(data);
      }
    };

    // Listen for color change events
    _socketService.onColorChanged = (data) {
      if (data['sender_id'] == widget.otherUser.id) {
        _handleColorChange(data);
      }
    };

    // Listen for color reset events
    _socketService.onColorReset = (data) {
      if (data['sender_id'] == widget.otherUser.id) {
        _handleColorReset(data);
      }
    };

    // Listen for file messages (received from web)
    _socketService.onFileReceived = (data) {
      debugPrint('📎 Received file_message in chat: $data');
      if (data['sender_id'] == widget.otherUser.id) {
        _handleIncomingFileMessage(data);
      }
    };
    // Listen for all messages deleted event
    _socketService.onAllMessagesDeleted = (data) {
      _handleAllMessagesDeleted(data);
    };

    // Listen for file messages from web
    _socketService.onFileReceived = (data) {
      debugPrint('📎 File message received in chat: $data');
      // Only process if it's from the current conversation partner
      if (data['sender_id'] == widget.otherUser.id) {
        final now = DateTime.now();
        final timestampMs = data['timestamp_ms'] ?? now.millisecondsSinceEpoch;
        // Create a message from the file data
        final message = Message(
          id: data['message_id'] ?? timestampMs,
          senderId: data['sender_id'],
          recipientId: _currentUserId ?? 0,
          content: data['file_name'] ?? 'File',
          messageType: (data['file_type'] as String?)?.startsWith('image/') == true ? 'image' : 'file',
          timestamp: now.toIso8601String(),
          timestampMs: timestampMs,
          isRead: false,
          status: 'delivered',
          threadId: '',
          reactions: {},
          isDeleted: false,
          fileUrl: data['file_url'],
          fileName: data['file_name'],
          fileType: data['file_type'],
          fileSize: data['file_size'],
        );
        
        setState(() {
          _messages.insert(0, message);
        });
        
        // Play message sound
        try {
          _audioPlayer.play(AssetSource('sounds/splat2.m4a'));
        } catch (e) {
          debugPrint('Error playing message sound: $e');
        }
        
        // Scroll to bottom
        _scrollToBottom();
      }
    };
  }

  void _handleColorChange(Map<String, dynamic> data) {
    final colorHex = data['color'] as String?;
    final senderName = data['sender_name'] ?? widget.otherUser.fullName;
    
    if (colorHex != null) {
      try {
        // Parse hex color (e.g., "#FF5733" or "FF5733")
        final hexColor = colorHex.replaceAll('#', '');
        final color = Color(int.parse('FF$hexColor', radix: 16));
        
        setState(() {
          _headerColor = color;
          _showResetButton = true;
        });
        
        // Create incoming system message about color change
        final colorMessage = Message(
          id: DateTime.now().millisecondsSinceEpoch,
          senderId: widget.otherUser.id,
          recipientId: _currentUserId!,
          content: '$senderName changed your bg color to $colorHex',
          messageType: 'system',
          timestamp: DateTime.now().toIso8601String(),
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          isRead: true,
          status: 'delivered',
          threadId: 'thread_${_currentUserId}_${widget.otherUser.id}',
          reactions: {},
          isDeleted: false,
        );

        setState(() {
          _messages.insert(0, colorMessage);
        });

        // Scroll to bottom to show the message
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToBottom();
        });
        
        debugPrint('🎨 Color changed to: $colorHex');
      } catch (e) {
        debugPrint('Error parsing color: $e');
      }
    }
  }

  void _handleColorReset(Map<String, dynamic> data) {
    final senderName = data['sender_name'] ?? widget.otherUser.fullName;
    
    // Reset header color to default
    const defaultColor = Color(0xFF1E1E1E);
    
    setState(() {
      _headerColor = defaultColor;
      _showResetButton = false;
    });
    
    // Create incoming system message about color reset
    final resetMessage = Message(
      id: DateTime.now().millisecondsSinceEpoch,
      senderId: widget.otherUser.id,
      recipientId: _currentUserId!,
      content: '$senderName reset your bg color',
      messageType: 'system',
      timestamp: DateTime.now().toIso8601String(),
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      isRead: true,
      status: 'delivered',
      threadId: 'thread_${_currentUserId}_${widget.otherUser.id}',
      reactions: {},
      isDeleted: false,
    );

    setState(() {
      _messages.insert(0, resetMessage);
    });

    // Scroll to bottom to show the notification
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
    
    debugPrint('🔄 Color reset by ${widget.otherUser.fullName}');
  }

  void _handleIncomingDoorbell(Map<String, dynamic> data) {
    final senderName = data['sender_name'] ?? widget.otherUser.fullName;
    final timestampMs = data['timestamp_ms'] as int;
    
    // Check if we already have this doorbell notification to prevent duplicates
    final alreadyExists = _messages.any((msg) => 
      msg.messageType == 'system' && 
      msg.timestampMs == timestampMs &&
      msg.content.contains('sent a notification')
    );
    
    if (alreadyExists) {
      debugPrint('Doorbell notification already exists, skipping duplicate');
      return;
    }
    
    // Play doorbell notification sound
    try {
      _audioPlayer.play(AssetSource('sounds/notif-sound.wav'));
    } catch (e) {
      debugPrint('Error playing doorbell sound: $e');
    }
    
    // Create incoming notification message
    final doorbellMessage = Message(
      id: DateTime.now().millisecondsSinceEpoch,
      senderId: widget.otherUser.id,
      recipientId: _currentUserId!,
      content: '$senderName sent a notification',
      messageType: 'system',
      timestamp: DateTime.now().toIso8601String(),
      timestampMs: timestampMs,
      isRead: true,
      status: 'delivered',
      threadId: 'thread_${_currentUserId}_${widget.otherUser.id}',
      reactions: {},
      isDeleted: false,
    );

    setState(() {
      _messages.insert(0, doorbellMessage);
    });

    // Scroll to bottom to show the notification
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
  }

  void _handleAllMessagesDeleted(Map<String, dynamic> data) {
    debugPrint('🗑️ Handling all messages deleted event: $data');
    
    final String deletedRoom = data['room'] ?? '';
    
    // Validate room ID
    if (deletedRoom.isEmpty) {
      debugPrint('⚠️ Warning: Received delete event with no room ID');
      return;
    }
    
    // Generate current room ID (same format as backend: chat_{userId1}_{userId2} sorted)
    if (_currentUserId == null) {
      debugPrint('⚠️ Warning: Current user ID is null');
      return;
    }
    
    final List<int> userIds = [_currentUserId!, widget.otherUser.id];
    userIds.sort();
    final currentRoomId = 'chat_${userIds[0]}_${userIds[1]}';
    
    // Only clear messages if the event is for the current room
    if (deletedRoom != currentRoomId) {
      debugPrint('ℹ️ Ignoring delete event for different room: $deletedRoom (current: $currentRoomId)');
      return;
    }
    
    // Clear all messages
    setState(() {
      _messages.clear();
    });

    // Show a snackbar notification
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All messages have been deleted'),
          duration: Duration(seconds: 3),
          backgroundColor: Colors.orange,
        ),
      );
    }

    debugPrint('✅ Messages cleared for room: $currentRoomId');
  }

  Future<void> _loadMessages() async {
    setState(() => _isLoading = true);
    try {
      final messages = await MessageService.getConversationMessages(
        userId: widget.otherUser.id,
        limit: 50,
      );
      setState(() {
        _messages = messages.reversed.toList(); // Reverse to show newest at bottom
        _isLoading = false;
      });
      
      // Mark all as read
      if (messages.isNotEmpty) {
        await MessageService.markAsRead(
          senderId: widget.otherUser.id,
          lastMessageId: messages.first.id,
        );
      }
      
      _scrollToBottom();
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading messages: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      // For reverse list, scroll to 0 (which is the bottom)
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;

    // Create optimistic message for immediate UI update
    final optimisticMessage = Message(
      id: DateTime.now().millisecondsSinceEpoch, // Temporary ID
      senderId: _currentUserId!,
      recipientId: widget.otherUser.id,
      content: content,
      messageType: 'text',
      timestamp: DateTime.now().toIso8601String(),
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      isRead: false,
      status: 'sending',
      threadId: 'thread_${_currentUserId}_${widget.otherUser.id}',
      reactions: {},
      isDeleted: false,
    );

    setState(() {
      _messages.insert(0, optimisticMessage);
    });

    // Play message sound when sending
    try {
      _audioPlayer.play(AssetSource('sounds/splat2.m4a'));
    } catch (e) {
      debugPrint('Error playing message sound: $e');
    }

    _messageController.clear();
    _stopTyping();
    
    // Scroll to bottom immediately after sending
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });

    // Try to send message
    try {
      // Check if Socket.IO is connected
      if (_socketService.isConnected) {
        // Send via Socket.IO for real-time delivery
        debugPrint('✅ Sending message via Socket.IO');
        _socketService.sendMessage(
          recipientId: widget.otherUser.id,
          content: content,
          messageType: 'text',
        );
      } else {
        // Fallback to REST API
        debugPrint('⚠️ Socket.IO not connected, using REST API fallback');
        final sentMessage = await MessageService.sendMessage(
          recipientId: widget.otherUser.id,
          content: content,
          messageType: 'text',
        );
        
        // Update optimistic message with real message data
        if (sentMessage != null && mounted) {
          setState(() {
            final index = _messages.indexWhere((m) => m.id == optimisticMessage.id);
            if (index != -1) {
              _messages[index] = sentMessage;
            }
          });
          debugPrint('✅ Message sent via REST API');
        }
      }
    } catch (e) {
      debugPrint('❌ Error sending message: $e');
      // Update message status to failed
      if (mounted) {
        setState(() {
          final index = _messages.indexWhere((m) => m.id == optimisticMessage.id);
          if (index != -1) {
            _messages[index] = Message(
              id: _messages[index].id,
              senderId: _messages[index].senderId,
              recipientId: _messages[index].recipientId,
              content: _messages[index].content,
              messageType: _messages[index].messageType,
              timestamp: _messages[index].timestamp,
              timestampMs: _messages[index].timestampMs,
              isRead: _messages[index].isRead,
              status: 'failed',
              threadId: _messages[index].threadId,
              reactions: _messages[index].reactions,
              isDeleted: _messages[index].isDeleted,
            );
          }
        });
      }
    }
  }

  void _onTextChanged(String text) {
    if (text.isEmpty) {
      if (_isTyping) {
        _stopTyping();
      }
      return;
    }

    // Only update typing state if not already typing
    if (!_isTyping) {
      _startTyping();
    }
    
    // Send live preview (throttled) - no setState here
    _sendTypingUpdate(text);
    
    // Reset typing timer
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 3), () {
      if (_isTyping) {
        _stopTyping();
      }
    });
  }

  void _sendTypingUpdate(String text) {
    // Throttle typing updates to avoid spamming
    final now = DateTime.now();
    if (_lastTypingUpdate != null) {
      final diff = now.difference(_lastTypingUpdate!);
      if (diff.inMilliseconds < 500) {
        // Too soon, schedule for later
        _typingUpdateThrottle?.cancel();
        _typingUpdateThrottle = Timer(const Duration(milliseconds: 500), () {
          _socketService.sendTypingUpdate(widget.otherUser.id, text);
          _lastTypingUpdate = DateTime.now();
        });
        return;
      }
    }

    // Send immediately
    _socketService.sendTypingUpdate(widget.otherUser.id, text);
    _lastTypingUpdate = now;
  }

  void _startTyping() {
    if (mounted) {
      setState(() => _isTyping = true);
    }
    _socketService.startTyping(widget.otherUser.id);
  }

  void _stopTyping() {
    if (mounted) {
      setState(() => _isTyping = false);
    }
    _socketService.stopTyping(widget.otherUser.id);
    _typingTimer?.cancel();
  }

  void _resetColor() {
    // Reset to default color
    const defaultColor = Color(0xFF1E1E1E);
    
    setState(() {
      _headerColor = defaultColor;
      _showResetButton = false;
    });
    
    // Emit reset color event
    _socketService.emit('change_color', {
      'recipient_id': widget.otherUser.id,
      'color': '#1E1E1E',
      'sender_name': 'You',
    });
    
    // Add outgoing message about reset
    final resetMessage = Message(
      id: DateTime.now().millisecondsSinceEpoch,
      senderId: _currentUserId!,
      recipientId: widget.otherUser.id,
      content: 'Reset bg color',
      messageType: 'system',
      timestamp: DateTime.now().toIso8601String(),
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      isRead: false,
      status: 'sent',
      threadId: 'thread_${_currentUserId}_${widget.otherUser.id}',
      reactions: {},
      isDeleted: false,
    );

    setState(() {
      _messages.insert(0, resetMessage);
    });

    // Scroll to bottom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
    
    debugPrint('🎨 Color reset to default');
  }

  void _changeColor() {
    // Show full-screen color picker modal
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ColorPickerModal(
        onColorSelected: (selectedColor) {
          // Only send color to other user, don't change our own background
          final colorHex = selectedColor.value.toRadixString(16).substring(2).toUpperCase();
          _socketService.emit('change_color', {
            'recipient_id': widget.otherUser.id,
            'color': '#$colorHex',
            'sender_name': 'You',
          });
          
          // Add outgoing system message to show we changed their color
          final colorMessage = Message(
            id: DateTime.now().millisecondsSinceEpoch,
            senderId: _currentUserId!,
            recipientId: widget.otherUser.id,
            content: 'Changed bg color',
            messageType: 'system',
            timestamp: DateTime.now().toIso8601String(),
            timestampMs: DateTime.now().millisecondsSinceEpoch,
            isRead: false,
            status: 'sent',
            threadId: 'thread_${_currentUserId}_${widget.otherUser.id}',
            reactions: {},
            isDeleted: false,
          );

          setState(() {
            _messages.insert(0, colorMessage);
          });

          // Scroll to bottom to show the message
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToBottom();
          });
          
          debugPrint('🎨 Color sent to ${widget.otherUser.fullName}: #$colorHex');
        },
      ),
    );
  }

  void _ringDoorbell() {
    // Send doorbell via Socket.IO
    _socketService.ringDoorbell(widget.otherUser.id);
    
    // Play doorbell notification sound
    try {
      _audioPlayer.play(AssetSource('sounds/notif-sound.wav'));
    } catch (e) {
      debugPrint('Error playing doorbell sound: $e');
    }
    
    // Create a system message in chat to show doorbell was sent
    final doorbellMessage = Message(
      id: DateTime.now().millisecondsSinceEpoch,
      senderId: _currentUserId!,
      recipientId: widget.otherUser.id,
      content: 'Sent a notification',
      messageType: 'system',
      timestamp: DateTime.now().toIso8601String(),
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      isRead: false,
      status: 'sent',
      threadId: 'thread_${_currentUserId}_${widget.otherUser.id}',
      reactions: {},
      isDeleted: false,
    );

    setState(() {
      _messages.insert(0, doorbellMessage);
    });

    // Scroll to bottom to show the notification message
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
  }

  /// Handle incoming file message from web
  void _handleIncomingFileMessage(Map<String, dynamic> data) {
    final now = DateTime.now();
    final fileUrl = data['file_url'] as String?;
    final fileName = data['file_name'] as String? ?? 'File';
    final fileType = data['file_type'] as String? ?? 'application/octet-stream';
    final fileSize = data['file_size'] as int? ?? 0;
    final messageType = fileType.startsWith('image/') ? 'image' : 
                        fileType.startsWith('video/') ? 'video' : 'file';
    
    final message = Message(
      id: data['message_id'] ?? now.millisecondsSinceEpoch,
      senderId: widget.otherUser.id,
      recipientId: _currentUserId!,
      content: fileName,
      messageType: messageType,
      timestamp: data['timestamp'] ?? now.toIso8601String(),
      timestampMs: data['timestamp_ms'] ?? now.millisecondsSinceEpoch,
      isRead: false,
      status: 'received',
      threadId: '',
      reactions: {},
      isDeleted: false,
      fileUrl: fileUrl,
      fileName: fileName,
      fileType: fileType,
      fileSize: fileSize,
    );

    setState(() {
      _messages.insert(0, message);
    });

    // Scroll to bottom to show the new message
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
    
    // Play notification sound
    try {
      _audioPlayer.play(AssetSource('sounds/notif-sound.wav'));
    } catch (e) {
      debugPrint('Error playing notification sound: $e');
    }
  }

  final ImagePicker _imagePicker = ImagePicker();

  /// Pick a file from device storage
  Future<void> _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        if (file.path != null) {
          _showFilePreviewModal(File(file.path!), file.name, isFromCamera: false);
        }
      }
    } catch (e) {
      debugPrint('Error picking file: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking file: $e')),
        );
      }
    }
  }

  bool _useFrontCamera = false;

  /// Take a photo with camera
  Future<void> _takePhoto() async {
    try {
      final XFile? photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        preferredCameraDevice: _useFrontCamera ? CameraDevice.front : CameraDevice.rear,
      );

      if (photo != null) {
        _showFilePreviewModal(File(photo.path), photo.name, isFromCamera: true);
      }
    } catch (e) {
      debugPrint('Error taking photo: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error accessing camera: $e')),
        );
      }
    }
  }

  /// Show file preview modal before sending
  void _showFilePreviewModal(File file, String fileName, {bool isFromCamera = false}) {
    final mimeType = lookupMimeType(file.path) ?? 'application/octet-stream';
    final isImage = mimeType.startsWith('image/');
    final isVideo = mimeType.startsWith('video/');
    final fileSize = file.lengthSync();
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: const BoxDecoration(
          color: Color(0xFF2D2D2D),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[600],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Title
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Send File',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            // Preview area
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    // Image/Video/File preview
                    if (isImage)
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(
                            file,
                            fit: BoxFit.contain,
                          ),
                        ),
                      )
                    else if (isVideo)
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.videocam, color: Colors.white, size: 64),
                                SizedBox(height: 8),
                                Text(
                                  'Video File',
                                  style: TextStyle(color: Colors.white, fontSize: 16),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.grey[800],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _getFileIcon(mimeType),
                                  color: Colors.white,
                                  size: 64,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  fileName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _formatFileSize(fileSize),
                                  style: TextStyle(
                                    color: Colors.grey[400],
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    // File info
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[800],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(_getFileIcon(mimeType), color: Colors.white70, size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  fileName,
                                  style: const TextStyle(color: Colors.white, fontSize: 14),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '${_formatFileSize(fileSize)} • $mimeType',
                                  style: TextStyle(color: Colors.grey[400], fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Action buttons
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Camera switch button (only for camera captures)
                  if (isFromCamera) ...[
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        setState(() {
                          _useFrontCamera = !_useFrontCamera;
                        });
                        _takePhoto();
                      },
                      icon: const Icon(Icons.cameraswitch),
                      label: Text(_useFrontCamera ? 'Switch to Back Camera' : 'Switch to Front Camera'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Colors.white30),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Row(
                    children: [
                      // Replace / Take Another button
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            if (isFromCamera) {
                              _takePhoto();
                            } else {
                              _pickFile();
                            }
                          },
                          icon: Icon(isFromCamera ? Icons.camera_alt : Icons.refresh),
                          label: Text(isFromCamera ? 'Take Another' : 'Replace'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white54),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Send button
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _uploadAndSendFile(file, fileName, mimeType);
                          },
                          icon: const Icon(Icons.send),
                          label: const Text('Send'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6D28D9),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getFileIcon(String mimeType) {
    if (mimeType.startsWith('image/')) return Icons.image;
    if (mimeType.startsWith('video/')) return Icons.videocam;
    if (mimeType.startsWith('audio/')) return Icons.audiotrack;
    if (mimeType.contains('pdf')) return Icons.picture_as_pdf;
    if (mimeType.contains('word') || mimeType.contains('document')) return Icons.description;
    if (mimeType.contains('excel') || mimeType.contains('spreadsheet')) return Icons.table_chart;
    if (mimeType.contains('zip') || mimeType.contains('archive')) return Icons.folder_zip;
    return Icons.insert_drive_file;
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// Format duration for display (mm:ss)
  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  /// Show voice recording modal
  Future<void> _showVoiceRecordingModal() async {
    // Request microphone permission
    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Microphone permission is required to record voice messages'),
            action: SnackBarAction(
              label: 'Settings',
              onPressed: () => openAppSettings(),
            ),
          ),
        );
      }
      return;
    }

    // Reset recording state
    setState(() {
      _isRecording = false;
      _isPaused = false;
      _recordingPath = null;
      _recordingDuration = Duration.zero;
      _waveformData = [];
    });

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      builder: (context) => _VoiceRecordingModal(
        onSend: (path, duration) async {
          Navigator.pop(context);
          await _uploadAndSendVoiceMessage(path, duration);
        },
        onCancel: () {
          // Recording lifecycle is managed inside _VoiceRecordingModal.
          Navigator.pop(context);
        },
      ),
    );
  }

  /// Upload and send voice message
  Future<void> _uploadAndSendVoiceMessage(String path, Duration duration) async {
    try {
      // Show uploading indicator
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              SizedBox(width: 12),
              Text('Sending voice message...'),
            ],
          ),
          duration: Duration(seconds: 30),
        ),
      );

      final file = File(path);
      final fileName = 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      
      // Upload file using MessageService
      final result = await MessageService.uploadFile(
        file: file,
        recipientId: widget.otherUser.id,
      );

      // Hide uploading indicator
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      if (result != null && result['success'] == true) {
        final fileData = result['file'] ?? result;
        
        // Emit file message via socket
        _socketService.emit('send_file', {
          'recipient_id': widget.otherUser.id,
          'file_id': fileData['file_id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
          'file_name': fileName,
          'file_type': 'audio/m4a',
          'file_size': file.lengthSync(),
          'file_url': fileData['file_url'] ?? fileData['url'],
        });

        // Create local message to show in chat
        final now = DateTime.now();
        final message = Message(
          id: DateTime.now().millisecondsSinceEpoch,
          senderId: _currentUserId!,
          recipientId: widget.otherUser.id,
          content: fileName,
          messageType: 'voice',
          timestamp: now.toIso8601String(),
          timestampMs: now.millisecondsSinceEpoch,
          isRead: false,
          status: 'sent',
          threadId: '',
          reactions: {},
          isDeleted: false,
          fileUrl: fileData['file_url'] ?? fileData['url'],
          fileName: fileName,
          fileType: 'audio/m4a',
          fileSize: file.lengthSync(),
        );

        setState(() {
          _messages.insert(0, message);
        });

        // Scroll to bottom
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToBottom();
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Voice message sent!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );

        // Clean up recording file
        try {
          await file.delete();
        } catch (_) {}
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to send voice message'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error uploading voice message: $e');
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sending voice message: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Upload file to server and send via socket
  Future<void> _uploadAndSendFile(File file, String fileName, String mimeType) async {
    try {
      // Show uploading indicator
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              SizedBox(width: 12),
              Text('Uploading file...'),
            ],
          ),
          duration: Duration(seconds: 30),
        ),
      );

      // Upload file using MessageService
      final result = await MessageService.uploadFile(
        file: file,
        recipientId: widget.otherUser.id,
      );

      // Hide uploading indicator
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      if (result != null && result['success'] == true) {
        final fileData = result['file'] ?? result;
        
        // Emit file message via socket
        _socketService.emit('send_file', {
          'recipient_id': widget.otherUser.id,
          'file_id': fileData['file_id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
          'file_name': fileName,
          'file_type': mimeType,
          'file_size': file.lengthSync(),
          'file_url': fileData['file_url'] ?? fileData['url'],
        });

        // Create local message to show in chat
        final now = DateTime.now();
        final message = Message(
          id: DateTime.now().millisecondsSinceEpoch,
          senderId: _currentUserId!,
          recipientId: widget.otherUser.id,
          content: fileName,
          messageType: mimeType.startsWith('image/') ? 'image' : 
                       mimeType.startsWith('video/') ? 'video' : 'file',
          timestamp: now.toIso8601String(),
          timestampMs: now.millisecondsSinceEpoch,
          isRead: false,
          status: 'sent',
          threadId: '',
          reactions: {},
          isDeleted: false,
          fileUrl: fileData['file_url'] ?? fileData['url'],
          fileName: fileName,
          fileType: mimeType,
          fileSize: file.lengthSync(),
        );

        setState(() {
          _messages.insert(0, message);
        });
        _scrollToBottom();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('File sent!'),
            duration: Duration(seconds: 2),
          ),
        );
      } else {
        throw Exception(result?['error'] ?? 'Upload failed');
      }
    } catch (e) {
      debugPrint('Error uploading file: $e');
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send file: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _audioPlayer.dispose();
    _inputFocusNode.dispose();
    _typingTimer?.cancel();
    _typingUpdateThrottle?.cancel();
    
    // Send typing stop without setState (widget is being disposed)
    _socketService.stopTyping(widget.otherUser.id);
    
    // Leave chat room
    _socketService.leaveChat(widget.otherUser.id);
    
    // Clear callbacks
    _socketService.onMessageReceived = null;
    _socketService.onUserTyping = null;
    _socketService.onTypingUpdate = null;
    _socketService.onJoinedChat = null;
    _socketService.onDoorbellRing = null;
    _socketService.onColorChanged = null;
    
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: const Color(0xFF2C2C2C),
      appBar: AppBar(
        backgroundColor: _headerColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: _getAvatarColor(),
              child: Text(
                widget.otherUser.initials,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.otherUser.fullName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    _otherUserTyping
                        ? 'typing...'
                        : (widget.otherUser.isOnline ? 'online' : 'offline'),
                    style: TextStyle(
                      color: _otherUserTyping
                          ? const Color(0xFF4CAF50)
                          : (widget.otherUser.isOnline
                              ? const Color(0xFF4CAF50)
                              : Colors.grey[600]),
                      fontSize: 12,
                      fontStyle: _otherUserTyping ? FontStyle.italic : FontStyle.normal,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: const [],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // Messages list
              Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey[700]),
                            const SizedBox(height: 16),
                            Text(
                              'No messages yet',
                              style: TextStyle(color: Colors.grey[600], fontSize: 16),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Send a message to start the conversation',
                              style: TextStyle(color: Colors.grey[700], fontSize: 14),
                            ),
                          ],
                        ),
                      )
                    : RepaintBoundary(
                        child: ListView.builder(
                          controller: _scrollController,
                          reverse: true,
                          padding: const EdgeInsets.all(16),
                          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                          cacheExtent: 500,
                          itemCount: _messages.length,
                          addAutomaticKeepAlives: true,
                          addRepaintBoundaries: true,
                          itemBuilder: (context, index) {
                            final message = _messages[index];
                            final isSentByMe = message.senderId == _currentUserId;
                            return _buildMessageBubble(message, isSentByMe);
                          },
                        ),
                      ),
          ),
          // Typing preview - pinned at bottom, always visible
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            height: (_otherUserTyping && _typingPreview.isNotEmpty) ? null : 0,
            padding: (_otherUserTyping && _typingPreview.isNotEmpty)
                ? const EdgeInsets.symmetric(horizontal: 16, vertical: 8)
                : EdgeInsets.zero,
            decoration: const BoxDecoration(
              color: Color(0xFF2C2C2C),
              border: Border(
                top: BorderSide(color: Color(0xFF3D3D3D), width: 1),
              ),
            ),
            child: (_otherUserTyping && _typingPreview.isNotEmpty)
                ? RepaintBoundary(child: _buildTypingPreviewBubble())
                : const SizedBox.shrink(),
          ),
          // Message input
          RepaintBoundary(
            child: Container(
              padding: EdgeInsets.only(
                left: 12,
                right: 12,
                top: 12,
                bottom: 12 + MediaQuery.of(context).viewInsets.bottom,
              ),
              decoration: const BoxDecoration(
                color: Color(0xFF2D2D2D),
                border: Border(
                  top: BorderSide(color: Color(0xFF3D3D3D), width: 1),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                // Text input field - full width, max 3 lines
                RepaintBoundary(
                  child: TextField(
                    key: const ValueKey('message_input'),
                    controller: _messageController,
                    focusNode: _inputFocusNode,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      hintStyle: TextStyle(color: Colors.grey[600]),
                      filled: true,
                      fillColor: const Color(0xFF4D4D4D),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                    onChanged: _onTextChanged,
                    onSubmitted: (_) => _sendMessage(),
                    minLines: 1,
                    maxLines: 3,
                    textInputAction: TextInputAction.send,
                    keyboardType: TextInputType.text,
                    textCapitalization: TextCapitalization.sentences,
                    enableInteractiveSelection: true,
                    autocorrect: true,
                    enableSuggestions: true,
                    scribbleEnabled: false,
                  ),
                ),
                const SizedBox(height: 8),
                // Primary buttons row - aligned to the right
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // Clear button
                    ElevatedButton(
                      onPressed: () {
                        _messageController.clear();
                        _stopTyping();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEF4444), // rgb(239 68 68)
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Clear'),
                    ),
                    const SizedBox(width: 8),
                    // Send button
                    ElevatedButton(
                      onPressed: _sendMessage,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6D28D9), // rgb(109 40 217)
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Send'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Action buttons - Grid layout (hidden when typing)
                if (_messageController.text.isEmpty)
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                    // Ring Doorbell
                    ElevatedButton(
                      onPressed: _ringDoorbell,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF8B5CF6), // Violet
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                      child: const Text('Ring Doorbell'),
                    ),
                    // Change Color
                    ElevatedButton(
                      onPressed: _changeColor,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFA855F7), // Purple
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                      child: const Text('Change Color'),
                    ),
                    // Reset Color button (only show when color has been changed)
                    if (_showResetButton)
                      ElevatedButton(
                        onPressed: _resetColor,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black87,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          textStyle: const TextStyle(fontSize: 12),
                        ),
                        child: const Text('Reset Color'),
                      ),
                    // Send File
                    ElevatedButton(
                      onPressed: _pickFile,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981), // Green
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                      child: const Text('Send File'),
                    ),
                    // Camera
                    ElevatedButton(
                      onPressed: _takePhoto,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3B82F6), // Blue
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                      child: const Text('Camera'),
                    ),
                    // Record Voice Message
                    ElevatedButton(
                      onPressed: _showVoiceRecordingModal,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEF4444), // Red
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                      child: const Text('Voice'),
                    ),
                    // Show Timestamps
                    ElevatedButton(
                      onPressed: () {
                        // TODO: Implement show timestamps
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Show Timestamps - Coming soon!')),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF8B5CF6), // Purple
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                      child: const Text('Show Timestamps'),
                    ),
                    // Export Chat
                    ElevatedButton(
                      onPressed: () {
                        // TODO: Implement export chat
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Export Chat - Coming soon!')),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6B7280), // Gray
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                      child: const Text('Export Chat'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTypingPreviewBubble() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFFA32CC4), // Purple color for typing preview
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          '${widget.otherUser.fullName}: $_typingPreview',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(Message message, bool isSentByMe) {
    final bool isImage = message.messageType == 'image' || 
        (message.fileType?.startsWith('image/') ?? false);
    final bool isVideo = message.messageType == 'video' || 
        (message.fileType?.startsWith('video/') ?? false);
    final bool isAudio = message.messageType == 'voice' || 
        message.messageType == 'audio' ||
        (message.fileType?.startsWith('audio/') ?? false);
    final bool isMedia = isImage || isVideo;
    
    return Align(
      alignment: isSentByMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isSentByMe ? const Color(0xFF420796) : const Color(0xFF3944BC),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isSentByMe ? 16 : 4),
            bottomRight: Radius.circular(isSentByMe ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image/Video content
            if (isMedia && message.fileUrl != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(message.content.isNotEmpty && !_isOnlyFilename(message.content) ? 0 : (isSentByMe ? 16 : 4)),
                  bottomRight: Radius.circular(message.content.isNotEmpty && !_isOnlyFilename(message.content) ? 0 : (isSentByMe ? 4 : 16)),
                ),
                child: GestureDetector(
                  onTap: () => _openMediaViewer(message),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (isImage)
                        Image.network(
                          message.fileUrl!,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Container(
                              height: 150,
                              color: Colors.grey[800],
                              child: Center(
                                child: CircularProgressIndicator(
                                  value: loadingProgress.expectedTotalBytes != null
                                      ? loadingProgress.cumulativeBytesLoaded / 
                                        loadingProgress.expectedTotalBytes!
                                      : null,
                                  color: Colors.white,
                                ),
                              ),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              height: 100,
                              color: Colors.grey[800],
                              child: const Center(
                                child: Icon(Icons.broken_image, color: Colors.white54, size: 40),
                              ),
                            );
                          },
                        )
                      else if (isVideo)
                        Container(
                          height: 150,
                          color: Colors.black87,
                          child: const Center(
                            child: Icon(Icons.play_circle_fill, color: Colors.white, size: 60),
                          ),
                        ),
                      // Play button overlay for video
                      if (isVideo)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.black45,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.play_arrow, color: Colors.white, size: 36),
                        ),
                    ],
                  ),
                ),
              ),
            ],
            // Audio/Voice message content
            if (isAudio && message.fileUrl != null) ...[
              _AudioMessagePlayer(
                audioUrl: message.fileUrl!,
                fileSize: message.fileSize,
              ),
            ],
            // Text content (if not just filename and not audio)
            if ((!isMedia && !isAudio) || (message.content.isNotEmpty && !_isOnlyFilename(message.content) && !isAudio))
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Text(
                  isMedia ? (message.fileName ?? message.content) : message.content,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                  ),
                ),
              )
            else if (isMedia || isAudio)
              const SizedBox(height: 8),
            // Timestamp and read status
            Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                bottom: 8,
                top: isMedia && (message.content.isEmpty || _isOnlyFilename(message.content)) ? 0 : 0,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Show file size for file messages
                  if (message.fileSize != null && message.fileSize! > 0) ...[
                    Text(
                      _formatFileSize(message.fileSize!),
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 11,
                      ),
                    ),
                    Text(
                      ' • ',
                      style: TextStyle(color: Colors.grey[500], fontSize: 11),
                    ),
                  ],
                  Text(
                    message.formattedTime,
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 11,
                    ),
                  ),
                  if (isSentByMe) ...[
                    const SizedBox(width: 4),
                    Icon(
                      message.isRead
                          ? Icons.done_all
                          : (message.status == 'delivered'
                              ? Icons.done_all
                              : Icons.done),
                      size: 14,
                      color: message.isRead ? const Color(0xFF4CAF50) : Colors.grey[400],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Check if content is just a filename (for media messages)
  bool _isOnlyFilename(String content) {
    if (content.isEmpty) return true;
    // Check if it looks like a filename with extension
    final filenamePattern = RegExp(r'^[\w\-\.\s]+\.\w{2,5}$');
    return filenamePattern.hasMatch(content.trim());
  }

  /// Open full screen media viewer
  void _openMediaViewer(Message message) {
    if (message.fileUrl == null) return;
    
    final isVideo = message.messageType == 'video' || 
        (message.fileType?.startsWith('video/') ?? false);
    
    if (isVideo) {
      // For video, we could open in external player or implement video player
      // For now, show a snackbar
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Video: ${message.fileName ?? "Video"}'),
          action: SnackBarAction(
            label: 'Open',
            onPressed: () {
              // Could use url_launcher to open video URL
            },
          ),
        ),
      );
    } else {
      // Show image in full screen dialog
      showDialog(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.zero,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Dark background
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(color: Colors.black87),
              ),
              // Image
              Center(
                child: InteractiveViewer(
                  child: Image.network(
                    message.fileUrl!,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              // Close button
              Positioned(
                top: 40,
                right: 16,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 30),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  Color _getAvatarColor() {
    const colors = [
      Color(0xFFE91E63),
      Color(0xFF9C27B0),
      Color(0xFF673AB7),
      Color(0xFF3F51B5),
      Color(0xFF2196F3),
      Color(0xFF00BCD4),
      Color(0xFF009688),
      Color(0xFF4CAF50),
      Color(0xFFFF9800),
      Color(0xFFFF5722),
    ];
    return colors[widget.otherUser.avatarColorIndex % colors.length];
  }
}

/// Voice Recording Modal Widget
class _VoiceRecordingModal extends StatefulWidget {
  final Function(String path, Duration duration) onSend;
  final VoidCallback onCancel;

  const _VoiceRecordingModal({
    required this.onSend,
    required this.onCancel,
  });

  @override
  State<_VoiceRecordingModal> createState() => _VoiceRecordingModalState();
}

class _VoiceRecordingModalState extends State<_VoiceRecordingModal> {
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  final FlutterSoundPlayer _player = FlutterSoundPlayer();
  
  bool _isRecorderInitialized = false;
  bool _isPlayerInitialized = false;
  bool _isRecording = false;
  bool _isPaused = false;
  bool _hasRecording = false;
  String? _recordingPath;
  Duration _duration = Duration.zero;
  Timer? _timer;
  List<double> _waveformData = [];
  bool _isPlaying = false;
  StreamSubscription? _recorderSubscription;

  @override
  void initState() {
    super.initState();
    _initRecorder();
  }

  Future<void> _initRecorder() async {
    try {
      await _recorder.openRecorder();
      await _player.openPlayer();
      setState(() {
        _isRecorderInitialized = true;
        _isPlayerInitialized = true;
      });
      
      // Set up subscription for recording updates
      _recorder.setSubscriptionDuration(const Duration(milliseconds: 100));
    } catch (e) {
      debugPrint('Error initializing recorder: $e');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _recorderSubscription?.cancel();
    _recorder.closeRecorder();
    _player.closePlayer();
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  Future<void> _startRecording() async {
    if (!_isRecorderInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recorder not initialized')),
      );
      return;
    }
    
    try {
      final directory = await getTemporaryDirectory();
      final path = '${directory.path}/voice_${DateTime.now().millisecondsSinceEpoch}.aac';
      
      _recorderSubscription = _recorder.onProgress?.listen((e) {
        if (mounted && _isRecording && !_isPaused) {
          setState(() {
            _duration = e.duration;
            // Generate waveform data from decibels
            final db = e.decibels ?? -160.0;
            final normalized = ((db + 160) / 160).clamp(0.1, 1.0);
            _waveformData.add(normalized);
            if (_waveformData.length > 50) {
              _waveformData.removeAt(0);
            }
          });
        }
      });
      
      await _recorder.startRecorder(
        toFile: path,
        codec: Codec.aacADTS,
      );
      
      setState(() {
        _isRecording = true;
        _isPaused = false;
        _recordingPath = path;
        _duration = Duration.zero;
        _waveformData = [];
      });
    } catch (e) {
      debugPrint('Error starting recording: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error starting recording: $e')),
      );
    }
  }

  Future<void> _pauseRecording() async {
    try {
      await _recorder.pauseRecorder();
      setState(() => _isPaused = true);
    } catch (e) {
      debugPrint('Error pausing recording: $e');
    }
  }

  Future<void> _resumeRecording() async {
    try {
      await _recorder.resumeRecorder();
      setState(() => _isPaused = false);
    } catch (e) {
      debugPrint('Error resuming recording: $e');
    }
  }

  Future<void> _stopRecording() async {
    try {
      _recorderSubscription?.cancel();
      await _recorder.stopRecorder();
      setState(() {
        _isRecording = false;
        _isPaused = false;
        _hasRecording = true;
      });
    } catch (e) {
      debugPrint('Error stopping recording: $e');
    }
  }

  Future<void> _playRecording() async {
    if (_recordingPath == null || !_isPlayerInitialized) return;
    try {
      await _player.startPlayer(
        fromURI: _recordingPath!,
        whenFinished: () {
          if (mounted) setState(() => _isPlaying = false);
        },
      );
      setState(() => _isPlaying = true);
    } catch (e) {
      debugPrint('Error playing recording: $e');
    }
  }

  Future<void> _stopPlaying() async {
    try {
      await _player.stopPlayer();
      setState(() => _isPlaying = false);
    } catch (e) {
      debugPrint('Error stopping playback: $e');
    }
  }

  void _discardRecording() {
    setState(() {
      _hasRecording = false;
      _waveformData = [];
      _duration = Duration.zero;
    });
    // Delete the file
    if (_recordingPath != null) {
      try {
        File(_recordingPath!).delete();
      } catch (_) {}
    }
    _recordingPath = null;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.45,
      decoration: const BoxDecoration(
        color: Color(0xFF2D2D2D),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[600],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          
          // Title
          const Text(
            'Voice Message',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),
          
          // Duration display
          Text(
            _formatDuration(_duration),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 48,
              fontWeight: FontWeight.w300,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 24),
          
          // Waveform visualization
          Container(
            height: 60,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (int i = 0; i < 50; i++)
                  Container(
                    width: 4,
                    height: (i < _waveformData.length ? _waveformData[i] : 0.1) * 50,
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    decoration: BoxDecoration(
                      color: _isRecording && !_isPaused
                          ? const Color(0xFFEF4444)
                          : (_hasRecording ? const Color(0xFF10B981) : Colors.grey[600]),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          
          // Controls
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (!_isRecording && !_hasRecording) ...[
                    // Initial state - Start button
                    ElevatedButton.icon(
                      onPressed: _isRecorderInitialized ? _startRecording : null,
                      icon: const Icon(Icons.mic, size: 28),
                      label: Text(
                        _isRecorderInitialized ? 'Start Recording' : 'Initializing...',
                        style: const TextStyle(fontSize: 18),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEF4444),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      ),
                    ),
                  ] else if (_isRecording) ...[
                    // Recording state - Pause/Resume and Stop
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Pause/Resume button
                        IconButton(
                          onPressed: _isPaused ? _resumeRecording : _pauseRecording,
                          icon: Icon(
                            _isPaused ? Icons.play_arrow : Icons.pause,
                            size: 36,
                            color: Colors.white,
                          ),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.grey[700],
                            padding: const EdgeInsets.all(16),
                          ),
                        ),
                        const SizedBox(width: 24),
                        // Stop button
                        IconButton(
                          onPressed: _stopRecording,
                          icon: const Icon(Icons.stop, size: 36, color: Colors.white),
                          style: IconButton.styleFrom(
                            backgroundColor: const Color(0xFFEF4444),
                            padding: const EdgeInsets.all(16),
                          ),
                        ),
                      ],
                    ),
                  ] else if (_hasRecording) ...[
                    // Has recording - Play, Discard, Send
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Discard button
                        IconButton(
                          onPressed: _discardRecording,
                          icon: const Icon(Icons.delete, size: 28, color: Colors.white),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.grey[700],
                            padding: const EdgeInsets.all(12),
                          ),
                        ),
                        // Play/Stop button
                        IconButton(
                          onPressed: _isPlaying ? _stopPlaying : _playRecording,
                          icon: Icon(
                            _isPlaying ? Icons.stop : Icons.play_arrow,
                            size: 36,
                            color: Colors.white,
                          ),
                          style: IconButton.styleFrom(
                            backgroundColor: const Color(0xFF3B82F6),
                            padding: const EdgeInsets.all(16),
                          ),
                        ),
                        // Send button
                        IconButton(
                          onPressed: () {
                            if (_recordingPath != null) {
                              widget.onSend(_recordingPath!, _duration);
                            }
                          },
                          icon: const Icon(Icons.send, size: 28, color: Colors.white),
                          style: IconButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
                            padding: const EdgeInsets.all(12),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          
          // Cancel button
          Padding(
            padding: const EdgeInsets.only(bottom: 32),
            child: TextButton(
              onPressed: () async {
                if (_isRecording) {
                  await _recorder.stopRecorder();
                }
                widget.onCancel();
              },
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Audio Message Player Widget for playing voice messages in chat
class _AudioMessagePlayer extends StatefulWidget {
  final String audioUrl;
  final int? fileSize;

  const _AudioMessagePlayer({
    required this.audioUrl,
    this.fileSize,
  });

  @override
  State<_AudioMessagePlayer> createState() => _AudioMessagePlayerState();
}

class _AudioMessagePlayerState extends State<_AudioMessagePlayer> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  StreamSubscription? _durationSubscription;
  StreamSubscription? _positionSubscription;
  StreamSubscription? _completeSubscription;

  @override
  void initState() {
    super.initState();
    _setupAudioPlayer();
  }

  void _setupAudioPlayer() {
    _durationSubscription = _audioPlayer.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    
    _positionSubscription = _audioPlayer.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    
    _completeSubscription = _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _position = Duration.zero;
        });
      }
    });
  }

  @override
  void dispose() {
    _durationSubscription?.cancel();
    _positionSubscription?.cancel();
    _completeSubscription?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _togglePlayPause() async {
    try {
      if (_isPlaying) {
        await _audioPlayer.pause();
        setState(() => _isPlaying = false);
      } else {
        await _audioPlayer.play(UrlSource(widget.audioUrl));
        setState(() => _isPlaying = true);
      }
    } catch (e) {
      debugPrint('Error playing audio: $e');
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final progress = _duration.inMilliseconds > 0
        ? _position.inMilliseconds / _duration.inMilliseconds
        : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Play/Pause button
          GestureDetector(
            onTap: _togglePlayPause,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
                size: 28,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Waveform and progress
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Waveform visualization (static bars)
                Row(
                  children: List.generate(20, (index) {
                    final barHeight = [8.0, 14.0, 10.0, 18.0, 12.0, 20.0, 16.0, 22.0, 14.0, 18.0,
                                       12.0, 16.0, 20.0, 14.0, 10.0, 18.0, 12.0, 8.0, 14.0, 10.0][index];
                    final isPlayed = progress > (index / 20);
                    return Container(
                      width: 3,
                      height: barHeight,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        color: isPlayed ? Colors.white : Colors.white38,
                        borderRadius: BorderRadius.circular(1.5),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 4),
                // Duration text
                Text(
                  _isPlaying || _position > Duration.zero
                      ? '${_formatDuration(_position)} / ${_formatDuration(_duration)}'
                      : _formatDuration(_duration),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
