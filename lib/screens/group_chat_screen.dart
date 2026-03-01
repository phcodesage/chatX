import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mime/mime.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/group.dart';
import '../services/group_service.dart';
import '../services/socket_service.dart';
import '../services/storage_service.dart';
import '../services/chat_cache_service.dart';
import '../services/translation_service.dart';
import '../services/active_chat_service.dart';
import '../widgets/reaction_picker.dart';

/// Group chat screen for messaging in a group
class GroupChatScreen extends StatefulWidget {
  final Group group;

  const GroupChatScreen({super.key, required this.group});

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final SocketService _socketService = SocketService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final FocusNode _inputFocusNode = FocusNode();

  List<GroupMessage> _messages = [];
  bool _isLoading = true;
  bool _isLoadingMessages = false;
  int? _currentUserId;

  // Scroll to bottom button state
  bool _isAtBottom = true;

  // Reply state
  GroupMessage? _replyingToMessage;

  // Reaction state
  final Map<int, Map<String, Set<String>>> _messageReactions = {};

  // Action buttons state
  bool _showActionButtons = false;

  // Emoji picker state for chat input
  bool _showEmojiPicker = false;
  int _emojiCategoryIndex = 0;

  // Keyboard visibility state
  bool _isKeyboardVisible = false;

  // Timestamp visibility toggle
  bool _showTimestamps = false;

  // Auto-translate toggle
  bool _autoTranslate = false;

  // Translation state: { messageId: translatedText }
  final Map<int, String> _messageTranslations = {};

  // Color customization (for group chat theme)
  bool _showResetButton = false;

  // Admin status
  bool _currentUserIsAdmin = false;

  // Typing indicator state
  String _typingUserName = '';
  String _typingMessage = '';
  Timer? _typingHideTimer;
  Timer? _typingEmitTimer;

