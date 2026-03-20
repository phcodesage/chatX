import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:io';
import 'dart:ui';
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
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/lobby_user.dart';
import '../models/message.dart';
import '../services/lobby_service.dart';
import '../services/message_service.dart';
import '../services/socket_service.dart';
import '../services/storage_service.dart';
import '../services/chat_cache_service.dart';
import '../services/translation_service.dart';
import '../widgets/color_picker_modal.dart';
import '../services/active_chat_service.dart';
import '../widgets/call_setup_modal.dart';
import '../widgets/outgoing_call_modal.dart';
import '../widgets/incoming_call_setup_modal.dart';
import '../widgets/reaction_picker.dart';
import '../services/call_service.dart';
import '../services/presence_service.dart';
import '../config/api_config.dart';
import 'connected_call_screen.dart';

/// Chat screen for messaging with a specific user
class ChatScreen extends StatefulWidget {
  final LobbyUser otherUser;

  const ChatScreen({super.key, required this.otherUser});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    with SingleTickerProviderStateMixin {
  final SocketService _socketService = SocketService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final FocusNode _inputFocusNode = FocusNode();

  List<Message> _messages = [];
  List<Map<String, dynamic>> _pinnedExcalidrawLinks = [];
  bool _isLoading = true;
  bool _isLoadingMessages = false; // Guard against concurrent message loads
  bool _isTyping = false;
  bool _isKeyboardVisible = false;
  bool _otherUserTyping = false;
  String _typingPreview = '';
  int? _currentUserId;
  Timer? _typingTimer;
  Timer?
  _typingHideTimer; // auto-clears the partner's typing indicator if stop event is missed
  Timer? _typingUpdateThrottle;
  Timer? _lastSeenRefreshTimer;
  DateTime? _lastTypingUpdate;
  Color _headerColor = const Color(0xFF4C1D95); // Default purple color
  bool _showResetButton = false;

  // Timestamp visibility toggle (hidden by default like web)
  bool _showTimestamps = false;

  // Auto-translate toggle
  bool _autoTranslate = false;

  // Scroll to bottom button state
  bool _isAtBottom = true;
  int _unreadCount = 0;

  // Reply state
  Message? _replyingToMessage;

  // Reaction state: { messageId: { emoji: Set<userId> } }
  final Map<int, Map<String, Set<String>>> _messageReactions = {};

  static final RegExp _messageUrlRegex = RegExp(
    r'((?:https?:\/\/|www\.)[^\s]+)',
    caseSensitive: false,
  );
  static final RegExp _excalidrawUrlRegex = RegExp(
    r'((?:https?:\/\/)?(?:www\.)?excalidraw\.com[^\s]*)',
    caseSensitive: false,
  );

  // Translation state: { messageId: translatedText }
  final Map<int, String> _messageTranslations = {};

  // Emoji picker state for chat input
  bool _showEmojiPicker = false;

  bool _isActionsPanelOpen = false;

  // Backend restart notification banner
  bool _showBackendRestartBanner = false;
  Timer? _backendRestartBannerTimer;

  // Flag to suppress doorbell echo on the triggering device
  bool _localDoorbellPending = false;

  // Keep doorbell AudioPlayer references alive until playback completes (prevents GC mid-play)
  final List<AudioPlayer> _activeDoorbellPlayers = [];

  // Flag to suppress color reset echo on the triggering device
  bool _localColorResetPending = false;

  // Whether the currently logged-in user is an admin
  bool _currentUserIsAdmin = false;

  // Track optimistic messages awaiting server confirmation (dedup keys)
  final Set<String> _pendingMessageKeys = {};

  // One-tap composer mode: next message is auto-marked as a task.
  bool _markNextMessageAsTask = false;

  // Dedup-keyed task intents so repeated identical messages are handled safely.
  final Map<String, int> _pendingTaskIntentsByDedupKey = {};

  // Task events can arrive before the corresponding message payload.
  final Map<int, String?> _pendingLiveTaskCreatedAtByMessageId = {};
  final Map<int, String?> _pendingLiveTaskCompletedAtByMessageId = {};
  int? _selectedTaskActionMessageId;

  // Message IDs loaded from local cache/server history.
  // For these historical records, UI should always display status as "sent".
  final Set<int> _databaseLoadedMessageIds = {};

  // Animated task count badge
  late AnimationController _taskBadgeAnimController;
  late Animation<double> _taskBadgeScale;

  // Rebuild open task modal on live task updates.
  final ValueNotifier<int> _taskModalVersion = ValueNotifier<int>(0);

  // _isHandlingIncomingCall is now global via PresenceService().isHandlingIncomingCall

  // Presence state for the chat partner
  String _partnerStatus = 'offline';
  String? _partnerLastSeen;

  void _notifyTaskModalChanged() {
    _taskModalVersion.value = _taskModalVersion.value + 1;
  }

  @override
  void initState() {
    super.initState();
    _taskBadgeAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _taskBadgeScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.0,
          end: 1.5,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.5,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.elasticOut)),
        weight: 60,
      ),
    ]).animate(_taskBadgeAnimController);
    _inputFocusNode.addListener(_onFocusChange);
    _scrollController.addListener(_onScroll);

    // Set this user as active to prevent FCM notifications
    ActiveChatService().setActiveUser(widget.otherUser.id);

    _initialize();
    // Periodically refresh "last seen" relative label in header (like the web app does)
    _lastSeenRefreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted && _getEffectivePartnerStatus() != 'online') setState(() {});
    });
  }

  Widget _buildChatShimmer() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 6,
      itemBuilder: (_, index) {
        final isMe = index % 2 == 0;
        return Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Shimmer.fromColors(
              baseColor: const Color(0xFF3A3A4F),
              highlightColor: const Color(0xFF4A4A60),
              child: Container(
                width: 180,
                height: 20,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Listen to scroll position to show/hide scroll-to-bottom button
  Future<void> _onScroll() async {
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
      final currentUserId = await StorageService.getUserId();
      if (currentUserId != null) {
        await ChatCacheService.saveConversationMessages(
          currentUserId,
          widget.otherUser.id,
          _messages.reversed.toList(),
        );
      }
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
      // Mark messages as read/viewed so both web + lobby state clear their badges
      _socketService.markMessagesRead(widget.otherUser.id);
      _socketService.markMessagesViewed(widget.otherUser.id);
      debugPrint(
        'ðŸ“§ Sent read confirmations for ${unreadMessageIds.length} messages to update web clients',
      );
    }
  }

  /// Sync delivery and read statuses for messages loaded from history.
  Future<void> _syncLoadedMessageStatuses(List<Message> loadedMessages) async {
    if (loadedMessages.isEmpty) return;

    final incomingMessages = loadedMessages.where((message) {
      return message.senderId == widget.otherUser.id && !message.isDeleted;
    }).toList();

    if (incomingMessages.isEmpty) return;

    final incomingMessageIds = incomingMessages
        .map((message) => message.id)
        .toSet()
        .toList();

    for (final messageId in incomingMessageIds) {
      _socketService.emit('message_delivered', {'message_id': messageId});
    }

    _socketService.markMessagesRead(widget.otherUser.id);
    _socketService.markMessagesViewed(widget.otherUser.id);

    final latestIncomingMessageId = incomingMessageIds.reduce(math.max);
    await MessageService.markAsRead(
      senderId: widget.otherUser.id,
      lastMessageId: latestIncomingMessageId,
    );

    debugPrint(
      'ðŸ“§ Synced statuses for ${incomingMessageIds.length} loaded messages (including files)',
    );
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

  Future<void> _initialize() async {
    _currentUserId = await StorageService.getUserId();
    _currentUserIsAdmin = await StorageService.getIsAdmin();

    // Initialize presence state from widget
    _partnerStatus = widget.otherUser.status;
    _partnerLastSeen = widget.otherUser.lastSeen;

    // Load saved chat color for this conversation partner
    await _loadSavedChatColor();

    await _loadTimestampPreference();
    await _loadCachedMessages();
    await _loadMessages();
    _loadPinnedExcalidrawLinks();
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
          _showResetButton = color.toARGB32() != defaultColor.toARGB32();
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
    final autoTranslateSaved =
        prefs.getBool('autoTranslate_${widget.otherUser.id}') ?? false;
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
          content: Text(
            newValue ? 'Auto-translate enabled' : 'Auto-translate disabled',
          ),
          duration: const Duration(seconds: 1),
          backgroundColor: newValue
              ? const Color(0xFF059669)
              : Colors.grey[700],
        ),
      );
    }

    // If enabling, translate existing messages
    if (newValue) {
      await _translateExistingMessages();
    }
  }

  /// Translate all existing messages for this conversation
  Future<void> _translateExistingMessages() async {
    if (!mounted) return;

    final targetLang = await TranslationService.getUserLanguage();
    debugPrint('Translating messages to: $targetLang');

    // Get current messages from cache
    final currentUserId = await StorageService.getUserId();
    if (currentUserId == null) return;

    final messages = await ChatCacheService.loadConversationMessages(
      currentUserId,
      widget.otherUser.id,
    );

    if (messages.isEmpty) return;

    // Translate each message
    final translatedMessages = <Message>[];
    for (final message in messages) {
      if (message.content.isNotEmpty && !message.isDeleted) {
        final translated = await TranslationService.translateMessageObject(
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
    await ChatCacheService.saveConversationMessages(
      currentUserId,
      widget.otherUser.id,
      translatedMessages.reversed.toList(),
    );

    // Refresh the UI
    if (mounted) {
      setState(() {
        _messages = translatedMessages;
        _databaseLoadedMessageIds
          ..clear()
          ..addAll(
            translatedMessages
                .where((message) => message.id > 0)
                .map((message) => message.id),
          );
      });
    }
  }

  void _joinChatRoom() {
    // Test connection status first
    _socketService.testConnection();

    // Try to join chat room
    _socketService.joinChat(widget.otherUser.id);
  }

  void _setupRealtimeListeners() {
    const key = 'chat';

    // Listen for new messages (from other user)
    _socketService.addListener('messageReceived', key, (
      Map<String, dynamic> data,
    ) async {
      final incomingMessage = _applyPendingLiveTaskState(
        Message.fromJson(data),
      );

      // Only add if it's from the current conversation
      if (incomingMessage.senderId == widget.otherUser.id ||
          incomingMessage.recipientId == widget.otherUser.id) {
        // Skip if this is our own message (we already have it optimistically)
        if (incomingMessage.senderId == _currentUserId) return;

        // Always clear typing indicator when a real message arrives
        _typingHideTimer?.cancel();

        setState(() {
          _messages.insert(0, incomingMessage);
          // Clear typing preview whenever a message from partner arrives
          _otherUserTyping = false;
          _typingPreview = '';

          // Increment unread count if not at bottom (for incoming messages)
          if (!_isAtBottom && incomingMessage.senderId == widget.otherUser.id) {
            _unreadCount++;
          }
        });

        // Auto-translate incoming message if enabled and it's a text message from the other user
        if (_autoTranslate &&
            incomingMessage.senderId == widget.otherUser.id &&
            incomingMessage.messageType == 'text' &&
            incomingMessage.content.isNotEmpty) {
          _autoTranslateMessage(incomingMessage);
        }

        // Save to cache for offline access
        if (_currentUserId != null) {
          await ChatCacheService.addMessageToCache(
            _currentUserId!,
            widget.otherUser.id,
            incomingMessage,
          );
          debugPrint('ðŸ’¾ Cached incoming message ${incomingMessage.id}');
        }

        // Play message sound for incoming messages
        if (incomingMessage.senderId == widget.otherUser.id) {
          try {
            _audioPlayer.play(AssetSource('sounds/splat2.m4a'));
          } catch (e) {
            debugPrint('Error playing message sound: $e');
          }
        }

        // Mark as read whenever chat is open and message is from partner.
        // Only auto-scroll if user is already at bottom to avoid interrupting reading
        if (incomingMessage.senderId == widget.otherUser.id) {
          _socketService.markMessagesRead(widget.otherUser.id);
          _socketService.markMessagesViewed(widget.otherUser.id);
          debugPrint(
            'ðŸ“§ Marked message ${incomingMessage.id} as seen (chat is open)',
          );

          // Only auto-scroll if user is at bottom, otherwise just show unread badge
          if (_isAtBottom) {
            _scrollToBottom();
          }
        }
      }
    });

    // Listen for message_sent (echoes our own messages from other devices)
    _socketService.addListener('messageSent', key, (Map<String, dynamic> data) {
      final recipientId = _toInt(data['recipient_id']);
      // Only process if this is for the current conversation
      if (recipientId == widget.otherUser.id) {
        final message = _applyPendingLiveTaskState(Message.fromJson(data));
        final dedupKey =
            '${message.senderId}:${message.recipientId}:${message.content}';
        final shouldMarkAsTask = _consumePendingTaskIntent(dedupKey);
        final uiMessage = shouldMarkAsTask
            ? _copyMessageWithTaskState(
                message,
                isTask: true,
                taskCreatedAt:
                    message.taskCreatedAt ?? DateTime.now().toIso8601String(),
                taskCompletedAt: null,
              )
            : message;

        if (_pendingMessageKeys.contains(dedupKey)) {
          // This is the server echo of our optimistic message â€” replace it with real data
          _pendingMessageKeys.remove(dedupKey);
          setState(() {
            final index = _messages.indexWhere(
              (m) =>
                  m.senderId == message.senderId &&
                  m.content == message.content &&
                  m.status == 'sending',
            );
            if (index != -1) {
              _messages[index] = uiMessage;
            }
          });
          debugPrint(
            'ðŸ“¤ Replaced optimistic message with server data (id: ${message.id})',
          );
          if (shouldMarkAsTask) {
            _socketService.addTask(message.id);
          }
        } else {
          // Check if message already exists (by ID)
          final alreadyExists = _messages.any((m) => m.id == message.id);
          if (!alreadyExists) {
            setState(() {
              _messages.insert(0, uiMessage);
            });
            // Only auto-scroll if user is at bottom, otherwise just show unread badge
            if (_isAtBottom) {
              _scrollToBottom();
            }
            debugPrint('ðŸ“¤ Cross-device: added own sent message to chat');
          }
          if (shouldMarkAsTask) {
            _socketService.addTask(message.id);
          }
        }
      }
    });

    // Listen for typing indicator (includes live typing preview)
    _socketService.addListener('userTyping', key, (Map<String, dynamic> data) {
      if (data['user_id'] == widget.otherUser.id) {
        setState(() {
          final isTyping = data['is_typing'] ?? false;
          final message = data['message'] as String? ?? '';

          if (isTyping) {
            _otherUserTyping = true;
            if (message.isNotEmpty) {
              _typingPreview = message;
            }
            // Auto-hide after 6 s in case typing_stop is never received
            _typingHideTimer?.cancel();
            _typingHideTimer = Timer(const Duration(seconds: 6), () {
              if (mounted) {
                setState(() {
                  _otherUserTyping = false;
                  _typingPreview = '';
                });
              }
            });
          } else {
            _typingHideTimer?.cancel();
            _otherUserTyping = false;
            _typingPreview = '';
          }
        });
      }
    });

    // Listen for live typing preview (separate event if used)
    _socketService.addListener('typingUpdate', key, (
      Map<String, dynamic> data,
    ) {
      if (data['user_id'] == widget.otherUser.id ||
          data['sender_id'] == widget.otherUser.id) {
        final preview = data['message'] ?? '';
        setState(() {
          _otherUserTyping = preview.isNotEmpty;
          _typingPreview = preview;
        });
        // Reset the auto-hide timer on every preview update
        _typingHideTimer?.cancel();
        if (preview.isNotEmpty) {
          _typingHideTimer = Timer(const Duration(seconds: 6), () {
            if (mounted) {
              setState(() {
                _otherUserTyping = false;
                _typingPreview = '';
              });
            }
          });
        }
      }
    });

    // Listen for joined chat confirmation
    _socketService.addListener('joinedChat', key, (Map<String, dynamic> data) {
      debugPrint('Successfully joined chat with ${widget.otherUser.fullName}');
    });

    // Listen for doorbell rings (from other user OR from self on another device)
    _socketService.addListener('doorbellRing', key, (
      Map<String, dynamic> data,
    ) {
      final senderId = data['sender_id'] as int?;
      final recipientId = data['recipient_id'] as int?;
      if (senderId == widget.otherUser.id) {
        _handleIncomingDoorbell(data);
      } else if (senderId == _currentUserId &&
          recipientId == widget.otherUser.id) {
        if (_localDoorbellPending) {
          // This is the echo from OUR ring â€” ignore, we already showed it optimistically
          _localDoorbellPending = false;
        } else {
          // Cross-device: our other device rang the doorbell â€” show outgoing system message
          _handleOutgoingDoorbellSync(data);
        }
      }
    });

    // Listen for color change events (from other user OR from self on another device)
    _socketService.addListener('colorChanged', key, (
      Map<String, dynamic> data,
    ) {
      final senderId = data['sender_id'] as int?;
      final recipientId = data['recipient_id'] as int?;
      if (senderId == widget.otherUser.id) {
        _handleColorChange(data);
      } else if (senderId == _currentUserId &&
          recipientId == widget.otherUser.id) {
        _handleColorChange(data);
      }
    });

    // Listen for color reset events (from other user OR from self on another device)
    _socketService.addListener('colorReset', key, (Map<String, dynamic> data) {
      final senderId = data['sender_id'] as int?;
      final recipientId = data['recipient_id'] as int?;
      if (senderId == widget.otherUser.id) {
        _handleColorReset(data);
      } else if (senderId == _currentUserId &&
          recipientId == widget.otherUser.id) {
        if (_localColorResetPending) {
          // This is the echo from OUR reset â€” ignore, we already showed it optimistically
          _localColorResetPending = false;
        } else {
          // Cross-device: our other device reset the color
          _handleColorReset(data);
        }
      }
    });

    // Listen for all messages deleted event
    _socketService.addListener('allMessagesDeleted', key, (
      Map<String, dynamic> data,
    ) {
      _handleAllMessagesDeleted(data);
    });

    // Listen for single message deleted event
    _socketService.addListener('messageDeleted', key, (
      Map<String, dynamic> data,
    ) {
      _handleMessageDeleted(data);
    });

    // Listen for message edited event
    _socketService.addListener('messageEdited', key, (
      Map<String, dynamic> data,
    ) {
      _handleMessageEdited(data);
    });

    // Listen for task added event
    _socketService.addListener('taskAdded', key, (Map<String, dynamic> data) {
      _handleTaskAdded(data);
    });

    // Listen for task completed event
    _socketService.addListener('taskCompleted', key, (
      Map<String, dynamic> data,
    ) {
      _handleTaskCompleted(data);
    });

    // Listen for task uncompleted event
    _socketService.addListener('taskUncompleted', key, (
      Map<String, dynamic> data,
    ) {
      _handleTaskUncompleted(data);
    });

    // Listen for excalidraw pinned event
    _socketService.addListener('excalidrawPinned', key, (
      Map<String, dynamic> data,
    ) {
      _handleExcalidrawPinned(data);
    });

    // Listen for excalidraw unpinned event
    _socketService.addListener('excalidrawUnpinned', key, (
      Map<String, dynamic> data,
    ) {
      _handleExcalidrawUnpinned(data);
    });

    // Listen for message status updates (delivered/seen)
    _socketService.addListener('messageStatusUpdated', key, (
      Map<String, dynamic> data,
    ) {
      _handleMessageStatusUpdate(data);
    });

    // Listen for messages read notifications
    _socketService.addListener('messagesRead', key, (
      Map<String, dynamic> data,
    ) {
      _handleMessagesRead(data);
    });

    // Listen for individual message delivery confirmations
    _socketService.addListener('messageDelivered', key, (
      Map<String, dynamic> data,
    ) {
      final messageId = _toInt(data['message_id']);
      if (messageId != null) {
        _handleMessageStatusUpdate({
          'message_id': messageId,
          'status': 'delivered',
          'delivered_at':
              data['delivered_at'] ?? DateTime.now().toIso8601String(),
        });
      }
    });

    // Listen for individual message read confirmations
    _socketService.addListener('messageRead', key, (Map<String, dynamic> data) {
      final messageId = _toInt(data['message_id']);
      if (messageId != null) {
        _handleMessageStatusUpdate({
          'message_id': messageId,
          'status': 'seen',
          'read_at': data['read_at'] ?? DateTime.now().toIso8601String(),
        });
      }
    });

    // Listen for file messages from web
    _socketService.addListener('fileReceived', key, (
      Map<String, dynamic> data,
    ) {
      debugPrint('ðŸ“Ž File message received in chat: $data');
      final senderId = data['sender_id'] as int?;
      final recipientId = data['recipient_id'] as int?;

      // Process if from conversation partner OR from current user (cross-device sync)
      final isFromPartner = senderId == widget.otherUser.id;
      final isFromSelfToPartner =
          senderId == _currentUserId && recipientId == widget.otherUser.id;

      if (isFromPartner || isFromSelfToPartner) {
        final now = DateTime.now();
        final timestampMs = data['timestamp_ms'] ?? now.millisecondsSinceEpoch;

        // Check for duplicates (cross-device sync may send same message twice)
        final messageId = data['message_id'];
        if (messageId != null && _messages.any((m) => m.id == messageId)) {
          debugPrint('ðŸ“Ž Skipping duplicate file message: $messageId');
          return;
        }

        // Detect audio files as voice messages
        final fileType = (data['file_type'] as String?) ?? '';
        final msgType = (data['message_type'] as String?) ?? '';
        String messageType;
        if (fileType.startsWith('audio/') ||
            msgType == 'voice' ||
            msgType == 'audio') {
          messageType = 'voice';
        } else if (fileType.startsWith('image/')) {
          messageType = 'image';
        } else if (fileType.startsWith('video/')) {
          messageType = 'video';
        } else {
          messageType = 'file';
        }
        // Build full URL if it's a relative path
        final rawFileUrl = data['file_url'] as String? ?? '';
        final fullFileUrl = rawFileUrl.startsWith('http')
            ? rawFileUrl
            : '${ApiConfig.baseUrl}$rawFileUrl';

        // Create a message from the file data
        final message = Message(
          id: messageId ?? timestampMs,
          senderId: senderId ?? 0,
          recipientId: recipientId ?? _currentUserId ?? 0,
          content: data['file_name'] ?? 'File',
          messageType: messageType,
          timestamp: now.toIso8601String(),
          timestampMs: timestampMs,
          isRead: false,
          status: 'delivered',
          threadId: '',
          reactions: {},
          isDeleted: false,
          fileUrl: fullFileUrl,
          fileName: data['file_name'],
          fileType: data['file_type'],
          fileSize: data['file_size'],
        );

        setState(() {
          _messages.insert(0, message);
        });

        // Play message sound only for incoming messages from partner
        if (isFromPartner) {
          try {
            _audioPlayer.play(AssetSource('sounds/splat2.m4a'));
          } catch (e) {
            debugPrint('Error playing message sound: $e');
          }

          _socketService.markMessagesRead(widget.otherUser.id);
          _socketService.markMessagesViewed(widget.otherUser.id);
          debugPrint(
            'ðŸ“§ Marked file message ${message.id} as delivered/seen (chat is open)',
          );
        } else {
          debugPrint('ðŸ“Ž Cross-device: added own sent file to chat');
        }

        // Only auto-scroll if user is at bottom, otherwise just show unread badge
        if (_isAtBottom) {
          _scrollToBottom();
        }
      }
    });

    // Listen for voice messages from web
    _socketService.addListener('voiceMessageReceived', key, (
      Map<String, dynamic> data,
    ) {
      debugPrint('ðŸŽ¤ Voice message received in chat: $data');
      final senderId = data['sender_id'] as int?;
      final recipientId = data['recipient_id'] as int?;

      // Process if from conversation partner OR from current user (cross-device sync)
      final isFromPartner = senderId == widget.otherUser.id;
      final isFromSelfToPartner =
          senderId == _currentUserId && recipientId == widget.otherUser.id;
      debugPrint(
        'ðŸŽ¤ Voice filter: senderId=$senderId, recipientId=$recipientId, _currentUserId=$_currentUserId, otherUserId=${widget.otherUser.id}, isFromPartner=$isFromPartner, isFromSelfToPartner=$isFromSelfToPartner',
      );

      if (isFromPartner || isFromSelfToPartner) {
        final now = DateTime.now();
        final timestampMs = data['timestamp_ms'] ?? now.millisecondsSinceEpoch;
        final audioUrl = data['audio_url'] as String?;
        if (audioUrl == null || audioUrl.isEmpty) {
          debugPrint('ðŸŽ¤ Voice message has no audio_url, ignoring');
          return;
        }

        // Check for duplicates (cross-device sync may send same message twice)
        final messageId = data['message_id'];
        if (messageId != null && _messages.any((m) => m.id == messageId)) {
          debugPrint('ðŸŽ¤ Skipping duplicate voice message: $messageId');
          return;
        }

        // Build full URL if it's a relative path
        final fullAudioUrl = audioUrl.startsWith('http')
            ? audioUrl
            : '${ApiConfig.baseUrl}$audioUrl';
        final message = Message(
          id: messageId ?? timestampMs,
          senderId: senderId ?? 0,
          recipientId: recipientId ?? _currentUserId ?? 0,
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

        // Play message sound only for incoming messages from partner
        if (isFromPartner) {
          try {
            _audioPlayer.play(AssetSource('sounds/splat2.m4a'));
          } catch (e) {
            debugPrint('Error playing message sound: $e');
          }

          _socketService.markMessagesRead(widget.otherUser.id);
          _socketService.markMessagesViewed(widget.otherUser.id);
          debugPrint(
            'ðŸ“§ Marked voice message ${message.id} as delivered/seen (chat is open)',
          );
        } else {
          debugPrint('ðŸŽ¤ Cross-device: added own sent voice message to chat');
        }

        // Only auto-scroll if user is at bottom, otherwise just show unread badge
        if (_isAtBottom) {
          _scrollToBottom();
        }
      }
    });

    // Listen for incoming calls (while in chat)
    // NOTE: We only listen to 'incomingCall' here (not 'crossRoomCallOffer') because the
    // server sends BOTH events to the callee for the same call. 'incomingCall' contains
    // full call data (call_id, call_room_id) and is sufficient for mobile clients.
    // Listening to both would open two modals for the same call.
    _socketService.addListener('incomingCall', key, (
      Map<String, dynamic> data,
    ) {
      _handleIncomingCallInChat(data);
    });

    // FALLBACK: Also listen for crossRoomCallOffer in case backend only sends this event
    // This handles cases where web clients call mobile and backend doesn't send 'incomingCall'
    _socketService.addListener('crossRoomCallOffer', key, (
      Map<String, dynamic> data,
    ) {
      debugPrint(
        'ðŸ“² Fallback: Received crossRoomCallOffer in chat, converting to incomingCall format',
      );
      debugPrint('ðŸ“² Original crossRoomCallOffer data: $data');

      // Convert crossRoomCallOffer format to incomingCall format
      // Note: crossRoomCallOffer uses 'caller_id' and 'caller_username', not 'callerId' and 'callerName'
      final convertedData = {
        'id': DateTime.now().millisecondsSinceEpoch, // Generate call ID
        'call_room_id': data['room'] as String?,
        'call_type': data['call_type'] as String? ?? 'video',
        'caller': {
          'id': data['caller_id'] as int?,
          'username': data['caller_username'] as String? ?? 'Unknown',
          'full_name': data['caller_username'] as String? ?? 'Unknown',
        },
      };

      debugPrint('ðŸ“² Converted to incomingCall format: $convertedData');
      _handleIncomingCallInChat(convertedData);
    });

    // Listen for reaction updates (multi-reaction: user can have multiple different emojis)
    _socketService.addListener('reactionUpdated', key, (
      Map<String, dynamic> data,
    ) {
      debugPrint('ðŸ‘ Reaction updated received: $data');
      final messageId = data['message_id'] as int?;
      final reactorId = data['user_id']?.toString() ?? '';
      final reaction = data['reaction'] as String?;

      if (messageId != null &&
          reaction != null &&
          reaction.isNotEmpty &&
          reactorId.isNotEmpty) {
        setState(() {
          _messageReactions.putIfAbsent(messageId, () => {});
          // Simply add user to the target reaction (don't remove from others)
          _messageReactions[messageId]!.putIfAbsent(reaction, () => {});
          _messageReactions[messageId]![reaction]!.add(reactorId);
        });
      }
    });

    _socketService.addListener('reactionCleared', key, (
      Map<String, dynamic> data,
    ) {
      debugPrint('âŒ Reaction cleared received: $data');
      final messageId = data['message_id'] as int?;
      final reactorId = data['user_id']?.toString() ?? '';
      final reaction = data['reaction'] as String?;

      if (messageId != null && reactorId.isNotEmpty) {
        setState(() {
          if (_messageReactions.containsKey(messageId)) {
            if (reaction != null && reaction.isNotEmpty) {
              // Remove user from only the specific reaction emoji
              _messageReactions[messageId]![reaction]?.remove(reactorId);
              if (_messageReactions[messageId]![reaction]?.isEmpty ?? false) {
                _messageReactions[messageId]!.remove(reaction);
              }
            } else {
              // Legacy: no specific reaction provided, remove from all
              _messageReactions[messageId]!.forEach((emoji, users) {
                users.remove(reactorId);
              });
              _messageReactions[messageId]!.removeWhere(
                (key, value) => value.isEmpty,
              );
            }

            if (_messageReactions[messageId]!.isEmpty) {
              _messageReactions.remove(messageId);
            }
          }
        });
      }
    });

    // Listen for presence updates (status changes)
    _socketService.addListener('presenceUpdate', key, (
      Map<String, dynamic> data,
    ) {
      debugPrint('ðŸ‘¤ Presence update in chat: $data');
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
    });

    // â”€â”€ Call summary system messages â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    // Show an in-chat pill when a call ends, is missed, or is declined.
    // Only insert if the event involves the person we are currently chatting with.
    _socketService.addListener('call_ended', key, (Map<String, dynamic> data) {
      final callerId = data['caller_id'] as int?;
      final calleeId = data['callee_id'] as int?;
      if (callerId == null || calleeId == null) return;
      if (callerId != widget.otherUser.id && calleeId != widget.otherUser.id) {
        return;
      }
      // Format duration if available (duration is stored in seconds by the server)
      final rawDuration = data['duration'];
      String durationStr = '';
      if (rawDuration != null) {
        final secs = (rawDuration is num
            ? rawDuration.toInt()
            : int.tryParse(rawDuration.toString()) ?? 0);
        final m = (secs ~/ 60).toString().padLeft(2, '0');
        final s = (secs % 60).toString().padLeft(2, '0');
        durationStr = ' Â· $m:$s';
      }
      final callType = data['call_type'] as String? ?? 'call';
      final icon = callType == 'video' ? 'ðŸ“¹' : 'ðŸ“ž';
      _insertCallSummaryMessage('$icon Call ended$durationStr');
    });

    _socketService.addListener('call_declined', key, (
      Map<String, dynamic> data,
    ) {
      final callerId = data['caller_id'] as int?;
      final calleeId = data['callee_id'] as int?;
      if (callerId == null || calleeId == null) return;
      if (callerId != widget.otherUser.id && calleeId != widget.otherUser.id) {
        return;
      }
      _insertCallSummaryMessage('ðŸ“ž Call declined');
    });

    _socketService.addListener('call_missed', key, (Map<String, dynamic> data) {
      final callerId = data['caller_id'] as int?;
      final calleeId = data['callee_id'] as int?;
      if (callerId == null || calleeId == null) return;
      if (callerId != widget.otherUser.id && calleeId != widget.otherUser.id) {
        return;
      }
      _insertCallSummaryMessage('ðŸ“ž Missed call');
    });

  }

  /// Insert an ephemeral system message pill for call events (not persisted)
  void _insertCallSummaryMessage(String text) {
    if (!mounted) return;
    final now = DateTime.now().toUtc();
    final synthetic = Message(
      id: -(now
          .millisecondsSinceEpoch), // negative id = synthetic, never collides with DB
      senderId: 0,
      recipientId: 0,
      content: text,
      messageType: 'system',
      timestamp: now.toIso8601String(),
      timestampMs: now.millisecondsSinceEpoch,
      isRead: true,
      status: 'read',
      threadId: '',
      reactions: {},
      isDeleted: false,
    );
    setState(() => _messages.insert(0, synthetic));
  }

  /// Handle cross-room call offer from web client while in chat
  // ignore: unused_element
  Future<void> _handleCrossRoomCallOfferInChat(
    Map<String, dynamic> data,
  ) async {
    if (!mounted) return;

    if (PresenceService().isHandlingIncomingCall) {
      debugPrint(
        'âš ï¸ Already handling an incoming call, ignoring cross-room duplicate',
      );
      return;
    }
    PresenceService().isHandlingIncomingCall = true;

    debugPrint('ðŸ“² Cross-room call offer received in chat: $data');

    final callerId = data['caller_id'] as int?;
    final callerUsername =
        data['caller_username'] as String? ?? widget.otherUser.fullName;
    final callType = data['call_type'] as String? ?? 'video';
    final room = data['room'] as String?;

    if (callerId == null || room == null) {
      debugPrint('âš ï¸ Invalid cross-room call offer data');
      PresenceService().isHandlingIncomingCall = false;
      return;
    }

    // Initialize call service FIRST
    final callService = CallService();
    await callService.initialize();

    if (!mounted) {
      PresenceService().isHandlingIncomingCall = false;
      return;
    }

    // Set up signal handler IMMEDIATELY - before handleIncomingCall
    // This ensures we capture any signals that arrive while setting up
    _socketService.onSignal = (signalData) {
      debugPrint('ðŸ“¡ Signal received for cross-room call: $signalData');
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

    // Use keyed listeners for call ended/declined handlers
    const crossRoomListenerKey = 'chat_cross_room_call';
    _socketService.addListener('callEnded', crossRoomListenerKey, (
      Map<String, dynamic> endData,
    ) {
      debugPrint('ðŸ“´ Call ended by remote user (chat cross-room)');
      _socketService.stopSignalBuffering();
      callService.handleCallEnded();
    });

    _socketService.addListener('callDeclined', crossRoomListenerKey, (
      Map<String, dynamic> declineData,
    ) {
      debugPrint('âŒ Call declined (chat cross-room)');
      _socketService.stopSignalBuffering();
      callService.handleCallDeclined();
    });

    // Show incoming call setup modal with device selection
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (context) => IncomingCallSetupModal(
              callerName: callerUsername,
              callerId: callerId,
              callType: callType,
              callService: callService,
              onDecline: () {
                debugPrint('ðŸ“ž Call declined by user');
                _socketService.stopSignalBuffering();
                _socketService.removeListener(
                  'callEnded',
                  crossRoomListenerKey,
                );
                _socketService.removeListener(
                  'callDeclined',
                  crossRoomListenerKey,
                );
              },
            ),
          ),
        )
        .then((result) {
          // Clean up listeners when modal closes
          _socketService.removeListener('callEnded', crossRoomListenerKey);
          _socketService.removeListener('callDeclined', crossRoomListenerKey);

          if (!mounted) {
            PresenceService().isHandlingIncomingCall = false;
            return;
          }

          if (result is Map &&
              (result['result'] == 'accepted' ||
                  result['result'] == 'connected')) {
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
          PresenceService().isHandlingIncomingCall = false;
        });
  }

  /// Handle incoming call while in chat screen
  Future<void> _handleIncomingCallInChat(Map<String, dynamic> data) async {
    if (!mounted) return;

    // Guard: ignore if already in an active call
    if (PresenceService().isCallInProgress) {
      debugPrint(
        '\u26a0\ufe0f Ignoring incoming_call \u2014 call already in progress',
      );
      return;
    }

    // Guard against duplicate/rapid incoming call events (global flag shared with lobby)
    if (PresenceService().isHandlingIncomingCall) {
      debugPrint(
        '\u26a0\ufe0f Already handling an incoming call, ignoring duplicate',
      );
      return;
    }
    PresenceService().isHandlingIncomingCall = true;

    debugPrint('\ud83d\udcf2 Incoming call received in chat: $data');

    final callId = data['id'] as int?;
    final callRoomId = data['call_room_id'] as String?;
    final callType = data['call_type'] as String? ?? 'video';
    final callerData = data['caller'] as Map<String, dynamic>?;
    final callerId = callerData?['id'] as int? ?? data['caller_id'] as int?;
    final callerName =
        callerData?['full_name'] as String? ??
        callerData?['username'] as String? ??
        widget.otherUser.fullName;

    if (callId == null || callRoomId == null || callerId == null) {
      debugPrint('\u26a0\ufe0f Invalid incoming call data');
      PresenceService().isHandlingIncomingCall = false;
      return;
    }

    // START buffering WebRTC signals immediately â€” before the async callService.initialize().
    _socketService.startSignalBuffering();

    // Initialize call service (fetches ICE servers) and set up the call state
    final callService = CallService();

    // Reset the singleton to ensure clean state for new call
    callService.reset();

    await callService.initialize();

    if (!mounted) {
      PresenceService().isHandlingIncomingCall = false;
      return;
    }

    callService.handleIncomingCall(data);

    // Set up signal handler for WebRTC
    _socketService.onSignal = (signalData) {
      debugPrint('ðŸ“¡ Signal received for incoming call: $signalData');
      callService.handleSignal(signalData);
    };

    // Use keyed listeners for call ended/declined handlers to avoid overwriting
    const callListenerKey = 'chat_incoming_call';
    _socketService.addListener('callEnded', callListenerKey, (
      Map<String, dynamic> endData,
    ) {
      debugPrint('ðŸ“´ Call ended by remote user (chat)');
      callService.handleCallEnded();
    });

    _socketService.addListener('callDeclined', callListenerKey, (
      Map<String, dynamic> declineData,
    ) {
      debugPrint('âŒ Call declined (chat)');
      callService.handleCallDeclined();
    });

    // Show incoming call setup modal with device selection
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (context) => IncomingCallSetupModal(
              callerName: callerName,
              callerId: callerId,
              callType: callType,
              callService: callService,
              onDecline: () {
                debugPrint('ðŸ“ž Call declined by user');
                // Clean up listeners
                _socketService.removeListener('callEnded', callListenerKey);
                _socketService.removeListener('callDeclined', callListenerKey);
              },
            ),
          ),
        )
        .then((result) {
          // Clean up listeners when modal closes
          _socketService.removeListener('callEnded', callListenerKey);
          _socketService.removeListener('callDeclined', callListenerKey);

          if (!mounted) {
            PresenceService().isHandlingIncomingCall = false;
            return;
          }

          if (result is Map &&
              (result['result'] == 'accepted' ||
                  result['result'] == 'connected')) {
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
          PresenceService().isHandlingIncomingCall = false;
        });
  }

  void _handleColorChange(Map<String, dynamic> data) {
    final colorHex = data['color'] as String?;
    final senderName = data['sender_name'] ?? widget.otherUser.fullName;
    final senderId = data['sender_id'] as int?;
    final isFromSelf = senderId == _currentUserId;
    final timestampMs =
        data['timestamp_ms'] as int? ?? DateTime.now().millisecondsSinceEpoch;

    if (colorHex != null) {
      try {
        // Dedup check - look for any existing color change message
        final alreadyExists = _messages.any(
          (msg) =>
              msg.messageType == 'system' &&
              (msg.content.contains('bg color') ||
                  msg.content.contains('Changed bg color')),
        );

        // If from self and message already exists locally, skip (same device echo)
        if (isFromSelf && alreadyExists) {
          debugPrint(
            'ðŸŽ¨ Skipping color change from self (already added locally)',
          );
          return;
        }

        // Parse hex color (e.g., "#FF5733" or "FF5733")
        final hexColor = colorHex.replaceAll('#', '');
        final color = Color(int.parse('FF$hexColor', radix: 16));

        // Only apply color change if we are the RECIPIENT (not the sender)
        if (!isFromSelf) {
          setState(() {
            _headerColor = color;
            _showResetButton = true;
          });

          // Persist the color so it survives app restarts / background
          _saveChatColor(colorHex);
        }

        // Create system message
        final colorMessage = Message(
          id: timestampMs,
          senderId: isFromSelf ? _currentUserId! : widget.otherUser.id,
          recipientId: isFromSelf ? widget.otherUser.id : _currentUserId!,
          content: isFromSelf
              ? 'You changed the bg color of ${widget.otherUser.fullName}'
              : '$senderName changed your bg color to $colorHex',
          messageType: 'system',
          timestamp: DateTime.now().toIso8601String(),
          timestampMs: timestampMs,
          isRead: true,
          status: isFromSelf ? 'sent' : 'delivered',
          threadId: 'thread_${_currentUserId}_${widget.otherUser.id}',
          reactions: {},
          isDeleted: false,
        );

        setState(() {
          _messages.insert(0, colorMessage);
        });

        // Only auto-scroll if user is at bottom, otherwise just show unread badge
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_isAtBottom) {
            _scrollToBottom();
          }
        });

        debugPrint(
          'ðŸŽ¨ Color changed to: $colorHex (${isFromSelf ? "cross-device sync" : "incoming from $senderName"})',
        );
      } catch (e) {
        debugPrint('Error parsing color: $e');
      }
    }
  }

  void _handleColorReset(Map<String, dynamic> data) {
    final senderName = data['sender_name'] ?? widget.otherUser.fullName;
    final senderId = data['sender_id'] as int?;
    final isFromSelf = senderId == _currentUserId;
    final timestampMs =
        data['timestamp_ms'] as int? ?? DateTime.now().millisecondsSinceEpoch;

    // Dedup check
    final alreadyExists = _messages.any(
      (msg) =>
          msg.messageType == 'system' &&
          msg.timestampMs == timestampMs &&
          (msg.content.contains('reset') || msg.content.contains('Reset')),
    );
    if (alreadyExists) {
      debugPrint('ðŸ”„ Skipping duplicate color reset message');
      return;
    }

    // Always reset bg color â€” whether incoming (other user resets) or
    // cross-device (we reset from another device), our bg should update
    const defaultColor = Color(0xFF1E1E1E);
    setState(() {
      _headerColor = defaultColor;
      _showResetButton = false;
    });
    _saveChatColor('#1E1E1E');

    // Create system message
    final resetMessage = Message(
      id: timestampMs,
      senderId: isFromSelf ? _currentUserId! : widget.otherUser.id,
      recipientId: isFromSelf ? widget.otherUser.id : _currentUserId!,
      content: isFromSelf
          ? 'Reset bg color'
          : '$senderName reset\'s their bg color',
      messageType: 'system',
      timestamp: DateTime.now().toIso8601String(),
      timestampMs: timestampMs,
      isRead: true,
      status: isFromSelf ? 'sent' : 'delivered',
      threadId: 'thread_${_currentUserId}_${widget.otherUser.id}',
      reactions: {},
      isDeleted: false,
    );

    setState(() {
      _messages.insert(0, resetMessage);
    });

    // Only auto-scroll if user is at bottom, otherwise just show unread badge
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isAtBottom) {
        _scrollToBottom();
      }
    });

    debugPrint(
      'ðŸ”„ Color ${isFromSelf ? "reset (cross-device sync)" : "reset by ${widget.otherUser.fullName}"}',
    );
  }

  void _handleIncomingDoorbell(Map<String, dynamic> data) {
    final senderName = data['sender_name'] ?? widget.otherUser.fullName;
    final timestampMs = data['timestamp_ms'] as int;

    // Check if we already have this doorbell notification to prevent duplicates
    final alreadyExists = _messages.any(
      (msg) =>
          msg.messageType == 'system' &&
          msg.timestampMs == timestampMs &&
          msg.content.contains('sent a notification'),
    );

    if (alreadyExists) {
      debugPrint('Doorbell notification already exists, skipping duplicate');
      return;
    }

    // Play doorbell notification sound
    _playDoorbellSound();

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

    // Only auto-scroll if user is at bottom, otherwise just show unread badge
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isAtBottom) {
        _scrollToBottom();
      }
    });
  }

  /// Cross-device sync: show outgoing doorbell system message when we rang from another device
  void _handleOutgoingDoorbellSync(Map<String, dynamic> data) {
    final timestampMs =
        data['timestamp_ms'] as int? ?? DateTime.now().millisecondsSinceEpoch;

    // Check for duplicates
    final alreadyExists = _messages.any(
      (msg) =>
          msg.messageType == 'system' &&
          msg.timestampMs == timestampMs &&
          (msg.content.contains('sent a notification') ||
              msg.content.contains('Sent a notification')),
    );

    if (alreadyExists) {
      debugPrint(
        'ðŸ”” Cross-device doorbell already exists, skipping duplicate',
      );
      return;
    }

    debugPrint('ðŸ”” Cross-device: showing outgoing doorbell in chat');

    final doorbellMessage = Message(
      id: timestampMs,
      senderId: _currentUserId!,
      recipientId: widget.otherUser.id,
      content: 'Sent a notification',
      messageType: 'system',
      timestamp: DateTime.now().toIso8601String(),
      timestampMs: timestampMs,
      isRead: true,
      status: 'sent',
      threadId: 'thread_${_currentUserId}_${widget.otherUser.id}',
      reactions: {},
      isDeleted: false,
    );

    setState(() {
      _messages.insert(0, doorbellMessage);
    });

    // Only auto-scroll if user is at bottom, otherwise just show unread badge
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isAtBottom) {
        _scrollToBottom();
      }
    });
  }

  void _handleAllMessagesDeleted(Map<String, dynamic> data) {
    debugPrint('ðŸ—‘ï¸ Handling all messages deleted event: $data');

    final String deletedRoom = data['room'] ?? '';

    // Validate room ID
    if (deletedRoom.isEmpty) {
      debugPrint('âš ï¸ Warning: Received delete event with no room ID');
      return;
    }

    // Generate current room ID (same format as backend: chat_{userId1}_{userId2} sorted)
    if (_currentUserId == null) {
      debugPrint('âš ï¸ Warning: Current user ID is null');
      return;
    }

    final List<int> userIds = [_currentUserId!, widget.otherUser.id];
    userIds.sort();
    final currentRoomId = 'chat_${userIds[0]}_${userIds[1]}';

    // Only clear messages if the event is for the current room
    if (deletedRoom != currentRoomId) {
      debugPrint(
        'â„¹ï¸ Ignoring delete event for different room: $deletedRoom (current: $currentRoomId)',
      );
      return;
    }

    // Clear all messages
    setState(() {
      _messages.clear();
      _databaseLoadedMessageIds.clear();
    });

    // Clear the local cache so stale messages don't reload
    if (_currentUserId != null) {
      ChatCacheService.clearConversationCache(
        _currentUserId!,
        widget.otherUser.id,
      );
      debugPrint('ðŸ—‘ï¸ Conversation cache cleared for room: $currentRoomId');
    }

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

    debugPrint('âœ… Messages cleared for room: $currentRoomId');
  }

  Future<void> _loadCachedMessages() async {
    final currentUserId = await StorageService.getUserId();
    if (currentUserId == null) {
      debugPrint('âš ï¸ No user ID available for cache loading');
      return;
    }

    try {
      final cached = await ChatCacheService.loadConversationMessages(
        currentUserId,
        widget.otherUser.id,
      );

      if (cached.isNotEmpty && mounted) {
        debugPrint('ðŸ“¦ Loaded ${cached.length} messages from cache');
        setState(() {
          _messages = cached.reversed.toList();
          _databaseLoadedMessageIds
            ..clear()
            ..addAll(
              cached
                  .where((message) => message.id > 0)
                  .map((message) => message.id),
            );
          _isLoading = false; // Show cached messages immediately
        });
      } else {
        debugPrint(
          'ðŸ“¦ No cached messages available - this is expected on first open',
        );
        // Don't show empty state - let _loadMessages handle it
      }
    } catch (e) {
      debugPrint('Error loading cached messages: $e');
      // Don't modify loading state - let _loadMessages handle it
    }
  }

  Future<void> _loadPinnedExcalidrawLinks() async {
    try {
      final links = await MessageService.getConversationExcalidrawLinks(
        userId: widget.otherUser.id,
      );
      if (mounted) {
        setState(() => _pinnedExcalidrawLinks = links);
      }
    } catch (e) {
      debugPrint('Error loading pinned excalidraw links: $e');
    }
  }

  Future<void> _loadMessages() async {
    // Guard against concurrent calls
    if (_isLoadingMessages) {
      debugPrint(
        'âš ï¸ _loadMessages already in progress, skipping duplicate call',
      );
      return;
    }

    _isLoadingMessages = true;
    if (_isLoading) {
      setState(() => _isLoading = true);
    }
    try {
      debugPrint('ðŸ”„ Loading messages for user ${widget.otherUser.id}...');
      final messages = await MessageService.getConversationMessages(
        userId: widget.otherUser.id,
        limit: 50,
        offlineFirst: false, // Cache was already shown by _loadCachedMessages
      );
      debugPrint('âœ… Successfully loaded ${messages.length} messages');

      if (!mounted) {
        debugPrint('âš ï¸ Widget unmounted before setState, skipping update');
        _isLoadingMessages = false;
        return;
      }

      setState(() {
        _messages = messages.reversed
            .toList(); // Reverse to show newest at bottom
        _databaseLoadedMessageIds
          ..clear()
          ..addAll(
            _messages
                .where((message) => message.id > 0)
                .map((message) => message.id),
          );
        _isLoading = false;

        // Populate _messageReactions from loaded messages
        _messageReactions.clear();
        for (final msg in _messages) {
          if (msg.reactions.isNotEmpty) {
            debugPrint(
              'ðŸ“¦ Message ${msg.id} reactions raw: ${msg.reactions}',
            );
            _messageReactions[msg.id] = {};

            // Backend sends format: { "counts": {"ðŸ˜€": 1}, "by_user": [{"user_id": 1, "reaction": "ðŸ˜€"}] }
            // We need to extract reactions from by_user array and group by emoji
            final byUser = msg.reactions['by_user'];
            if (byUser is List && byUser.isNotEmpty) {
              // New format: extract from by_user array
              for (final entry in byUser) {
                if (entry is Map) {
                  final emoji = entry['reaction']?.toString();
                  final userId = entry['user_id']?.toString();
                  if (emoji != null && emoji.isNotEmpty && userId != null) {
                    _messageReactions[msg.id]!.putIfAbsent(
                      emoji,
                      () => <String>{},
                    );
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
                      users.map((u) => u.toString()),
                    );
                  }
                } else if (value is List) {
                  // Simple format: { "emoji": [user1, user2] }
                  final emoji = key.toString();
                  _messageReactions[msg.id]![emoji] = Set<String>.from(
                    value.map((u) => u.toString()),
                  );
                }
              });
            }

            debugPrint(
              'ðŸ“¦ Message ${msg.id} reactions parsed: ${_messageReactions[msg.id]}',
            );
          }
        }
      });

      await _syncLoadedMessageStatuses(messages);

      _scrollToBottom();
    } catch (e) {
      debugPrint('âŒ Error loading messages: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } finally {
      _isLoadingMessages = false;
      debugPrint('ðŸ Message loading process completed');
    }
  }

  String _mapConnectivityError(
    Object error, {
    String offlineLabel = 'No internet connection.',
    String backendLabel = 'Server unreachable.',
  }) {
    final message = error.toString();
    if (error is SocketException ||
        message.contains('SocketException') ||
        message.contains('Failed host lookup')) {
      return offlineLabel;
    }
    if (error is TimeoutException ||
        message.contains('TimeoutException') ||
        message.contains('Connection timed out')) {
      return backendLabel;
    }
    return 'Something went wrong. Please try again.';
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
      final myName = 'Me';
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

        final senderName = message.senderId == _currentUserId
            ? myName
            : otherName;
        final time = _formatExportTime(message.timestamp);
        final content = message.isDeleted
            ? '[Message deleted]'
            : message.content;

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
      final defaultFileName =
          'chat_${widget.otherUser.fullName.replaceAll(' ', '_')}_${DateTime.now().day}-${DateTime.now().month}-${DateTime.now().year}.txt';
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

  /// Admin-only: delete all messages in this conversation
  Future<void> _adminDeleteAllMessages() async {
    if (!_currentUserIsAdmin) return;

    // Build the room ID the same way the socket join uses it
    final ids = [_currentUserId!, widget.otherUser.id]..sort();
    final room = 'chat_${ids[0]}_${ids[1]}';

    // Confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D2D),
        title: const Text(
          'Delete All Messages',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'This will permanently delete ALL messages between you and '
          '${widget.otherUser.fullName}, including all uploaded files. '
          'This cannot be undone.',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Show progress
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              SizedBox(width: 12),
              Text('Deleting all messages...'),
            ],
          ),
          duration: Duration(seconds: 30),
        ),
      );
    }

    try {
      final token = await StorageService.getToken();
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/mobile/admin/delete-all-messages'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: '{"room":"$room"}',
      );

      if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();

      if (response.statusCode == 200) {
        // Clear the local messages list immediately
        setState(() {
          _messages.clear();
          _databaseLoadedMessageIds.clear();
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('All messages deleted successfully'),
              backgroundColor: Color(0xFF10B981),
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Failed to delete messages (${response.statusCode})',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Format date for export separator
  String _formatExportDate(String timestamp) {
    try {
      final date = _parseUtcTimestamp(timestamp);
      final weekdays = [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ];
      final months = [
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December',
      ];
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
    final markAsTask = _markNextMessageAsTask;

    // Capture reply info before clearing
    final replyToId = _replyingToMessage?.id;
    String? replyPreviewContent;
    if (_replyingToMessage != null) {
      final msg = _replyingToMessage!;
      final senderName = msg.senderId == _currentUserId
          ? 'You'
          : widget.otherUser.fullName;
      String previewText;
      // Handle different message types
      if (msg.isDeleted) {
        previewText = 'Deleted message';
      } else if (msg.messageType == 'voice' || msg.messageType == 'audio') {
        previewText = 'ðŸŽ¤ Voice message';
      } else if (msg.messageType == 'image') {
        previewText = 'ðŸ“· Photo';
      } else if (msg.messageType == 'video') {
        previewText = 'ðŸŽ¬ Video';
      } else if (msg.messageType == 'file') {
        previewText = 'ðŸ“Ž ${msg.fileName ?? "File"}';
      } else {
        // For text, truncate if too long
        previewText = msg.content.length > 60
            ? '${msg.content.substring(0, 60)}...'
            : msg.content;
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
      isTask: markAsTask,
      taskCreatedAt: markAsTask ? DateTime.now().toIso8601String() : null,
    );

    // Track this optimistic message for dedup when server echoes back
    final dedupKey = '$_currentUserId:${widget.otherUser.id}:$content';
    _pendingMessageKeys.add(dedupKey);
    if (markAsTask) {
      _enqueuePendingTaskIntent(dedupKey);
    }

    setState(() {
      _messages.insert(0, optimisticMessage);
      _replyingToMessage = null; // Clear reply after sending
      _markNextMessageAsTask = false;
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
        debugPrint(
          'âœ… Sending message via Socket.IO${replyToId != null ? ' (replying to $replyToId)' : ''}',
        );
        _socketService.sendMessage(
          recipientId: widget.otherUser.id,
          content: content,
          messageType: 'text',
          replyToId: replyToId,
        );
      } else {
        // Fallback to REST API
        debugPrint('âš ï¸ Socket.IO not connected, using REST API fallback');
        final sentMessage = await MessageService.sendMessage(
          recipientId: widget.otherUser.id,
          content: content,
          messageType: 'text',
        );

        // Update optimistic message with real message data
        if (sentMessage != null && mounted) {
          final uiMessage = markAsTask
              ? _copyMessageWithTaskState(
                  sentMessage,
                  isTask: true,
                  taskCreatedAt:
                      sentMessage.taskCreatedAt ??
                      DateTime.now().toIso8601String(),
                  taskCompletedAt: null,
                )
              : sentMessage;

          setState(() {
            final index = _messages.indexWhere(
              (m) => m.id == optimisticMessage.id,
            );
            if (index != -1) {
              _messages[index] = uiMessage;
            }
          });

          if (markAsTask) {
            _consumePendingTaskIntent(dedupKey);
          }

          if (markAsTask && _socketService.isConnected) {
            _socketService.addTask(sentMessage.id);
          }
          debugPrint('âœ… Message sent via REST API');
        }
      }
    } catch (e) {
      debugPrint('âŒ Error sending message: $e');
      _pendingMessageKeys.remove(dedupKey);
      if (markAsTask) {
        _consumePendingTaskIntent(dedupKey);
      }
      // Update message status to failed
      if (mounted) {
        setState(() {
          final index = _messages.indexWhere(
            (m) => m.id == optimisticMessage.id,
          );
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

  void _enqueuePendingTaskIntent(String dedupKey) {
    final current = _pendingTaskIntentsByDedupKey[dedupKey] ?? 0;
    _pendingTaskIntentsByDedupKey[dedupKey] = current + 1;
  }

  bool _consumePendingTaskIntent(String dedupKey) {
    final current = _pendingTaskIntentsByDedupKey[dedupKey] ?? 0;
    if (current <= 0) {
      return false;
    }

    if (current == 1) {
      _pendingTaskIntentsByDedupKey.remove(dedupKey);
    } else {
      _pendingTaskIntentsByDedupKey[dedupKey] = current - 1;
    }

    return true;
  }

  Message _copyMessageWithTaskState(
    Message message, {
    required bool isTask,
    String? taskCreatedAt,
    String? taskCompletedAt,
  }) {
    return Message(
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
      isTask: isTask,
      taskCreatedAt: taskCreatedAt,
      taskCompletedAt: taskCompletedAt,
      isExcalidrawLink: message.isExcalidrawLink,
      excalidrawPinnedAt: message.excalidrawPinnedAt,
      isPinned: message.isPinned,
      pinnedAt: message.pinnedAt,
      pinnedByUserId: message.pinnedByUserId,
    );
  }

  Message _copyMessageWithExcalidrawState(
    Message message, {
    required bool isExcalidrawLink,
    String? excalidrawPinnedAt,
  }) {
    return Message(
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
      isTask: message.isTask,
      taskCreatedAt: message.taskCreatedAt,
      taskCompletedAt: message.taskCompletedAt,
      isExcalidrawLink: isExcalidrawLink,
      excalidrawPinnedAt: excalidrawPinnedAt,
      isPinned: excalidrawPinnedAt != null,
      pinnedAt: excalidrawPinnedAt,
      pinnedByUserId: excalidrawPinnedAt != null
          ? (_currentUserId ?? message.pinnedByUserId)
          : null,
    );
  }

  Message _applyPendingLiveTaskState(Message message) {
    final pendingCreatedAt = _pendingLiveTaskCreatedAtByMessageId.remove(
      message.id,
    );
    final pendingCompletedAt = _pendingLiveTaskCompletedAtByMessageId.remove(
      message.id,
    );

    if (!message.isTask &&
        pendingCreatedAt == null &&
        pendingCompletedAt == null) {
      return message;
    }

    return _copyMessageWithTaskState(
      message,
      isTask: true,
      taskCreatedAt:
          pendingCreatedAt ??
          message.taskCreatedAt ??
          DateTime.now().toIso8601String(),
      taskCompletedAt: pendingCompletedAt ?? message.taskCompletedAt,
    );
  }

  String _buildBulkBatchId() {
    final now = DateTime.now().toUtc();
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return 'flutter-batch-${now.year}-${twoDigits(now.month)}-${twoDigits(now.day)}-${now.millisecondsSinceEpoch}';
  }

  Future<void> _showSendToManyDialog() async {
    final draftContent = _messageController.text.trim();
    if (draftContent.isEmpty) return;

    final currentUserId = _currentUserId ?? await StorageService.getUserId();
    if (!mounted) return;

    final usersFuture = LobbyService.getLobbyUsers();
    final selectedRecipientIds = <int>{widget.otherUser.id};
    var searchQuery = '';

    final selectedIds = await showDialog<List<int>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setModalState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E1E2E),
              title: const Text(
                'Send to many',
                style: TextStyle(color: Colors.white),
              ),
              content: SizedBox(
                width: double.maxFinite,
                height: 380,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Select recipients for this message.',
                      style: TextStyle(color: Colors.grey[300], fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A2A3A),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: TextField(
                        onChanged: (value) {
                          setModalState(() => searchQuery = value);
                        },
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Search users',
                          hintStyle: TextStyle(color: Colors.grey[500]),
                          prefixIcon: Icon(
                            Icons.search,
                            color: Colors.grey[500],
                            size: 18,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: FutureBuilder<List<LobbyUser>>(
                        future: usersFuture,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }

                          if (snapshot.hasError) {
                            return Center(
                              child: Text(
                                'Failed to load users',
                                style: TextStyle(color: Colors.grey[400]),
                              ),
                            );
                          }

                          final users = snapshot.data ?? const <LobbyUser>[];
                          final selectableUsers = users.where((user) {
                            if (currentUserId != null &&
                                user.id == currentUserId) {
                              return false;
                            }
                            return true;
                          }).toList();

                          final selectedUsers = selectableUsers.where((user) {
                            return selectedRecipientIds.contains(user.id);
                          }).toList();

                          final normalizedSearch = searchQuery
                              .trim()
                              .toLowerCase();
                          final filteredUsers = selectableUsers.where((user) {
                            if (normalizedSearch.isEmpty) {
                              return true;
                            }
                            return user.fullName.toLowerCase().contains(
                                  normalizedSearch,
                                ) ||
                                user.username.toLowerCase().contains(
                                  normalizedSearch,
                                );
                          }).toList();

                          filteredUsers.sort((a, b) {
                            final aSelected = selectedRecipientIds.contains(
                              a.id,
                            );
                            final bSelected = selectedRecipientIds.contains(
                              b.id,
                            );
                            if (aSelected == bSelected) {
                              return a.fullName.toLowerCase().compareTo(
                                b.fullName.toLowerCase(),
                              );
                            }
                            return aSelected ? -1 : 1;
                          });

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${selectedRecipientIds.length} selected',
                                style: const TextStyle(
                                  color: Color(0xFF7C3AED),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                width: double.infinity,
                                constraints: const BoxConstraints(
                                  minHeight: 44,
                                  maxHeight: 110,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF2A2A3A),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: const Color(0xFF3B3B4E),
                                  ),
                                ),
                                child: selectedUsers.isEmpty
                                    ? Center(
                                        child: Text(
                                          'No recipients selected',
                                          style: TextStyle(
                                            color: Colors.grey[500],
                                            fontSize: 12,
                                          ),
                                        ),
                                      )
                                    : SingleChildScrollView(
                                        child: Wrap(
                                          spacing: 6,
                                          runSpacing: 6,
                                          children: selectedUsers
                                              .map(
                                                (user) => InputChip(
                                                  label: Text(
                                                    user.fullName,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                  labelStyle: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 12,
                                                  ),
                                                  backgroundColor: const Color(
                                                    0xFF4C1D95,
                                                  ),
                                                  deleteIconColor:
                                                      Colors.white70,
                                                  onDeleted: () {
                                                    setModalState(() {
                                                      selectedRecipientIds
                                                          .remove(user.id);
                                                    });
                                                  },
                                                  materialTapTargetSize:
                                                      MaterialTapTargetSize
                                                          .shrinkWrap,
                                                ),
                                              )
                                              .toList(),
                                        ),
                                      ),
                              ),
                              const SizedBox(height: 8),
                              Expanded(
                                child: filteredUsers.isEmpty
                                    ? Center(
                                        child: Text(
                                          'No users found',
                                          style: TextStyle(
                                            color: Colors.grey[400],
                                          ),
                                        ),
                                      )
                                    : ListView.builder(
                                        itemCount: filteredUsers.length,
                                        itemBuilder: (context, index) {
                                          final user = filteredUsers[index];
                                          final isSelected =
                                              selectedRecipientIds.contains(
                                                user.id,
                                              );
                                          return CheckboxListTile(
                                            dense: true,
                                            value: isSelected,
                                            onChanged: (value) {
                                              setModalState(() {
                                                if (value == true) {
                                                  selectedRecipientIds.add(
                                                    user.id,
                                                  );
                                                } else {
                                                  selectedRecipientIds.remove(
                                                    user.id,
                                                  );
                                                }
                                              });
                                            },
                                            controlAffinity:
                                                ListTileControlAffinity.leading,
                                            activeColor: const Color(
                                              0xFF7C3AED,
                                            ),
                                            checkColor: Colors.white,
                                            title: Text(
                                              user.fullName,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 14,
                                              ),
                                            ),
                                            subtitle: Text(
                                              '@${user.username}',
                                              style: TextStyle(
                                                color: Colors.grey[400],
                                                fontSize: 12,
                                              ),
                                            ),
                                            contentPadding: EdgeInsets.zero,
                                          );
                                        },
                                      ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: selectedRecipientIds.isEmpty
                      ? null
                      : () {
                          Navigator.pop(
                            dialogContext,
                            selectedRecipientIds.toList(),
                          );
                        },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF7C3AED),
                  ),
                  child: const Text('Send'),
                ),
              ],
            );
          },
        );
      },
    );

    if (selectedIds == null || selectedIds.isEmpty || !mounted) {
      return;
    }

    final replyToId = _replyingToMessage?.id;
    try {
      final response = await MessageService.sendManyMessages(
        recipientIds: selectedIds,
        content: draftContent,
        messageType: 'text',
        replyToId: replyToId,
        bulkBatchId: _buildBulkBatchId(),
      );

      _messageController.clear();
      _stopTyping();
      if (mounted) {
        setState(() {
          _replyingToMessage = null;
        });
      }

      if (!mounted) return;

      final summaryText = response.failedCount > 0
          ? 'Sent to ${response.sentCount}/${response.requestedCount}. ${response.failedCount} failed.'
          : 'Sent to ${response.sentCount} recipients.';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(summaryText),
          backgroundColor: response.failedCount > 0
              ? Colors.orange
              : Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Bulk send failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildSendToManyQuickAction() {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _messageController,
      builder: (context, value, _) {
        if (value.text.trim().isEmpty) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _showSendToManyDialog,
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A1F45),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: const Color(0xFF7C3AED).withValues(alpha: 0.8),
                        width: 1,
                      ),
                    ),
                    child: const Text(
                      'send to many',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              const Spacer(),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _markNextMessageAsTask = !_markNextMessageAsTask;
                    });
                  },
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: _markNextMessageAsTask
                          ? const Color(0xFF7C2D12)
                          : const Color(0xFF2D2A1F),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: _markNextMessageAsTask
                            ? const Color(0xFFF59E0B)
                            : const Color(0xFFB45309).withValues(alpha: 0.75),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      'mark as task',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _onTextChanged(String text) {
    final normalizedText = _normalizeTextForEmojiCompatibility(text);
    if (normalizedText != text) {
      _replaceInputTextWithSanitized(normalizedText);
      return;
    }

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
    // Cancel any pending throttled typing update so it doesn't fire after stop
    _typingUpdateThrottle?.cancel();
    _typingUpdateThrottle = null;
    // Send empty typing_update to explicitly clear live preview on receiver
    _socketService.sendTypingUpdate(widget.otherUser.id, '');
    _socketService.stopTyping(widget.otherUser.id);
    _typingTimer?.cancel();
  }

  void _resetColor() {
    // Mark that we locally triggered the reset so we can suppress the echo
    _localColorResetPending = true;

    // Reset to default color
    const defaultColor = Color(0xFF1E1E1E);

    setState(() {
      _headerColor = defaultColor;
      _showResetButton = false;
    });

    // Persist the reset color
    _saveChatColor('#1E1E1E');

    // Emit reset color event (must be 'reset_color' so backend broadcasts to all devices)
    _socketService.emit('reset_color', {'recipient_id': widget.otherUser.id});

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

    // Only auto-scroll if user is at bottom, otherwise just show unread badge
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isAtBottom) {
        _scrollToBottom();
      }
    });

    debugPrint('ðŸŽ¨ Color reset to default');
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
          final colorHex = selectedColor
              .toARGB32()
              .toRadixString(16)
              .substring(2)
              .toUpperCase();
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
            content: 'You changed the bg color of ${widget.otherUser.fullName}',
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

          // Only auto-scroll if user is at bottom, otherwise just show unread badge
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_isAtBottom) {
              _scrollToBottom();
            }
          });

          debugPrint(
            'ðŸŽ¨ Color sent to ${widget.otherUser.fullName}: #$colorHex',
          );
        },
      ),
    );
  }

  /// Play doorbell sound, holding the AudioPlayer reference alive in a list
  /// so it isn't garbage-collected before playback completes.
  void _playDoorbellSound() {
    try {
      final player = AudioPlayer();
      _activeDoorbellPlayers.add(player);
      player.play(AssetSource('sounds/notif-sound.wav'));
      player.onPlayerComplete.listen((_) {
        _activeDoorbellPlayers.remove(player);
        player.dispose();
      });
    } catch (e) {
      debugPrint('Error playing doorbell sound: $e');
    }
  }

  void _ringDoorbell() {
    // Mark that we locally triggered the doorbell so we can suppress the echo
    _localDoorbellPending = true;

    // Send doorbell via Socket.IO
    _socketService.ringDoorbell(widget.otherUser.id);

    // Play doorbell notification sound (each tap gets its own player so rapid rings don't cancel each other)
    _playDoorbellSound();

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

    // Only auto-scroll if user is at bottom, otherwise just show unread badge
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isAtBottom) {
        _scrollToBottom();
      }
    });
  }

  /// Mirrors lobby's _getEffectiveStatus: corrects a stale 'online' flag by
  /// checking the lastSeen timestamp, so the chat header stays in sync with
  /// what the contact list shows.
  String _getEffectivePartnerStatus() {
    if (_partnerStatus == 'online') {
      if (_partnerLastSeen != null) {
        try {
          final lastSeenTime = _parseUtcTimestamp(_partnerLastSeen!);
          final age = DateTime.now().difference(lastSeenTime);
          if (age.inMinutes <= 2) return 'online';
          return age.inHours < 24 ? 'away' : 'offline';
        } catch (_) {
          return 'online';
        }
      }
      return 'online';
    }
    return _partnerStatus;
  }

  String _getHeaderStatusLabel() {
    if (_otherUserTyping) {
      return 'typing...';
    }

    final effective = _getEffectivePartnerStatus();

    if (effective == 'online') {
      return 'Online';
    }

    if (effective == 'offline') {
      if (_partnerLastSeen != null) {
        return _formatLastSeen(_partnerLastSeen!);
      }
      return 'Offline';
    }

    // away
    if (_partnerLastSeen != null) {
      return _formatLastSeen(_partnerLastSeen!);
    }

    return 'Away';
  }

  Color _getHeaderStatusColor() {
    final effective = _getEffectivePartnerStatus();
    if (_otherUserTyping || effective == 'online') {
      return const Color(0xFF22C55E);
    }

    if (effective == 'offline') {
      return const Color(0xFFEF4444);
    }

    return const Color(0xFF9CA3AF);
  }

  /// Returns a UI scale factor (0.80–1.0) so elements shrink gracefully on
  /// small screens (< 360 dp wide) while staying full-size on normal screens.
  double _uiScale(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return (width / 411.0).clamp(0.78, 1.0);
  }

  Widget _buildHeaderStatusPill() {
    final statusColor = _getHeaderStatusColor();
    final scale = _uiScale(context);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 4 * scale),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: statusColor.withValues(alpha: 0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8 * scale,
            height: 8 * scale,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: 6 * scale),
          Flexible(
            child: Text(
              _getHeaderStatusLabel(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: statusColor,
                fontSize: 11 * scale,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _runActionSheetAction(
    BuildContext sheetContext,
    FutureOr<void> Function() action,
  ) async {
    _closeActionsPanel(sheetContext);
    await Future<void>.delayed(const Duration(milliseconds: 120));

    if (!mounted) {
      return;
    }

    _keepInputUnfocused();
    await action();
  }

  void _keepInputUnfocused() {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_inputFocusNode.hasFocus) {
      _inputFocusNode.unfocus();
    }
  }

  void _closeActionsPanel(BuildContext panelContext) {
    _keepInputUnfocused();

    final navigator = Navigator.of(panelContext);
    if (navigator.canPop()) {
      navigator.pop();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _keepInputUnfocused();
    });
  }

  Widget _buildActionSheetButton({
    required String label,
    required Color backgroundColor,
    required VoidCallback onPressed,
    Color foregroundColor = Colors.white,
  }) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        minimumSize: const Size(0, 0),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
      child: Text(label),
    );
  }

  Widget _buildFloatingActionsToggle() {
    const toggleHeight = 62.0;
    const verticalPadding = 12.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
        final visibleHeight = math.max(
          0.0,
          constraints.maxHeight - keyboardInset,
        );
        final maxTop = math.max(
          verticalPadding,
          visibleHeight - toggleHeight - verticalPadding,
        );
        final top = ((visibleHeight - toggleHeight) / 2)
            .clamp(verticalPadding, maxTop)
            .toDouble();

        return Stack(
          children: [
            Positioned(
              top: top,
              right: 0,
              child: Tooltip(
                message: 'Actions',
                child: ClipRRect(
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(16),
                  ),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                    child: Material(
                      color: Colors.transparent,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _showActionsSheet,
                        onHorizontalDragUpdate: (details) {
                          if (details.primaryDelta != null &&
                              details.primaryDelta! < -2) {
                            _showActionsSheet();
                          }
                        },
                        child: Container(
                          width: 28,
                          height: toggleHeight,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2),
                            ),
                            borderRadius: const BorderRadius.horizontal(
                              left: Radius.circular(16),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.18),
                                blurRadius: 10,
                                offset: const Offset(-2, 3),
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.chevron_left_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showActionsSheet() async {
    if (_isActionsPanelOpen || !mounted) {
      return;
    }

    _isActionsPanelOpen = true;
    _keepInputUnfocused();
    if (_showEmojiPicker) {
      setState(() {
        _showEmojiPicker = false;
      });
    }

    try {
      await showGeneralDialog<void>(
        context: context,
        barrierDismissible: false,
        barrierLabel: 'Chat actions',
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (dialogContext, animation, secondaryAnimation) {
          final media = MediaQuery.of(dialogContext);
          final topInset = media.padding.top + kToolbarHeight + 10;
          final bottomInset =
              media.padding.bottom + media.viewInsets.bottom + 10;
          final availableHeight = math.max(
            180.0,
            media.size.height - topInset - bottomInset,
          );
          final maxPanelHeight = math.min(
            availableHeight,
            media.size.height * 0.7,
          );

          final actionButtons = <Widget>[
            _buildActionSheetButton(
              label: 'Ring Doorbell',
              backgroundColor: const Color(0xFF8B5CF6),
              onPressed: () => _ringDoorbell(),
            ),
            _buildActionSheetButton(
              label: 'Change Color',
              backgroundColor: const Color(0xFFA855F7),
              onPressed: () => _runActionSheetAction(dialogContext, () {
                _changeColor();
              }),
            ),
            if (_showResetButton)
              _buildActionSheetButton(
                label: 'Reset Color',
                backgroundColor: Colors.white,
                foregroundColor: Colors.black87,
                onPressed: () => _runActionSheetAction(dialogContext, () {
                  _resetColor();
                }),
              ),
            _buildActionSheetButton(
              label: 'Send File',
              backgroundColor: const Color(0xFF10B981),
              onPressed: () => _runActionSheetAction(dialogContext, _pickFile),
            ),
            _buildActionSheetButton(
              label: 'Camera',
              backgroundColor: const Color(0xFF3B82F6),
              onPressed: () => _runActionSheetAction(dialogContext, _takePhoto),
            ),
            _buildActionSheetButton(
              label: 'Voice Message',
              backgroundColor: const Color(0xFFEF4444),
              onPressed: () => _runActionSheetAction(
                dialogContext,
                _showVoiceRecordingModal,
              ),
            ),
            _buildActionSheetButton(
              label: _autoTranslate ? 'Translate On' : 'Translate Off',
              backgroundColor: _autoTranslate
                  ? const Color(0xFF059669)
                  : const Color(0xFF0891B2),
              onPressed: () =>
                  _runActionSheetAction(dialogContext, _toggleAutoTranslate),
            ),
            _buildActionSheetButton(
              label: _showTimestamps ? 'Hide Timestamps' : 'Show Timestamps',
              backgroundColor: _showTimestamps
                  ? const Color(0xFF4F46E5)
                  : const Color(0xFF8B5CF6),
              onPressed: () =>
                  _runActionSheetAction(dialogContext, _toggleTimestamps),
            ),
            _buildActionSheetButton(
              label: 'Export Chat',
              backgroundColor: const Color(0xFF6B7280),
              onPressed: () =>
                  _runActionSheetAction(dialogContext, _exportChat),
            ),
            if (_currentUserIsAdmin)
              _buildActionSheetButton(
                label: 'Delete All',
                backgroundColor: const Color(0xFFDC2626),
                onPressed: () => _runActionSheetAction(
                  dialogContext,
                  _adminDeleteAllMessages,
                ),
              ),
          ];

          return Material(
            color: Colors.transparent,
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () => _closeActionsPanel(dialogContext),
                    behavior: HitTestBehavior.opaque,
                    child: const SizedBox.expand(),
                  ),
                ),
                Positioned.fill(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(12, topInset, 12, bottomInset),
                    child: Align(
                      alignment: Alignment.center,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: 560,
                          maxHeight: maxPanelHeight,
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF1F1F24),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.1),
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  14,
                                  10,
                                  14,
                                  4,
                                ),
                                child: SizedBox(
                                  height: 38,
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      const Center(
                                        child: Text(
                                          'Chat Actions',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 18,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        right: 0,
                                        child: TextButton(
                                          onPressed: () =>
                                              _closeActionsPanel(dialogContext),
                                          style: TextButton.styleFrom(
                                            foregroundColor: Colors.white70,
                                            textStyle: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          child: const Text('Close'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              Flexible(
                                child: SingleChildScrollView(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    8,
                                    16,
                                    16,
                                  ),
                                  child: Wrap(
                                    alignment: WrapAlignment.center,
                                    spacing: 10,
                                    runSpacing: 10,
                                    children: actionButtons,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
        transitionBuilder:
            (dialogContext, animation, secondaryAnimation, child) {
              final curved = CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
                reverseCurve: Curves.easeInCubic,
              );

              return SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(1, 0),
                  end: Offset.zero,
                ).animate(curved),
                child: child,
              );
            },
      );
    } finally {
      _isActionsPanelOpen = false;
      if (mounted) {
        _keepInputUnfocused();
      }
    }
  }

  /// Show user profile bottom sheet (Skype-style)
  void _showUserProfile() {
    final user = widget.otherUser;
    final avatarColor = _getAvatarColor();
    final effectiveStatus = _getEffectivePartnerStatus();
    final statusText = effectiveStatus == 'online'
        ? 'Online'
        : effectiveStatus == 'away'
        ? (_partnerLastSeen != null
              ? _formatLastSeen(_partnerLastSeen!)
              : 'Away')
        : (_partnerLastSeen != null
              ? _formatLastSeen(_partnerLastSeen!)
              : 'Offline');
    final statusColor = effectiveStatus == 'online'
        ? const Color(0xFF00E676)
        : effectiveStatus == 'away'
        ? const Color(0xFFFFC107)
        : Colors.grey;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final scale = _uiScale(context);
        return Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1E1E2E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.symmetric(horizontal: 24 * scale, vertical: 16 * scale),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 40 * scale,
              height: 4,
              margin: EdgeInsets.only(bottom: 20 * scale),
              decoration: BoxDecoration(
                color: Colors.grey[600],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Profile picture
            CircleAvatar(
              radius: 48 * scale,
              backgroundColor: avatarColor,
              child: user.avatarUrl != null
                  ? ClipOval(
                      child: Image.network(
                        user.avatarUrl!,
                        width: 96 * scale,
                        height: 96 * scale,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Text(
                          user.initials,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 36 * scale,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    )
                  : Text(
                      user.initials,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 36 * scale,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
            SizedBox(height: 16 * scale),
            // Full name
            Text(
              user.fullName,
              style: TextStyle(
                color: Colors.white,
                fontSize: 22 * scale,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 4 * scale),
            // Username
            Text(
              '@${user.username}',
              style: TextStyle(color: Colors.grey[400], fontSize: 14 * scale),
            ),
            SizedBox(height: 8 * scale),
            // Status badge
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 4 * scale),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8 * scale,
                    height: 8 * scale,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  SizedBox(width: 6 * scale),
                  Text(
                    statusText,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 13 * scale,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 20 * scale),
            // Info rows
            _buildProfileInfoRow(Icons.email_outlined, 'Email', user.email, scale),
            if (user.bio != null && user.bio!.isNotEmpty)
              _buildProfileInfoRow(Icons.info_outline, 'Bio', user.bio!, scale),
            _buildProfileInfoRow(Icons.access_time, 'Timezone', user.timezone, scale),
            if (_partnerLastSeen != null &&
                _getEffectivePartnerStatus() != 'online')
              _buildProfileInfoRow(
                Icons.visibility_outlined,
                'Last seen',
                _formatLastSeen(_partnerLastSeen!),
                scale,
              ),
            if (user.isAdmin || user.isAdminUser)
              _buildProfileInfoRow(Icons.shield_outlined, 'Role', 'Admin', scale),
            SizedBox(height: 16 * scale),
            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _showCallSetupModal(CallType.audio);
                    },
                    icon: Icon(Icons.call, size: 18 * scale),
                    label: Text('Call', style: TextStyle(fontSize: 14 * scale)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF4CAF50),
                      side: const BorderSide(color: Color(0xFF4CAF50)),
                      padding: EdgeInsets.symmetric(vertical: 12 * scale),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 12 * scale),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _showCallSetupModal(CallType.video);
                    },
                    icon: Icon(Icons.videocam, size: 18 * scale),
                    label: Text('Video', style: TextStyle(fontSize: 14 * scale)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF3B82F6),
                      side: const BorderSide(color: Color(0xFF3B82F6)),
                      padding: EdgeInsets.symmetric(vertical: 12 * scale),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: MediaQuery.of(context).viewPadding.bottom + 8),
          ],
        ),
      );
      },
    );
  }

  Widget _buildProfileInfoRow(IconData icon, String label, String value, [double scale = 1.0]) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6 * scale),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey[500], size: 20 * scale),
          SizedBox(width: 12 * scale),
          Text(
            '$label:',
            style: TextStyle(color: Colors.grey[500], fontSize: 13 * scale),
          ),
          SizedBox(width: 8 * scale),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: Colors.white, fontSize: 14 * scale),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// Show call setup modal for video/audio calls
  void _showCallSetupModal(CallType callType) {
    final isVideoCall = callType == CallType.video;
    final isAudioCall = callType == CallType.audio;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: isVideoCall ? 1.0 : 0.62,
        minChildSize: isAudioCall ? 0.42 : 0.3,
        maxChildSize: isVideoCall ? 1.0 : 0.72,
        builder: (context, scrollController) => CallSetupModal(
          recipientName: widget.otherUser.fullName,
          callType: callType,
          scrollController: scrollController,
          onStartCall:
              (
                localStream,
                selectedMic,
                selectedSpeaker,
                selectedCamera,
                videoEnabled,
              ) {
                Navigator.pop(context); // Close modal
                _initiateCall(localStream, callType, videoEnabled);
              },
        ),
      ),
    );
  }

  /// Initiate call via CallService
  Future<void> _initiateCall(
    dynamic localStream,
    CallType callType,
    bool videoEnabled,
  ) async {
    final callService = CallService();

    // Reset the singleton to ensure clean state for new call
    callService.reset();

    final callTypeStr = callType == CallType.video ? 'video' : 'audio';

    // Set up socket signal handler
    _socketService.onSignal = (data) {
      callService.handleSignal(data);
    };

    // Use keyed listeners for proper event handling
    const callListenerKey = 'chat_outgoing_call';
    _socketService.addListener('callInitiated', callListenerKey, (
      Map<String, dynamic> data,
    ) {
      callService.handleCallInitiated(data);
    });

    _socketService.addListener('callEnded', callListenerKey, (
      Map<String, dynamic> data,
    ) {
      debugPrint('ðŸ“´ Call ended - cleaning up');
      callService.handleCallEnded();
    });

    _socketService.addListener('callDeclined', callListenerKey, (
      Map<String, dynamic> data,
    ) {
      debugPrint('âŒ Call declined by remote user');
      callService.handleCallDeclined();
    });

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

    if (!mounted) return;

    debugPrint(
      'ðŸŽ¥ Initiated ${callType.name} call with ${widget.otherUser.fullName}',
    );

    // Show outgoing call modal
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => OutgoingCallModal(
          recipientName: widget.otherUser.fullName,
          callType: callTypeStr,
          callService: callService,
          onCancel: () {
            debugPrint('ðŸ“ž Call cancelled by user');
            // Clean up listeners
            _socketService.removeListener('callInitiated', callListenerKey);
            _socketService.removeListener('callEnded', callListenerKey);
            _socketService.removeListener('callDeclined', callListenerKey);
          },
          onConnected: () {
            debugPrint('ðŸ“ž Call connected!');
          },
        ),
      ),
    );

    // Clean up listeners when modal closes (if not already cleaned up)
    _socketService.removeListener('callInitiated', callListenerKey);
    _socketService.removeListener('callEnded', callListenerKey);
    _socketService.removeListener('callDeclined', callListenerKey);

    // Navigate to connected call screen if call connected
    // Trust the modal result 'connected' as authoritative â€” the call was connected.
    // Do NOT re-check callService.callState here because ICE renegotiation can
    // briefly set it to 'connecting' after initial connection, creating a race
    // condition that blocks navigation.
    if (result == 'connected' && mounted) {
      debugPrint(
        'ðŸ“ž Navigating to ConnectedCallScreen after modal returned: $result (callType: $callTypeStr)',
      );

      // Use post-frame callback to ensure widget tree is stable for release builds
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          debugPrint(
            'âŒ Widget unmounted - aborting navigation to ConnectedCallScreen',
          );
          return;
        }

        _performNavigation(callService, localStream, callTypeStr);
      });
    } else {
      debugPrint(
        'ðŸ“ž Modal result: $result, mounted: $mounted, callType: $callTypeStr - not navigating to ConnectedCallScreen',
      );
    }
  }

  /// Perform navigation to ConnectedCallScreen with proper error handling
  Future<void> _performNavigation(
    CallService callService,
    dynamic localStream,
    String callTypeStr,
  ) async {
    debugPrint('ðŸ“ž _performNavigation called for $callTypeStr call');

    if (!mounted) {
      debugPrint('âŒ Widget unmounted in navigation method - aborting');
      return;
    }

    try {
      debugPrint('ðŸ“ž About to push ConnectedCallScreen route');
      debugPrint('ðŸ“ž Current call state: ${callService.callState}');

      // Use the safest possible navigation approach
      final navigator = Navigator.maybeOf(context);
      if (navigator == null) {
        debugPrint('âŒ Navigator is null - aborting navigation');
        return;
      }

      // Check localStream more thoroughly
      debugPrint('ðŸ“ž localStream type: ${localStream.runtimeType}');
      debugPrint(
        'ðŸ“ž localStream is MediaStream: ${localStream is MediaStream}',
      );
      if (localStream != null && localStream is! MediaStream) {
        debugPrint(
          'âš ï¸ localStream is not a MediaStream: ${localStream.runtimeType}',
        );
      }

      // Check widget state
      debugPrint('ðŸ“ž widget: available');
      debugPrint('ðŸ“ž widget.otherUser: available');

      debugPrint('ðŸ“ž Parameters validated - proceeding with navigation');
      debugPrint('ðŸ“ž remoteName: ${widget.otherUser.fullName}');
      debugPrint('ðŸ“ž callType: $callTypeStr');
      debugPrint(
        'ðŸ“ž localStream: ${localStream != null ? 'available' : 'null'}',
      );
      debugPrint('ðŸ“ž callService.callState: ${callService.callState}');
      debugPrint('ðŸ“ž callService.remoteUserId: ${callService.remoteUserId}');
      debugPrint(
        'ðŸ“ž callService.localStream: ${callService.localStream != null ? 'available' : 'null'}',
      );
      debugPrint(
        'ðŸ“ž callService.remoteStream: ${callService.remoteStream != null ? 'available' : 'null'}',
      );

      debugPrint('ðŸ“ž Creating MaterialPageRoute...');
      final route = MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) {
          debugPrint('ðŸ“ž Building ConnectedCallScreen widget');

          try {
            final remoteName = widget.otherUser.fullName;
            debugPrint('ðŸ“ž Using remoteName: $remoteName');

            return ConnectedCallScreen(
              remoteName: remoteName,
              callType: callTypeStr,
              callService: callService,
              localStream: localStream,
              onChatPressed: () {
                Navigator.of(context).pop(); // Return to chat
              },
            );
          } catch (e) {
            debugPrint('âŒ Error creating ConnectedCallScreen: $e');
            // Return a fallback widget
            return Scaffold(
              appBar: AppBar(title: const Text('Call Error')),
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error, size: 64, color: Colors.red),
                    const SizedBox(height: 16),
                    const Text('Failed to initialize call screen'),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Go Back'),
                    ),
                  ],
                ),
              ),
            );
          }
        },
      );

      debugPrint('ðŸ“ž MaterialPageRoute created, pushing...');
      final navigationResult = await navigator.push(route);

      debugPrint(
        'ðŸ“ž ConnectedCallScreen navigation completed for $callTypeStr call with result: $navigationResult',
      );
    } catch (e) {
      debugPrint(
        'âŒ Error navigating to ConnectedCallScreen for $callTypeStr call: $e',
      );
      debugPrint('âŒ Error type: ${e.runtimeType}');
      debugPrint('âŒ Stack trace: ${StackTrace.current}');

      // Try to show a user-friendly error
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to open call screen: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  /// Handle incoming file message from web
  // ignore: unused_element
  void _handleIncomingFileMessage(Map<String, dynamic> data) {
    final now = DateTime.now();
    final fileUrl = data['file_url'] as String?;
    final fileName = data['file_name'] as String? ?? 'File';
    final fileType = data['file_type'] as String? ?? 'application/octet-stream';
    final fileSize = data['file_size'] as int? ?? 0;
    final messageType = fileType.startsWith('image/')
        ? 'image'
        : fileType.startsWith('video/')
        ? 'video'
        : 'file';

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

    // Only auto-scroll if user is at bottom, otherwise just show unread badge
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isAtBottom) {
        _scrollToBottom();
      }
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
          _showFilePreviewModal(
            File(file.path!),
            file.name,
            isFromCamera: false,
          );
        }
      }
    } catch (e) {
      debugPrint('Error picking file: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error picking file: $e')));
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
        preferredCameraDevice: _useFrontCamera
            ? CameraDevice.front
            : CameraDevice.rear,
      );

      if (photo != null) {
        _showFilePreviewModal(File(photo.path), photo.name, isFromCamera: true);
      }
    } catch (e) {
      debugPrint('Error taking photo: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error accessing camera: $e')));
      }
    }
  }

  /// Show file preview modal before sending
  void _showFilePreviewModal(
    File file,
    String fileName, {
    bool isFromCamera = false,
  }) {
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
                          child: Image.file(file, fit: BoxFit.contain),
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
                                Icon(
                                  Icons.videocam,
                                  color: Colors.white,
                                  size: 64,
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Video File',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                  ),
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
                          Icon(
                            _getFileIcon(mimeType),
                            color: Colors.white70,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  fileName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '${_formatFileSize(fileSize)} â€¢ $mimeType',
                                  style: TextStyle(
                                    color: Colors.grey[400],
                                    fontSize: 12,
                                  ),
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
                      label: Text(
                        _useFrontCamera
                            ? 'Switch to Back Camera'
                            : 'Switch to Front Camera',
                      ),
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
                          icon: Icon(
                            isFromCamera ? Icons.camera_alt : Icons.refresh,
                          ),
                          label: Text(
                            isFromCamera ? 'Take Another' : 'Replace',
                          ),
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
    if (mimeType.contains('word') || mimeType.contains('document')) {
      return Icons.description;
    }
    if (mimeType.contains('excel') || mimeType.contains('spreadsheet')) {
      return Icons.table_chart;
    }
    if (mimeType.contains('zip') || mimeType.contains('archive')) {
      return Icons.folder_zip;
    }
    return Icons.insert_drive_file;
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// Show voice recording modal
  Future<void> _showVoiceRecordingModal() async {
    // Request microphone permission
    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Microphone permission is required to record voice messages',
            ),
            action: SnackBarAction(
              label: 'Settings',
              onPressed: () => openAppSettings(),
            ),
          ),
        );
      }
      return;
    }

    if (!mounted) return;

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
  /// Behaves like FB Messenger: emoji picker replaces the keyboard.
  void _showEmojiPickerModal(BuildContext context) {
    if (_showEmojiPicker) {
      // Closing emoji picker â†’ bring keyboard back
      setState(() {
        _showEmojiPicker = false;
      });
      _inputFocusNode.requestFocus();
    } else {
      // Opening emoji picker â†’ dismiss keyboard first
      _inputFocusNode.unfocus();
      setState(() {
        _showEmojiPicker = true;
      });
    }
  }

  // Emoji category tab index
  int _emojiCategoryIndex = 0;

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

  // Some newer emoji code points are not available on older Android emoji fonts.
  // Normalize them to broadly supported alternatives for consistent rendering.
  static const Map<String, String> _emojiCompatibilityFallbacks = {
    '🩷': '💗',
    '🩵': '💙',
    '🩶': '🤍',
    '🫶': '🤝',
    '🫵': '👉',
    '🫱': '👈',
    '🫲': '👉',
    '🫳': '👇',
    '🫴': '🖐️',
    '🫰': '👌',
    '🫠': '🙂',
    '🫡': '👍',
    '🫣': '🙈',
    '🫢': '🤐',
    '🫥': '😶',
    '🫨': '😲',
    '🫦': '💋',
    '🫀': '❤️',
    '🫁': '💨',
    '🩻': '🦴',
    '🩼': '🦯',
  };

  bool _isPotentiallyUnsupportedEmoji(String emoji) {
    for (final rune in emoji.runes) {
      if (rune >= 0x1FA70 && rune <= 0x1FAFF) {
        return true;
      }
    }
    return false;
  }

  String _normalizeEmojiForCompatibility(String emoji) {
    final mapped = _emojiCompatibilityFallbacks[emoji];
    if (mapped != null) {
      return mapped;
    }

    // Skip unmapped symbols in newer emoji blocks to avoid tofu squares.
    if (_isPotentiallyUnsupportedEmoji(emoji)) {
      return '';
    }

    return emoji;
  }

  List<String> _normalizedEmojiList(List<String> emojis) {
    final normalized = <String>[];
    final seen = <String>{};

    for (final emoji in emojis) {
      final safeEmoji = _normalizeEmojiForCompatibility(emoji);
      if (safeEmoji.isEmpty) {
        continue;
      }

      if (seen.add(safeEmoji)) {
        normalized.add(safeEmoji);
      }
    }

    return normalized;
  }

  String _normalizeTextForEmojiCompatibility(String text) {
    var normalized = text;

    for (final entry in _emojiCompatibilityFallbacks.entries) {
      normalized = normalized.replaceAll(entry.key, entry.value);
    }

    final buffer = StringBuffer();
    for (final rune in normalized.runes) {
      if (rune >= 0x1FA70 && rune <= 0x1FAFF) {
        continue;
      }
      buffer.writeCharCode(rune);
    }

    return buffer.toString();
  }

  void _replaceInputTextWithSanitized(String sanitizedText) {
    final selection = _messageController.selection;
    final rawOffset = selection.baseOffset;
    final safeOffset = rawOffset < 0
        ? sanitizedText.length
        : rawOffset.clamp(0, sanitizedText.length).toInt();

    _messageController.value = TextEditingValue(
      text: sanitizedText,
      selection: TextSelection.collapsed(offset: safeOffset),
      composing: TextRange.empty,
    );
  }

  /// Build inline emoji picker widget with category tabs
  Widget _buildInlineEmojiPicker() {
    final category = _emojiCategories[_emojiCategoryIndex];
    final emojis = _normalizedEmojiList(category['emojis'] as List<String>);

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
                final icon = _normalizeEmojiForCompatibility(
                  cat['icon'] as String,
                );
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
                        icon.isEmpty ? '🙂' : icon,
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

                    // Trigger text changed and rebuild UI
                    _onTextChanged(newText);
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

  /// Upload and send voice message
  Future<void> _uploadAndSendVoiceMessage(
    String path,
    Duration duration,
  ) async {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);

    try {
      // Show uploading indicator
      messenger.showSnackBar(
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

      if (!mounted) return;

      // Hide uploading indicator
      messenger.hideCurrentSnackBar();

      if (result != null && result['success'] == true) {
        final fileData = result['file'] ?? result;

        // NOTE: The REST API upload already emits file_message to the recipient,
        // so we do NOT emit send_file here to avoid duplicate messages on the web.

        // Check if the fileReceived socket handler already added this message
        // (race condition: socket event can arrive before REST response)
        final serverId = fileData['message_id'];
        if (serverId != null && _messages.any((m) => m.id == serverId)) {
          debugPrint(
            'ðŸŽ¤ Voice message already added by socket handler, skipping local insert',
          );
        } else {
          // Create local message to show in chat
          final now = DateTime.now();
          final message = Message(
            id: serverId ?? DateTime.now().millisecondsSinceEpoch,
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

          if (!mounted) return;
          setState(() {
            _messages.insert(0, message);
          });
        }

        // Scroll to bottom
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToBottom();
        });

        messenger.showSnackBar(
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
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Failed to send voice message'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error uploading voice message: $e');
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text('Error sending voice message: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Upload file to server and send via socket
  Future<void> _uploadAndSendFile(
    File file,
    String fileName,
    String mimeType,
  ) async {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);

    try {
      // Show uploading indicator
      messenger.showSnackBar(
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

      // Create MultipartFile with explicit content type so server knows the MIME type
      final multipartFile = await http.MultipartFile.fromPath(
        'file',
        file.path,
        filename: fileName,
        contentType: MediaType.parse(mimeType),
      );

      // Upload file using MessageService
      final result = await MessageService.uploadFile(
        file: multipartFile,
        recipientId: widget.otherUser.id,
      );

      if (!mounted) return;

      // Hide uploading indicator
      messenger.hideCurrentSnackBar();

      if (result != null && result['success'] == true) {
        final fileData = result['file'] ?? result;

        // NOTE: The REST API upload already creates the DB message and emits
        // file_message to the recipient, so we do NOT emit send_file here to
        // avoid duplicate messages. Cross-device sync is handled by the REST
        // endpoint emitting to the sender's room as well.

        // Check if the fileReceived socket handler already added this message
        // (race condition: socket event can arrive before REST response)
        final serverId = fileData['message_id'];
        if (serverId != null && _messages.any((m) => m.id == serverId)) {
          debugPrint(
            'ðŸ“Ž File message already added by socket handler, skipping local insert',
          );
        } else {
          // Create local message to show in chat
          // Use server message_id so the fileReceived dedup check catches the echo
          final now = DateTime.now();
          final message = Message(
            id: serverId ?? DateTime.now().millisecondsSinceEpoch,
            senderId: _currentUserId!,
            recipientId: widget.otherUser.id,
            content: fileName,
            messageType: mimeType.startsWith('image/')
                ? 'image'
                : mimeType.startsWith('video/')
                ? 'video'
                : 'file',
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

          if (!mounted) return;
          setState(() {
            _messages.insert(0, message);
          });
        }
        _scrollToBottom();

        messenger.showSnackBar(
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
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to send file: $e')),
      );
    }
  }

  @override
  void dispose() {
    _taskBadgeAnimController.dispose();
    _taskModalVersion.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    _audioPlayer.dispose();
    for (final p in _activeDoorbellPlayers) {
      p.dispose();
    }
    _activeDoorbellPlayers.clear();
    _inputFocusNode.dispose();
    _typingTimer?.cancel();
    _typingHideTimer?.cancel();
    _typingUpdateThrottle?.cancel();
    _lastSeenRefreshTimer?.cancel();

    // Send typing stop without setState (widget is being disposed)
    _socketService.stopTyping(widget.otherUser.id);

    // Leave chat room
    _socketService.leaveChat(widget.otherUser.id);

    // Clear active chat so FCM notifications resume for this user
    ActiveChatService().clearActiveChat();

    // Clear all chat socket listeners (does NOT affect lobby listeners)
    _socketService.removeListenersForKey('chat');

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = _uiScale(context);
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
        titleSpacing: 0,
        title: GestureDetector(
          onTap: () => _showUserProfile(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 15 * scale,
                backgroundColor: _getAvatarColor(),
                child: Text(
                  widget.otherUser.initials,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12 * scale,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              SizedBox(width: 8 * scale),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.otherUser.fullName.split(' ').first,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15 * scale,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    _buildHeaderStatusPill(),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          // Video call button
          IconButton(
            icon: Icon(Icons.videocam, color: Colors.white, size: 24 * scale),
            onPressed: () => _showCallSetupModal(CallType.video),
            tooltip: 'Video Call',
          ),
          // Audio call button
          IconButton(
            icon: Icon(Icons.call, color: Colors.white, size: 24 * scale),
            onPressed: () => _showCallSetupModal(CallType.audio),
            tooltip: 'Audio Call',
          ),
          // Dedicated task button with animated count badge
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                icon: Icon(Icons.task_alt, color: Colors.white, size: 24 * scale),
                onPressed: _showTasksModal,
                tooltip: 'Tasks',
              ),
              Builder(
                builder: (context) {
                  final count = _messages.where((m) => m.isTask).length;
                  if (count == 0) return const SizedBox.shrink();
                  return Positioned(
                    right: 4,
                    top: 4,
                    child: ScaleTransition(
                      scale: _taskBadgeScale,
                      child: Container(
                        padding: EdgeInsets.all(2 * scale),
                        constraints: BoxConstraints(
                          minWidth: 16 * scale,
                          minHeight: 16 * scale,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.black.withValues(alpha: 0.3),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          '$count',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9 * scale,
                            fontWeight: FontWeight.w800,
                            height: 1.0,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          // Excalidraw button with count badge
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                icon: Icon(Icons.draw_outlined, color: Colors.white, size: 24 * scale),
                onPressed: _showExcalidrawModal,
                tooltip: 'Excalidraw',
              ),
              Builder(
                builder: (context) {
                  final count = _pinnedExcalidrawLinks.length;
                  if (count == 0) return const SizedBox.shrink();
                  return Positioned(
                    right: 4,
                    top: 4,
                    child: Container(
                      padding: EdgeInsets.all(2 * scale),
                      constraints: BoxConstraints(
                        minWidth: 16 * scale,
                        minHeight: 16 * scale,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF7C3AED),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.black.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        '$count',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 9 * scale,
                          fontWeight: FontWeight.w800,
                          height: 1.0,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
      body: GestureDetector(
        onTap: () {
          FocusScope.of(context).unfocus();
          if (_selectedTaskActionMessageId != null) {
            setState(() {
              _selectedTaskActionMessageId = null;
            });
          }
        },
        behavior: HitTestBehavior.translucent,
        child: Stack(
          children: [
            Column(
              children: [
                // Messages list
                Expanded(
                  child: _isLoading
                      ? _buildChatShimmer()
                      : _messages.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.chat_bubble_outline,
                                size: 64 * scale,
                                color: Colors.grey[700],
                              ),
                              SizedBox(height: 16 * scale),
                              Text(
                                'No messages yet',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 16 * scale,
                                ),
                              ),
                              SizedBox(height: 8 * scale),
                              Text(
                                'Send a message to start the conversation',
                                style: TextStyle(
                                  color: Colors.grey[700],
                                  fontSize: 14 * scale,
                                ),
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
                                padding: EdgeInsets.fromLTRB(
                                  16 * scale,
                                  16 * scale,
                                  16 * scale,
                                  4 * scale,
                                ),
                                physics: const BouncingScrollPhysics(
                                  parent: AlwaysScrollableScrollPhysics(),
                                ),
                                cacheExtent: 500,
                                itemCount: _messages.length,
                                addAutomaticKeepAlives: false,
                                addRepaintBoundaries: true,
                                itemBuilder: (context, index) {
                                  final message = _messages[index];
                                  final isSentByMe =
                                      message.senderId == _currentUserId;

                                  // Check if we need to show date separator
                                  // Since list is reversed, check the NEXT message (index + 1) for date change
                                  Widget? dateSeparator;
                                  if (index < _messages.length - 1) {
                                    final nextMessage = _messages[index + 1];
                                    if (!_isSameDay(
                                      message.timestamp,
                                      nextMessage.timestamp,
                                    )) {
                                      dateSeparator = _buildDateSeparator(
                                        message.timestamp,
                                      );
                                    }
                                  } else {
                                    // First message (oldest) always shows date
                                    dateSeparator = _buildDateSeparator(
                                      message.timestamp,
                                    );
                                  }

                                  return Column(
                                    children: [
                                      ?dateSeparator,
                                      // System messages (call summaries) render as a centered pill
                                      if (message.messageType == 'system')
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 6,
                                          ),
                                          child: Center(
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 14,
                                                    vertical: 5,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.white.withValues(
                                                  alpha: 0.08,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                              ),
                                              child: Text(
                                                message.content,
                                                style: TextStyle(
                                                  color: Colors.grey[400],
                                                  fontSize: 12,
                                                  fontStyle: FontStyle.italic,
                                                ),
                                              ),
                                            ),
                                          ),
                                        )
                                      else
                                        _buildSwipeableMessage(
                                          message,
                                          isSentByMe,
                                          _buildMessageBubble(
                                            message,
                                            isSentByMe,
                                          ),
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
                                      width: 48 * scale,
                                      height: 48 * scale,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF7C3AED),
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: 0.3,
                                            ),
                                            blurRadius: 8,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          Icon(
                                            Icons.keyboard_arrow_down,
                                            color: Colors.white,
                                            size: 28 * scale,
                                          ),
                                          if (_unreadCount > 0)
                                            Positioned(
                                              top: 2,
                                              right: 2,
                                              child: Container(
                                                padding: EdgeInsets.all(
                                                  4 * scale,
                                                ),
                                                decoration: const BoxDecoration(
                                                  color: Colors.red,
                                                  shape: BoxShape.circle,
                                                ),
                                                constraints:
                                                    BoxConstraints(
                                                      minWidth: 18 * scale,
                                                      minHeight: 18 * scale,
                                                    ),
                                                child: Text(
                                                  _unreadCount > 99
                                                      ? '99+'
                                                      : _unreadCount.toString(),
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 10 * scale,
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
                Container(
                  height: (_otherUserTyping && _typingPreview.isNotEmpty)
                      ? null
                      : 0,
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
                      left: 12 * scale,
                      right: 12 * scale,
                      top: 0,
                      bottom: 4 + MediaQuery.of(context).viewInsets.bottom,
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
                        // Quick bulk-send button above the input; in-flow layout avoids covering chat bubbles.
                        _buildSendToManyQuickAction(),
                        // Text input field with embedded emoji button and send button
                        RepaintBoundary(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
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
                                        onPressed: () =>
                                            _showEmojiPickerModal(context),
                                        icon: Icon(
                                          _showEmojiPicker
                                              ? Icons.keyboard_outlined
                                              : Icons
                                                    .sentiment_satisfied_alt_outlined,
                                          color: Colors.white70,
                                          size: 18 * scale,
                                        ),
                                        padding: EdgeInsets.all(4 * scale),
                                        constraints: const BoxConstraints(),
                                        tooltip: _showEmojiPicker
                                            ? 'Keyboard'
                                            : 'Emoji',
                                      ),
                                      // Text input
                                      Expanded(
                                        child: TextField(
                                          key: const ValueKey('message_input'),
                                          controller: _messageController,
                                          focusNode: _inputFocusNode,
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 14 * scale,
                                          ),
                                          decoration: InputDecoration(
                                            hintText: 'Type a message...',
                                            hintStyle: TextStyle(
                                              color: Colors.grey[600],
                                              fontSize: 14 * scale,
                                            ),
                                            border: InputBorder.none,
                                            filled: false,
                                            contentPadding:
                                                const EdgeInsets.only(
                                                  left: 0,
                                                  right: 4,
                                                  top: 10,
                                                  bottom: 10,
                                                ),
                                            isDense: true,
                                          ),
                                          onChanged: _onTextChanged,
                                          minLines: 1,
                                          maxLines: 5,
                                          textInputAction:
                                              TextInputAction.newline,
                                          keyboardType: TextInputType.multiline,
                                          textCapitalization:
                                              TextCapitalization.sentences,
                                          enableInteractiveSelection: true,
                                          autocorrect: true,
                                          enableSuggestions: true,
                                          stylusHandwritingEnabled: false,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              // Send button â€” always visible, vertically centred
                              Container(
                                margin: const EdgeInsets.only(left: 6),
                                child: ElevatedButton(
                                  onPressed: _sendMessage,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF6D28D9),
                                    foregroundColor: Colors.white,
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 12 * scale,
                                      vertical: 8 * scale,
                                    ),
                                    minimumSize: const Size(0, 0),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  child: Text(
                                    'Send',
                                    style: TextStyle(fontSize: 12 * scale),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Inline emoji picker (shown when active)
                        if (_showEmojiPicker) _buildInlineEmojiPicker(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Positioned.fill(child: _buildFloatingActionsToggle()),
          ],
        ),
      ),
    );
  }

  Widget _buildTypingPreviewBubble() {
    final scale = _uiScale(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16 * scale, vertical: 10 * scale),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFFA32CC4), // Purple color for typing preview
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          '${widget.otherUser.fullName}: $_typingPreview',
          style: TextStyle(color: Colors.white, fontSize: 15 * scale),
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
  bool _canQuickToggleTaskAction(Message message) {
    return message.messageType == 'text' && !message.isDeleted;
  }

  bool _isExcalidrawMessage(Message message) {
    if (message.isDeleted) return false;
    return _extractExcalidrawUrl(message.content) != null;
  }

  bool _canQuickToggleExcalidrawPin(Message message) {
    return _isExcalidrawMessage(message);
  }

  void _toggleTaskActionForMessage(Message message) {
    if (!_canQuickToggleTaskAction(message)) {
      if (_selectedTaskActionMessageId != null) {
        setState(() {
          _selectedTaskActionMessageId = null;
        });
      }
      return;
    }

    setState(() {
      _selectedTaskActionMessageId = _selectedTaskActionMessageId == message.id
          ? null
          : message.id;
    });
  }

  Widget _buildSwipeableMessage(
    Message message,
    bool isSentByMe,
    Widget child,
  ) {
    return _SwipeableMessage(
      key: ValueKey<String>('swipe_${message.id}'),
      isSentByMe: isSentByMe,
      onReply: () => _setReplyTo(message),
      onTap: () => _toggleTaskActionForMessage(message),
      onLongPress: () => _showMessageContextMenu(message, isSentByMe),
      child: child,
    );
  }

  /// Show context menu for message
  void _showMessageContextMenu(Message message, bool isSentByMe) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E2E),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFF7C3AED).withValues(alpha: 0.28),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF420796).withValues(alpha: 0.28),
                blurRadius: 24,
                spreadRadius: 0.2,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 5,
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Row(
                children: [
                  const Icon(
                    Icons.tune_rounded,
                    color: Color(0xFFB794F6),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Message Actions',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  if (message.isTask)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: const Color(
                            0xFFF59E0B,
                          ).withValues(alpha: 0.55),
                        ),
                      ),
                      child: const Text(
                        'Task',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              _buildContextMenuActionTile(
                icon: Icons.reply_rounded,
                label: 'Reply',
                onTap: () {
                  Navigator.pop(context);
                  _setReplyTo(message);
                },
              ),
              if (message.messageType == 'text' && !message.isDeleted)
                _buildContextMenuActionTile(
                  icon: Icons.copy_rounded,
                  label: 'Copy',
                  onTap: () {
                    Navigator.pop(context);
                    _copyMessageToClipboard(message);
                  },
                ),
              if (!isSentByMe &&
                  message.messageType == 'text' &&
                  !message.isDeleted &&
                  message.content.isNotEmpty)
                _buildContextMenuActionTile(
                  icon: _messageTranslations.containsKey(message.id)
                      ? Icons.translate_outlined
                      : Icons.translate,
                  label: _messageTranslations.containsKey(message.id)
                      ? 'Hide Translation'
                      : 'Translate',
                  iconColor: const Color(0xFF60A5FA),
                  onTap: () {
                    Navigator.pop(context);
                    _translateMessage(message);
                  },
                ),
              if (isSentByMe &&
                  message.messageType == 'text' &&
                  !message.isDeleted)
                _buildContextMenuActionTile(
                  icon: Icons.edit_rounded,
                  label: 'Edit',
                  onTap: () {
                    Navigator.pop(context);
                    _showEditMessageDialog(message);
                  },
                ),
              if (isSentByMe && !message.isDeleted)
                _buildContextMenuActionTile(
                  icon: Icons.delete_outline,
                  label: 'Delete',
                  iconColor: const Color(0xFFF87171),
                  textColor: const Color(0xFFFCA5A5),
                  tileColor: const Color(0xFF341E2A),
                  onTap: () {
                    Navigator.pop(context);
                    _showDeleteConfirmation(message);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContextMenuActionTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color iconColor = Colors.white,
    Color textColor = Colors.white,
    Color tileColor = const Color(0xFF252542),
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              color: tileColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Row(
                children: [
                  Icon(icon, color: iconColor, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white.withValues(alpha: 0.35),
                    size: 18,
                  ),
                ],
              ),
            ),
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
      _selectedTaskActionMessageId = null;
      final index = _messages.indexWhere((m) => m.id == message.id);
      if (index != -1) {
        _messages[index] = _copyMessageWithTaskState(
          message,
          isTask: true,
          taskCreatedAt: DateTime.now().toIso8601String(),
          taskCompletedAt: null,
        );
      }
    });
    _taskBadgeAnimController.forward(from: 0);
    _notifyTaskModalChanged();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Added to tasks'),
        duration: Duration(seconds: 2),
        backgroundColor: Color(0xFF4CAF50),
      ),
    );
  }

  /// Unmark message as task
  void _unmarkMessageTask(Message message) {
    _socketService.unmarkTask(message.id);

    setState(() {
      _selectedTaskActionMessageId = null;
      final index = _messages.indexWhere((m) => m.id == message.id);
      if (index != -1) {
        final currentMessage = _messages[index];
        _messages[index] = _copyMessageWithTaskState(
          currentMessage,
          isTask: false,
          taskCreatedAt: null,
          taskCompletedAt: null,
        );
      }

      _pendingLiveTaskCreatedAtByMessageId.remove(message.id);
      _pendingLiveTaskCompletedAtByMessageId.remove(message.id);
    });
    _taskBadgeAnimController.forward(from: 0);
    _notifyTaskModalChanged();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Removed from tasks'),
        duration: Duration(seconds: 2),
        backgroundColor: Color(0xFF4CAF50),
      ),
    );
  }

  /// Toggle excalidraw pin status
  Future<void> _toggleExcalidrawPin(Message message) async {
    final initialIndex = _messages.indexWhere((m) => m.id == message.id);
    if (initialIndex == -1) return;

    final originalMessage = _messages[initialIndex];
    final wasPinned = originalMessage.excalidrawPinnedAt != null;
    final hasExcalidrawUrl =
        _extractExcalidrawUrl(originalMessage.content) != null;

    // Optimistically update before the API response arrives.
    setState(() {
      _selectedTaskActionMessageId = null;
      _messages[initialIndex] = _copyMessageWithExcalidrawState(
        originalMessage,
        isExcalidrawLink: hasExcalidrawUrl,
        excalidrawPinnedAt: wasPinned ? null : DateTime.now().toIso8601String(),
      );
    });

    final success = wasPinned
        ? await MessageService.unpinExcalidrawLink(messageId: message.id)
        : await MessageService.pinExcalidrawLink(messageId: message.id);

    if (!mounted) return;

    if (!success) {
      setState(() {
        final currentIndex = _messages.indexWhere((m) => m.id == message.id);
        if (currentIndex != -1) {
          _messages[currentIndex] = originalMessage;
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            wasPinned
                ? 'Failed to unpin Excalidraw'
                : 'Failed to pin Excalidraw',
            style: const TextStyle(color: Colors.white),
          ),
          duration: const Duration(seconds: 2),
          backgroundColor: const Color(0xFFD32F2F),
        ),
      );
      return;
    }

    await _refreshMessages();

    if (!mounted) return;

    await _loadPinnedExcalidrawLinks();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          wasPinned ? 'Excalidraw unpinned' : 'Excalidraw pinned',
          style: const TextStyle(color: Colors.white),
        ),
        duration: const Duration(seconds: 2),
        backgroundColor: const Color(0xFF420796),
      ),
    );
  }

  /// Unpin Excalidraw from modal list with realtime socket event.
  Future<void> _unpinExcalidrawFromModal(Map<String, dynamic> link) async {
    final messageId = _toInt(link['id']);
    if (messageId == null) return;

    final messageIndex = _messages.indexWhere((m) => m.id == messageId);
    Message? originalMessage;

    setState(() {
      if (messageIndex != -1) {
        originalMessage = _messages[messageIndex];
        final hasExcalidrawUrl =
            _extractExcalidrawUrl(originalMessage!.content) != null;
        _messages[messageIndex] = _copyMessageWithExcalidrawState(
          originalMessage!,
          isExcalidrawLink: hasExcalidrawUrl,
          excalidrawPinnedAt: null,
        );
      }

      _pinnedExcalidrawLinks.removeWhere(
        (item) => _toInt(item['id']) == messageId,
      );
    });

    // Emit realtime socket event so other active clients update immediately.
    _socketService.unpinExcalidraw(messageId);

    final success = await MessageService.unpinExcalidrawLink(
      messageId: messageId,
    );

    if (!mounted) return;

    if (!success) {
      if (originalMessage != null) {
        setState(() {
          final index = _messages.indexWhere((m) => m.id == messageId);
          if (index != -1) {
            _messages[index] = originalMessage!;
          }
        });
      }

      await _loadPinnedExcalidrawLinks();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Failed to unpin Excalidraw',
            style: TextStyle(color: Colors.white),
          ),
          duration: Duration(seconds: 2),
          backgroundColor: Color(0xFFD32F2F),
        ),
      );
      return;
    }

    await _loadPinnedExcalidrawLinks();
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
        title: const Text(
          'Edit Message',
          style: TextStyle(color: Colors.white),
        ),
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

  /// Auto-translate incoming message (silent, no loading indicators)
  Future<void> _autoTranslateMessage(Message message) async {
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
          'ðŸŒ Auto-translated message ${message.id}: "${message.content}" â†’ "$translatedText"',
        );
      }
    } catch (e) {
      debugPrint('Auto-translation failed for message ${message.id}: $e');
      // Fail silently for auto-translation
    }
  }

  /// Translate a message manually
  Future<void> _translateMessage(Message message) async {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);

    try {
      // Check if already translated - toggle off if so
      if (_messageTranslations.containsKey(message.id)) {
        setState(() {
          _messageTranslations.remove(message.id);
        });
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Translation hidden'),
            duration: Duration(seconds: 1),
            backgroundColor: Color(0xFF6B7280),
          ),
        );
        return;
      }

      // Show loading indicator
      messenger.showSnackBar(
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

      if (!mounted) return;

      // Hide loading indicator
      messenger.hideCurrentSnackBar();

      if (translatedText != null && translatedText != message.content) {
        // Store translation and update UI
        setState(() {
          _messageTranslations[message.id] = translatedText;
        });

        messenger.showSnackBar(
          const SnackBar(
            content: Text('Message translated'),
            duration: Duration(seconds: 1),
            backgroundColor: Color(0xFF4CAF50),
          ),
        );
      } else if (translatedText == message.content) {
        // Same text, no translation needed
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Message is already in your language'),
            duration: Duration(seconds: 2),
            backgroundColor: Color(0xFF6B7280),
          ),
        );
      } else {
        // Translation failed
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Translation failed. Please try again.'),
            duration: Duration(seconds: 3),
            backgroundColor: Color(0xFFEF4444),
          ),
        );
      }
    } catch (e) {
      // Hide loading indicator
      if (!mounted) return;
      messenger.hideCurrentSnackBar();

      debugPrint('Translation error: $e');
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Translation failed. Please try again.'),
          duration: Duration(seconds: 3),
          backgroundColor: Color(0xFFEF4444),
        ),
      );
    }
  }

  /// Show delete confirmation dialog
  void _showDeleteConfirmation(Message message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text(
          'Delete Message',
          style: TextStyle(color: Colors.white),
        ),
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
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
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
    final messageId = _extractTaskMessageId(data);
    if (messageId == null) return;

    final payload = _extractTaskPayloadMap(data);

    setState(() {
      final index = _messages.indexWhere((m) => m.id == messageId);
      if (index == -1) {
        final createdAt = _extractTaskCreatedAt(data);
        final completedAt = _extractTaskCompletedAt(data);
        final payloadIsTask =
            (payload?['is_task'] as bool?) ??
            (data['is_task'] as bool?) ??
            createdAt != null || completedAt != null;
        if (payloadIsTask) {
          _pendingLiveTaskCreatedAtByMessageId[messageId] =
              _pendingLiveTaskCreatedAtByMessageId[messageId] ??
              createdAt ??
              DateTime.now().toIso8601String();
          if (completedAt != null) {
            _pendingLiveTaskCompletedAtByMessageId[messageId] = completedAt;
          }
        }
        return;
      }

      final message = _messages[index];

      if (payload != null) {
        final mergedPayload = <String, dynamic>{
          ...payload,
          'id':
              _toInt(payload['id']) ??
              _toInt(payload['message_id']) ??
              message.id,
          'sender_id': _toInt(payload['sender_id']) ?? message.senderId,
          'recipient_id':
              _toInt(payload['recipient_id']) ?? message.recipientId,
          'content': payload['content'] ?? message.content,
          'message_type': payload['message_type'] ?? message.messageType,
          'timestamp': payload['timestamp'] ?? message.timestamp,
          'timestamp_ms':
              _toInt(payload['timestamp_ms']) ?? message.timestampMs,
          'is_read': payload['is_read'] ?? message.isRead,
          'status': payload['status'] ?? message.status,
          'thread_id': payload['thread_id'] ?? message.threadId,
          'reply_to_id': payload['reply_to_id'] ?? message.replyToId,
          'reply_preview': payload['reply_preview'] ?? message.replyPreview,
          'reactions': payload['reactions'] ?? message.reactions,
          'file_url': payload['file_url'] ?? message.fileUrl,
          'file_name': payload['file_name'] ?? message.fileName,
          'file_size': payload['file_size'] ?? message.fileSize,
          'file_type': payload['file_type'] ?? message.fileType,
          'is_deleted': payload['is_deleted'] ?? message.isDeleted,
          'read_at': payload['read_at'] ?? message.readAt,
          'read_at_ms': payload['read_at_ms'] ?? message.readAtMs,
          'delivered_at': payload['delivered_at'] ?? message.deliveredAt,
          'delivered_at_ms':
              payload['delivered_at_ms'] ?? message.deliveredAtMs,
          'is_task':
              payload['is_task'] ??
              (data['is_task'] as bool?) ??
              message.isTask,
          'task_created_at':
              payload['task_created_at'] ??
              data['task_created_at'] ??
              data['created_at'] ??
              message.taskCreatedAt,
          'task_completed_at':
              payload['task_completed_at'] ??
              data['task_completed_at'] ??
              data['completed_at'] ??
              message.taskCompletedAt,
          'is_excalidraw_link':
              payload['is_excalidraw_link'] ?? message.isExcalidrawLink,
          'excalidraw_pinned_at':
              payload['excalidraw_pinned_at'] ?? message.excalidrawPinnedAt,
          'is_pinned': payload['is_pinned'] ?? message.isPinned,
          'pinned_at': payload['pinned_at'] ?? message.pinnedAt,
          'pinned_by_user_id':
              _toInt(payload['pinned_by_user_id']) ?? message.pinnedByUserId,
        };

        _messages[index] = _applyPendingLiveTaskState(
          Message.fromJson(mergedPayload),
        );
        return;
      }

      final newContent = data['content'] as String?;
      final hasTaskCompletedField =
          data.containsKey('task_completed_at') ||
          data.containsKey('completed_at');
      final updatedMessage = Message(
        id: message.id,
        senderId: message.senderId,
        recipientId: message.recipientId,
        content: newContent ?? message.content,
        messageType: (data['message_type'] as String?) ?? message.messageType,
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
        isTask: (data['is_task'] as bool?) ?? message.isTask,
        taskCreatedAt: _extractTaskCreatedAt(data) ?? message.taskCreatedAt,
        taskCompletedAt: hasTaskCompletedField
            ? _extractTaskCompletedAt(data)
            : message.taskCompletedAt,
        isExcalidrawLink: message.isExcalidrawLink,
        excalidrawPinnedAt: message.excalidrawPinnedAt,
        isPinned: message.isPinned,
        pinnedAt: message.pinnedAt,
        pinnedByUserId: message.pinnedByUserId,
      );
      _messages[index] = updatedMessage;
    });
    _notifyTaskModalChanged();
  }

  /// Handle task added event from socket
  void _handleTaskAdded(Map<String, dynamic> data) {
    final messageId = _extractTaskMessageId(data);
    if (messageId == null) return;

    final createdAt =
        _extractTaskCreatedAt(data) ?? DateTime.now().toIso8601String();

    setState(() {
      final index = _messages.indexWhere((m) => m.id == messageId);
      if (index != -1) {
        final message = _messages[index];
        final updatedMessage = _copyMessageWithTaskState(
          message,
          isTask: true,
          taskCreatedAt: createdAt,
          taskCompletedAt: null,
        );
        _messages[index] = updatedMessage;
      } else {
        _pendingLiveTaskCreatedAtByMessageId[messageId] = createdAt;
        _pendingLiveTaskCompletedAtByMessageId.remove(messageId);
      }
    });
    if (mounted) _taskBadgeAnimController.forward(from: 0);
    _notifyTaskModalChanged();
  }

  /// Handle task completed event from socket
  void _handleTaskCompleted(Map<String, dynamic> data) {
    final messageId = _extractTaskMessageId(data);
    if (messageId == null) return;

    final createdAt =
        _extractTaskCreatedAt(data) ?? DateTime.now().toIso8601String();
    final completedAt =
        _extractTaskCompletedAt(data) ?? DateTime.now().toIso8601String();

    setState(() {
      final index = _messages.indexWhere((m) => m.id == messageId);
      if (index != -1) {
        final message = _messages[index];
        final updatedMessage = _copyMessageWithTaskState(
          message,
          isTask: true,
          taskCreatedAt: message.taskCreatedAt ?? createdAt,
          taskCompletedAt: completedAt,
        );
        _messages[index] = updatedMessage;
      } else {
        _pendingLiveTaskCreatedAtByMessageId[messageId] =
            _pendingLiveTaskCreatedAtByMessageId[messageId] ?? createdAt;
        _pendingLiveTaskCompletedAtByMessageId[messageId] = completedAt;
      }
    });
    _notifyTaskModalChanged();
  }

  /// Handle task uncompleted event from socket
  void _handleTaskUncompleted(Map<String, dynamic> data) {
    final messageId = _extractTaskMessageId(data);
    if (messageId == null) return;

    final payload = _extractTaskPayloadMap(data);
    final explicitTaskState =
        (payload?['is_task'] as bool?) ?? (data['is_task'] as bool?);
    final shouldRemainTask = explicitTaskState ?? true;
    final createdAt =
        _extractTaskCreatedAt(data) ?? DateTime.now().toIso8601String();

    setState(() {
      final index = _messages.indexWhere((m) => m.id == messageId);
      if (index != -1) {
        final message = _messages[index];
        _messages[index] = _copyMessageWithTaskState(
          message,
          isTask: shouldRemainTask,
          taskCreatedAt: shouldRemainTask
              ? (message.taskCreatedAt ?? createdAt)
              : null,
          taskCompletedAt: null,
        );
      } else {
        if (shouldRemainTask) {
          _pendingLiveTaskCreatedAtByMessageId[messageId] =
              _pendingLiveTaskCreatedAtByMessageId[messageId] ?? createdAt;
        } else {
          _pendingLiveTaskCreatedAtByMessageId.remove(messageId);
        }
        _pendingLiveTaskCompletedAtByMessageId.remove(messageId);
      }
    });
    if (mounted) _taskBadgeAnimController.forward(from: 0);
    _notifyTaskModalChanged();
  }

  String? _extractExcalidrawPinnedAtFromEvent(Map<String, dynamic> data) {
    final directPinnedAt = _asNonEmptyString(data['pinned_at']);
    if (directPinnedAt != null) {
      return directPinnedAt;
    }

    final payload = data['message_data'];
    if (payload is Map<String, dynamic>) {
      return _asNonEmptyString(payload['excalidraw_pinned_at']) ??
          _asNonEmptyString(payload['pinned_at']);
    }
    if (payload is Map) {
      final mapped = Map<String, dynamic>.from(payload);
      return _asNonEmptyString(mapped['excalidraw_pinned_at']) ??
          _asNonEmptyString(mapped['pinned_at']);
    }

    return null;
  }

  /// Handle excalidraw pinned event from socket
  void _handleExcalidrawPinned(Map<String, dynamic> data) {
    final messageId = data['message_id'] as int?;
    if (messageId == null) return;

    final pinnedAt =
        _extractExcalidrawPinnedAtFromEvent(data) ??
        DateTime.now().toIso8601String();

    setState(() {
      final index = _messages.indexWhere((m) => m.id == messageId);
      if (index != -1) {
        final message = _messages[index];
        final hasExcalidrawUrl = _extractExcalidrawUrl(message.content) != null;
        final updatedMessage = _copyMessageWithExcalidrawState(
          message,
          isExcalidrawLink: hasExcalidrawUrl,
          excalidrawPinnedAt: pinnedAt,
        );
        _messages[index] = updatedMessage;

        // Add to pinned links if not already present
        if (!_pinnedExcalidrawLinks.any(
          (l) => (l['id'] as int?) == messageId,
        )) {
          _pinnedExcalidrawLinks.add({
            'id': messageId,
            'sender_id': message.senderId,
            'recipient_id': message.recipientId,
            'content': message.content,
            'is_excalidraw_link': hasExcalidrawUrl,
            'excalidraw_pinned_at': pinnedAt,
          });
        }
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
        final hasExcalidrawUrl = _extractExcalidrawUrl(message.content) != null;
        final updatedMessage = _copyMessageWithExcalidrawState(
          message,
          isExcalidrawLink: hasExcalidrawUrl,
          excalidrawPinnedAt: null,
        );
        _messages[index] = updatedMessage;
      }
      // Remove from pinned links
      _pinnedExcalidrawLinks.removeWhere((l) => (l['id'] as int?) == messageId);
    });
  }

  /// Safely parse any numeric type (int, double, String) to int.
  /// Socket.IO JSON may deliver numbers as double on some platforms.
  int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  String? _asNonEmptyString(dynamic value) {
    if (value == null) return null;
    final stringValue = value.toString();
    return stringValue.isEmpty ? null : stringValue;
  }

  Map<String, dynamic>? _extractTaskPayloadMap(Map<String, dynamic> data) {
    final payload = data['message_data'] ?? data['message'];
    if (payload is Map<String, dynamic>) {
      return payload;
    }
    if (payload is Map) {
      return Map<String, dynamic>.from(payload);
    }
    return null;
  }

  int? _extractTaskMessageId(Map<String, dynamic> data) {
    final directId =
        _toInt(data['message_id']) ??
        _toInt(data['messageId']) ??
        _toInt(data['id']);
    if (directId != null) {
      return directId;
    }

    final nestedMessage = _extractTaskPayloadMap(data);
    if (nestedMessage != null) {
      return _toInt(nestedMessage['message_id']) ??
          _toInt(nestedMessage['messageId']) ??
          _toInt(nestedMessage['id']);
    }

    return null;
  }

  String? _extractTaskCreatedAt(Map<String, dynamic> data) {
    final direct =
        _asNonEmptyString(data['task_created_at']) ??
        _asNonEmptyString(data['created_at']);
    if (direct != null && direct.isNotEmpty) {
      return direct;
    }

    final nestedMessage = _extractTaskPayloadMap(data);
    if (nestedMessage != null) {
      final nested =
          _asNonEmptyString(nestedMessage['task_created_at']) ??
          _asNonEmptyString(nestedMessage['created_at']);
      if (nested != null && nested.isNotEmpty) {
        return nested;
      }
    }

    return null;
  }

  String? _extractTaskCompletedAt(Map<String, dynamic> data) {
    final direct =
        _asNonEmptyString(data['task_completed_at']) ??
        _asNonEmptyString(data['completed_at']);
    if (direct != null && direct.isNotEmpty) {
      return direct;
    }

    final nestedMessage = _extractTaskPayloadMap(data);
    if (nestedMessage != null) {
      final nested =
          _asNonEmptyString(nestedMessage['task_completed_at']) ??
          _asNonEmptyString(nestedMessage['completed_at']);
      if (nested != null && nested.isNotEmpty) {
        return nested;
      }
    }

    return null;
  }

  /// Handle message status updates (delivered/seen)
  void _handleMessageStatusUpdate(Map<String, dynamic> data) {
    final messageId = _toInt(data['message_id']);
    final status = data['status'] as String?;
    final deliveredAt = data['delivered_at'] as String?;
    final readAt = data['read_at'] as String?;

    if (messageId == null || status == null) return;

    // Status priority â€” never downgrade (server may send 'seen' then 'delivered' out of order)
    const statusRank = {'sending': 0, 'sent': 1, 'delivered': 2, 'seen': 3};

    setState(() {
      final index = _messages.indexWhere((m) => m.id == messageId);
      if (index != -1) {
        final message = _messages[index];
        // Skip if incoming status is lower priority than current
        final currentRank = statusRank[message.status] ?? 0;
        final incomingRank = statusRank[status] ?? 0;
        if (incomingRank < currentRank) {
          debugPrint(
            'âš ï¸ Ignoring status downgrade for $messageId: ${message.status} â†’ $status',
          );
          return;
        }
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
          readAtMs: readAt != null
              ? DateTime.parse(readAt).millisecondsSinceEpoch
              : null,
          deliveredAt: deliveredAt ?? message.deliveredAt,
          deliveredAtMs: deliveredAt != null
              ? DateTime.parse(deliveredAt).millisecondsSinceEpoch
              : message.deliveredAtMs,
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

    debugPrint('ðŸ“Š Message $messageId status updated to: $status');
  }

  /// Handle messages read notifications
  void _handleMessagesRead(Map<String, dynamic> data) {
    final readerId = _toInt(data['reader_id']);
    final messageCount = _toInt(data['message_count']);

    if (readerId == widget.otherUser.id &&
        messageCount != null &&
        messageCount > 0) {
      debugPrint(
        'âœ“âœ“ ${widget.otherUser.fullName} read $messageCount messages',
      );

      // Update status of sent messages to 'seen'
      setState(() {
        for (int i = 0; i < _messages.length; i++) {
          final message = _messages[i];
          if (message.senderId == _currentUserId &&
              message.recipientId == widget.otherUser.id &&
              message.status != 'seen') {
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
    final mediaQuery = MediaQuery.of(context);
    final topOffset = mediaQuery.padding.top + kToolbarHeight + 6;
    final bottomOffset = 80.0; // Reserve space for input area
    final availableHeight = mediaQuery.size.height - topOffset - bottomOffset;
    final maxDialogHeight = availableHeight > 200 ? availableHeight : 200.0;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Tasks',
      barrierColor: Colors.black.withValues(alpha: 0.5),
      transitionDuration: const Duration(milliseconds: 320),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -0.08),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
      pageBuilder: (context, animation, secondaryAnimation) {
        return ValueListenableBuilder<int>(
          valueListenable: _taskModalVersion,
          builder: (context, _, __) {
            final tasks = _messages.where((m) => m.isTask).toList();
            final completedCount = tasks
                .where((t) => t.taskCompletedAt != null)
                .length;
            return Padding(
              padding: EdgeInsets.fromLTRB(10, topOffset, 10, 10),
              child: Align(
                alignment: Alignment.topCenter,
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    constraints: BoxConstraints(maxHeight: maxDialogHeight),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A2B),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 24,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFF2B2B48), Color(0xFF1F1F34)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(20),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFFF59E0B,
                                  ).withValues(alpha: 0.2),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: const Color(
                                      0xFFF59E0B,
                                    ).withValues(alpha: 0.6),
                                  ),
                                ),
                                child: const Icon(
                                  Icons.check_circle_outline,
                                  color: Color(0xFFFBBF24),
                                  size: 16,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Tasks',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.2,
                                ),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFFF59E0B,
                                  ).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: const Color(
                                      0xFFF59E0B,
                                    ).withValues(alpha: 0.5),
                                  ),
                                ),
                                child: Text(
                                  '$completedCount/${tasks.length}',
                                  style: const TextStyle(
                                    color: Color(0xFFFCD34D),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              InkWell(
                                onTap: () => Navigator.pop(context),
                                borderRadius: BorderRadius.circular(16),
                                child: Container(
                                  width: 26,
                                  height: 26,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.08),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.close,
                                    color: Colors.white70,
                                    size: 16,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Divider(
                          color: Colors.white.withValues(alpha: 0.08),
                          height: 1,
                        ),
                        Flexible(
                          child: tasks.isEmpty
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24,
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 50,
                                          height: 50,
                                          decoration: BoxDecoration(
                                            color: const Color(
                                              0xFFF59E0B,
                                            ).withValues(alpha: 0.14),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.task_alt,
                                            color: Color(0xFFFBBF24),
                                            size: 26,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          'No tasks yet',
                                          style: TextStyle(
                                            color: Colors.grey[300],
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Tap a message bubble, then tap "Mark as task"',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: Colors.grey[500],
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : GridView.builder(
                                  padding: const EdgeInsets.all(8),
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: 2,
                                        crossAxisSpacing: 6,
                                        mainAxisSpacing: 6,
                                        childAspectRatio: 1.2,
                                      ),
                                  itemCount: tasks.length,
                                  itemBuilder: (context, index) {
                                    final task = tasks[index];
                                    final isCompleted =
                                        task.taskCompletedAt != null;
                                    return Container(
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF252542),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: isCompleted
                                              ? const Color(
                                                  0xFF22C55E,
                                                ).withValues(alpha: 0.45)
                                              : Colors.white.withValues(
                                                  alpha: 0.07,
                                                ),
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                              8,
                                              6,
                                              6,
                                              4,
                                            ),
                                            child: Row(
                                              children: [
                                                InkWell(
                                                  onTap: () {
                                                    if (isCompleted) {
                                                      _socketService
                                                          .uncompleteTask(
                                                            task.id,
                                                          );
                                                    } else {
                                                      _socketService
                                                          .completeTask(
                                                            task.id,
                                                          );
                                                    }
                                                    Navigator.pop(context);
                                                    _refreshMessages();
                                                  },
                                                  child: Icon(
                                                    isCompleted
                                                        ? Icons.check_circle
                                                        : Icons.circle_outlined,
                                                    color: isCompleted
                                                        ? const Color(
                                                            0xFF22C55E,
                                                          )
                                                        : Colors.grey,
                                                    size: 18,
                                                  ),
                                                ),
                                                const Spacer(),
                                                InkWell(
                                                  onTap: () {
                                                    _removeTask(task);
                                                  },
                                                  child: const Icon(
                                                    Icons.delete_outline,
                                                    color: Color(0xFFF87171),
                                                    size: 16,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Expanded(
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.fromLTRB(
                                                    8,
                                                    0,
                                                    8,
                                                    6,
                                                  ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      task.content,
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 11,
                                                        decoration: isCompleted
                                                            ? TextDecoration
                                                                  .lineThrough
                                                            : null,
                                                        decorationColor:
                                                            Colors.grey,
                                                        fontWeight:
                                                            FontWeight.w500,
                                                        height: 1.3,
                                                      ),
                                                      maxLines: 4,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    task.formattedTime,
                                                    style: TextStyle(
                                                      color: Colors.grey[500],
                                                      fontSize: 9,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
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
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Remove task from message
  void _removeTask(Message message) {
    _unmarkMessageTask(message);
  }

  /// Show excalidraw modal
  void _showExcalidrawModal() {
    final excalidrawLinks = List<Map<String, dynamic>>.from(
      _pinnedExcalidrawLinks,
    );
    final mediaQuery = MediaQuery.of(context);
    final topOffset = mediaQuery.padding.top + kToolbarHeight + 6;
    final availableHeight = mediaQuery.size.height - topOffset - 10;
    final maxDialogHeight = availableHeight > 240 ? availableHeight : 240.0;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Excalidraw',
      barrierColor: Colors.black.withValues(alpha: 0.5),
      transitionDuration: const Duration(milliseconds: 320),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -0.08),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
      pageBuilder: (context, animation, secondaryAnimation) {
        return Padding(
          padding: EdgeInsets.fromLTRB(10, topOffset, 10, 10),
          child: Align(
            alignment: Alignment.topCenter,
            child: Material(
              color: Colors.transparent,
              child: SizedBox(
                height: maxDialogHeight,
                child: Container(
                  clipBehavior: Clip.hardEdge,
                  decoration: BoxDecoration(
                    color: const Color(0xFF191729),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 24,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.fromLTRB(14, 14, 12, 12),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFF2A2147), Color(0xFF1C1734)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(20),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF7C3AED,
                                ).withValues(alpha: 0.22),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(
                                    0xFF7C3AED,
                                  ).withValues(alpha: 0.65),
                                ),
                              ),
                              child: const Icon(
                                Icons.draw_outlined,
                                color: Color(0xFFC4B5FD),
                                size: 19,
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              'Excalidraw',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 19,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.2,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF7C3AED,
                                ).withValues(alpha: 0.22),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: const Color(
                                    0xFF7C3AED,
                                  ).withValues(alpha: 0.6),
                                ),
                              ),
                              child: Text(
                                '${excalidrawLinks.length} pinned',
                                style: const TextStyle(
                                  color: Color(0xFFE9D5FF),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            InkWell(
                              onTap: () => Navigator.pop(context),
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close,
                                  color: Colors.white70,
                                  size: 18,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Divider(
                        color: Colors.white.withValues(alpha: 0.08),
                        height: 1,
                      ),
                      Flexible(
                        child: excalidrawLinks.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 70,
                                        height: 70,
                                        decoration: BoxDecoration(
                                          color: const Color(
                                            0xFF7C3AED,
                                          ).withValues(alpha: 0.14),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.draw,
                                          color: Color(0xFFC4B5FD),
                                          size: 34,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        'No pinned Excalidraw links',
                                        style: TextStyle(
                                          color: Colors.grey[300],
                                          fontSize: 17,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Pin an Excalidraw link in chat to see it here',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Colors.grey[500],
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : GridView.builder(
                                padding: const EdgeInsets.all(8),
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 2,
                                      crossAxisSpacing: 6,
                                      mainAxisSpacing: 6,
                                      childAspectRatio: 1.2,
                                    ),
                                itemCount: excalidrawLinks.length,
                                itemBuilder: (context, index) {
                                  final link = excalidrawLinks[index];
                                  const isPinned = true;
                                  final content =
                                      (link['content'] as String?) ?? '';
                                  final extractedUrl = _extractExcalidrawUrl(
                                    content,
                                  );
                                  final displayText =
                                      (extractedUrl ?? content).trim().isEmpty
                                      ? 'Excalidraw link'
                                      : (extractedUrl ?? content).trim();
                                  return Container(
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF252542),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: isPinned
                                            ? const Color(
                                                0xFF7C3AED,
                                              ).withValues(alpha: 0.5)
                                            : Colors.white.withValues(
                                                alpha: 0.07,
                                              ),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                            8,
                                            6,
                                            6,
                                            4,
                                          ),
                                          child: Row(
                                            children: [
                                              InkWell(
                                                onTap: () async {
                                                  Navigator.pop(context);
                                                  await _unpinExcalidrawFromModal(
                                                    link,
                                                  );
                                                },
                                                child: Icon(
                                                  isPinned
                                                      ? Icons.push_pin
                                                      : Icons.push_pin_outlined,
                                                  color: isPinned
                                                      ? const Color(0xFFA78BFA)
                                                      : Colors.grey,
                                                  size: 18,
                                                ),
                                              ),
                                              const Spacer(),
                                              InkWell(
                                                onTap: () {
                                                  Navigator.pop(context);
                                                  if (extractedUrl != null) {
                                                    _openMessageUrl(
                                                      extractedUrl,
                                                    );
                                                  } else {
                                                    _openExcalidrawLink(
                                                      content,
                                                    );
                                                  }
                                                },
                                                child: const Icon(
                                                  Icons.open_in_new,
                                                  color: Color(0xFF60A5FA),
                                                  size: 16,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Expanded(
                                          child: Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                              8,
                                              0,
                                              8,
                                              6,
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    displayText,
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                      height: 1.3,
                                                    ),
                                                    maxLines: 4,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  _formatPinnedAt(
                                                    link['excalidraw_pinned_at']
                                                        as String?,
                                                  ),
                                                  style: TextStyle(
                                                    color: Colors.grey[500],
                                                    fontSize: 9,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
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
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatPinnedAt(String? pinnedAt) {
    if (pinnedAt == null) return '';
    try {
      final dt = DateTime.parse(pinnedAt).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inDays == 0) {
        final hour = dt.hour;
        final min = dt.minute.toString().padLeft(2, '0');
        final period = hour >= 12 ? 'PM' : 'AM';
        final h = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
        return '$h:$min $period';
      } else if (diff.inDays == 1) {
        return 'Yesterday';
      } else if (diff.inDays < 7) {
        return '${diff.inDays}d ago';
      } else {
        return '${dt.month}/${dt.day}/${dt.year}';
      }
    } catch (_) {
      return '';
    }
  }

  String? _extractExcalidrawUrl(String content) {
    for (final match in _excalidrawUrlRegex.allMatches(content)) {
      final rawUrl = match.group(0);
      if (rawUrl == null || rawUrl.isEmpty) continue;

      final cleanedUrl = _trimTrailingUrlCharacters(rawUrl);
      if (cleanedUrl.isEmpty) continue;

      final normalizedUrl = cleanedUrl.toLowerCase().startsWith('http')
          ? cleanedUrl
          : 'https://$cleanedUrl';

      final uri = Uri.tryParse(normalizedUrl);
      if (uri != null && uri.host.toLowerCase().contains('excalidraw.com')) {
        return normalizedUrl;
      }
    }

    return null;
  }

  /// Open excalidraw link in browser
  void _openExcalidrawLink(String content) {
    final extractedUrl = _extractExcalidrawUrl(content);
    if (extractedUrl == null) {
      return;
    }

    _openMessageUrl(extractedUrl);
  }

  String _trimTrailingUrlCharacters(String url) {
    const trailingPunctuation = '.,!?;:';
    var trimmed = url;

    while (trimmed.isNotEmpty &&
        trailingPunctuation.contains(trimmed[trimmed.length - 1])) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }

    while (trimmed.endsWith(')')) {
      final openParens = '('.allMatches(trimmed).length;
      final closeParens = ')'.allMatches(trimmed).length;
      if (closeParens <= openParens) {
        break;
      }
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }

    return trimmed;
  }

  Future<void> _openMessageUrl(String rawUrl) async {
    final normalizedUrl = rawUrl.toLowerCase().startsWith('http')
        ? rawUrl
        : 'https://$rawUrl';
    final uri = Uri.tryParse(normalizedUrl);

    if (uri == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid link'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    var opened = false;

    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Failed to open URL externally: $e');
    }

    if (!opened) {
      try {
        opened = await launchUrl(uri, mode: LaunchMode.platformDefault);
      } catch (e) {
        debugPrint('Failed to open URL with platform default mode: $e');
      }
    }

    if (opened) {
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Could not open: $normalizedUrl'),
        backgroundColor: Colors.red,
      ),
    );
  }

  List<InlineSpan> _buildLinkifiedTextSpans(String text, TextStyle baseStyle) {
    final linkStyle = baseStyle.copyWith(
      color: const Color(0xFF93C5FD),
      decoration: TextDecoration.underline,
      decorationColor: const Color(0xFF93C5FD),
    );

    final spans = <InlineSpan>[];
    var cursor = 0;

    for (final match in _messageUrlRegex.allMatches(text)) {
      if (match.start > cursor) {
        spans.add(
          TextSpan(text: text.substring(cursor, match.start), style: baseStyle),
        );
      }

      final matchedText = match.group(0) ?? '';
      final cleanedUrl = _trimTrailingUrlCharacters(matchedText);
      final trailing = matchedText.substring(cleanedUrl.length);

      if (cleanedUrl.isNotEmpty) {
        spans.add(
          TextSpan(
            text: cleanedUrl,
            style: linkStyle,
            recognizer: TapGestureRecognizer()
              ..onTap = () {
                _openMessageUrl(cleanedUrl);
              },
          ),
        );
      }

      if (trailing.isNotEmpty) {
        spans.add(TextSpan(text: trailing, style: baseStyle));
      }

      cursor = match.end;
    }

    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor), style: baseStyle));
    }

    if (spans.isEmpty) {
      spans.add(TextSpan(text: text, style: baseStyle));
    }

    return spans;
  }

  Widget _buildLinkifiedMessageText({
    required String text,
    required bool isTaskMessage,
    required Color taskAccentColor,
  }) {
    final scale = _uiScale(context);
    final baseStyle = TextStyle(color: Colors.white, fontSize: 15 * scale);
    final spans = _buildLinkifiedTextSpans(text, baseStyle);

    if (isTaskMessage) {
      return Text.rich(
        TextSpan(
          children: [
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Container(
                width: 18 * scale,
                height: 18 * scale,
                margin: EdgeInsets.only(right: 6 * scale),
                decoration: BoxDecoration(
                  color: taskAccentColor.withValues(alpha: 0.25),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: taskAccentColor.withValues(alpha: 0.75),
                    width: 1.2,
                  ),
                ),
                child: Center(
                  child: Text(
                    'T',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9 * scale,
                      fontWeight: FontWeight.w800,
                      height: 1.0,
                    ),
                  ),
                ),
              ),
            ),
            ...spans,
          ],
        ),
      );
    }

    return Text.rich(TextSpan(children: spans));
  }

  /// Refresh messages from server
  Future<void> _refreshMessages() async {
    try {
      final messages = await MessageService.getConversationMessages(
        userId: widget.otherUser.id,
        limit: 50,
        offlineFirst: false,
      );
      setState(() {
        _messages = messages.reversed.toList();
        _databaseLoadedMessageIds
          ..clear()
          ..addAll(
            _messages
                .where((message) => message.id > 0)
                .map((message) => message.id),
          );
      });
      _notifyTaskModalChanged();
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
    } else if (message.messageType == 'voice' ||
        message.messageType == 'audio') {
      content = 'ðŸŽ¤ Voice message';
    } else if (message.messageType == 'image') {
      content = 'ðŸ“· Photo';
    } else if (message.messageType == 'video') {
      content = 'ðŸŽ¬ Video';
    } else if (message.messageType == 'file') {
      content = 'ðŸ“Ž ${message.fileName ?? "File"}';
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
          left: BorderSide(color: const Color(0xFF7C3AED), width: 4),
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
                  style: TextStyle(color: Colors.grey[400], fontSize: 13),
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
        final months = [
          'Jan',
          'Feb',
          'Mar',
          'Apr',
          'May',
          'Jun',
          'Jul',
          'Aug',
          'Sep',
          'Oct',
          'Nov',
          'Dec',
        ];
        final weekday = weekdays[date.weekday - 1];
        final month = months[date.month - 1];
        dateText = '$weekday. $month ${date.day}, ${date.year}';
      }

      final scale = _uiScale(context);
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 16 * scale),
        child: Center(
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 16 * scale, vertical: 8 * scale),
            decoration: BoxDecoration(
              color: const Color(0xFF3D4752), // Dark gray like the image
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              dateText,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13 * scale,
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

  /// Ensure emoji uses color presentation (appends U+FE0F if needed)
  /// Characters like â¤ (U+2764) render as black text on Android without this.
  String _ensureColorEmoji(String emoji) {
    const variationSelector = '\uFE0F';
    // Characters that need the variation selector for color rendering
    const needsSelector = <int>{
      0x2764, // â¤
      0x2602, // â˜‚
      0x2614, // â˜”
      0x263A, // â˜º
      0x2B50, // â­
      0x2600, // â˜€
      0x2601, // â˜
      0x260E, // â˜Ž
      0x2709, // âœ‰
      0x270F, // âœ
      0x2744, // â„
      0x2728, // âœ¨
      0x2702, // âœ‚
      0x26A1, // âš¡
      0x2615, // â˜•
    };
    if (emoji.isNotEmpty &&
        needsSelector.contains(emoji.runes.first) &&
        !emoji.contains(variationSelector)) {
      return emoji + variationSelector;
    }
    return emoji;
  }

  /// Build reaction pills for a message
  Widget _buildReactionPills(int messageId) {
    final reactions = _messageReactions[messageId];
    if (reactions == null || reactions.isEmpty) {
      return const SizedBox.shrink();
    }

    final currentUserStr = _currentUserId?.toString() ?? '';
    final pills = <Widget>[];
    reactions.forEach((emoji, users) {
      if (users.isNotEmpty) {
        final iReacted = users.contains(currentUserStr);
        final displayEmoji = _ensureColorEmoji(emoji);
        pills.add(
          GestureDetector(
            onTap: () => _showReactorsSheet(messageId),
            child: Container(
              margin: const EdgeInsets.only(right: 2),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: iReacted
                    ? const Color(0xFF3A3A5C) // Highlighted if you reacted
                    : const Color(0xFF2C2C2E),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: iReacted
                      ? const Color(0xFF6D28D9).withValues(alpha: 0.5)
                      : Colors.white.withValues(alpha: 0.15),
                  width: iReacted ? 1.0 : 0.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(displayEmoji, style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 2),
                  Text(
                    '${users.length}',
                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    });

    if (pills.isEmpty) return const SizedBox.shrink();

    return Wrap(spacing: 2, runSpacing: 2, children: pills);
  }

  /// Toggle reaction (add or remove specific emoji, supports multiple reactions per user)
  void _toggleReaction(int messageId, String emoji) {
    // Backend set_reaction now handles toggle: if user has this emoji it removes it,
    // if not it adds it. User can have multiple different emojis on same message.
    _socketService.setReaction(messageId, emoji);
    debugPrint('ðŸ‘† Toggling reaction $emoji on message $messageId');
  }

  /// Resolve a user ID string to a display name for the reactions sheet.
  String _resolveReactorName(String odorIdStr) {
    final currentUserStr = _currentUserId?.toString() ?? '';
    if (odorIdStr == currentUserStr) return 'You';
    if (odorIdStr == widget.otherUser.id.toString()) {
      return widget.otherUser.fullName;
    }
    return 'User $odorIdStr';
  }

  /// Show bottom sheet listing who reacted to a message (WhatsApp-style)
  /// Tapping your own reaction row removes it.
  void _showReactorsSheet(int messageId) {
    final reactions = _messageReactions[messageId];
    if (reactions == null || reactions.isEmpty) return;

    final currentUserStr = _currentUserId?.toString() ?? '';

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const Text(
                  'Reactions',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                ...reactions.entries.where((e) => e.value.isNotEmpty).map((
                  entry,
                ) {
                  final emoji = entry.key;
                  final users = entry.value;
                  final iReacted = users.contains(currentUserStr);
                  // Resolve user IDs to display names
                  final displayNames = users
                      .map((id) => _resolveReactorName(id))
                      .toList();
                  return GestureDetector(
                    onTap: iReacted
                        ? () {
                            // Remove your reaction and close sheet
                            _toggleReaction(messageId, emoji);
                            Navigator.of(ctx).pop();
                          }
                        : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 8,
                      ),
                      margin: const EdgeInsets.only(bottom: 4),
                      decoration: BoxDecoration(
                        color: iReacted
                            ? const Color(0xFF2A2A3E)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Text(
                            _ensureColorEmoji(emoji),
                            style: const TextStyle(fontSize: 24),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  displayNames.join(', '),
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 14,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 2,
                                ),
                                if (iReacted)
                                  const Text(
                                    'Tap to remove',
                                    style: TextStyle(
                                      color: Color(0xFF9B59B6),
                                      fontSize: 11,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Text(
                            '${users.length}',
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Show reaction picker for a message
  void _showReactionPicker(
    BuildContext context,
    int messageId,
    Offset position,
  ) {
    ReactionPicker.show(
      context: context,
      position: position,
      onReactionSelected: (emoji) {
        _socketService.setReaction(messageId, emoji);
      },
    );
  }

  Widget _buildMessageBubble(Message message, bool isSentByMe) {
    final scale = _uiScale(context);
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
    final hasReactions =
        _messageReactions[message.id] != null &&
        _messageReactions[message.id]!.isNotEmpty;
    final isTaskMessage = message.isTask;
    final isTaskCompleted = message.taskCompletedAt != null;
    final isPinnedExcalidraw =
        _canQuickToggleExcalidrawPin(message) &&
        message.excalidrawPinnedAt != null;
    const excalidrawAccentColor = Color(0xFFB794F6);
    final taskAccentColor = isTaskCompleted
        ? const Color(0xFF22C55E)
        : const Color(0xFFF59E0B);
    final bubbleAccentColor = isTaskMessage
        ? taskAccentColor
        : (isPinnedExcalidraw ? excalidrawAccentColor : null);

    // Build the main bubble widget (without Align - alignment handled in return)
    final bubbleWidget = Container(
      margin: EdgeInsets.only(bottom: hasReactions ? 2 : 12),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * (scale < 0.9 ? 0.82 : 0.70),
      ),
      decoration: BoxDecoration(
        color: isSentByMe ? const Color(0xFF420796) : const Color(0xFF3944BC),
        border: bubbleAccentColor != null
            ? Border.all(
                color: bubbleAccentColor.withValues(alpha: 0.85),
                width: 1.4,
              )
            : null,
        boxShadow: bubbleAccentColor != null
            ? [
                BoxShadow(
                  color: bubbleAccentColor.withValues(alpha: 0.45),
                  blurRadius: 14,
                  spreadRadius: 0.2,
                ),
              ]
            : null,
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
          if (_selectedTaskActionMessageId == message.id &&
              _canQuickToggleTaskAction(message))
            Padding(
              padding: EdgeInsets.fromLTRB(12 * scale, 10 * scale, 12 * scale, 2),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  OutlinedButton(
                    onPressed: () {
                      if (message.isTask) {
                        _unmarkMessageTask(message);
                      } else {
                        _addMessageToTask(message);
                      }
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.8),
                      ),
                      backgroundColor: const Color(
                        0xFFF59E0B,
                      ).withValues(alpha: 0.16),
                      padding: EdgeInsets.symmetric(
                        horizontal: 12 * scale,
                        vertical: 7 * scale,
                      ),
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                      textStyle: TextStyle(
                        fontSize: 13 * scale,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    child: Text(
                      message.isTask ? 'Unmark task' : 'Mark as task',
                    ),
                  ),
                  if (_canQuickToggleExcalidrawPin(message))
                    OutlinedButton(
                      onPressed: () => _toggleExcalidrawPin(message),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                          color: const Color(0xFFB794F6).withValues(alpha: 0.8),
                        ),
                        backgroundColor: const Color(
                          0xFFB794F6,
                        ).withValues(alpha: 0.14),
                        padding: EdgeInsets.symmetric(
                          horizontal: 12 * scale,
                          vertical: 7 * scale,
                        ),
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                        textStyle: TextStyle(
                          fontSize: 13 * scale,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      child: Text(
                        message.excalidrawPinnedAt != null
                            ? 'Unpin Excalidraw'
                            : 'Pin Excalidraw',
                      ),
                    ),
                ],
              ),
            ),

          if (isPinnedExcalidraw)
            Padding(
              padding: EdgeInsets.fromLTRB(12 * scale, 8 * scale, 12 * scale, 2),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 9 * scale, vertical: 3 * scale),
                decoration: BoxDecoration(
                  color: excalidrawAccentColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: excalidrawAccentColor.withValues(alpha: 0.55),
                  ),
                ),
                child: Text(
                  'Pinned Excalidraw',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11 * scale,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),

          // Quoted reply (if this is a reply to another message)
          if (message.replyToId != null || message.replyPreview != null)
            Opacity(
              opacity: 0.85, // WhatsApp-like dimmed effect
              child: Container(
                margin: EdgeInsets.only(left: 8 * scale, right: 8 * scale, top: 8 * scale),
                padding: EdgeInsets.symmetric(
                  horizontal: 10 * scale,
                  vertical: 6 * scale,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.15),
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
                      contentText = 'ðŸŽ¤ Voice message';
                    } else if (contentText.contains('<img') ||
                        contentText.contains('image/')) {
                      contentText = 'ðŸ“· Photo';
                    } else if (contentText.contains('<video') ||
                        contentText.contains('video/')) {
                      contentText = 'ðŸŽ¬ Video';
                    } else if (contentText.contains('file/') ||
                        contentText.endsWith('.pdf') ||
                        contentText.endsWith('.doc')) {
                      contentText = 'ðŸ“Ž File';
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          senderName,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 11 * scale,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 2 * scale),
                        Text(
                          contentText,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 12 * scale,
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
                        decoration: BoxDecoration(
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
            _AudioMessagePlayer(
              audioUrl: message.fileUrl!,
              fileSize: message.fileSize,
            ),
          ],
          // Text content (if not just filename and not audio)
          if ((!isMedia && !isAudio) ||
              (message.content.isNotEmpty &&
                  !_isOnlyFilename(message.content) &&
                  !isAudio))
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16 * scale, vertical: 10 * scale),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Original message text
                  _buildLinkifiedMessageText(
                    text: isMedia
                        ? (message.fileName ?? message.content)
                        : message.content,
                    isTaskMessage: isTaskMessage,
                    taskAccentColor: taskAccentColor,
                  ),
                  // Translation (if available)
                  if (_messageTranslations.containsKey(message.id)) ...[
                    const SizedBox(height: 8),
                    // Separator line
                    Container(
                      height: 1,
                      color: Colors.white.withValues(alpha: 0.3),
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
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                        const SizedBox(width: 4),
                        // Language indicator (placeholder for now)
                        Text(
                          'auto â†’ en',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
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
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 14,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
            )
          else if (isMedia || isAudio)
            const SizedBox(height: 8),
          // Message status indicator and timestamp for sent messages
          if (isSentByMe)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16 * scale, vertical: 6 * scale),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Timestamp (always shown for sent messages)
                  Text(
                    message.formattedTime,
                    style: TextStyle(color: Colors.white70, fontSize: 11 * scale),
                  ),
                  SizedBox(width: 4 * scale),
                  // Status indicator
                  _buildStatusIndicator(_statusForUi(message), scale),
                ],
              ),
            ),
          // Full timestamp - only visible when _showTimestamps is true
          if (_showTimestamps)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16 * scale, vertical: 6 * scale),
              child: Text(
                message.formattedTimestampFull,
                style: TextStyle(
                  color: const Color(0xFFFF69B4), // Hot pink
                  fontSize: 12 * scale,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );

    // Wrap bubble with Column for reactions below (Column keeps pills in hit-test bounds)
    return Align(
      alignment: isSentByMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isSentByMe
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row with bubble and reaction button - wrapped in Builder to get row position
          Builder(
            builder: (BuildContext rowContext) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // The bubble
                  bubbleWidget,
                  // For incoming (not sent by me): show reaction button on right
                  if (!isSentByMe)
                    GestureDetector(
                      onTap: () {
                        // Get the position of the entire row (bubble + button)
                        final RenderBox? renderBox =
                            rowContext.findRenderObject() as RenderBox?;
                        if (renderBox != null) {
                          final position = renderBox.localToGlobal(Offset.zero);
                          // Position picker above the bubble
                          _showReactionPicker(
                            context,
                            message.id,
                            Offset(
                              0, // Full width from left
                              position.dy, // Top of the message bubble row
                            ),
                          );
                        }
                      },
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4 * scale),
                        child: Icon(
                          Icons.sentiment_satisfied_alt_outlined,
                          color: Colors.white.withValues(alpha: 0.6),
                          size: 22 * scale,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),

          // Reaction pills below bubble â€” tight against bubble bottom
          if (hasReactions)
            Padding(
              padding: EdgeInsets.only(
                left: isSentByMe ? 0 : 8,
                right: isSentByMe ? 8 : 0,
                top: 0,
                bottom: 6,
              ),
              child: _buildReactionPills(message.id),
            ),
        ],
      ),
    );
  }

  String _statusForUi(Message message) {
    if (_databaseLoadedMessageIds.contains(message.id)) {
      return 'sent';
    }
    return message.status;
  }

  /// Check if content is just a filename (for media messages)
  bool _isOnlyFilename(String content) {
    if (content.isEmpty) return true;
    // Check if it looks like a filename with extension
    final filenamePattern = RegExp(r'^[\w\-\.\s]+\.\w{2,5}$');
    return filenamePattern.hasMatch(content.trim());
  }

  /// Build message status indicator widget
  Widget _buildStatusIndicator(String status, [double scale = 1.0]) {
    switch (status) {
      case 'sent':
        return Icon(Icons.check, size: 16 * scale, color: Colors.white70);
      case 'delivered':
        return Icon(Icons.done_all, size: 16 * scale, color: Colors.white70);
      case 'seen':
        return Icon(
          Icons.done_all,
          size: 16 * scale,
          color: const Color(0xFF00BCD4), // Cyan color like WhatsApp
        );
      default:
        return Icon(Icons.schedule, size: 16 * scale, color: Colors.white54);
    }
  }

  /// Open full screen media viewer
  void _openMediaViewer(Message message) {
    if (message.fileUrl == null) return;

    final isVideo =
        message.messageType == 'video' ||
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

class _SwipeableMessage extends StatefulWidget {
  const _SwipeableMessage({
    super.key,
    required this.isSentByMe,
    required this.onReply,
    required this.onTap,
    required this.onLongPress,
    required this.child,
  });

  final bool isSentByMe;
  final VoidCallback onReply;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final Widget child;

  @override
  State<_SwipeableMessage> createState() => _SwipeableMessageState();
}

class _SwipeableMessageState extends State<_SwipeableMessage> {
  static const double _maxSlide = 70.0;
  static const double _threshold = 50.0;

  double _dragOffset = 0.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (details) {
        setState(() {
          if (widget.isSentByMe) {
            _dragOffset = (_dragOffset + details.delta.dx).clamp(
              -_maxSlide,
              0.0,
            );
          } else {
            _dragOffset = (_dragOffset + details.delta.dx).clamp(
              0.0,
              _maxSlide,
            );
          }
        });
      },
      onHorizontalDragEnd: (details) {
        if (_dragOffset.abs() > _threshold) {
          widget.onReply();
        }
        setState(() {
          _dragOffset = 0.0;
        });
      },
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: Transform.translate(
        offset: Offset(_dragOffset, 0),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (_dragOffset.abs() > 10)
              Positioned(
                left: widget.isSentByMe ? -35 : null,
                right: widget.isSentByMe ? null : -35,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Opacity(
                    opacity: (_dragOffset.abs() / _maxSlide).clamp(0.0, 1.0),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF7C3AED).withValues(alpha: 0.9),
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
            widget.child,
          ],
        ),
      ),
    );
  }
}

/// Voice Recording Modal Widget
class _VoiceRecordingModal extends StatefulWidget {
  final Function(String path, Duration duration) onSend;
  final VoidCallback onCancel;

  const _VoiceRecordingModal({required this.onSend, required this.onCancel});

  @override
  State<_VoiceRecordingModal> createState() => _VoiceRecordingModalState();
}

class _VoiceRecordingModalState extends State<_VoiceRecordingModal> {
  // Native channel â€” backed by Android MediaRecorder
  static const _ch = MethodChannel(
    'com.example.flutter_messenger_v2/audio_recorder',
  );

  // Keep FlutterSoundPlayer for pre-send playback preview
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

  @override
  void initState() {
    super.initState();
    _initRecorder();
  }

  Future<void> _initRecorder() async {
    try {
      // Only open the player â€” recording goes through the native channel
      await _player.openPlayer();
      setState(() {
        _isRecorderInitialized = true; // native channel is always ready
        _isPlayerInitialized = true;
      });
    } catch (e) {
      debugPrint('Error initializing player: $e');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    // Stop any in-progress recording when modal is dismissed
    if (_isRecording) {
      _ch.invokeMethod('stopRecording').catchError((_) {});
    }
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
    if (!_isRecorderInitialized) return;

    try {
      final directory = await getTemporaryDirectory();
      final path =
          '${directory.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

      setState(() {
        _isRecording = true;
        _isPaused = false;
        _recordingPath = path;
        _duration = Duration.zero;
        _waveformData = [];
      });

      // Start the native MediaRecorder
      await _ch.invokeMethod('startRecording', {'path': path});

      // Poll amplitude every 100 ms via MediaRecorder.getMaxAmplitude()
      _startWaveformTimer();
    } catch (e) {
      debugPrint('Native startRecording error: $e');
      if (mounted) {
        setState(() => _isRecording = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error starting recording: $e')));
      }
    }
  }

  void _startWaveformTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (t) async {
      if (!mounted || !_isRecording || _isPaused) return;
      try {
        // getMaxAmplitude returns 0-32767; it resets each call (peak-hold)
        final raw = await _ch.invokeMethod<int>('getAmplitude') ?? 0;
        // Normalise: apply sqrt so quiet sounds are more visible
        final normalized = raw > 0
            ? math.sqrt(raw / 32767.0).clamp(0.05, 1.0)
            : 0.05;
        if (mounted && _isRecording && !_isPaused) {
          setState(() {
            _duration += const Duration(milliseconds: 100);
            _waveformData.add(normalized);
            if (_waveformData.length > 50) _waveformData.removeAt(0);
          });
        }
      } catch (_) {
        // Channel error â€” just increment duration silently
        if (mounted && _isRecording && !_isPaused) {
          setState(() => _duration += const Duration(milliseconds: 100));
        }
      }
    });
  }

  Future<void> _pauseRecording() async {
    try {
      await _ch.invokeMethod('pauseRecording');
      _timer?.cancel();
      setState(() => _isPaused = true);
    } catch (e) {
      debugPrint('Pause error: $e');
    }
  }

  Future<void> _resumeRecording() async {
    try {
      await _ch.invokeMethod('resumeRecording');
      setState(() => _isPaused = false);
      _startWaveformTimer();
    } catch (e) {
      debugPrint('Resume error: $e');
    }
  }

  Future<void> _stopRecording() async {
    try {
      _timer?.cancel();
      await _ch.invokeMethod('stopRecording');
      setState(() {
        _isRecording = false;
        _isPaused = false;
        _hasRecording = true;
      });
    } catch (e) {
      debugPrint('Stop recording error: $e');
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
    final mq = MediaQuery.of(context);
    // Tight vertical budget: keeps waveform, timer, controls and cancel all visible
    final isCompact = mq.size.height < 600;

    return SafeArea(
      top: false, // bottom sheet â€” only apply bottom safe area
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF2D2D2D),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle bar
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[600],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),

                // Title
                const Text(
                  'Voice Message',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: isCompact ? 12 : 20),

                // Duration display
                Text(
                  _formatDuration(_duration),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 44,
                    fontWeight: FontWeight.w300,
                    fontFamily: 'monospace',
                  ),
                ),
                SizedBox(height: isCompact ? 10 : 16),

                // Waveform visualization
                SizedBox(
                  height: isCompact ? 40 : 56,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (int i = 0; i < 50; i++)
                        Container(
                          width: 4,
                          height:
                              (i < _waveformData.length
                                  ? _waveformData[i]
                                  : 0.1) *
                              (isCompact ? 36 : 48),
                          margin: const EdgeInsets.symmetric(horizontal: 1),
                          decoration: BoxDecoration(
                            color: _isRecording && !_isPaused
                                ? const Color(0xFFEF4444)
                                : (_hasRecording
                                      ? const Color(0xFF10B981)
                                      : Colors.grey[600]),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(height: isCompact ? 16 : 24),

                // Controls
                if (!_isRecording && !_hasRecording) ...[
                  // Initial state â€” Start button
                  ElevatedButton.icon(
                    onPressed: _isRecorderInitialized ? _startRecording : null,
                    icon: const Icon(Icons.mic, size: 24),
                    label: Text(
                      _isRecorderInitialized
                          ? 'Start Recording'
                          : 'Initializing...',
                      style: const TextStyle(fontSize: 16),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEF4444),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                    ),
                  ),
                ] else if (_isRecording) ...[
                  // Recording state â€” Pause/Resume + Stop
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        onPressed: _isPaused
                            ? _resumeRecording
                            : _pauseRecording,
                        icon: Icon(
                          _isPaused ? Icons.play_arrow : Icons.pause,
                          size: 32,
                          color: Colors.white,
                        ),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.grey[700],
                          padding: const EdgeInsets.all(14),
                        ),
                      ),
                      const SizedBox(width: 20),
                      IconButton(
                        onPressed: _stopRecording,
                        icon: const Icon(
                          Icons.stop,
                          size: 32,
                          color: Colors.white,
                        ),
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFFEF4444),
                          padding: const EdgeInsets.all(14),
                        ),
                      ),
                    ],
                  ),
                ] else if (_hasRecording) ...[
                  // Has recording â€” Discard / Play / Send
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        onPressed: _discardRecording,
                        icon: const Icon(
                          Icons.delete,
                          size: 26,
                          color: Colors.white,
                        ),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.grey[700],
                          padding: const EdgeInsets.all(12),
                        ),
                      ),
                      IconButton(
                        onPressed: _isPlaying ? _stopPlaying : _playRecording,
                        icon: Icon(
                          _isPlaying ? Icons.stop : Icons.play_arrow,
                          size: 32,
                          color: Colors.white,
                        ),
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFF3B82F6),
                          padding: const EdgeInsets.all(14),
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          if (_recordingPath != null) {
                            widget.onSend(_recordingPath!, _duration);
                          }
                        },
                        icon: const Icon(
                          Icons.send,
                          size: 26,
                          color: Colors.white,
                        ),
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          padding: const EdgeInsets.all(12),
                        ),
                      ),
                    ],
                  ),
                ],

                SizedBox(height: isCompact ? 12 : 20),

                // Cancel button
                TextButton(
                  onPressed: () async {
                    if (_isRecording) {
                      await _ch
                          .invokeMethod('stopRecording')
                          .catchError((_) {});
                    }
                    widget.onCancel();
                  },
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.grey, fontSize: 15),
                  ),
                ),

                // Bottom safe-area padding (accounts for home indicator etc.)
                SizedBox(height: mq.padding.bottom > 0 ? mq.padding.bottom : 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Audio Message Player Widget for playing voice messages in chat
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
                color: Colors.white.withValues(alpha: 0.2),
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
                    color: Colors.white.withValues(alpha: 0.7),
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
