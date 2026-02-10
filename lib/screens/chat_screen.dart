import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mime/mime.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import '../models/lobby_user.dart';
import '../models/message.dart';
import '../services/message_service.dart';
import '../services/socket_service.dart';
import '../services/storage_service.dart';
import '../widgets/color_picker_modal.dart';
import '../services/firebase_messaging_service.dart';
import '../widgets/call_setup_modal.dart';
import '../widgets/outgoing_call_modal.dart';
import '../widgets/incoming_call_setup_modal.dart';
import '../widgets/reaction_picker.dart';
import '../services/call_service.dart';
import '../config/api_config.dart';
import 'connected_call_screen.dart';

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
  Timer? _lastSeenRefreshTimer;
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
  
  // Timestamp visibility toggle (hidden by default like web)
  bool _showTimestamps = false;
  
  // Auto-translate toggle
  bool _autoTranslate = false;
  
  // Scroll to bottom button state
  bool _isAtBottom = true;
  int _unreadCount = 0;
  
  // Reply state
  Message? _replyingToMessage;
  
  // Reaction state: { messageId: { emoji: Set<userName> } }
  final Map<int, Map<String, Set<String>>> _messageReactions = {};
  
  // Emoji picker state for chat input
  bool _showEmojiPicker = false;
  
  // Presence state for the chat partner
  String _partnerStatus = 'offline';
  String? _partnerLastSeen;

  @override
  void initState() {
    super.initState();
    _inputFocusNode.addListener(_onFocusChange);
    _scrollController.addListener(_onScroll);
    // Suppress FCM notifications for this chat partner while screen is active
    FirebaseMessagingService.instance.activeChatUserId = widget.otherUser.id;
    _initialize();
    // Periodically refresh "last seen" relative label in header (like the web app does)
    _lastSeenRefreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted && _partnerStatus != 'online') setState(() {});
    });
  }
  
  /// Listen to scroll position to show/hide scroll-to-bottom button
  void _onScroll() {
    // Since list is reversed, position 0 means we're at the bottom (newest messages)
    // We're "at bottom" if scroll offset is near 0
    final isAtBottom = _scrollController.offset < 100;
    if (_isAtBottom != isAtBottom) {
      setState(() {
        _isAtBottom = isAtBottom;
        // Reset unread count when at bottom
        if (isAtBottom) {
          _unreadCount = 0;
          // Mark visible messages as read when scrolling to bottom
          _markVisibleMessagesAsRead();
        }
      });
    }
  }

  /// Mark visible messages as read
  void _markVisibleMessagesAsRead() {
    final unreadMessageIds = <int>[];
    
    // Find unread messages from the other user
    for (final message in _messages) {
      if (message.senderId == widget.otherUser.id && !message.isRead) {
        unreadMessageIds.add(message.id);
      }
    }
    
    if (unreadMessageIds.isNotEmpty) {
      // Mark messages as viewed via socket - this will notify web clients
      _socketService.markMessagesViewed(widget.otherUser.id);
      debugPrint('📧 Sent read confirmations for ${unreadMessageIds.length} messages to update web clients');
    }
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
    
    // Initialize presence state from widget
    _partnerStatus = widget.otherUser.status;
    _partnerLastSeen = widget.otherUser.lastSeen;
    
    // Load saved chat color for this conversation partner
    await _loadSavedChatColor();
    
    await _loadTimestampPreference();
    await _loadMessages();
    _joinChatRoom();
    _setupRealtimeListeners();
  }

  /// Load persisted chat color from SharedPreferences
  Future<void> _loadSavedChatColor() async {
    final prefs = await SharedPreferences.getInstance();
    final savedColorHex = prefs.getString('chat_color_${widget.otherUser.id}');
    if (savedColorHex != null && mounted) {
      try {
        final hexColor = savedColorHex.replaceAll('#', '');
        final color = Color(int.parse('FF$hexColor', radix: 16));
        final defaultColor = const Color(0xFF4C1D95);
        setState(() {
          _headerColor = color;
          _showResetButton = color.value != defaultColor.value;
        });
      } catch (e) {
        debugPrint('Error loading saved chat color: $e');
      }
    }
  }

  /// Persist chat color to SharedPreferences
  Future<void> _saveChatColor(String colorHex) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('chat_color_${widget.otherUser.id}', colorHex);
  }

  /// Load timestamp visibility preference from SharedPreferences
  Future<void> _loadTimestampPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool('showTimestamps') ?? false;
    final autoTranslateSaved = prefs.getBool('autoTranslate_${widget.otherUser.id}') ?? false;
    if (mounted) {
      setState(() {
        _showTimestamps = saved;
        _autoTranslate = autoTranslateSaved;
      });
    }
  }

  /// Toggle timestamp visibility and save preference
  Future<void> _toggleTimestamps() async {
    final newValue = !_showTimestamps;
    setState(() {
      _showTimestamps = newValue;
    });
    
    // Save to SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('showTimestamps', newValue);
    
    // Show feedback snackbar
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(newValue ? 'Timestamps shown' : 'Timestamps hidden'),
          duration: const Duration(seconds: 1),
          backgroundColor: newValue ? const Color(0xFF4F46E5) : Colors.grey[700],
        ),
      );
    }
  }

  /// Toggle auto-translate and save preference
  Future<void> _toggleAutoTranslate() async {
    final newValue = !_autoTranslate;
    setState(() {
      _autoTranslate = newValue;
    });
    
    // Save to SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('autoTranslate_${widget.otherUser.id}', newValue);
    
    // Emit socket event to notify other user
    _socketService.emit('toggle_translate', {
      'recipient_id': widget.otherUser.id,
      'enabled': newValue,
    });
    
    // Show feedback snackbar
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(newValue ? 'Auto-translate enabled' : 'Auto-translate disabled'),
          duration: const Duration(seconds: 1),
          backgroundColor: newValue ? const Color(0xFF059669) : Colors.grey[700],
        ),
      );
    }
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
          
          // Increment unread count if not at bottom (for incoming messages)
          if (!_isAtBottom && message.senderId == widget.otherUser.id) {
            _unreadCount++;
          }
        });
        
        // Play message sound for incoming messages
        if (message.senderId == widget.otherUser.id) {
          try {
            _audioPlayer.play(AssetSource('sounds/splat2.m4a'));
          } catch (e) {
            debugPrint('Error playing message sound: $e');
          }
        }
        
        // If at bottom, auto-scroll and mark messages as read immediately
        if (_isAtBottom && message.senderId == widget.otherUser.id) {
          // Mark messages from sender as read immediately - this will show "seen" on web
          _socketService.markMessagesRead(widget.otherUser.id);
          
          // Also mark specific messages as viewed for real-time status updates
          _socketService.markMessagesViewed(widget.otherUser.id);
          
          debugPrint('📧 Immediately marked message ${message.id} as seen - web will show "seen" status');
          
          // Scroll to bottom
          _scrollToBottom();
        }
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

    // Listen for all messages deleted event
    _socketService.onAllMessagesDeleted = (data) {
      _handleAllMessagesDeleted(data);
    };

    // Listen for single message deleted event
    _socketService.onMessageDeleted = (data) {
      _handleMessageDeleted(data);
    };

    // Listen for message edited event
    _socketService.onMessageEdited = (data) {
      _handleMessageEdited(data);
    };

    // Listen for task added event
    _socketService.onTaskAdded = (data) {
      _handleTaskAdded(data);
    };

    // Listen for task completed event
    _socketService.onTaskCompleted = (data) {
      _handleTaskCompleted(data);
    };

    // Listen for task uncompleted event
    _socketService.onTaskUncompleted = (data) {
      _handleTaskUncompleted(data);
    };

    // Listen for excalidraw pinned event
    _socketService.onExcalidrawPinned = (data) {
      _handleExcalidrawPinned(data);
    };

    // Listen for excalidraw unpinned event
    _socketService.onExcalidrawUnpinned = (data) {
      _handleExcalidrawUnpinned(data);
    };

    // Listen for message status updates (delivered/seen)
    _socketService.onMessageStatusUpdated = (data) {
      _handleMessageStatusUpdate(data);
    };

    // Listen for messages read notifications
    _socketService.onMessagesRead = (data) {
      _handleMessagesRead(data);
    };

    // Listen for file messages from web
    _socketService.onFileReceived = (data) {
      debugPrint('📎 File message received in chat: $data');
      // Only process if it's from the current conversation partner
      if (data['sender_id'] == widget.otherUser.id) {
        final now = DateTime.now();
        final timestampMs = data['timestamp_ms'] ?? now.millisecondsSinceEpoch;
        // Detect audio files as voice messages
        final fileType = (data['file_type'] as String?) ?? '';
        final msgType = (data['message_type'] as String?) ?? '';
        String messageType;
        if (fileType.startsWith('audio/') || msgType == 'voice' || msgType == 'audio') {
          messageType = 'voice';
        } else if (fileType.startsWith('image/')) {
          messageType = 'image';
        } else if (fileType.startsWith('video/')) {
          messageType = 'video';
        } else {
          messageType = 'file';
        }
        // Create a message from the file data
        final message = Message(
          id: data['message_id'] ?? timestampMs,
          senderId: data['sender_id'],
          recipientId: _currentUserId ?? 0,
          content: data['file_name'] ?? 'File',
          messageType: messageType,
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

    // Listen for voice messages from web
    _socketService.onVoiceMessageReceived = (data) {
      debugPrint('🎤 Voice message received in chat: $data');
      // Only process if it's from the current conversation partner
      if (data['sender_id'] == widget.otherUser.id) {
        final now = DateTime.now();
        final timestampMs = data['timestamp_ms'] ?? now.millisecondsSinceEpoch;
        final audioUrl = data['audio_url'] as String?;
        if (audioUrl == null || audioUrl.isEmpty) {
          debugPrint('🎤 Voice message has no audio_url, ignoring');
          return;
        }
        // Build full URL if it's a relative path
        final fullAudioUrl = audioUrl.startsWith('http')
            ? audioUrl
            : '${ApiConfig.baseUrl}$audioUrl';
        final message = Message(
          id: data['message_id'] ?? timestampMs,
          senderId: data['sender_id'],
          recipientId: _currentUserId ?? 0,
          content: 'Voice message',
          messageType: 'voice',
          timestamp: now.toIso8601String(),
          timestampMs: timestampMs,
          isRead: false,
          status: 'delivered',
          threadId: '',
          reactions: {},
          isDeleted: false,
          fileUrl: fullAudioUrl,
          fileName: 'voice_message.wav',
          fileType: 'audio/wav',
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

    // Listen for incoming calls (while in chat)
    _socketService.onIncomingCall = (data) {
      _handleIncomingCallInChat(data);
    };
    
    // Listen for cross-room call offers (from web client)
    _socketService.onCrossRoomCallOffer = (data) {
      _handleCrossRoomCallOfferInChat(data);
    };
    
    // Listen for reaction updates
    _socketService.onReactionUpdated = (data) {
      debugPrint('👍 Reaction updated received: $data');
      final messageId = data['message_id'] as int?;
      // Use user_id for consistent tracking (convert to string for Set storage)
      final reactorId = data['user_id']?.toString() ?? '';
      final reaction = data['reaction'] as String?;
      
      if (messageId != null && reaction != null && reaction.isNotEmpty && reactorId.isNotEmpty) {
        setState(() {
          // Initialize reaction map for this message if it doesn't exist
          _messageReactions.putIfAbsent(messageId, () => {});
          
          // Remove this user from all other reactions on this message
          _messageReactions[messageId]!.forEach((emoji, users) {
            if (emoji != reaction) {
              users.remove(reactorId);
            }
          });
          
          // Remove empty reaction sets
          _messageReactions[messageId]!.removeWhere((key, value) => value.isEmpty);
          
          // Add user to the target reaction
          _messageReactions[messageId]!.putIfAbsent(reaction, () => {});
          _messageReactions[messageId]![reaction]!.add(reactorId);
        });
      }
    };
    
    _socketService.onReactionCleared = (data) {
      debugPrint('❌ Reaction cleared received: $data');
      final messageId = data['message_id'] as int?;
      // Use user_id for consistent tracking
      final reactorId = data['user_id']?.toString() ?? '';
      
      if (messageId != null && reactorId.isNotEmpty) {
        setState(() {
          if (_messageReactions.containsKey(messageId)) {
            // Remove user from all reactions on this message
            _messageReactions[messageId]!.forEach((emoji, users) {
              users.remove(reactorId);
            });
            
            // Remove empty reaction sets
            _messageReactions[messageId]!.removeWhere((key, value) => value.isEmpty);
            
            // Remove message entry if no reactions left
            if (_messageReactions[messageId]!.isEmpty) {
              _messageReactions.remove(messageId);
            }
          }
        });
      }
    };
    
    // Listen for presence updates (status changes)
    _socketService.onPresenceUpdate = (data) {
      debugPrint('👤 Presence update in chat: $data');
      final userId = data['user_id'] as int?;
      final status = data['status'] as String?;
      final timestamp = data['timestamp'] as String?;
      
      // Only update if this is for our chat partner
      if (userId == widget.otherUser.id && status != null) {
        setState(() {
          _partnerStatus = status;
          if (timestamp != null) {
            _partnerLastSeen = timestamp;
          }
        });
      }
    };
  }
  
  /// Handle cross-room call offer from web client while in chat
  Future<void> _handleCrossRoomCallOfferInChat(Map<String, dynamic> data) async {
    if (!mounted) return;
    
    debugPrint('📲 Cross-room call offer received in chat: $data');
    
    final callerId = data['caller_id'] as int?;
    final callerUsername = data['caller_username'] as String? ?? widget.otherUser.fullName;
    final callType = data['call_type'] as String? ?? 'video';
    final room = data['room'] as String?;
    
    if (callerId == null || room == null) {
      debugPrint('⚠️ Invalid cross-room call offer data');
      return;
    }
    
    // Initialize call service FIRST
    final callService = CallService();
    await callService.initialize();
    
    // Set up signal handler IMMEDIATELY - before handleIncomingCall
    // This ensures we capture any signals that arrive while setting up
    _socketService.onSignal = (signalData) {
      debugPrint('📡 Signal received for cross-room call: $signalData');
      callService.handleSignal(signalData);
    };
    
    // Create synthetic incoming call data for the call service
    final syntheticCallData = {
      'id': DateTime.now().millisecondsSinceEpoch,
      'call_room_id': room,
      'call_type': callType,
      'caller_id': callerId,
      'caller': {
        'id': callerId,
        'username': callerUsername,
        'full_name': callerUsername,
      },
    };
    callService.handleIncomingCall(syntheticCallData);
    
    // Set up call ended/declined handlers
    _socketService.onCallEnded = (endData) {
      debugPrint('📴 Call ended by remote user');
      _socketService.stopSignalBuffering();
      callService.handleCallEnded();
    };
    
    _socketService.onCallDeclined = (declineData) {
      debugPrint('❌ Call declined');
      _socketService.stopSignalBuffering();
      callService.handleCallDeclined();
    };
    
    // Show incoming call setup modal with device selection
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => IncomingCallSetupModal(
          callerName: callerUsername,
          callerId: callerId,
          callType: callType,
          callService: callService,
          onDecline: () {
            debugPrint('📞 Call declined by user');
            _socketService.stopSignalBuffering();
          },
        ),
      ),
    ).then((result) {
      if (result is Map && (result['result'] == 'accepted' || result['result'] == 'connected')) {
        final localStream = result['localStream'];
        Navigator.of(context).push(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (context) => ConnectedCallScreen(
              remoteName: callerUsername,
              callType: callType,
              callService: callService,
              localStream: localStream ?? callService.localStream,
              onChatPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ),
        );
      }
    });
  }

  /// Handle incoming call while in chat screen
  Future<void> _handleIncomingCallInChat(Map<String, dynamic> data) async {
    if (!mounted) return;
    
    debugPrint('📲 Incoming call received in chat: $data');
    
    final callId = data['id'] as int?;
    final callRoomId = data['call_room_id'] as String?;
    final callType = data['call_type'] as String? ?? 'video';
    final callerData = data['caller'] as Map<String, dynamic>?;
    final callerId = callerData?['id'] as int? ?? data['caller_id'] as int?;
    final callerName = callerData?['full_name'] as String? ?? 
                       callerData?['username'] as String? ?? 
                       widget.otherUser.fullName;
    
    if (callId == null || callRoomId == null || callerId == null) {
      debugPrint('⚠️ Invalid incoming call data');
      return;
    }
    
    // Initialize call service (fetches ICE servers) and set up the call state
    final callService = CallService();
    await callService.initialize();
    callService.handleIncomingCall(data);
    
    // Set up signal handler for WebRTC
    _socketService.onSignal = (signalData) {
      debugPrint('📡 Signal received for incoming call: $signalData');
      callService.handleSignal(signalData);
    };
    
    // Set up call ended/declined handlers
    _socketService.onCallEnded = (endData) {
      debugPrint('📴 Call ended by remote user');
      callService.handleCallEnded();
    };
    
    _socketService.onCallDeclined = (declineData) {
      debugPrint('❌ Call declined');
      callService.handleCallDeclined();
    };
    
    // Show incoming call setup modal with device selection
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => IncomingCallSetupModal(
          callerName: callerName,
          callerId: callerId,
          callType: callType,
          callService: callService,
          onDecline: () {
            debugPrint('📞 Call declined by user');
          },
        ),
      ),
    ).then((result) {
      if (result is Map && (result['result'] == 'accepted' || result['result'] == 'connected')) {
        // Navigate to connected call screen with the local stream from setup
        final localStream = result['localStream'];
        Navigator.of(context).push(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (context) => ConnectedCallScreen(
              remoteName: callerName,
              callType: callType,
              callService: callService,
              localStream: localStream ?? callService.localStream,
              onChatPressed: () {
                Navigator.of(context).pop(); // Return to chat
              },
            ),
          ),
        );
      }
    });
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
        
        // Persist the color so it survives app restarts / background
        _saveChatColor(colorHex);
        
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
    
    // Persist the reset color
    _saveChatColor('#1E1E1E');
    
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
        
        // Populate _messageReactions from loaded messages
        _messageReactions.clear();
        for (final msg in _messages) {
          if (msg.reactions.isNotEmpty) {
            debugPrint('📦 Message ${msg.id} reactions raw: ${msg.reactions}');
            _messageReactions[msg.id] = {};
            
            // Backend sends format: { "counts": {"😀": 1}, "by_user": [{"user_id": 1, "reaction": "😀"}] }
            // We need to extract reactions from by_user array and group by emoji
            final byUser = msg.reactions['by_user'];
            if (byUser is List && byUser.isNotEmpty) {
              // New format: extract from by_user array
              for (final entry in byUser) {
                if (entry is Map) {
                  final emoji = entry['reaction']?.toString();
                  final userId = entry['user_id']?.toString();
                  if (emoji != null && emoji.isNotEmpty && userId != null) {
                    _messageReactions[msg.id]!.putIfAbsent(emoji, () => <String>{});
                    _messageReactions[msg.id]![emoji]!.add(userId);
                  }
                }
              }
            } else {
              // Fallback: Legacy format handling
              // Handle format: { "emoji": { "by_user": [user_id, ...] } }
              // or format: { "emoji": [user_name1, user_name2] }
              msg.reactions.forEach((key, value) {
                // Skip known wrapper keys
                if (key == 'counts' || key == 'by_user') return;
                
                if (value is Map) {
                  // Nested format: { "emoji": { "by_user": [...] } }
                  final emoji = key.toString();
                  final users = value['by_user'];
                  if (users is List && users.isNotEmpty) {
                    _messageReactions[msg.id]![emoji] = Set<String>.from(
                      users.map((u) => u.toString())
                    );
                  }
                } else if (value is List) {
                  // Simple format: { "emoji": [user1, user2] }
                  final emoji = key.toString();
                  _messageReactions[msg.id]![emoji] = Set<String>.from(
                    value.map((u) => u.toString())
                  );
                }
              });
            }
            
            debugPrint('📦 Message ${msg.id} reactions parsed: ${_messageReactions[msg.id]}');
          }
        }
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
  
  /// Scroll to bottom and mark all messages as read
  Future<void> _scrollToBottomAndMarkRead() async {
    // Scroll to bottom
    _scrollToBottom();
    
    // Reset unread count
    setState(() {
      _unreadCount = 0;
      _isAtBottom = true;
    });
    
    // Mark all messages as read
    if (_messages.isNotEmpty) {
      final latestMessage = _messages.first;
      await MessageService.markAsRead(
        senderId: widget.otherUser.id,
        lastMessageId: latestMessage.id,
      );
      _socketService.confirmRead(latestMessage.id);
    }
  }
  
  /// Export chat to a text file
  Future<void> _exportChat() async {
    try {
      // Request storage permission first
      final storageStatus = await Permission.storage.request();
      if (!storageStatus.isGranted) {
        // Try manage external storage for Android 11+
        final manageStatus = await Permission.manageExternalStorage.request();
        if (!manageStatus.isGranted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Storage permission required to save file'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }
      }
      
      // Show loading indicator
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Preparing chat export...'),
            duration: Duration(seconds: 1),
          ),
        );
      }
      
      // Build the export content
      final buffer = StringBuffer();
      final myName = 'Me'; // TODO: Get actual user name if available
      final otherName = widget.otherUser.fullName;
      
      buffer.writeln('Chat Export');
      buffer.writeln('Conversation with: $otherName');
      buffer.writeln('Exported on: ${DateTime.now().toString()}');
      buffer.writeln('=' * 50);
      buffer.writeln();
      
      // Messages are reversed (newest first), so reverse them for export
      final sortedMessages = _messages.reversed.toList();
      
      String? lastDate;
      for (final message in sortedMessages) {
        // Add date separator if day changed
        final messageDate = _formatExportDate(message.timestamp);
        if (messageDate != lastDate) {
          buffer.writeln();
          buffer.writeln('--- $messageDate ---');
          buffer.writeln();
          lastDate = messageDate;
        }
        
        final senderName = message.senderId == _currentUserId ? myName : otherName;
        final time = _formatExportTime(message.timestamp);
        final content = message.isDeleted ? '[Message deleted]' : message.content;
        
        // Handle different message types
        String messageContent;
        if (message.messageType == 'voice' || message.messageType == 'audio') {
          messageContent = '[Voice message]';
        } else if (message.messageType == 'image') {
          messageContent = '[Image: ${message.fileName ?? "image"}]';
        } else if (message.messageType == 'video') {
          messageContent = '[Video: ${message.fileName ?? "video"}]';
        } else if (message.messageType == 'file') {
          messageContent = '[File: ${message.fileName ?? "file"}]';
        } else {
          messageContent = content;
        }
        
        buffer.writeln('[$time] $senderName: $messageContent');
      }
      
      buffer.writeln();
      buffer.writeln('=' * 50);
      buffer.writeln('End of export - ${sortedMessages.length} messages');
      
      // Generate default filename and convert content to bytes
      final defaultFileName = 'chat_${widget.otherUser.fullName.replaceAll(' ', '_')}_${DateTime.now().day}-${DateTime.now().month}-${DateTime.now().year}.txt';
      final contentBytes = buffer.toString().codeUnits;
      
      // Let user choose where to save the file (pass bytes for Android/iOS)
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Chat Export',
        fileName: defaultFileName,
        type: FileType.custom,
        allowedExtensions: ['txt'],
        bytes: Uint8List.fromList(contentBytes),
      );
      
      if (savePath == null) {
        // User cancelled the picker
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Export cancelled'),
              duration: Duration(seconds: 1),
            ),
          );
        }
        return;
      }
      
      // On Android, the file is already saved when bytes are provided
      // On other platforms, we may need to write the file
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Chat saved to: ${savePath.split('/').last}'),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error exporting chat: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to export chat: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  /// Format date for export separator
  String _formatExportDate(String timestamp) {
    try {
      final date = _parseUtcTimestamp(timestamp);
      final weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
      final months = ['January', 'February', 'March', 'April', 'May', 'June', 
                      'July', 'August', 'September', 'October', 'November', 'December'];
      return '${weekdays[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}, ${date.year}';
    } catch (e) {
      return timestamp;
    }
  }
  
  /// Format time for export message
  String _formatExportTime(String timestamp) {
    try {
      final date = _parseUtcTimestamp(timestamp);
      final hour = date.hour.toString().padLeft(2, '0');
      final minute = date.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    } catch (e) {
      return '';
    }
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;

    // Capture reply info before clearing
    final replyToId = _replyingToMessage?.id;
    String? replyPreviewContent;
    if (_replyingToMessage != null) {
      final msg = _replyingToMessage!;
      final senderName = msg.senderId == _currentUserId ? 'You' : widget.otherUser.fullName;
      String previewText;
      // Handle different message types
      if (msg.isDeleted) {
        previewText = 'Deleted message';
      } else if (msg.messageType == 'voice' || msg.messageType == 'audio') {
        previewText = '🎤 Voice message';
      } else if (msg.messageType == 'image') {
        previewText = '📷 Photo';
      } else if (msg.messageType == 'video') {
        previewText = '🎬 Video';
      } else if (msg.messageType == 'file') {
        previewText = '📎 ${msg.fileName ?? "File"}';
      } else {
        // For text, truncate if too long
        previewText = msg.content.length > 60 ? '${msg.content.substring(0, 60)}...' : msg.content;
      }
      replyPreviewContent = '$senderName: $previewText';
    }

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
      replyToId: replyToId,
      replyPreview: replyPreviewContent,
      reactions: {},
      isDeleted: false,
    );

    setState(() {
      _messages.insert(0, optimisticMessage);
      _replyingToMessage = null; // Clear reply after sending
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
        debugPrint('✅ Sending message via Socket.IO${replyToId != null ? ' (replying to $replyToId)' : ''}');
        _socketService.sendMessage(
          recipientId: widget.otherUser.id,
          content: content,
          messageType: 'text',
          replyToId: replyToId,
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
    
    // Persist the reset color
    _saveChatColor('#1E1E1E');
    
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

  /// Show call setup modal for video/audio calls
  void _showCallSetupModal(CallType callType) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => CallSetupModal(
          recipientName: widget.otherUser.fullName,
          callType: callType,
          onStartCall: (localStream, selectedMic, selectedSpeaker, selectedCamera, videoEnabled) {
            Navigator.pop(context); // Close modal
            _initiateCall(localStream, callType, videoEnabled);
          },
        ),
      ),
    );
  }

  /// Initiate call via CallService
  Future<void> _initiateCall(dynamic localStream, CallType callType, bool videoEnabled) async {
    final callService = CallService();
    final callTypeStr = callType == CallType.video ? 'video' : 'audio';
    
    // Set up socket signal handler
    _socketService.onSignal = (data) {
      callService.handleSignal(data);
    };
    
    _socketService.onCallInitiated = (data) {
      callService.handleCallInitiated(data);
    };
    
    _socketService.onCallEnded = (data) {
      debugPrint('📴 Call ended - cleaning up');
      callService.handleCallEnded();
    };
    
    _socketService.onCallDeclined = (data) {
      debugPrint('❌ Call declined by remote user');
      callService.handleCallDeclined();
    };
    
    // Set up error callback
    callService.onCallError = (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Call error: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    };
    
    // Initialize and start the call (await to ensure ICE servers are fetched)
    await callService.initialize();
    await callService.initiateCall(
      calleeId: widget.otherUser.id,
      callType: callTypeStr,
      localStream: localStream,
    );
    
    debugPrint('🎥 Initiated ${callType.name} call with ${widget.otherUser.fullName}');
    
    // Show outgoing call modal
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => OutgoingCallModal(
          recipientName: widget.otherUser.fullName,
          callType: callTypeStr,
          callService: callService,
          onCancel: () {
            debugPrint('📞 Call cancelled by user');
          },
          onConnected: () {
            debugPrint('📞 Call connected!');
          },
        ),
      ),
    );
    
    // Navigate to connected call screen if call connected
    if (result == 'connected' && mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (context) => ConnectedCallScreen(
            remoteName: widget.otherUser.fullName,
            callType: callTypeStr,
            callService: callService,
            localStream: localStream,
            onChatPressed: () {
              Navigator.of(context).pop(); // Return to chat
            },
          ),
        ),
      );
    }
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

  /// Toggle emoji picker visibility (inline below input)
  void _showEmojiPickerModal(BuildContext context) {
    setState(() {
      _showEmojiPicker = !_showEmojiPicker;
    });
  }

  /// Build inline emoji picker widget
  Widget _buildInlineEmojiPicker() {
    // Common emojis organized by category
    const List<String> emojis = [
      // Smileys & People
      '😀', '😃', '😄', '😁', '😅', '😂', '🤣', '😊', '😇', '🙂',
      '😉', '😍', '🥰', '😘', '😗', '😋', '😛', '😜', '🤪', '😝',
      '🤑', '🤗', '🤭', '🤫', '🤔', '🤐', '🤨', '😐', '😑', '😶',
      '😏', '😒', '🙄', '😬', '😮', '😲', '🥱', '😴', '🤤', '😷',
      '🤒', '🤕', '🤢', '🤮', '🤧', '🥵', '🥶', '😵', '🤯', '🤠',
      '🥳', '🥸', '😎', '🤓', '🧐', '😕', '😟', '🙁', '😮', '😯',
      '😢', '😭', '😤', '😠', '😡', '🤬', '😈', '👿', '💀', '☠️',
      '💩', '🤡', '👹', '👺', '👻', '👽', '👾', '🤖', '😺', '😸',
      // Gestures
      '👍', '👎', '👊', '✊', '🤛', '🤜', '👏', '🙌', '👐', '🤲',
      '🤝', '🙏', '✌️', '🤞', '🤟', '🤘', '🤙', '👈', '👉', '👆',
      '👇', '☝️', '👋', '🤚', '🖐️', '✋', '🖖', '💪', '🦾', '🙏',
      // Hearts & Symbols
      '❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍', '🤎', '💔',
      '❣️', '💕', '💞', '💓', '💗', '💖', '💘', '💝', '💟', '☮️',
      // Objects
      '🔥', '💧', '🌟', '⭐', '✨', '💫', '🌈', '☀️', '🌤️', '⛅',
      '🎉', '🎊', '🎈', '🎁', '🎀', '🎄', '🎃', '🎗️', '🎟️', '🎫',
    ];

    return Container(
      height: 200,
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF3D3D3D),
        borderRadius: BorderRadius.circular(12),
      ),
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
              
              final newText = text.substring(0, cursorPos) + 
                              emojis[index] + 
                              text.substring(cursorPos);
              
              _messageController.text = newText;
              _messageController.selection = TextSelection.collapsed(
                offset: cursorPos + emojis[index].length,
              );
              
              // Trigger text changed and rebuild UI
              _onTextChanged(newText);
              setState(() {}); // Force rebuild to update button visibility
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
      final ext = path.split('.').last.toLowerCase();
      final fileName = 'voice_${DateTime.now().millisecondsSinceEpoch}.$ext';
      
      // Determine correct MIME type for voice files
      // MultipartFile.fromPath doesn't detect .aac/.m4a properly (sends application/octet-stream)
      String mimeType = lookupMimeType(path) ?? 'application/octet-stream';
      if (mimeType == 'application/octet-stream') {
        // Fallback based on extension
        const audioMimeMap = {
          'aac': 'audio/aac',
          'm4a': 'audio/mp4',
          'mp3': 'audio/mpeg',
          'wav': 'audio/wav',
          'ogg': 'audio/ogg',
          'opus': 'audio/opus',
          'flac': 'audio/flac',
        };
        mimeType = audioMimeMap[ext] ?? mimeType;
      }
      
      // Create MultipartFile with explicit content type
      final multipartFile = await http.MultipartFile.fromPath(
        'file',
        path,
        filename: fileName,
        contentType: MediaType.parse(mimeType),
      );
      
      // Upload file using MessageService
      final result = await MessageService.uploadFile(
        file: multipartFile,
        recipientId: widget.otherUser.id,
      );

      // Hide uploading indicator
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      if (result != null && result['success'] == true) {
        final fileData = result['file'] ?? result;
        
        // NOTE: The REST API upload already emits file_message to the recipient,
        // so we do NOT emit send_file here to avoid duplicate messages on the web.

        // Create local message to show in chat
        final now = DateTime.now();
        final message = Message(
          id: fileData['message_id'] ?? DateTime.now().millisecondsSinceEpoch,
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
          fileType: 'audio/mp4',
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
    _lastSeenRefreshTimer?.cancel();
    
    // Send typing stop without setState (widget is being disposed)
    _socketService.stopTyping(widget.otherUser.id);
    
    // Leave chat room
    _socketService.leaveChat(widget.otherUser.id);
    
    // Clear active chat so FCM notifications resume for this user
    FirebaseMessagingService.instance.activeChatUserId = null;
    
    // Clear callbacks
    _socketService.onMessageReceived = null;
    _socketService.onUserTyping = null;
    _socketService.onTypingUpdate = null;
    _socketService.onJoinedChat = null;
    _socketService.onDoorbellRing = null;
    _socketService.onColorChanged = null;
    _socketService.onMessageDeleted = null;
    _socketService.onMessageEdited = null;
    _socketService.onTaskAdded = null;
    _socketService.onTaskCompleted = null;
    _socketService.onTaskUncompleted = null;
    _socketService.onExcalidrawPinned = null;
    _socketService.onExcalidrawUnpinned = null;
    
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
                        : (_partnerStatus == 'online' 
                            ? 'online' 
                            : _partnerStatus == 'away'
                                ? (_partnerLastSeen != null 
                                    ? 'Last seen ${_formatLastSeen(_partnerLastSeen!)}' 
                                    : 'away')
                                : (_partnerLastSeen != null 
                                    ? 'Last seen ${_formatLastSeen(_partnerLastSeen!)}' 
                                    : 'offline')),
                    style: TextStyle(
                      color: _otherUserTyping
                          ? const Color(0xFF4CAF50)
                          : (_partnerStatus == 'online'
                              ? const Color(0xFF4CAF50)
                              : _partnerStatus == 'away'
                                  ? const Color(0xFFFFC107)
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
        actions: [
          // Video call button
          IconButton(
            icon: const Icon(Icons.videocam, color: Colors.white),
            onPressed: () => _showCallSetupModal(CallType.video),
            tooltip: 'Video Call',
          ),
          // Audio call button
          IconButton(
            icon: const Icon(Icons.call, color: Colors.white),
            onPressed: () => _showCallSetupModal(CallType.audio),
            tooltip: 'Audio Call',
          ),
          // More options menu (Tasks & Excalidraw)
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            color: const Color(0xFF1E1E2E),
            onSelected: (value) {
              if (value == 'tasks') {
                _showTasksModal();
              } else if (value == 'excalidraw') {
                _showExcalidrawModal();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'tasks',
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
                    SizedBox(width: 12),
                    Text('Tasks', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'excalidraw',
                child: Row(
                  children: [
                    Icon(Icons.draw_outlined, color: Colors.white, size: 20),
                    SizedBox(width: 12),
                    Text('Excalidraw', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: Stack(
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
                    : Stack(
                        children: [
                          RepaintBoundary(
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
                                
                                // Check if we need to show date separator
                                // Since list is reversed, check the NEXT message (index + 1) for date change
                                Widget? dateSeparator;
                                if (index < _messages.length - 1) {
                                  final nextMessage = _messages[index + 1];
                                  if (!_isSameDay(message.timestamp, nextMessage.timestamp)) {
                                    dateSeparator = _buildDateSeparator(message.timestamp);
                                  }
                                } else {
                                  // First message (oldest) always shows date
                                  dateSeparator = _buildDateSeparator(message.timestamp);
                                }
                                
                                return Column(
                                  children: [
                                    if (dateSeparator != null) dateSeparator,
                                    _buildSwipeableMessage(
                                      message,
                                      isSentByMe,
                                      _buildMessageBubble(message, isSentByMe),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                          // Scroll to bottom button - positioned inside messages area
                          if (!_isAtBottom)
                            Positioned(
                              bottom: 16,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: GestureDetector(
                                  onTap: _scrollToBottomAndMarkRead,
                                  child: Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF7C3AED),
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.3),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        const Icon(
                                          Icons.keyboard_arrow_down,
                                          color: Colors.white,
                                          size: 28,
                                        ),
                                        if (_unreadCount > 0)
                                          Positioned(
                                            top: 2,
                                            right: 2,
                                            child: Container(
                                              padding: const EdgeInsets.all(4),
                                              decoration: const BoxDecoration(
                                                color: Colors.red,
                                                shape: BoxShape.circle,
                                              ),
                                              constraints: const BoxConstraints(
                                                minWidth: 18,
                                                minHeight: 18,
                                              ),
                                              child: Text(
                                                _unreadCount > 99 ? '99+' : _unreadCount.toString(),
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                                textAlign: TextAlign.center,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
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
            decoration: BoxDecoration(
              color: _headerColor,
              border: const Border(
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
              decoration: BoxDecoration(
                color: _headerColor,
                border: const Border(
                  top: BorderSide(color: Color(0xFF3D3D3D), width: 1),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                // Reply preview (when replying to a message)
                _buildReplyPreview(),
                // Text input field with emoji button - full width, max 3 lines
                RepaintBoundary(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Emoji picker button
                      Container(
                        margin: const EdgeInsets.only(right: 8, bottom: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6D28D9), // Purple like web app
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: IconButton(
                          onPressed: () => _showEmojiPickerModal(context),
                          icon: const Icon(
                            Icons.sentiment_satisfied_alt_outlined,
                            color: Colors.white,
                          ),
                          padding: const EdgeInsets.all(12),
                          constraints: const BoxConstraints(),
                        ),
                      ),
                      // Text input field
                      Expanded(
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
                    ],
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
                // Inline emoji picker (shown when active)
                if (_showEmojiPicker)
                  _buildInlineEmojiPicker(),
                // Action buttons (shown when emoji picker is closed AND keyboard is not visible)
                // Wrapped in AnimatedSize for smooth transition when keyboard opens/closes
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  alignment: Alignment.topCenter,
                  child: (!_showEmojiPicker && MediaQuery.of(context).viewInsets.bottom == 0)
                    ? Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                        // Ring Doorbell
                        ElevatedButton(
                          onPressed: _ringDoorbell,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF8B5CF6), // Violet
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                            textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                          child: const Text('Ring Doorbell'),
                        ),
                        // Change Color
                        ElevatedButton(
                          onPressed: _changeColor,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFA855F7), // Purple
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                            textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
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
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                            ),
                            child: const Text('Reset Color'),
                          ),
                        // Send File
                        ElevatedButton(
                          onPressed: _pickFile,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981), // Green
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                            textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                          child: const Text('Send File'),
                        ),
                        // Camera
                        ElevatedButton(
                          onPressed: _takePhoto,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF3B82F6), // Blue
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                            textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                          child: const Text('Camera'),
                        ),
                        // Record Voice Message
                        ElevatedButton(
                          onPressed: _showVoiceRecordingModal,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFEF4444), // Red
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                            textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                          child: const Text('Voice Message'),
                        ),
                        // Auto-Translate
                        ElevatedButton(
                          onPressed: _toggleAutoTranslate,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _autoTranslate 
                                ? const Color(0xFF059669)  // Green when ON
                                : const Color(0xFF0891B2), // Cyan when OFF
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                            textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                          child: Text(_autoTranslate ? 'Translate: ON' : 'Translate: OFF'),
                        ),
                        // Show Timestamps
                        ElevatedButton(
                          onPressed: _toggleTimestamps,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _showTimestamps 
                                ? const Color(0xFF4F46E5)  // Indigo when ON
                                : const Color(0xFF8B5CF6), // Purple when OFF
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                            textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                          child: Text(_showTimestamps ? 'Hide Timestamps' : 'Show Timestamps'),
                        ),
                        // Export Chat
                        ElevatedButton(
                          onPressed: _exportChat,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6B7280), // Gray
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                            textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                          child: const Text('Export Chat'),
                        ),
                      ],
                    )
                    : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
          ),
            ],
          ),
        ],
      ),
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

  /// Clear reply state
  void _clearReply() {
    setState(() {
      _replyingToMessage = null;
    });
  }

  /// Set reply target
  void _setReplyTo(Message message) {
    setState(() {
      _replyingToMessage = message;
    });
    // Give haptic feedback
    _inputFocusNode.requestFocus();
  }

  /// Build swipeable message wrapper with slide animation
  Widget _buildSwipeableMessage(Message message, bool isSentByMe, Widget child) {
    // Swipe direction: incoming (from left) swipe right, outgoing (from right) swipe left
    const double maxSlide = 70.0;
    const double threshold = 50.0;
    
    // Use ValueNotifier for proper state tracking during drag
    final dragOffset = ValueNotifier<double>(0.0);
    
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (details) {
        if (isSentByMe) {
          // Outgoing: swipe left (negative)
          dragOffset.value = (dragOffset.value + details.delta.dx).clamp(-maxSlide, 0.0);
        } else {
          // Incoming: swipe right (positive)
          dragOffset.value = (dragOffset.value + details.delta.dx).clamp(0.0, maxSlide);
        }
      },
      onHorizontalDragEnd: (details) {
        // If swiped far enough, trigger reply
        if (dragOffset.value.abs() > threshold) {
          _setReplyTo(message);
        }
        // Animate back to 0
        dragOffset.value = 0.0;
      },
      onLongPress: () => _showMessageContextMenu(message, isSentByMe),
      child: ValueListenableBuilder<double>(
        valueListenable: dragOffset,
        builder: (context, offset, _) {
          return Transform.translate(
            offset: Offset(offset, 0),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Reply icon that appears when swiping
                if (offset.abs() > 10)
                  Positioned(
                    left: isSentByMe ? -35 : null,
                    right: isSentByMe ? null : -35,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: Opacity(
                        opacity: (offset.abs() / maxSlide).clamp(0.0, 1.0),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF7C3AED).withOpacity(0.9),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.reply,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                  ),
                child,
              ],
            ),
          );
        },
      ),
    );
  }

  /// Show context menu for message
  void _showMessageContextMenu(Message message, bool isSentByMe) {
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
              // Reply option
              ListTile(
                leading: const Icon(Icons.reply, color: Colors.white),
                title: const Text('Reply', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _setReplyTo(message);
                },
              ),
              // Copy option (for text messages)
              if (message.messageType == 'text' && !message.isDeleted)
                ListTile(
                  leading: const Icon(Icons.copy, color: Colors.white),
                  title: const Text('Copy', style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(context);
                    _copyMessageToClipboard(message);
                  },
                ),
              // Edit option (for own text messages only)
              if (isSentByMe && message.messageType == 'text' && !message.isDeleted)
                ListTile(
                  leading: const Icon(Icons.edit, color: Colors.white),
                  title: const Text('Edit', style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(context);
                    _showEditMessageDialog(message);
                  },
                ),
              // Delete option (for own messages)
              if (isSentByMe && !message.isDeleted)
                ListTile(
                  leading: const Icon(Icons.delete, color: Colors.red),
                  title: const Text('Delete', style: TextStyle(color: Colors.red)),
                  onTap: () {
                    Navigator.pop(context);
                    _showDeleteConfirmation(message);
                  },
                ),
              // Add to Tasks option (for text messages)
              if (message.messageType == 'text' && !message.isDeleted && !message.isTask)
                ListTile(
                  leading: const Icon(Icons.add_task, color: Colors.orange),
                  title: const Text('Add to Tasks', style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(context);
                    _addMessageToTask(message);
                  },
                ),
              // Pin Excalidraw option (for excalidraw links)
              if ((message.content.contains('excalidraw.com') || message.isExcalidrawLink) && !message.isDeleted)
                ListTile(
                  leading: Icon(
                    message.excalidrawPinnedAt != null ? Icons.push_pin : Icons.push_pin_outlined,
                    color: message.excalidrawPinnedAt != null ? const Color(0xFF420796) : Colors.white,
                  ),
                  title: Text(
                    message.excalidrawPinnedAt != null ? 'Unpin Excalidraw' : 'Pin Excalidraw',
                    style: const TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _toggleExcalidrawPin(message);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Add message to tasks
  void _addMessageToTask(Message message) {
    _socketService.addTask(message.id);
    
    // Optimistically update the message locally
    setState(() {
      final index = _messages.indexWhere((m) => m.id == message.id);
      if (index != -1) {
        final updatedMessage = Message(
          id: message.id,
          senderId: message.senderId,
          recipientId: message.recipientId,
          content: message.content,
          messageType: message.messageType,
          timestamp: message.timestamp,
          timestampMs: message.timestampMs,
          isRead: message.isRead,
          readAt: message.readAt,
          readAtMs: message.readAtMs,
          deliveredAt: message.deliveredAt,
          deliveredAtMs: message.deliveredAtMs,
          status: message.status,
          threadId: message.threadId,
          replyToId: message.replyToId,
          replyPreview: message.replyPreview,
          reactions: message.reactions,
          fileUrl: message.fileUrl,
          fileName: message.fileName,
          fileSize: message.fileSize,
          fileType: message.fileType,
          isDeleted: message.isDeleted,
          isTask: true,
          taskCreatedAt: DateTime.now().toIso8601String(),
        );
        _messages[index] = updatedMessage;
      }
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Added to tasks'),
        duration: Duration(seconds: 2),
        backgroundColor: Color(0xFF4CAF50),
      ),
    );
  }

  /// Toggle excalidraw pin status
  void _toggleExcalidrawPin(Message message) {
    if (message.excalidrawPinnedAt != null) {
      _socketService.unpinExcalidraw(message.id);
    } else {
      _socketService.pinExcalidraw(message.id);
    }
    
    // Optimistically update the message locally
    setState(() {
      final index = _messages.indexWhere((m) => m.id == message.id);
      if (index != -1) {
        final updatedMessage = Message(
          id: message.id,
          senderId: message.senderId,
          recipientId: message.recipientId,
          content: message.content,
          messageType: message.messageType,
          timestamp: message.timestamp,
          timestampMs: message.timestampMs,
          isRead: message.isRead,
          readAt: message.readAt,
          readAtMs: message.readAtMs,
          deliveredAt: message.deliveredAt,
          deliveredAtMs: message.deliveredAtMs,
          status: message.status,
          threadId: message.threadId,
          replyToId: message.replyToId,
          replyPreview: message.replyPreview,
          reactions: message.reactions,
          fileUrl: message.fileUrl,
          fileName: message.fileName,
          fileSize: message.fileSize,
          fileType: message.fileType,
          isDeleted: message.isDeleted,
          isExcalidrawLink: true,
          excalidrawPinnedAt: message.excalidrawPinnedAt != null ? null : DateTime.now().toIso8601String(),
        );
        _messages[index] = updatedMessage;
      }
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message.excalidrawPinnedAt != null ? 'Excalidraw unpinned' : 'Excalidraw pinned'),
        duration: const Duration(seconds: 2),
        backgroundColor: const Color(0xFF420796),
      ),
    );
  }

  /// Copy message content to clipboard
  void _copyMessageToClipboard(Message message) {
    Clipboard.setData(ClipboardData(text: message.content));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Message copied to clipboard'),
        duration: Duration(seconds: 2),
        backgroundColor: Color(0xFF4CAF50),
      ),
    );
  }

  /// Show edit message dialog
  void _showEditMessageDialog(Message message) {
    final editController = TextEditingController(text: message.content);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('Edit Message', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: editController,
          style: const TextStyle(color: Colors.white),
          maxLines: 5,
          minLines: 1,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Edit your message...',
            hintStyle: TextStyle(color: Colors.grey[500]),
            filled: true,
            fillColor: const Color(0xFF252542),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              final newContent = editController.text.trim();
              if (newContent.isNotEmpty && newContent != message.content) {
                Navigator.pop(context);
                _editMessage(message, newContent);
              } else {
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF420796),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    
    editController.dispose;
  }

  /// Edit message via socket
  void _editMessage(Message message, String newContent) {
    _socketService.editMessage(message.id, newContent);
    
    // Optimistically update the message locally
    setState(() {
      final index = _messages.indexWhere((m) => m.id == message.id);
      if (index != -1) {
        final updatedMessage = Message(
          id: message.id,
          senderId: message.senderId,
          recipientId: message.recipientId,
          content: newContent,
          messageType: message.messageType,
          timestamp: message.timestamp,
          timestampMs: message.timestampMs,
          isRead: message.isRead,
          readAt: message.readAt,
          readAtMs: message.readAtMs,
          deliveredAt: message.deliveredAt,
          deliveredAtMs: message.deliveredAtMs,
          status: message.status,
          threadId: message.threadId,
          replyToId: message.replyToId,
          replyPreview: message.replyPreview,
          reactions: message.reactions,
          fileUrl: message.fileUrl,
          fileName: message.fileName,
          fileSize: message.fileSize,
          fileType: message.fileType,
          isDeleted: message.isDeleted,
        );
        _messages[index] = updatedMessage;
      }
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Message edited'),
        duration: Duration(seconds: 2),
        backgroundColor: Color(0xFF4CAF50),
      ),
    );
  }

  /// Show delete confirmation dialog
  void _showDeleteConfirmation(Message message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('Delete Message', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure you want to delete this message? This action cannot be undone.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteMessage(message);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  /// Delete message via socket
  void _deleteMessage(Message message) {
    _socketService.deleteMessage(message.id);
    
    // Optimistically update the message locally (mark as deleted)
    setState(() {
      final index = _messages.indexWhere((m) => m.id == message.id);
      if (index != -1) {
        final updatedMessage = Message(
          id: message.id,
          senderId: message.senderId,
          recipientId: message.recipientId,
          content: 'This message was deleted',
          messageType: message.messageType,
          timestamp: message.timestamp,
          timestampMs: message.timestampMs,
          isRead: message.isRead,
          readAt: message.readAt,
          readAtMs: message.readAtMs,
          deliveredAt: message.deliveredAt,
          deliveredAtMs: message.deliveredAtMs,
          status: message.status,
          threadId: message.threadId,
          replyToId: message.replyToId,
          replyPreview: message.replyPreview,
          reactions: message.reactions,
          fileUrl: message.fileUrl,
          fileName: message.fileName,
          fileSize: message.fileSize,
          fileType: message.fileType,
          isDeleted: true,
        );
        _messages[index] = updatedMessage;
      }
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Message deleted'),
        duration: Duration(seconds: 2),
        backgroundColor: Color(0xFF4CAF50),
      ),
    );
  }

  /// Handle message deleted event from socket (when other user deletes)
  void _handleMessageDeleted(Map<String, dynamic> data) {
    final messageId = data['message_id'] as int?;
    if (messageId == null) return;
    
    setState(() {
      final index = _messages.indexWhere((m) => m.id == messageId);
      if (index != -1) {
        final message = _messages[index];
        final updatedMessage = Message(
          id: message.id,
          senderId: message.senderId,
          recipientId: message.recipientId,
          content: 'This message was deleted',
          messageType: message.messageType,
          timestamp: message.timestamp,
          timestampMs: message.timestampMs,
          isRead: message.isRead,
          readAt: message.readAt,
          readAtMs: message.readAtMs,
          deliveredAt: message.deliveredAt,
          deliveredAtMs: message.deliveredAtMs,
          status: message.status,
          threadId: message.threadId,
          replyToId: message.replyToId,
          replyPreview: message.replyPreview,
          reactions: message.reactions,
          fileUrl: null,
          fileName: null,
          fileSize: null,
          fileType: null,
          isDeleted: true,
        );
        _messages[index] = updatedMessage;
      }
    });
  }

  /// Handle message edited event from socket (when other user edits)
  void _handleMessageEdited(Map<String, dynamic> data) {
    final messageId = data['message_id'] as int?;
    final newContent = data['content'] as String?;
    if (messageId == null || newContent == null) return;
    
    setState(() {
      final index = _messages.indexWhere((m) => m.id == messageId);
      if (index != -1) {
        final message = _messages[index];
        final updatedMessage = Message(
          id: message.id,
          senderId: message.senderId,
          recipientId: message.recipientId,
          content: newContent,
          messageType: message.messageType,
          timestamp: message.timestamp,
          timestampMs: message.timestampMs,
          isRead: message.isRead,
          readAt: message.readAt,
          readAtMs: message.readAtMs,
          deliveredAt: message.deliveredAt,
          deliveredAtMs: message.deliveredAtMs,
          status: message.status,
          threadId: message.threadId,
          replyToId: message.replyToId,
          replyPreview: message.replyPreview,
          reactions: message.reactions,
          fileUrl: message.fileUrl,
          fileName: message.fileName,
          fileSize: message.fileSize,
          fileType: message.fileType,
          isDeleted: message.isDeleted,
        );
        _messages[index] = updatedMessage;
      }
    });
  }

  /// Handle task added event from socket
  void _handleTaskAdded(Map<String, dynamic> data) {
    final messageId = data['message_id'] as int?;
    if (messageId == null) return;
    
    setState(() {
      final index = _messages.indexWhere((m) => m.id == messageId);
      if (index != -1) {
        final message = _messages[index];
        final updatedMessage = Message(
          id: message.id,
          senderId: message.senderId,
          recipientId: message.recipientId,
          content: message.content,
          messageType: message.messageType,
          timestamp: message.timestamp,
          timestampMs: message.timestampMs,
          isRead: message.isRead,
          readAt: message.readAt,
          readAtMs: message.readAtMs,
          deliveredAt: message.deliveredAt,
          deliveredAtMs: message.deliveredAtMs,
          status: message.status,
          threadId: message.threadId,
          replyToId: message.replyToId,
          replyPreview: message.replyPreview,
          reactions: message.reactions,
          fileUrl: message.fileUrl,
          fileName: message.fileName,
          fileSize: message.fileSize,
          fileType: message.fileType,
          isDeleted: message.isDeleted,
          isTask: true,
          taskCreatedAt: data['task_created_at'] as String? ?? DateTime.now().toIso8601String(),
        );
        _messages[index] = updatedMessage;
      }
    });
  }

  /// Handle task completed event from socket
  void _handleTaskCompleted(Map<String, dynamic> data) {
    final messageId = data['message_id'] as int?;
    if (messageId == null) return;
    
    setState(() {
      final index = _messages.indexWhere((m) => m.id == messageId);
      if (index != -1) {
        final message = _messages[index];
        final updatedMessage = Message(
          id: message.id,
          senderId: message.senderId,
          recipientId: message.recipientId,
          content: message.content,
          messageType: message.messageType,
          timestamp: message.timestamp,
          timestampMs: message.timestampMs,
          isRead: message.isRead,
          readAt: message.readAt,
          readAtMs: message.readAtMs,
          deliveredAt: message.deliveredAt,
          deliveredAtMs: message.deliveredAtMs,
          status: message.status,
          threadId: message.threadId,
          replyToId: message.replyToId,
          replyPreview: message.replyPreview,
          reactions: message.reactions,
          fileUrl: message.fileUrl,
          fileName: message.fileName,
          fileSize: message.fileSize,
          fileType: message.fileType,
          isDeleted: message.isDeleted,
          isTask: true,
          taskCreatedAt: message.taskCreatedAt,
          taskCompletedAt: data['completed_at'] as String? ?? DateTime.now().toIso8601String(),
        );
        _messages[index] = updatedMessage;
      }
    });
  }

  /// Handle task uncompleted event from socket
  void _handleTaskUncompleted(Map<String, dynamic> data) {
    final messageId = data['message_id'] as int?;
    if (messageId == null) return;
    
    setState(() {
      final index = _messages.indexWhere((m) => m.id == messageId);
      if (index != -1) {
        final message = _messages[index];
        final updatedMessage = Message(
          id: message.id,
          senderId: message.senderId,
          recipientId: message.recipientId,
          content: message.content,
          messageType: message.messageType,
          timestamp: message.timestamp,
          timestampMs: message.timestampMs,
          isRead: message.isRead,
          readAt: message.readAt,
          readAtMs: message.readAtMs,
          deliveredAt: message.deliveredAt,
          deliveredAtMs: message.deliveredAtMs,
          status: message.status,
          threadId: message.threadId,
          replyToId: message.replyToId,
          replyPreview: message.replyPreview,
          reactions: message.reactions,
          fileUrl: message.fileUrl,
          fileName: message.fileName,
          fileSize: message.fileSize,
          fileType: message.fileType,
          isDeleted: message.isDeleted,
          isTask: true,
          taskCreatedAt: message.taskCreatedAt,
          taskCompletedAt: null,
        );
        _messages[index] = updatedMessage;
      }
    });
  }

  /// Handle excalidraw pinned event from socket
  void _handleExcalidrawPinned(Map<String, dynamic> data) {
    final messageId = data['message_id'] as int?;
    if (messageId == null) return;
    
    setState(() {
      final index = _messages.indexWhere((m) => m.id == messageId);
      if (index != -1) {
        final message = _messages[index];
        final updatedMessage = Message(
          id: message.id,
          senderId: message.senderId,
          recipientId: message.recipientId,
          content: message.content,
          messageType: message.messageType,
          timestamp: message.timestamp,
          timestampMs: message.timestampMs,
          isRead: message.isRead,
          readAt: message.readAt,
          readAtMs: message.readAtMs,
          deliveredAt: message.deliveredAt,
          deliveredAtMs: message.deliveredAtMs,
          status: message.status,
          threadId: message.threadId,
          replyToId: message.replyToId,
          replyPreview: message.replyPreview,
          reactions: message.reactions,
          fileUrl: message.fileUrl,
          fileName: message.fileName,
          fileSize: message.fileSize,
          fileType: message.fileType,
          isDeleted: message.isDeleted,
          isExcalidrawLink: true,
          excalidrawPinnedAt: data['pinned_at'] as String? ?? DateTime.now().toIso8601String(),
        );
        _messages[index] = updatedMessage;
      }
    });
  }

  /// Handle excalidraw unpinned event from socket
  void _handleExcalidrawUnpinned(Map<String, dynamic> data) {
    final messageId = data['message_id'] as int?;
    if (messageId == null) return;
    
    setState(() {
      final index = _messages.indexWhere((m) => m.id == messageId);
      if (index != -1) {
        final message = _messages[index];
        final updatedMessage = Message(
          id: message.id,
          senderId: message.senderId,
          recipientId: message.recipientId,
          content: message.content,
          messageType: message.messageType,
          timestamp: message.timestamp,
          timestampMs: message.timestampMs,
          isRead: message.isRead,
          readAt: message.readAt,
          readAtMs: message.readAtMs,
          deliveredAt: message.deliveredAt,
          deliveredAtMs: message.deliveredAtMs,
          status: message.status,
          threadId: message.threadId,
          replyToId: message.replyToId,
          replyPreview: message.replyPreview,
          reactions: message.reactions,
          fileUrl: message.fileUrl,
          fileName: message.fileName,
          fileSize: message.fileSize,
          fileType: message.fileType,
          isDeleted: message.isDeleted,
          isExcalidrawLink: true,
          excalidrawPinnedAt: null,
        );
        _messages[index] = updatedMessage;
      }
    });
  }

  /// Handle message status updates (delivered/seen)
  void _handleMessageStatusUpdate(Map<String, dynamic> data) {
    final messageId = data['message_id'] as int?;
    final status = data['status'] as String?;
    final deliveredAt = data['delivered_at'] as String?;
    final readAt = data['read_at'] as String?;
    
    if (messageId == null || status == null) return;
    
    setState(() {
      final index = _messages.indexWhere((m) => m.id == messageId);
      if (index != -1) {
        final message = _messages[index];
        final updatedMessage = Message(
          id: message.id,
          senderId: message.senderId,
          recipientId: message.recipientId,
          content: message.content,
          messageType: message.messageType,
          timestamp: message.timestamp,
          timestampMs: message.timestampMs,
          isRead: status == 'seen',
          readAt: readAt,
          readAtMs: readAt != null ? DateTime.parse(readAt).millisecondsSinceEpoch : null,
          deliveredAt: deliveredAt ?? message.deliveredAt,
          deliveredAtMs: deliveredAt != null ? DateTime.parse(deliveredAt).millisecondsSinceEpoch : message.deliveredAtMs,
          status: status,
          threadId: message.threadId,
          replyToId: message.replyToId,
          replyPreview: message.replyPreview,
          reactions: message.reactions,
          fileUrl: message.fileUrl,
          fileName: message.fileName,
          fileSize: message.fileSize,
          fileType: message.fileType,
          isDeleted: message.isDeleted,
          isTask: message.isTask,
          taskCreatedAt: message.taskCreatedAt,
          taskCompletedAt: message.taskCompletedAt,
          isExcalidrawLink: message.isExcalidrawLink,
          excalidrawPinnedAt: message.excalidrawPinnedAt,
          isPinned: message.isPinned,
          pinnedAt: message.pinnedAt,
          pinnedByUserId: message.pinnedByUserId,
        );
        _messages[index] = updatedMessage;
      }
    });
    
    debugPrint('📊 Message $messageId status updated to: $status');
  }

  /// Handle messages read notifications
  void _handleMessagesRead(Map<String, dynamic> data) {
    final readerId = data['reader_id'] as int?;
    final messageCount = data['message_count'] as int?;
    
    if (readerId == widget.otherUser.id && messageCount != null && messageCount > 0) {
      debugPrint('✓✓ ${widget.otherUser.fullName} read $messageCount messages');
      
      // Update status of sent messages to 'seen'
      setState(() {
        for (int i = 0; i < _messages.length; i++) {
          final message = _messages[i];
          if (message.senderId == _currentUserId && message.recipientId == widget.otherUser.id && message.status != 'seen') {
            final updatedMessage = Message(
              id: message.id,
              senderId: message.senderId,
              recipientId: message.recipientId,
              content: message.content,
              messageType: message.messageType,
              timestamp: message.timestamp,
              timestampMs: message.timestampMs,
              isRead: true,
              readAt: DateTime.now().toIso8601String(),
              readAtMs: DateTime.now().millisecondsSinceEpoch,
              deliveredAt: message.deliveredAt,
              deliveredAtMs: message.deliveredAtMs,
              status: 'seen',
              threadId: message.threadId,
              replyToId: message.replyToId,
              replyPreview: message.replyPreview,
              reactions: message.reactions,
              fileUrl: message.fileUrl,
              fileName: message.fileName,
              fileSize: message.fileSize,
              fileType: message.fileType,
              isDeleted: message.isDeleted,
              isTask: message.isTask,
              taskCreatedAt: message.taskCreatedAt,
              taskCompletedAt: message.taskCompletedAt,
              isExcalidrawLink: message.isExcalidrawLink,
              excalidrawPinnedAt: message.excalidrawPinnedAt,
              isPinned: message.isPinned,
              pinnedAt: message.pinnedAt,
              pinnedByUserId: message.pinnedByUserId,
            );
            _messages[i] = updatedMessage;
          }
        }
      });
    }
  }

  /// Show tasks modal
  void _showTasksModal() {
    // Get all task messages from the conversation
    final tasks = _messages.where((m) => m.isTask).toList();
    
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E2E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey[600],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline, color: Colors.white, size: 24),
                  const SizedBox(width: 12),
                  const Text(
                    'Tasks',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${tasks.where((t) => t.taskCompletedAt != null).length}/${tasks.length} completed',
                    style: TextStyle(color: Colors.grey[400], fontSize: 14),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.grey),
            // Task list
            Expanded(
              child: tasks.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.task_alt, color: Colors.grey[600], size: 48),
                          const SizedBox(height: 16),
                          Text(
                            'No tasks yet',
                            style: TextStyle(color: Colors.grey[500], fontSize: 16),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Long-press a message and select "Add to Tasks"',
                            style: TextStyle(color: Colors.grey[600], fontSize: 12),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: tasks.length,
                      itemBuilder: (context, index) {
                        final task = tasks[index];
                        final isCompleted = task.taskCompletedAt != null;
                        return ListTile(
                          leading: IconButton(
                            icon: Icon(
                              isCompleted ? Icons.check_circle : Icons.circle_outlined,
                              color: isCompleted ? const Color(0xFF4CAF50) : Colors.grey,
                            ),
                            onPressed: () {
                              if (isCompleted) {
                                _socketService.uncompleteTask(task.id);
                              } else {
                                _socketService.completeTask(task.id);
                              }
                              Navigator.pop(context);
                              _refreshMessages();
                            },
                          ),
                          title: Text(
                            task.content.length > 50
                                ? '${task.content.substring(0, 50)}...'
                                : task.content,
                            style: TextStyle(
                              color: Colors.white,
                              decoration: isCompleted ? TextDecoration.lineThrough : null,
                              decorationColor: Colors.grey,
                            ),
                          ),
                          subtitle: Text(
                            task.formattedTime,
                            style: TextStyle(color: Colors.grey[500], fontSize: 12),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                            onPressed: () {
                              _removeTask(task);
                              Navigator.pop(context);
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Remove task from message
  void _removeTask(Message message) {
    // This would need a socket event to remove task status
    // For now, we'll just show a message
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Task removed'),
        backgroundColor: Color(0xFF4CAF50),
      ),
    );
    _refreshMessages();
  }

  /// Show excalidraw modal
  void _showExcalidrawModal() {
    // Get all excalidraw links from the conversation
    final excalidrawLinks = _messages.where((m) => 
      m.isExcalidrawLink || 
      m.content.contains('excalidraw.com') ||
      m.content.contains('excalidraw')
    ).toList();
    
    // Get pinned excalidraw
    final pinnedExcalidraw = excalidrawLinks.where((m) => m.excalidrawPinnedAt != null).toList();
    
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E2E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey[600],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.draw_outlined, color: Colors.white, size: 24),
                  const SizedBox(width: 12),
                  const Text(
                    'Excalidraw',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  if (pinnedExcalidraw.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF420796),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${pinnedExcalidraw.length} pinned',
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(color: Colors.grey),
            // Excalidraw list
            Expanded(
              child: excalidrawLinks.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.draw, color: Colors.grey[600], size: 48),
                          const SizedBox(height: 16),
                          Text(
                            'No Excalidraw links yet',
                            style: TextStyle(color: Colors.grey[500], fontSize: 16),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Share an excalidraw.com link in the chat',
                            style: TextStyle(color: Colors.grey[600], fontSize: 12),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: excalidrawLinks.length,
                      itemBuilder: (context, index) {
                        final link = excalidrawLinks[index];
                        final isPinned = link.excalidrawPinnedAt != null;
                        return ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isPinned ? const Color(0xFF420796) : Colors.grey[800],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              isPinned ? Icons.push_pin : Icons.draw_outlined,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          title: Text(
                            link.content.length > 40
                                ? '${link.content.substring(0, 40)}...'
                                : link.content,
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: Text(
                            link.formattedTime,
                            style: TextStyle(color: Colors.grey[500], fontSize: 12),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(
                                  isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                                  color: isPinned ? const Color(0xFF420796) : Colors.grey,
                                  size: 20,
                                ),
                                onPressed: () {
                                  if (isPinned) {
                                    _socketService.unpinExcalidraw(link.id);
                                  } else {
                                    _socketService.pinExcalidraw(link.id);
                                  }
                                  Navigator.pop(context);
                                  _refreshMessages();
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.open_in_new, color: Colors.blue, size: 20),
                                onPressed: () {
                                  _openExcalidrawLink(link.content);
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Open excalidraw link in browser
  void _openExcalidrawLink(String content) {
    // Extract URL from content if needed
    final urlRegex = RegExp(r'https?://[^\s]+');
    final match = urlRegex.firstMatch(content);
    if (match != null) {
      final url = match.group(0);
      // For now just show a message - would need url_launcher package
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Opening: $url'),
          backgroundColor: const Color(0xFF420796),
        ),
      );
    }
  }

  /// Refresh messages from server
  Future<void> _refreshMessages() async {
    try {
      final messages = await MessageService.getConversationMessages(
        userId: widget.otherUser.id,
        limit: 50,
      );
      setState(() {
        _messages.clear();
        _messages.addAll(messages);
      });
    } catch (e) {
      debugPrint('Error refreshing messages: $e');
    }
  }

  /// Build reply preview widget (shown above input)
  Widget _buildReplyPreview() {
    if (_replyingToMessage == null) return const SizedBox.shrink();
    
    final message = _replyingToMessage!;
    final isSentByMe = message.senderId == _currentUserId;
    final senderName = isSentByMe ? 'You' : widget.otherUser.fullName;
    
    // Get preview content
    String content;
    if (message.isDeleted) {
      content = 'Deleted message';
    } else if (message.messageType == 'voice' || message.messageType == 'audio') {
      content = '🎤 Voice message';
    } else if (message.messageType == 'image') {
      content = '📷 Photo';
    } else if (message.messageType == 'video') {
      content = '🎬 Video';
    } else if (message.messageType == 'file') {
      content = '📎 ${message.fileName ?? "File"}';
    } else {
      content = message.content.length > 50 
          ? '${message.content.substring(0, 50)}...' 
          : message.content;
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D44),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            color: const Color(0xFF7C3AED),
            width: 4,
          ),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.reply, color: Color(0xFF7C3AED), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Replying to $senderName',
                  style: const TextStyle(
                    color: Color(0xFF7C3AED),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  content,
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _clearReply,
            child: Container(
              padding: const EdgeInsets.all(4),
              child: const Icon(Icons.close, color: Colors.grey, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  /// Check if two timestamps are on the same day
  bool _isSameDay(String timestamp1, String timestamp2) {
    try {
      final date1 = _parseUtcTimestamp(timestamp1);
      final date2 = _parseUtcTimestamp(timestamp2);
      return date1.year == date2.year && 
             date1.month == date2.month && 
             date1.day == date2.day;
    } catch (e) {
      return true; // Assume same day if parsing fails
    }
  }

  /// Build date separator widget like Skype (Today, Yesterday, or full date)
  Widget _buildDateSeparator(String timestamp) {
    try {
      final date = _parseUtcTimestamp(timestamp);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));
      final messageDate = DateTime(date.year, date.month, date.day);
      
      String dateText;
      if (messageDate == today) {
        dateText = 'Today';
      } else if (messageDate == yesterday) {
        dateText = 'Yesterday';
      } else {
        // Format: Tue. Jan 20, 2026
        final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 
                        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        final weekday = weekdays[date.weekday - 1];
        final month = months[date.month - 1];
        dateText = '$weekday. $month ${date.day}, ${date.year}';
      }
      
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF3D4752), // Dark gray like the image
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              dateText,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      );
    } catch (e) {
      return const SizedBox.shrink();
    }
  }

  /// Build reaction pills for a message
  Widget _buildReactionPills(int messageId) {
    final reactions = _messageReactions[messageId];
    if (reactions == null || reactions.isEmpty) {
      return const SizedBox.shrink();
    }

    final pills = <Widget>[];
    reactions.forEach((emoji, users) {
      if (users.isNotEmpty) {
        pills.add(
          GestureDetector(
            onTap: () => _toggleReaction(messageId, emoji),
            child: Container(
              margin: const EdgeInsets.only(right: 4, top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF2C2C2E),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withOpacity(0.2),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    emoji,
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${users.length}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    });

    if (pills.isEmpty) return const SizedBox.shrink();

    return Wrap(
      children: pills,
    );
  }

  /// Toggle reaction (clear if already reacted with same emoji)
  void _toggleReaction(int messageId, String emoji) {
    final userId = _currentUserId?.toString() ?? '';
    final reactions = _messageReactions[messageId];
    
    // Check if current user has this reaction
    final hasThisReaction = reactions?[emoji]?.contains(userId) ?? false;
    
    if (hasThisReaction) {
      // User has this reaction, clear it
      _socketService.clearReaction(messageId);
      debugPrint('👆 Tapped reaction $emoji on message $messageId - clearing (user has this reaction)');
    } else {
      // User doesn't have this reaction, set it
      _socketService.setReaction(messageId, emoji);
      debugPrint('👆 Tapped reaction $emoji on message $messageId - setting (user adding reaction)');
    }
  }

  /// Show reaction picker for a message
  void _showReactionPicker(BuildContext context, int messageId, Offset position) {
    ReactionPicker.show(
      context: context,
      position: position,
      onReactionSelected: (emoji) {
        _socketService.setReaction(messageId, emoji);
      },
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
    
    // Build the main bubble widget (without Align - alignment handled in return)
    final bubbleWidget = Container(
      margin: const EdgeInsets.only(bottom: 12),
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
                opacity: 0.85, // WhatsApp-like dimmed effect
                child: Container(
                  margin: const EdgeInsets.only(left: 8, right: 8, top: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: const Border(
                      left: BorderSide(
                        color: Color(0xFFB794F6),
                        width: 3,
                      ),
                    ),
                  ),
                  child: Builder(
                    builder: (context) {
                      // Parse reply preview
                      final preview = message.replyPreview ?? '';
                      final colonIndex = preview.indexOf(':');
                      final senderName = colonIndex > 0 ? preview.substring(0, colonIndex) : 'Reply';
                      var contentText = colonIndex > 0 ? preview.substring(colonIndex + 1).trim() : preview;
                      
                      // Improve display for file messages
                      if (contentText.contains('<audio') || contentText.contains('audio/')) {
                        contentText = '🎤 Voice message';
                      } else if (contentText.contains('<img') || contentText.contains('image/')) {
                        contentText = '📷 Photo';
                      } else if (contentText.contains('<video') || contentText.contains('video/')) {
                        contentText = '🎬 Video';
                      } else if (contentText.contains('file/') || contentText.endsWith('.pdf') || contentText.endsWith('.doc')) {
                        contentText = '📎 File';
                      }
                      
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            senderName,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            contentText,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
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
            // Message status indicator and timestamp for sent messages
            if (isSentByMe)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // Timestamp (always shown for sent messages)
                    Text(
                      message.formattedTime,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(width: 4),
                    // Status indicator
                    _buildStatusIndicator(message.status),
                  ],
                ),
              ),
            // Full timestamp - only visible when _showTimestamps is true
            if (_showTimestamps)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Text(
                  message.formattedTimestampFull,
                  style: const TextStyle(
                    color: Color(0xFFFF69B4), // Hot pink
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
          ],
        ),
    );

    // Build the reaction button
    final reactionButton = Builder(
      builder: (BuildContext buttonContext) {
        return GestureDetector(
          onTap: () {
            final RenderBox renderBox = buttonContext.findRenderObject() as RenderBox;
            final position = renderBox.localToGlobal(Offset.zero);
            final size = renderBox.size;
            _showReactionPicker(
              context,
              message.id,
              Offset(
                position.dx + size.width / 2,
                position.dy,
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Icon(
              Icons.sentiment_satisfied_alt_outlined,
              color: Colors.white.withOpacity(0.6),
              size: 22,
            ),
          ),
        );
      },
    );

    // Check if this message has reactions to add extra bottom spacing
    final hasReactions = _messageReactions[message.id] != null && 
                         _messageReactions[message.id]!.isNotEmpty;
    
    // Wrap bubble with Column for reactions below (Column keeps pills in hit-test bounds)
    return Align(
      alignment: isSentByMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isSentByMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row with bubble and reaction button
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // The bubble
              bubbleWidget,
              // For incoming (not sent by me): show reaction button on right
              if (!isSentByMe) reactionButton,
            ],
          ),
          
          // Reaction pills below bubble (now in Column, so taps work!)
          if (hasReactions)
            Padding(
              padding: EdgeInsets.only(
                left: isSentByMe ? 0 : 8,
                right: isSentByMe ? 8 : 0,
                top: 4,
                bottom: 8,
              ),
              child: _buildReactionPills(message.id),
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

  /// Build message status indicator widget
  Widget _buildStatusIndicator(String status) {
    switch (status) {
      case 'sent':
        return const Icon(
          Icons.check,
          size: 16,
          color: Colors.white70,
        );
      case 'delivered':
        return const Icon(
          Icons.done_all,
          size: 16,
          color: Colors.white70,
        );
      case 'seen':
        return const Icon(
          Icons.done_all,
          size: 16,
          color: Color(0xFF00BCD4), // Cyan color like WhatsApp
        );
      default:
        return const Icon(
          Icons.schedule,
          size: 16,
          color: Colors.white54,
        );
    }
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
  
  /// Parse a timestamp string, treating it as UTC if no timezone info is present
  /// (matches the web app's parseTs() behavior)
  DateTime _parseUtcTimestamp(String timestamp) {
    final hasTimezone = RegExp(r'[zZ]|[+-]\d{2}:?\d{2}$').hasMatch(timestamp);
    final parsed = DateTime.parse(hasTimezone ? timestamp : '${timestamp}Z');
    return parsed.toLocal();
  }

  /// Format last seen timestamp as relative time
  String _formatLastSeen(String timestamp) {
    try {
      final DateTime lastSeen = _parseUtcTimestamp(timestamp);
      final DateTime now = DateTime.now();
      final Duration difference = now.difference(lastSeen);
      
      if (difference.inMinutes < 1) {
        return 'just now';
      } else if (difference.inMinutes < 60) {
        final mins = difference.inMinutes;
        return '$mins ${mins == 1 ? "minute" : "minutes"} ago';
      } else if (difference.inHours < 24) {
        final hours = difference.inHours;
        return '$hours ${hours == 1 ? "hour" : "hours"} ago';
      } else if (difference.inDays == 1) {
        return 'yesterday';
      } else if (difference.inDays < 7) {
        return '${difference.inDays} days ago';
      } else {
        return '${lastSeen.month}/${lastSeen.day}/${lastSeen.year}';
      }
    } catch (e) {
      debugPrint('Error parsing last seen: $e');
      return 'a while ago';
    }
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
      final path = '${directory.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      
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
        codec: Codec.aacMP4,
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
        // Stop any current playback first to ensure clean state
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
            content: Text('Error playing audio: ${e.toString().split(':').last.trim()}'),
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