  @override
  void initState() {
    super.initState();
    _inputFocusNode.addListener(_onFocusChange);
    _scrollController.addListener(_onScroll);
    _initialize();

    // Set this group as active to prevent FCM notifications
    ActiveChatService().setActiveGroup(widget.group.id);

    // Debug: Periodic connection check
    Timer.periodic(const Duration(seconds: 10), (timer) {
      if (mounted) {
        debugPrint(
          '🔌 [GROUP CHAT] Socket connected: ${_socketService.isConnected}',
        );
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _initialize() async {
    _currentUserId = await StorageService.getUserId();
    await _loadMessages();
    _setupRealtimeListeners();
    _socketService.joinGroupChat(widget.group.id);

    // Debug: Test socket connection with multiple approaches
    debugPrint('🧪 [GROUP CHAT] Testing socket connection...');
    _socketService.emit('test_connection', {'test': 'mobile_group_chat'});

    // Also test with a simple ping
    Future.delayed(const Duration(seconds: 2), () {
      debugPrint('🧪 [GROUP CHAT] Testing with ping...');
      _socketService.emit('ping', {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    });
  }

  void _onFocusChange() {
    // Only update if keyboard visibility actually changed
    final isVisible = _inputFocusNode.hasFocus;
    if (_isKeyboardVisible != isVisible) {
      setState(() {
        _isKeyboardVisible = isVisible;
        // Auto-close emoji picker when keyboard opens (user tapped text field)
        if (isVisible && _showEmojiPicker) {
          _showEmojiPicker = false;
        }
      });
    }
  }

  void _setupRealtimeListeners() {
    final key = 'group_chat_${widget.group.id}';

    // Debug: Check socket connection status
    debugPrint(
      '🔌 [GROUP CHAT] Setting up listeners, socket connected: ${_socketService.isConnected}',
    );

    // Debug: Test response listener
    _socketService.addListener('test_response', key, (data) {
      debugPrint('🧪 [TEST RESPONSE] Received in group chat screen: $data');
      debugPrint(
        '🧪 [TEST RESPONSE] This confirms mobile can receive Socket.IO events!',
      );
    });

    // Debug: Connection change listener
    _socketService.addListener('connectionChanged', key, (data) {
      debugPrint('🔌 [GROUP CHAT] Connection changed: $data');
    });

    // New message from another member
    _socketService.addListener('groupNewMessage', key, (data) {
      debugPrint(
        '💬 [GROUP NEW MESSAGE] Event received for group ${widget.group.id}',
      );
      debugPrint('💬 [GROUP NEW MESSAGE] Full data: $data');
      debugPrint('💬 [GROUP NEW MESSAGE] Data type: ${data.runtimeType}');
      debugPrint(
        '💬 [GROUP NEW MESSAGE] Group ID in data: ${data['group_id']}',
      );
      debugPrint('💬 [GROUP NEW MESSAGE] Current group ID: ${widget.group.id}');

      if (data['group_id'] == widget.group.id) {
        debugPrint(
          '💬 [GROUP NEW MESSAGE] Processing message for current group',
        );
        _handleNewMessage(data);
      } else {
        debugPrint(
          '💬 [GROUP NEW MESSAGE] Ignoring message for different group: ${data['group_id']}',
        );
      }
    });

    // Message sent confirmation
    _socketService.addListener('groupMessageSent', key, (data) {
      debugPrint('📤 [GROUP MESSAGE SENT] Event received: $data');
      if (data['group_id'] == widget.group.id) {
        debugPrint('📤 [GROUP MESSAGE SENT] Processing for current group');
        _handleMessageSent(data);
      }
    });

    // File message (also comes through groupNewMessage)
    _socketService.addListener('groupFileMessage', key, (data) {
      debugPrint('📎 [GROUP FILE MESSAGE] Event received: $data');
      if (data['group_id'] == widget.group.id) {
        debugPrint('📎 [GROUP FILE MESSAGE] Processing for current group');
        _handleNewMessage(data);
      }
    });

    // Message deleted
    _socketService.addListener('groupMessageDeleted', key, (data) {
      debugPrint('🗑️ [GROUP MESSAGE DELETED] Event received: $data');
      if (data['group_id'] == widget.group.id) {
        debugPrint('🗑️ [GROUP MESSAGE DELETED] Processing for current group');
        _handleMessageDeleted(data);
      }
    });

    // Message edited
    _socketService.addListener('groupMessageEdited', key, (data) {
      debugPrint('✏️ [GROUP MESSAGE EDITED] Event received: $data');
      if (data['group_id'] == widget.group.id) {
        debugPrint('✏️ [GROUP MESSAGE EDITED] Processing for current group');
        _handleMessageEdited(data);
      }
    });

    // Reaction updated
    _socketService.addListener('groupReactionUpdated', key, (data) {
      debugPrint('👍 [GROUP REACTION UPDATED] Event received: $data');
      if (data['group_id'] == widget.group.id) {
        debugPrint('👍 [GROUP REACTION UPDATED] Processing for current group');
        _handleReactionUpdated(data);
      }
    });

    // Reaction cleared
    _socketService.addListener('groupReactionCleared', key, (data) {
      debugPrint('❌ [GROUP REACTION CLEARED] Event received: $data');
      if (data['group_id'] == widget.group.id) {
        debugPrint('❌ [GROUP REACTION CLEARED] Processing for current group');
        _handleReactionCleared(data);
      }
    });

    // Doorbell notification
    _socketService.addListener('groupDoorbell', key, (data) {
      debugPrint('🔔 [GROUP DOORBELL] Event received: $data');
      if (data['group_id'] == widget.group.id) {
        debugPrint('🔔 [GROUP DOORBELL] Processing for current group');
        _handleGroupDoorbell(data);
      }
    });

    // Typing indicator
    _socketService.addListener('groupTyping', key, (data) {
      debugPrint('⌨️ [GROUP TYPING] Event received: $data');
      if (data['group_id'] == widget.group.id) {
        debugPrint('⌨️ [GROUP TYPING] Processing for current group');
        _handleGroupUserTyping(data);
      }
    });
  }

  Future<void> _loadMessages() async {
    if (_isLoadingMessages) return;
    setState(() {
      _isLoadingMessages = true;
      _isLoading = true;
    });

    try {
      final messages = await GroupService.getMessages(
        groupId: widget.group.id,
        limit: 50,
      );

      if (mounted) {
        setState(() {
          _messages = messages.reversed.toList();
          _isLoading = false;
          _isLoadingMessages = false;
        });

        // Mark messages as viewed
        _markMessagesAsViewed();

        // Scroll to bottom
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(
              _scrollController.position.maxScrollExtent,
            );
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading group messages: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingMessages = false;
        });
      }
    }
  }

  void _handleNewMessage(Map<String, dynamic> data) async {
    debugPrint('📨 [GROUP NEW MESSAGE] Received: data=$data');
    debugPrint('📨 [GROUP NEW MESSAGE] Attempting to parse message...');

    try {
      final message = GroupMessage.fromJson(data);
      debugPrint(
        '📨 [GROUP NEW MESSAGE] Successfully parsed message: ${message.id}',
      );
      debugPrint('📨 [GROUP NEW MESSAGE] Message content: ${message.content}');
      debugPrint('📨 [GROUP NEW MESSAGE] Sender ID: ${message.senderId}');
      debugPrint('📨 [GROUP NEW MESSAGE] Current user ID: $_currentUserId');

      if (mounted) {
        debugPrint(
          '📨 [GROUP NEW MESSAGE] Widget is mounted, adding to messages list',
        );
        setState(() {
          _messages.add(message);
          debugPrint(
            '📨 [GROUP NEW MESSAGE] Messages count: ${_messages.length}',
          );
        });

        // Auto-translate incoming message if enabled and it's a text message from another user
        if (_autoTranslate &&
            message.senderId != _currentUserId &&
            message.messageType == 'text' &&
            message.content.isNotEmpty) {
          _autoTranslateGroupMessage(message);
        }

        // Save to cache for offline access
        await ChatCacheService.addGroupMessageToCache(widget.group.id, message);
        debugPrint('💾 Cached group message ${message.id}');

        // Play notification sound if not from current user
        if (message.senderId != _currentUserId) {
          debugPrint(
            '🔊 Playing notification sound for message from other user',
          );
          _playNotificationSound();
        }

        // Mark as viewed if at bottom
        if (_isAtBottom) {
          debugPrint(
            '📨 [GROUP NEW MESSAGE] At bottom, marking messages as viewed',
          );
          _markMessagesAsViewed();
        }

        // Scroll to bottom
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients && _isAtBottom) {
            debugPrint('📨 [GROUP NEW MESSAGE] Scrolling to bottom');
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      } else {
        debugPrint(
          '📨 [GROUP NEW MESSAGE] Widget not mounted, ignoring message',
        );
      }
    } catch (e, stackTrace) {
      debugPrint('❌ [GROUP NEW MESSAGE] Error parsing message: $e');
      debugPrint('❌ [GROUP NEW MESSAGE] Stack trace: $stackTrace');
      debugPrint('❌ [GROUP NEW MESSAGE] Raw data: $data');
    }
  }

  void _handleMessageSent(Map<String, dynamic> data) {
    // Message sent confirmation - replace optimistic message with real message
    final messageId = data['message_id'] as int?;
    final senderId = data['sender_id'] as int?;
    final messageType = data['message_type'] as String? ?? 'text';

    debugPrint(
      '📨 [GROUP MESSAGE SENT] Received: messageId=$messageId, senderId=$senderId, type=$messageType, currentUserId=$_currentUserId',
    );

    if (messageId == null) return;

    if (mounted) {
      setState(() {
        // If this is from the current user, replace optimistic message
        if (senderId == _currentUserId) {
          // Find optimistic message (temporary ID > 1000000000000 - timestamp range)
          final optimisticIndex = _messages.indexWhere(
            (m) =>
                m.id > 1000000000000 && // Temporary ID range
                m.senderId == _currentUserId &&
                (m.content == data['content'] || // For text messages
                    (messageType != 'text' &&
                        m.messageType ==
                            messageType)), // For file messages, match by type
          );

          if (optimisticIndex != -1) {
            debugPrint(
              '📨 [GROUP MESSAGE SENT] Replacing optimistic message at index $optimisticIndex',
            );
            _messages[optimisticIndex] = GroupMessage.fromJson(data);
          } else {
            debugPrint(
              '📨 [GROUP MESSAGE SENT] No optimistic message found, adding new message',
            );
            // Fallback: add message if no optimistic message found
            final message = GroupMessage.fromJson(data);
            _messages.add(message);
          }
        } else {
          // Message from another user - this shouldn't happen in groupMessageSent
          debugPrint(
            '📨 [GROUP MESSAGE SENT] Ignoring message from other user: $senderId',
          );
        }
      });
    }
  }

  void _handleMessageDeleted(Map<String, dynamic> data) {
    final messageId = data['message_id'] as int?;
    if (messageId == null) return;

    if (mounted) {
      setState(() {
        _messages.removeWhere((m) => m.id == messageId);
      });
    }
  }

  void _handleMessageEdited(Map<String, dynamic> data) {
    final messageId = data['message_id'] as int?;
    final newContent = data['content'] as String?;
    if (messageId == null || newContent == null) return;

    if (mounted) {
      setState(() {
        final index = _messages.indexWhere((m) => m.id == messageId);
        if (index != -1) {
          _messages[index] = GroupMessage.fromJson({
            ..._messages[index].toJson(),
            'content': newContent,
          });
        }
      });
    }
  }

  void _handleReactionUpdated(Map<String, dynamic> data) {
    final messageId = data['message_id'] as int?;
    final reactions = data['reactions'] as Map<String, dynamic>?;
    if (messageId == null || reactions == null) return;

    if (mounted) {
      setState(() {
        final index = _messages.indexWhere((m) => m.id == messageId);
        if (index != -1) {
          _messages[index] = GroupMessage.fromJson({
            ..._messages[index].toJson(),
            'reactions': reactions,
          });
        }
      });
    }
  }

  void _handleReactionCleared(Map<String, dynamic> data) {
    _handleReactionUpdated(data);
  }

  void _handleGroupDoorbell(Map<String, dynamic> data) {
    final senderName = data['sender_name'] as String?;
    final senderId = data['sender_id'] as int?;
    final timestampMs =
        data['timestamp_ms'] as int? ?? DateTime.now().millisecondsSinceEpoch;

    // Don't show notification if we sent it
    if (senderId == _currentUserId) {
      debugPrint('Ignoring own doorbell notification');
      return;
    }

    // Check if we already have this doorbell notification to prevent duplicates
    final alreadyExists = _messages.any(
      (msg) =>
          msg.messageType == 'system' &&
          msg.timestampMs == timestampMs &&
          msg.content.contains('rang the doorbell'),
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

    // Create doorbell system message
    final doorbellMessage = GroupMessage(
      id: timestampMs,
      messageId: timestampMs,
      groupId: widget.group.id,
      senderId: senderId ?? 0,
      sender: GroupMessageSender(
        id: senderId ?? 0,
        username: senderName ?? 'Someone',
        firstName: senderName ?? 'Someone',
        lastName: '',
        fullName: senderName ?? 'Someone',
      ),
      content: '${senderName ?? "Someone"} rang the doorbell 🔔',
      messageType: 'system',
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        timestampMs,
      ).toIso8601String(),
      timestampMs: timestampMs,
      reactions: {},
    );

    setState(() {
      _messages.add(doorbellMessage);
    });

    // Scroll to bottom to show the notification
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });

    // Show snackbar notification
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🔔 ${senderName ?? "Someone"} rang the doorbell'),
          duration: const Duration(seconds: 3),
          backgroundColor: const Color(0xFF4C1D95),
        ),
      );
    }
  }

  void _handleGroupUserTyping(Map<String, dynamic> data) {
    final userId = data['user_id'] as int?;
    final username = data['username'] as String?;
    final fullName = data['full_name'] as String?;
    final message = data['message'] as String? ?? '';

    // Don't show typing indicator for own messages
    if (userId == _currentUserId) {
      return;
    }

    final displayName = fullName ?? username ?? 'Someone';

    // Cancel previous hide timer
    _typingHideTimer?.cancel();

    if (mounted) {
      setState(() {
        _typingUserName = displayName;
        _typingMessage = message;
      });

      // Auto-hide after 3 seconds
      _typingHideTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _typingUserName = '';
            _typingMessage = '';
          });
        }
      });
    }
  }

  void _markMessagesAsViewed() {
    if (_messages.isEmpty || _currentUserId == null) return;

    // Get unread messages from others
    final unreadMessages = _messages
        .where((m) => m.senderId != _currentUserId)
        .map((m) => m.id)
        .toList();

    if (unreadMessages.isEmpty) return;

    // Group by sender
    final bySender = <int, List<int>>{};
    for (final msg in _messages.where((m) => m.senderId != _currentUserId)) {
      bySender.putIfAbsent(msg.senderId, () => []).add(msg.id);
    }

    // Mark as viewed for each sender
    for (final entry in bySender.entries) {
      GroupService.markMessagesViewed(
        groupId: widget.group.id,
        messageIds: entry.value,
        senderId: entry.key,
      );
    }
  }

  Future<void> _playNotificationSound() async {
    try {
      await _audioPlayer.play(AssetSource('sounds/notif-sound.wav'));
    } catch (e) {
      debugPrint('Error playing notification sound: $e');
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final isAtBottom =
        _scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 100;

    if (isAtBottom != _isAtBottom) {
      setState(() => _isAtBottom = isAtBottom);

      if (isAtBottom) {
        _markMessagesAsViewed();
      }
    }
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;

    // Capture reply info before clearing
    final replyToId = _replyingToMessage?.id;

    // Generate a temporary ID for optimistic update
    final tempId = DateTime.now().millisecondsSinceEpoch;
    final now = DateTime.now();

    // Create optimistic message
    final optimisticMessage = GroupMessage(
      id: tempId, // Temporary ID
      messageId: tempId, // Use same temp ID for messageId
      groupId: widget.group.id,
      senderId: _currentUserId!,
      sender: null, // Will be updated with real data
      content: content,
      messageType: 'text',
      timestamp: now.toIso8601String(),
      timestampMs: now.millisecondsSinceEpoch,
      replyToId: replyToId,
    );

    // Clear input and reply state immediately for better UX
    _messageController.clear();
    setState(() {
      _replyingToMessage = null;
      _showActionButtons = false; // Hide action buttons after sending
      // Add optimistic message immediately
      _messages.add(optimisticMessage);
    });

    // Scroll to bottom after adding optimistic message
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });

    try {
      // Send message via API (this will trigger groupMessageSent event)
      await GroupService.sendMessage(
        groupId: widget.group.id,
        content: content,
        replyToId: replyToId,
      );

      // Don't add message here - wait for socket confirmation
      debugPrint(
        '📤 Message sent successfully, waiting for socket confirmation',
      );
    } catch (e) {
      debugPrint('Error sending message: $e');

      // Remove optimistic message on error
      if (mounted) {
        setState(() {
          _messages.removeWhere((m) => m.id == tempId);
        });

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send message: $e')));
      }
    }
  }

  Future<void> _pickAndSendImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);

    if (image == null) return;

    await _uploadFile(File(image.path));
  }

  Future<void> _pickAndSendFile() async {
    final result = await FilePicker.platform.pickFiles();

    if (result == null || result.files.isEmpty) return;

    final file = File(result.files.first.path!);
    await _uploadFile(file);
  }

  Future<void> _uploadFile(File file) async {
    // Generate a temporary ID for optimistic update
    final tempId = DateTime.now().millisecondsSinceEpoch;
    final now = DateTime.now();

    // Determine file type and create appropriate optimistic message
    final mimeType = lookupMimeType(file.path) ?? 'application/octet-stream';
    final fileName = file.path.split('/').last;
    final fileSize = await file.length();

    String messageType = 'file';
    String content = fileName;

    if (mimeType.startsWith('image/')) {
      messageType = 'image';
      content = 'Image: $fileName';
    } else if (mimeType.startsWith('video/')) {
      messageType = 'video';
      content = 'Video: $fileName';
    } else if (mimeType.startsWith('audio/')) {
      messageType = 'audio';
      content = 'Audio: $fileName';
    }

    // Create optimistic message
    final optimisticMessage = GroupMessage(
      id: tempId, // Temporary ID
      messageId: tempId, // Use same temp ID for messageId
      groupId: widget.group.id,
      senderId: _currentUserId!,
      sender: null, // Will be updated with real data
      content: content,
      messageType: messageType,
      timestamp: now.toIso8601String(),
      timestampMs: now.millisecondsSinceEpoch,
      fileName: fileName,
      fileSize: fileSize,
      fileType: mimeType,
    );

    // Add optimistic message immediately for responsive UI
    if (mounted) {
      setState(() {
        _messages.add(optimisticMessage);
      });

      // Scroll to bottom after adding optimistic message
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }

    try {
      // Upload file via API (this will trigger socket events)
      await GroupService.uploadFile(groupId: widget.group.id, file: file);

      // Don't add message here - wait for socket confirmation
      debugPrint(
        '📎 File uploaded successfully, waiting for socket confirmation',
      );
    } catch (e) {
      debugPrint('Error uploading file: $e');

      // Remove optimistic message on error
      if (mounted) {
        setState(() {
          _messages.removeWhere((m) => m.id == tempId);
        });

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to upload file: $e')));
      }
    }
  }

  Future<void> _deleteMessage(GroupMessage message) async {
    try {
      await GroupService.deleteMessage(
        groupId: widget.group.id,
        messageId: message.id,
      );

      if (mounted) {
        setState(() {
          _messages.removeWhere((m) => m.id == message.id);
        });
      }
    } catch (e) {
      debugPrint('Error deleting message: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to delete message: $e')));
      }
    }
  }

  Future<void> _addReaction(GroupMessage message, String emoji) async {
    try {
      final reactions = await GroupService.addReaction(
        groupId: widget.group.id,
        messageId: message.id,
        emoji: emoji,
      );

      if (mounted) {
        setState(() {
          final index = _messages.indexWhere((m) => m.id == message.id);
          if (index != -1) {
            _messages[index] = GroupMessage.fromJson({
              ..._messages[index].toJson(),
              'reactions': reactions,
            });
          }
        });
      }
    } catch (e) {
      debugPrint('Error adding reaction: $e');
    }
  }

  @override
  void dispose() {
    // Clear active chat when leaving group chat screen
    ActiveChatService().clearActiveChat();

    _socketService.removeListenersForKey('group_chat_${widget.group.id}');
    _socketService.leaveGroupChat(widget.group.id);
    _messageController.dispose();
    _scrollController.dispose();
    _audioPlayer.dispose();
    _inputFocusNode.dispose();
    _typingHideTimer?.cancel();
    _typingEmitTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: _buildAppBar(),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: Column(
          children: [
            // Messages list
            Expanded(
              child: _isLoading
                  ? _buildLoadingShimmer()
                  : _messages.isEmpty
                  ? const Center(
                      child: Text(
                        'No messages yet\nBe the first to send a message!',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey, fontSize: 16),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        return _buildMessageBubble(_messages[index]);
                      },
                    ),
            ),

            // Typing indicator
            if (_typingUserName.isNotEmpty) _buildTypingIndicator(),

            // Reply preview
            if (_replyingToMessage != null) _buildReplyPreview(),

            // Input area
            _buildInputArea(),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF4C1D95),
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () => Navigator.pop(context),
      ),
      title: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: const Color(0xFF00D9FF),
            child: widget.group.avatarUrl != null
                ? ClipOval(
                    child: Image.network(
                      widget.group.avatarUrl!,
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.group,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  )
                : const Icon(Icons.group, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.group.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${widget.group.memberCount} members',
                  style: TextStyle(color: Colors.grey[300], fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        // Doorbell button
        IconButton(
          icon: const Icon(Icons.notifications, color: Colors.white),
          onPressed: () {
            try {
              // Use Socket.IO instead of REST API
              _socketService.ringGroupDoorbell(widget.group.id);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('🔔 Doorbell sent to all members'),
                    backgroundColor: Color(0xFF4C1D95),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Failed to ring doorbell: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            }
          },
          tooltip: 'Ring Doorbell',
        ),
        // More options menu
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: Colors.white),
          color: const Color(0xFF1E1E2E),
          onSelected: (value) {
            if (value == 'members') {
              // TODO: Show members list
            } else if (value == 'settings') {
              // TODO: Show group settings
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'members',
              child: Row(
                children: [
                  Icon(Icons.people, color: Colors.white, size: 20),
                  SizedBox(width: 12),
                  Text('Members', style: TextStyle(color: Colors.white)),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'settings',
              child: Row(
                children: [
                  Icon(Icons.settings, color: Colors.white, size: 20),
                  SizedBox(width: 12),
                  Text('Group Settings', style: TextStyle(color: Colors.white)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLoadingShimmer() {
    return ListView.builder(
      itemCount: 10,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: index % 2 == 0
                ? MainAxisAlignment.start
                : MainAxisAlignment.end,
            children: [
              Container(
                width: 200,
                height: 60,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMessageBubble(GroupMessage message) {
    // Handle system messages (doorbell, etc.)
    if (message.messageType == 'system') {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF4C1D95).withOpacity(0.3),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            message.content,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final isSentByMe = message.senderId == _currentUserId;
    final bool isImage =
        message.messageType == 'image' ||
        (message.fileType?.startsWith('image/') ?? false);
    final bool isVideo =
        message.messageType == 'video' ||
        (message.fileType?.startsWith('video/') ?? false);
    final bool isAudio =
        message.messageType == 'voice' ||
        message.messageType == 'audio' ||
        (message.fileType?.startsWith('audio/') ?? false);
    final bool isMedia = isImage || isVideo;

    // Check if this message has reactions to adjust bottom margin
    final hasReactions = message.reactions.isNotEmpty;

    // Build the main bubble widget
    final bubbleWidget = Container(
      margin: EdgeInsets.only(bottom: hasReactions ? 2 : 12),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.70,
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
          // Quoted reply (if this is a reply to another message)
          if (message.replyToId != null || message.replyPreview != null)
            Opacity(
              opacity: 0.85,
              child: Container(
                margin: const EdgeInsets.only(left: 8, right: 8, top: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(38),
                  borderRadius: BorderRadius.circular(6),
                  border: const Border(
                    left: BorderSide(color: Color(0xFFB794F6), width: 3),
                  ),
                ),
                child: Builder(
                  builder: (context) {
                    // Parse reply preview
                    final preview = message.replyPreview ?? '';
                    final colonIndex = preview.indexOf(':');
                    final senderName = colonIndex > 0
                        ? preview.substring(0, colonIndex)
                        : 'Reply';
                    var contentText = colonIndex > 0
                        ? preview.substring(colonIndex + 1).trim()
                        : preview;

                    // Improve display for file messages
                    if (contentText.contains('<audio') ||
                        contentText.contains('audio/')) {
                      contentText = '🎤 Voice message';
                    } else if (contentText.contains('<img') ||
                        contentText.contains('image/')) {
                      contentText = '📷 Photo';
                    } else if (contentText.contains('<video') ||
                        contentText.contains('video/')) {
                      contentText = '🎬 Video';
                    } else if (contentText.contains('file/') ||
                        contentText.endsWith('.pdf') ||
                        contentText.endsWith('.doc')) {
                      contentText = '📎 File';
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          senderName,
                          style: TextStyle(
                            color: Colors.white.withAlpha(230),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          contentText,
                          style: TextStyle(
                            color: Colors.white.withAlpha(179),
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          // Image/Video content
          if (isMedia && message.fileUrl != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(
                  message.content.isNotEmpty &&
                          !_isOnlyFilename(message.content)
                      ? 0
                      : (isSentByMe ? 16 : 4),
                ),
                bottomRight: Radius.circular(
                  message.content.isNotEmpty &&
                          !_isOnlyFilename(message.content)
                      ? 0
                      : (isSentByMe ? 4 : 16),
                ),
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
                                value:
                                    loadingProgress.expectedTotalBytes != null
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
                              child: Icon(
                                Icons.broken_image,
                                color: Colors.white54,
                                size: 40,
                              ),
                            ),
                          );
                        },
                      )
                    else if (isVideo)
                      Container(
                        height: 150,
                        color: Colors.black87,
                        child: const Center(
                          child: Icon(
                            Icons.play_circle_fill,
                            color: Colors.white,
                            size: 60,
                          ),
                        ),
                      ),
                    // Play button overlay for video
                    if (isVideo)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: const BoxDecoration(
                          color: Colors.black45,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.play_arrow,
                          color: Colors.white,
                          size: 36,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
          // Audio/Voice message content
          if (isAudio && message.fileUrl != null) ...[
            _buildAudioPlayer(message.fileUrl!),
          ],
          // Text content (if not just filename and not audio)
          if ((!isMedia && !isAudio) ||
              (message.content.isNotEmpty &&
                  !_isOnlyFilename(message.content) &&
                  !isAudio))
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: IntrinsicWidth(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Original message text
                    Text(
                      isMedia
                          ? (message.fileName ?? message.content)
                          : message.content,
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                    ),
                    // Translation (if available)
                    if (_messageTranslations.containsKey(message.id)) ...[
                      const SizedBox(height: 8),
                      // Separator line
                      Container(
                        height: 1,
                        color: Colors.white.withOpacity(0.3),
                        margin: const EdgeInsets.symmetric(vertical: 4),
                      ),
                      // Translated text with language indicator
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Globe icon
                          Icon(
                            Icons.language,
                            size: 14,
                            color: Colors.white.withOpacity(0.7),
                          ),
                          const SizedBox(width: 4),
                          // Language indicator (placeholder for now)
                          Text(
                            'auto → en',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // Translated text in italic
                      Text(
                        _messageTranslations[message.id]!,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 14,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            )
          else if (isMedia || isAudio)
            const SizedBox(height: 8),
          // Message status indicator and timestamp for sent messages
          if (isSentByMe)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Timestamp
                  Text(
                    message.formattedTime,
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                  const SizedBox(width: 4),
                  // Status indicator (simplified for groups)
                  const Icon(Icons.done_all, size: 16, color: Colors.white70),
                ],
              ),
            ),
        ],
      ),
    );

    // Wrap bubble with Column for reactions below
    return Align(
      alignment: isSentByMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isSentByMe
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Show sender name for group messages (except own messages)
          if (!isSentByMe && message.sender != null)
            Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 4),
              child: Text(
                message.sender!.fullName,
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          // The bubble
          GestureDetector(
            onLongPress: () =>
                _showGroupMessageContextMenu(message, isSentByMe),
            child: bubbleWidget,
          ),
          // Reaction pills below bubble
          if (hasReactions)
            Padding(
              padding: EdgeInsets.only(
                left: isSentByMe ? 0 : 8,
                right: isSentByMe ? 8 : 0,
                top: 0,
                bottom: 6,
              ),
              child: Wrap(
                spacing: 4,
                children: message.reactions.entries.map((entry) {
                  final emoji = entry.key;
                  final users = entry.value as List;
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF420796),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      '$emoji ${users.length}',
                      style: const TextStyle(fontSize: 12, color: Colors.white),
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
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
  void _openMediaViewer(GroupMessage message) {
    if (message.fileUrl == null) return;

    final isVideo =
        message.messageType == 'video' ||
        (message.fileType?.startsWith('video/') ?? false);

    if (isVideo) {
      // For video, show a snackbar
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
                  child: Image.network(message.fileUrl!, fit: BoxFit.contain),
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

  /// Build audio player widget
  Widget _buildAudioPlayer(String audioUrl) {
    return _AudioMessagePlayer(audioUrl: audioUrl);
  }

  Widget _buildTypingIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFF1E293B).withOpacity(0.5),
      child: Row(
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF8B5CF6)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(color: Colors.white70, fontSize: 14),
                children: [
                  TextSpan(
                    text: '$_typingUserName: ',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF8B5CF6),
                    ),
                  ),
                  TextSpan(
                    text: _typingMessage.isEmpty ? 'typing...' : _typingMessage,
                    style: TextStyle(
                      color: _typingMessage.isEmpty
                          ? Colors.white54
                          : Colors.white70,
                      fontStyle: _typingMessage.isEmpty
                          ? FontStyle.italic
                          : FontStyle.normal,
                    ),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReplyPreview() {
    return Container(
      padding: const EdgeInsets.all(12),
      color: const Color(0xFF1E293B),
      child: Row(
        children: [
          Container(width: 4, height: 40, color: const Color(0xFF8B5CF6)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _replyingToMessage!.sender?.firstName ?? 'Someone',
                  style: const TextStyle(
                    color: Color(0xFF8B5CF6),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _replyingToMessage!.content,
                  style: const TextStyle(color: Colors.grey, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.grey),
            onPressed: () {
              setState(() {
                _replyingToMessage = null;
              });
            },
          ),
        ],
      ),
    );
  }

  // Emoji categories with icons and data
  static const List<Map<String, dynamic>> _emojiCategories = [
    {
      'icon': '😀',
      'label': 'Smileys',
      'emojis': [
        '😀',
        '😃',
        '😄',
        '😁',
        '😆',
        '😅',
        '😂',
        '🤣',
        '🥲',
        '😊',
        '😇',
        '🙂',
        '🙃',
        '😉',
        '😌',
        '😍',
        '🥰',
        '😘',
        '😗',
        '😙',
        '😚',
        '😋',
        '😛',
        '😝',
        '😜',
        '🤪',
        '🤨',
        '🧐',
        '🤓',
        '😎',
        '🥸',
        '🤩',
        '🥳',
        '😏',
        '😒',
        '😞',
        '😔',
        '😟',
        '😕',
        '🙁',
        '😣',
        '😖',
        '😫',
        '😩',
        '🥺',
        '😢',
        '😭',
        '😤',
        '😠',
        '😡',
        '🤬',
        '🤯',
        '😳',
        '🥵',
        '🥶',
        '😱',
        '😨',
        '😰',
        '😥',
        '😓',
        '🤗',
        '🤔',
        '🫣',
        '🤭',
        '🫢',
        '🫡',
        '🤫',
        '🫠',
        '🤥',
        '😶',
        '😐',
        '😑',
        '😬',
        '🫨',
        '🙄',
        '😯',
        '😦',
        '😧',
        '😮',
        '😲',
        '🥱',
        '😴',
        '🤤',
        '😪',
        '😵',
        '😵‍💫',
        '🫥',
        '🤐',
        '🥴',
        '🤢',
        '🤮',
        '🤧',
        '😷',
        '🤒',
        '🤕',
        '🤑',
        '🤠',
        '😈',
        '👿',
        '👹',
        '👺',
        '🤡',
        '💩',
        '👻',
        '💀',
        '☠️',
        '👽',
        '👾',
        '🤖',
        '🎃',
        '😺',
        '😸',
        '😹',
        '😻',
        '😼',
        '😽',
        '🙀',
        '😿',
        '😾',
      ],
    },
    {
      'icon': '👋',
      'label': 'Gestures',
      'emojis': [
        '👋',
        '🤚',
        '🖐️',
        '✋',
        '🖖',
        '🫱',
        '🫲',
        '🫳',
        '🫴',
        '👌',
        '🤌',
        '🤏',
        '✌️',
        '🤞',
        '🫰',
        '🤟',
        '🤘',
        '🤙',
        '👈',
        '👉',
        '👆',
        '🖕',
        '👇',
        '☝️',
        '🫵',
        '👍',
        '👎',
        '✊',
        '👊',
        '🤛',
        '🤜',
        '👏',
        '🙌',
        '🫶',
        '👐',
        '🤲',
        '🤝',
        '🙏',
        '✍️',
        '💅',
        '🤳',
        '💪',
        '🦾',
        '🦿',
        '🦵',
        '🦶',
        '👂',
        '🦻',
        '👃',
        '🧠',
        '🫀',
        '🫁',
        '🦷',
        '🦴',
        '👀',
        '👁️',
        '👅',
        '👄',
        '🫦',
        '💋',
      ],
    },
    {
      'icon': '❤️',
      'label': 'Hearts',
      'emojis': [
        '❤️',
        '🧡',
        '💛',
        '💚',
        '💙',
        '💜',
        '🖤',
        '🤍',
        '🤎',
        '❤️‍🔥',
        '❤️‍🩹',
        '💔',
        '❣️',
        '💕',
        '💞',
        '💓',
        '💗',
        '💖',
        '💘',
        '💝',
        '💟',
        '♥️',
        '🩷',
        '🩵',
        '🩶',
        '💌',
        '💐',
        '🌹',
        '🥀',
        '🌺',
        '🌸',
        '🌷',
        '🌻',
        '💑',
        '👩‍❤️‍👨',
        '👨‍❤️‍👨',
        '👩‍❤️‍👩',
        '💏',
        '😍',
        '🥰',
        '😘',
        '😻',
        '💒',
        '🏩',
      ],
    },
    {
      'icon': '🐱',
      'label': 'Animals',
      'emojis': [
        '🐶',
        '🐱',
        '🐭',
        '🐹',
        '🐰',
        '🦊',
        '🐻',
        '🐼',
        '🐻‍❄️',
        '🐨',
        '🐯',
        '🦁',
        '🐮',
        '🐷',
        '🐸',
        '🐵',
        '🙈',
        '🙉',
        '🙊',
        '🐒',
        '🐔',
        '🐧',
        '🐦',
        '🐤',
        '🐣',
        '🐥',
        '🦆',
        '🦅',
        '🦉',
        '🦇',
        '🐺',
        '🐗',
        '🐴',
        '🦄',
        '🐝',
        '🪱',
        '🐛',
        '🦋',
        '🐌',
        '🐞',
        '🐜',
        '🪰',
        '🪲',
        '🪳',
        '🦟',
        '🦗',
        '🕷️',
        '🦂',
        '🐢',
        '🐍',
        '🦎',
        '🦖',
        '🦕',
        '🐙',
        '🦑',
        '🦐',
        '🦞',
        '🦀',
        '🐡',
        '🐠',
        '🐟',
        '🐬',
        '🐳',
        '🐋',
        '🦈',
        '🦭',
        '🐊',
        '🐅',
        '🐆',
        '🦓',
        '🦍',
        '🦧',
        '🐘',
        '🦛',
        '🦏',
        '🐪',
        '🐫',
        '🦒',
        '🦘',
        '🦬',
      ],
    },
    {
      'icon': '🍕',
      'label': 'Food',
      'emojis': [
        '🍏',
        '🍎',
        '🍐',
        '🍊',
        '🍋',
        '🍌',
        '🍉',
        '🍇',
        '🍓',
        '🫐',
        '🍈',
        '🍒',
        '🍑',
        '🥭',
        '🍍',
        '🥥',
        '🥝',
        '🍅',
        '🍆',
        '🥑',
        '🥦',
        '🥬',
        '🥒',
        '🌶️',
        '🫑',
        '🌽',
        '🥕',
        '🫒',
        '🧄',
        '🧅',
        '🥔',
        '🍠',
        '🥐',
        '🥯',
        '🍞',
        '🥖',
        '🥨',
        '🧀',
        '🥚',
        '🍳',
        '🧈',
        '🥞',
        '🧇',
        '🥓',
        '🥩',
        '🍗',
        '🍖',
        '🌭',
        '🍔',
        '🍟',
        '🍕',
        '🫓',
        '🥪',
        '🥙',
        '🧆',
        '🌮',
        '🌯',
        '🫔',
        '🥗',
        '🥘',
        '🫕',
        '🍝',
        '🍜',
        '🍲',
        '🍛',
        '🍣',
        '🍱',
        '🥟',
        '🦪',
        '🍤',
        '🍙',
        '🍚',
        '🍘',
        '🍥',
        '🥠',
        '🥮',
        '🍢',
        '🍡',
        '🍧',
        '🍨',
        '🍦',
        '🥧',
        '🧁',
        '🍰',
        '🎂',
        '🍮',
        '🍭',
        '🍬',
        '🍫',
        '🍩',
        '🍪',
        '🌰',
        '🥜',
        '🍯',
        '🥛',
        '🍼',
        '☕',
        '🍵',
        '🧃',
        '🥤',
        '🧋',
        '🍶',
        '🍺',
        '🍻',
        '🥂',
        '🍷',
        '🥃',
        '🍸',
        '🍹',
        '🧉',
      ],
    },
    {
      'icon': '⚽',
      'label': 'Activities',
      'emojis': [
        '⚽',
        '🏀',
        '🏈',
        '⚾',
        '🥎',
        '🎾',
        '🏐',
        '🏉',
        '🥏',
        '🎱',
        '🪀',
        '🏓',
        '🏸',
        '🏒',
        '🏑',
        '🥍',
        '🏏',
        '🪃',
        '🥅',
        '⛳',
        '🪁',
        '🏹',
        '🎣',
        '🤿',
        '🥊',
        '🥋',
        '🎽',
        '🛹',
        '🛼',
        '🛷',
        '⛸️',
        '🥌',
        '🎿',
        '⛷️',
        '🏂',
        '🪂',
        '🏋️',
        '🤼',
        '🤸',
        '🤺',
        '⛹️',
        '🤾',
        '🏌️',
        '🏇',
        '🧘',
        '🏄',
        '🏊',
        '🤽',
        '🚣',
        '🧗',
        '🚵',
        '🚴',
        '🏆',
        '🥇',
        '🥈',
        '🥉',
        '🏅',
        '🎖️',
        '🏵️',
        '🎗️',
        '🎪',
        '🤹',
        '🎭',
        '🩰',
        '🎨',
        '🎬',
        '🎤',
        '🎧',
        '🎼',
        '🎹',
        '🥁',
        '🪘',
        '🎷',
        '🎺',
        '🪗',
        '🎸',
        '🪕',
        '🎻',
        '🎲',
        '♟️',
        '🎯',
        '🎳',
        '🎮',
        '🕹️',
        '🧩',
      ],
    },
    {
      'icon': '🚗',
      'label': 'Travel',
      'emojis': [
        '🚗',
        '🚕',
        '🚙',
        '🚌',
        '🚎',
        '🏎️',
        '🚓',
        '🚑',
        '🚒',
        '🚐',
        '🛻',
        '🚚',
        '🚛',
        '🚜',
        '🏍️',
        '🛵',
        '🚲',
        '🛴',
        '🛺',
        '🚔',
        '🚍',
        '🚘',
        '🚖',
        '🛞',
        '🚡',
        '🚠',
        '🚟',
        '🚃',
        '🚋',
        '🚞',
        '🚝',
        '🚄',
        '🚅',
        '🚈',
        '🚂',
        '🚆',
        '🚇',
        '🚊',
        '🚉',
        '✈️',
        '🛫',
        '🛬',
        '🛩️',
        '💺',
        '🛰️',
        '🚀',
        '🛸',
        '🚁',
        '🛶',
        '⛵',
        '🚤',
        '🛥️',
        '🛳️',
        '⛴️',
        '🚢',
        '🗼',
        '🏰',
        '🏯',
        '🏟️',
        '🎡',
        '🎢',
        '🎠',
        '⛲',
        '⛱️',
        '🏖️',
        '🏝️',
        '🏜️',
        '🌋',
        '⛰️',
        '🏔️',
        '🗻',
        '🏕️',
        '🛖',
        '🏠',
        '🏡',
        '🏢',
        '🏬',
        '🏣',
        '🏤',
        '🏥',
      ],
    },
    {
      'icon': '💡',
      'label': 'Objects',
      'emojis': [
        '🔥',
        '💧',
        '🌟',
        '⭐',
        '✨',
        '💫',
        '🌈',
        '☀️',
        '🌤️',
        '⛅',
        '🎉',
        '🎊',
        '🎈',
        '🎁',
        '🎀',
        '🎄',
        '🪅',
        '🎆',
        '🎇',
        '🧨',
        '💡',
        '🔦',
        '🕯️',
        '🪔',
        '💎',
        '🔮',
        '🧿',
        '🪬',
        '💰',
        '💴',
        '💵',
        '💶',
        '💷',
        '🪙',
        '💳',
        '💸',
        '🧲',
        '🔧',
        '🪛',
        '🔩',
        '⚙️',
        '🧰',
        '🪜',
        '🧱',
        '🪨',
        '🪵',
        '🔗',
        '🧬',
        '🔬',
        '🔭',
        '📡',
        '💉',
        '🩸',
        '💊',
        '🩹',
        '🩼',
        '🩺',
        '🩻',
        '🚪',
        '🛗',
        '🪞',
        '🪟',
        '🛏️',
        '🛋️',
        '🪑',
        '🚽',
        '🪠',
        '🚿',
        '🛁',
        '🪤',
        '📱',
        '💻',
        '⌨️',
        '🖥️',
        '🖨️',
        '🖱️',
        '💾',
        '💿',
        '📀',
        '📷',
        '📸',
        '📹',
        '🎥',
        '📽️',
        '🎞️',
        '📞',
        '☎️',
        '📟',
        '📠',
        '📺',
        '📻',
        '🎙️',
        '🎚️',
        '🎛️',
        '🧭',
        '⏱️',
        '⏲️',
        '⏰',
        '🕰️',
        '📡',
      ],
    },
    {
      'icon': '🏁',
      'label': 'Symbols',
      'emojis': [
        '🏳️',
        '🏴',
        '🏁',
        '🚩',
        '🏳️‍🌈',
        '🏳️‍⚧️',
        '🏴‍☠️',
        '✅',
        '❌',
        '❓',
        '❗',
        '‼️',
        '⁉️',
        '💯',
        '🔴',
        '🟠',
        '🟡',
        '🟢',
        '🔵',
        '🟣',
        '⚫',
        '⚪',
        '🟤',
        '🔶',
        '🔷',
        '🔸',
        '🔹',
        '🔺',
        '🔻',
        '💠',
        '🔘',
        '🔳',
        '🔲',
        '▪️',
        '▫️',
        '◾',
        '◽',
        '◼️',
        '◻️',
        '🟥',
        '🟧',
        '🟨',
        '🟩',
        '🟦',
        '🟪',
        '⬛',
        '⬜',
        '🟫',
        '♈',
        '♉',
        '♊',
        '♋',
        '♌',
        '♍',
        '♎',
        '♏',
        '♐',
        '♑',
        '♒',
        '♓',
        '⛎',
        '🔀',
        '🔁',
        '🔂',
        '▶️',
        '⏩',
        '⏭️',
        '⏯️',
        '◀️',
        '⏪',
        '⏮️',
        '🔼',
        '⏫',
        '🔽',
        '⏬',
        '⏸️',
        '⏹️',
        '⏺️',
        '⏏️',
        '🎦',
        '♾️',
        '♻️',
        '⚜️',
        '🔱',
        '📛',
        '🔰',
        '⭕',
        '✅',
        '☑️',
        '✔️',
        '❌',
        '❎',
        '➕',
        '➖',
        '➗',
        '✖️',
        '💲',
        '💱',
        '™️',
        '©️',
        '®️',
        '〰️',
        '➰',
        '➿',
        '🔚',
        '🔙',
        '🔛',
        '🔝',
        '🔜',
        '🆕',
      ],
    },
  ];

  /// Toggle emoji picker visibility (inline below input)
  void _showEmojiPickerModal(BuildContext context) {
    if (_showEmojiPicker) {
      // Closing emoji picker → bring keyboard back
      setState(() {
        _showEmojiPicker = false;
      });
      _inputFocusNode.requestFocus();
    } else {
      // Opening emoji picker → dismiss keyboard first
      _inputFocusNode.unfocus();
      setState(() {
        _showEmojiPicker = true;
      });
    }
  }

  /// Build inline emoji picker widget with category tabs
  Widget _buildInlineEmojiPicker() {
    final category = _emojiCategories[_emojiCategoryIndex];
    final emojis = category['emojis'] as List<String>;

    return Container(
      height: 260,
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF3D3D3D),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // Category tabs
          SizedBox(
            height: 44,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              itemCount: _emojiCategories.length,
              itemBuilder: (context, index) {
                final cat = _emojiCategories[index];
                final isSelected = index == _emojiCategoryIndex;
                return GestureDetector(
                  onTap: () => setState(() => _emojiCategoryIndex = index),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF6D28D9)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        cat['icon'] as String,
                        style: const TextStyle(fontSize: 20),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          // Emoji grid
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 8,
                childAspectRatio: 1,
              ),
              itemCount: emojis.length,
              itemBuilder: (context, index) {
                return GestureDetector(
                  onTap: () {
                    // Insert emoji at cursor position
                    final text = _messageController.text;
                    final selection = _messageController.selection;
                    final cursorPos = selection.baseOffset >= 0
                        ? selection.baseOffset
                        : text.length;

                    final newText =
                        text.substring(0, cursorPos) +
                        emojis[index] +
                        text.substring(cursorPos);

                    _messageController.text = newText;
                    _messageController.selection = TextSelection.collapsed(
                      offset: cursorPos + emojis[index].length,
                    );

                    setState(
                      () {},
                    ); // Force rebuild to update button visibility
                  },
                  child: Center(
                    child: Text(
                      emojis[index],
                      style: const TextStyle(fontSize: 24),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Ring doorbell for group (notify all members)
  void _ringDoorbell() async {
    // Show immediate feedback (optimistic)
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🔔 Ringing doorbell...'),
          duration: Duration(seconds: 1),
        ),
      );
    }

    try {
      // Use Socket.IO instead of REST API (backend doesn't have REST endpoint yet)
      _socketService.ringGroupDoorbell(widget.group.id);

      if (mounted) {
        // Update to success message
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🔔 Doorbell rung for all members'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error ringing doorbell: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to ring doorbell: $e')));
      }
    }
  }

  /// Pick a file from device storage
  Future<void> _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles();
      if (result != null && result.files.single.path != null) {
        await _uploadFile(File(result.files.single.path!));
      }
    } catch (e) {
      debugPrint('Error picking file: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to pick file: $e')));
      }
    }
  }

  /// Take a photo with camera
  Future<void> _takePhoto() async {
    try {
      final picker = ImagePicker();
      final XFile? photo = await picker.pickImage(source: ImageSource.camera);
      if (photo != null) {
        await _uploadFile(File(photo.path));
      }
    } catch (e) {
      debugPrint('Error taking photo: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to take photo: $e')));
      }
    }
  }

  /// Show voice recording modal (placeholder - to be implemented)
  Future<void> _showVoiceRecordingModal() async {
    // TODO: Implement voice recording for group chat
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Voice recording coming soon for group chats'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// Toggle timestamp visibility
  void _toggleTimestamps() {
    setState(() {
      _showTimestamps = !_showTimestamps;
    });
  }

  /// Toggle auto-translate
  Future<void> _toggleAutoTranslate() async {
    final newValue = !_autoTranslate;
    setState(() {
      _autoTranslate = newValue;
    });

    // Save to SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('autoTranslate_group_${widget.group.id}', newValue);

    // Show feedback snackbar
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          newValue ? 'Auto-translate enabled' : 'Auto-translate disabled',
        ),
        duration: const Duration(seconds: 2),
      ),
    );

    // If enabling, translate existing messages
    if (newValue) {
      await _translateExistingMessages();
    }
  }

  /// Translate all existing messages for this group
  Future<void> _translateExistingMessages() async {
    if (!mounted) return;

    final targetLang = await TranslationService.getUserLanguage();
    debugPrint('Translating group messages to: $targetLang');

    // Get current messages from cache
    final currentUserId = await StorageService.getUserId();
    if (currentUserId == null) return;

    final messages = await ChatCacheService.loadGroupMessages(widget.group.id);

    if (messages.isEmpty) return;

    // Translate each message
    final translatedMessages = <GroupMessage>[];
    for (final message in messages) {
      if (message.content.isNotEmpty && !message.isDeleted) {
        final translated = await TranslationService.translateGroupMessageObject(
          message: message,
          targetLang: targetLang,
        );
        if (translated != null) {
          translatedMessages.add(translated);
        } else {
          // Keep original if translation fails
          translatedMessages.add(message);
        }
      } else {
        translatedMessages.add(message);
      }
    }

    // Update cache with translated messages
    await ChatCacheService.saveGroupMessages(
      widget.group.id,
      translatedMessages,
    );

    // Refresh the UI
    if (mounted) {
      setState(() {
        _messages = translatedMessages;
      });
    }
  }

  /// Show context menu for group message
  void _showGroupMessageContextMenu(GroupMessage message, bool isSentByMe) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[600],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Copy option (for text messages)
              if (message.messageType == 'text' && !message.isDeleted)
                ListTile(
                  leading: const Icon(Icons.copy, color: Colors.white),
                  title: const Text(
                    'Copy',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _copyGroupMessageToClipboard(message);
                  },
                ),
              // Translate option (for incoming text messages)
              if (!isSentByMe &&
                  message.messageType == 'text' &&
                  !message.isDeleted &&
                  message.content.isNotEmpty)
                ListTile(
                  leading: Icon(
                    _messageTranslations.containsKey(message.id)
                        ? Icons.translate_outlined
                        : Icons.translate,
                    color: Colors.blue,
                  ),
                  title: Text(
                    _messageTranslations.containsKey(message.id)
                        ? 'Hide Translation'
                        : 'Translate',
                    style: const TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _translateGroupMessage(message);
                  },
                ),
              // Delete option (for own messages)
              if (isSentByMe && !message.isDeleted)
                ListTile(
                  leading: const Icon(Icons.delete, color: Colors.red),
                  title: const Text(
                    'Delete',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _showGroupDeleteConfirmation(message);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Copy group message to clipboard
  void _copyGroupMessageToClipboard(GroupMessage message) {
    Clipboard.setData(ClipboardData(text: message.content));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Message copied to clipboard'),
        duration: Duration(seconds: 2),
        backgroundColor: Color(0xFF4CAF50),
      ),
    );
  }

  /// Auto-translate incoming group message (silent, no loading indicators)
  Future<void> _autoTranslateGroupMessage(GroupMessage message) async {
    try {
      final targetLang = await TranslationService.getUserLanguage();
      final translatedText = await TranslationService.translateMessage(
        text: message.content,
        targetLang: targetLang,
      );

      if (translatedText != null &&
          translatedText != message.content &&
          mounted) {
        setState(() {
          _messageTranslations[message.id] = translatedText;
        });
        debugPrint(
          '🌐 Auto-translated group message ${message.id}: "${message.content}" → "$translatedText"',
        );
      }
    } catch (e) {
      debugPrint('Auto-translation failed for group message ${message.id}: $e');
      // Fail silently for auto-translation
    }
  }

  /// Translate a group message manually
  Future<void> _translateGroupMessage(GroupMessage message) async {
    try {
      // Check if already translated - toggle off if so
      if (_messageTranslations.containsKey(message.id)) {
        setState(() {
          _messageTranslations.remove(message.id);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Translation hidden'),
            duration: Duration(seconds: 2),
            backgroundColor: Color(0xFF6B7280),
          ),
        );
        return;
      }

      // Show loading indicator
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              SizedBox(width: 12),
              Text('Translating...'),
            ],
          ),
          duration: Duration(seconds: 30),
          backgroundColor: Color(0xFF4F46E5),
        ),
      );

      final targetLang = await TranslationService.getUserLanguage();
      final translatedText = await TranslationService.translateMessage(
        text: message.content,
        targetLang: targetLang,
      );

      // Hide loading indicator
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      if (translatedText != null && translatedText != message.content) {
        // Store translation and update UI
        setState(() {
          _messageTranslations[message.id] = translatedText;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message translated'),
            duration: Duration(seconds: 2),
            backgroundColor: Color(0xFF4CAF50),
          ),
        );
      } else if (translatedText == message.content) {
        // Same text, no translation needed
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message is already in your language'),
            duration: Duration(seconds: 2),
            backgroundColor: Color(0xFF6B7280),
          ),
        );
      } else {
        // Translation failed
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Translation failed. Please try again.'),
            duration: Duration(seconds: 3),
            backgroundColor: Color(0xFFEF4444),
          ),
        );
      }
    } catch (e) {
      // Hide loading indicator
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      debugPrint('Translation error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Translation failed. Please try again.'),
          duration: Duration(seconds: 3),
          backgroundColor: Color(0xFFEF4444),
        ),
      );
    }
  }

  /// Show delete confirmation for group message
  void _showGroupDeleteConfirmation(GroupMessage message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text(
          'Delete Message',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Are you sure you want to delete this message?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteGroupMessage(message);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  /// Delete group message (placeholder)
  void _deleteGroupMessage(GroupMessage message) {
    // TODO: Implement group message deletion
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Message deletion coming soon for group chats'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// Change group chat color (placeholder)
  void _changeColor() {
    // TODO: Implement color picker for group chat
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Color customization coming soon for group chats'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Reset group chat color (placeholder)
  void _resetColor() {
    setState(() {
      _showResetButton = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Color reset'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Export chat history
  Future<void> _exportChat() async {
    // TODO: Implement chat export for group chat
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Chat export coming soon for group chats'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Admin: Delete all messages in group
  Future<void> _adminDeleteAllMessages() async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete All Messages'),
        content: const Text(
          'Are you sure you want to delete all messages in this group? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // TODO: Implement delete all messages API call
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Delete all messages coming soon'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      debugPrint('Error deleting all messages: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete messages: $e')),
        );
      }
    }
  }

  Widget _buildInputArea() {
    final headerColor = const Color(0xFF1E293B); // Match group chat theme

    return Container(
      padding: const EdgeInsets.only(left: 12, right: 12, top: 0, bottom: 4),
      decoration: BoxDecoration(
        color: headerColor,
        border: const Border(
          top: BorderSide(color: Color(0xFF3D3D3D), width: 1),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Reply preview (when replying to a message)
          if (_replyingToMessage != null) _buildReplyPreview(),

          // Text input field with embedded emoji button and send button
          RepaintBoundary(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Actions toggle icon (hidden when input focused or has text)
                if (!_inputFocusNode.hasFocus &&
                    _messageController.text.isEmpty)
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3D3D3D),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: IconButton(
                      onPressed: () => setState(
                        () => _showActionButtons = !_showActionButtons,
                      ),
                      icon: Icon(
                        _showActionButtons
                            ? Icons.expand_more
                            : Icons.add_circle_outline,
                        color: Colors.white70,
                        size: 18,
                      ),
                      padding: const EdgeInsets.all(6),
                      constraints: const BoxConstraints(),
                      tooltip: _showActionButtons
                          ? 'Hide Actions'
                          : 'Show Actions',
                    ),
                  ),
                // Text input field with embedded emoji button
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF4D4D4D),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        // Emoji picker button (inside input) - toggles between emoji/keyboard icon
                        IconButton(
                          onPressed: () => _showEmojiPickerModal(context),
                          icon: Icon(
                            _showEmojiPicker
                                ? Icons.keyboard_outlined
                                : Icons.sentiment_satisfied_alt_outlined,
                            color: Colors.white70,
                            size: 18,
                          ),
                          padding: const EdgeInsets.all(4),
                          constraints: const BoxConstraints(),
                          tooltip: _showEmojiPicker ? 'Keyboard' : 'Emoji',
                        ),
                        // Text input
                        Expanded(
                          child: TextField(
                            key: const ValueKey('message_input'),
                            controller: _messageController,
                            focusNode: _inputFocusNode,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Type a message...',
                              hintStyle: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 14,
                              ),
                              border: InputBorder.none,
                              filled: false,
                              contentPadding: const EdgeInsets.only(
                                left: 0,
                                right: 4,
                                top: 10,
                                bottom: 10,
                              ),
                              isDense: true,
                            ),
                            onChanged: (text) {
                              setState(() {
                                // Hide action buttons when typing
                                if (text.isNotEmpty && _showActionButtons) {
                                  _showActionButtons = false;
                                }
                              });

                              // Emit typing indicator (throttled)
                              _typingEmitTimer?.cancel();
                              _typingEmitTimer = Timer(
                                const Duration(milliseconds: 150),
                                () {
                                  _socketService.sendGroupTyping(
                                    widget.group.id,
                                    text,
                                  );
                                },
                              );
                            },
                            minLines: 1,
                            maxLines: 5,
                            textInputAction: TextInputAction.newline,
                            keyboardType: TextInputType.multiline,
                            textCapitalization: TextCapitalization.sentences,
                            enableInteractiveSelection: true,
                            autocorrect: true,
                            enableSuggestions: true,
                            scribbleEnabled: false,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Clear (top) + Send (bottom) — always visible, vertically centred
                IntrinsicWidth(
                  child: Container(
                    margin: const EdgeInsets.only(left: 6),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Clear button (top)
                        ElevatedButton(
                          onPressed: () {
                            _messageController.clear();
                            setState(() {
                              _replyingToMessage = null;
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFEF4444),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 3,
                            ),
                            minimumSize: const Size(0, 0),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text(
                            'Clear',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                        const SizedBox(height: 4),
                        // Send button (bottom)
                        ElevatedButton(
                          onPressed: _sendMessage,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6D28D9),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 3,
                            ),
                            minimumSize: const Size(0, 0),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text(
                            'Send',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Inline emoji picker (shown when active)
          if (_showEmojiPicker) _buildInlineEmojiPicker(),
          // Collapsible action buttons panel
          // Only show when emoji picker is closed AND keyboard is not visible
          if (!_showEmojiPicker &&
              MediaQuery.of(context).viewInsets.bottom == 0) ...[
            // All action buttons (shown/hidden by toggle)
            if (_showActionButtons)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    // Ring Doorbell
                    ElevatedButton(
                      onPressed: _ringDoorbell,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF8B5CF6),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      child: const Text('Ring Doorbell'),
                    ),
                    // Change Color
                    ElevatedButton(
                      onPressed: _changeColor,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFA855F7),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
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
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          minimumSize: const Size(0, 0),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        child: const Text('Reset Color'),
                      ),
                    // Send File
                    ElevatedButton(
                      onPressed: _pickFile,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      child: const Text('Send File'),
                    ),
                    // Camera
                    ElevatedButton(
                      onPressed: _takePhoto,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3B82F6),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      child: const Text('Camera'),
                    ),
                    // Voice Message
                    ElevatedButton(
                      onPressed: _showVoiceRecordingModal,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEF4444),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      child: const Text('Voice Message'),
                    ),
                    // Auto-Translate
                    ElevatedButton(
                      onPressed: _toggleAutoTranslate,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _autoTranslate
                            ? const Color(0xFF059669)
                            : const Color(0xFF0891B2),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      child: Text(
                        _autoTranslate ? 'Translate: ON' : 'Translate: OFF',
                      ),
                    ),
                    // Show Timestamps
                    ElevatedButton(
                      onPressed: _toggleTimestamps,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _showTimestamps
                            ? const Color(0xFF4F46E5)
                            : const Color(0xFF8B5CF6),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      child: Text(
                        _showTimestamps ? 'Hide Timestamps' : 'Show Timestamps',
                      ),
                    ),
                    // Export Chat
                    ElevatedButton(
                      onPressed: _exportChat,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6B7280),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      child: const Text('Export Chat'),
                    ),
                    // Delete All Messages (admin only)
                    if (_currentUserIsAdmin)
                      ElevatedButton(
                        onPressed: _adminDeleteAllMessages,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFDC2626),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          minimumSize: const Size(0, 0),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [SizedBox(width: 4), Text('Delete All')],
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Audio Message Player Widget for playing voice messages in group chat
class _AudioMessagePlayer extends StatefulWidget {
  final String audioUrl;
  final int? fileSize;

  const _AudioMessagePlayer({required this.audioUrl, this.fileSize});

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
        // Stop any current playback first
        await _audioPlayer.stop();

        // Small delay to ensure player is ready
        await Future.delayed(const Duration(milliseconds: 100));

        // Play from URL
        await _audioPlayer.play(UrlSource(widget.audioUrl));
        setState(() => _isPlaying = true);
      }
    } catch (e) {
      debugPrint('AudioPlayers Exception: $e');
      if (mounted) {
        setState(() => _isPlaying = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error playing audio: ${e.toString().split(':').last.trim()}',
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
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
                color: Colors.white.withAlpha(51),
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
                    final barHeight = [
                      8.0,
                      14.0,
                      10.0,
                      18.0,
                      12.0,
                      20.0,
                      16.0,
                      22.0,
                      14.0,
                      18.0,
                      12.0,
                      16.0,
                      20.0,
                      14.0,
                      10.0,
                      18.0,
                      12.0,
                      8.0,
                      14.0,
                      10.0,
                    ][index];
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
                    color: Colors.white.withAlpha(179),
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
