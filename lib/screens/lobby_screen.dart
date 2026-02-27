import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shimmer/shimmer.dart';
import '../models/lobby_user.dart';
import '../models/group.dart';
import '../services/lobby_service.dart';
import '../services/group_service.dart';
import '../services/auth_service.dart';
import '../services/socket_service.dart';
import '../widgets/app_version_text.dart';
import '../services/call_service.dart';
import '../widgets/incoming_call_setup_modal.dart';
import 'sign_in_page.dart';
import 'chat_screen.dart';
import 'connected_call_screen.dart';
import 'task_list_screen.dart';
import 'group_chat_screen.dart';
import 'create_group_screen.dart';
import '../services/app_update_service.dart';
import '../services/storage_service.dart';
import '../config/api_config.dart';
import '../services/presence_service.dart';
import '../services/chat_cache_service.dart';

/// Lobby/Chat list screen
class LobbyScreen extends StatefulWidget {
  static const route = '/lobby';
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

enum LobbySortMode { recentChats, onlineFirst, allUsers }

class _LobbyScreenState extends State<LobbyScreen> {
  List<LobbyUser> _lobbyUsers = [];
  List<LobbyUser> _filteredUsers = [];
  List<Group> _groups = []; // Group chats
  List<Group> _filteredGroups = []; // Filtered group chats
  bool _isLoading = false;
  bool _isBackendAvailable = true;
  bool _isCurrentUserAdmin = false;
  LobbySortMode _sortMode = LobbySortMode.recentChats;
  final TextEditingController _searchController = TextEditingController();
  final SocketService _socketService = SocketService();
  Timer? _lastSeenRefreshTimer;
  String _connectivityBannerMessage = 'Server unavailable. Reconnecting...';
  // _isHandlingIncomingCall is now global via PresenceService().isHandlingIncomingCall

  // Typing indicator: maps userId → auto-clear timer
  final Map<int, Timer> _typingUsers = {};

  // Avatar colors palette
  static const List<Color> avatarColors = [
    Color(0xFFE91E63), // Pink
    Color(0xFF9C27B0), // Purple
    Color(0xFF673AB7), // Deep Purple
    Color(0xFF3F51B5), // Indigo
    Color(0xFF2196F3), // Blue
    Color(0xFF00BCD4), // Cyan
    Color(0xFF009688), // Teal
    Color(0xFF4CAF50), // Green
    Color(0xFFFF9800), // Orange
    Color(0xFFFF5722), // Deep Orange
  ];

  @override
  void initState() {
    super.initState();
    _loadLobby();
    _loadAdminStatus();
    _searchController.addListener(_filterUsers);
    _setupRealtimeListeners();
    // Check for app updates after a short delay
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        AppUpdateService().checkForUpdate(context);
      }
    });
    // Periodically refresh "last seen" relative labels (like the web app does)
    _lastSeenRefreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _loadAdminStatus() async {
    final isAdmin = await StorageService.getIsAdmin();
    if (mounted) {
      setState(() => _isCurrentUserAdmin = isAdmin);
    }
  }

  void _setupRealtimeListeners() {
    const key = 'lobby';

    // Listen for doorbell rings (only incoming — ignore self-sent for cross-device sync)
    _socketService.addListener('doorbellRing', key, (
      Map<String, dynamic> data,
    ) {
      final senderId = data['sender_id'] as int?;
      if (senderId == _socketService.currentUserId) return;
      _handleDoorbellRing(data);
    });

    // Listen for new messages (incoming)
    _socketService.addListener('messageReceived', key, (
      Map<String, dynamic> data,
    ) {
      _handleNewMessage(data);
    });

    // Listen for sent messages (outgoing from current user)
    _socketService.addListener('messageSent', key, (Map<String, dynamic> data) {
      _handleSentMessage(data);
    });

    // Listen for file messages (incoming files from web)
    _socketService.addListener('fileReceived', key, (
      Map<String, dynamic> data,
    ) {
      _handleFileMessage(data);
    });

    // Listen for voice messages (incoming voice from web)
    _socketService.addListener('voiceMessageReceived', key, (
      Map<String, dynamic> data,
    ) {
      _handleVoiceMessage(data);
    });

    // Listen for presence updates
    _socketService.addListener('presenceUpdate', key, (
      Map<String, dynamic> data,
    ) {
      _updateUserPresence(data);
    });

    // Listen for presence snapshot (initial state on connect)
    _socketService.addListener('presenceSnapshot', key, (
      List<dynamic> contacts,
    ) {
      _handlePresenceSnapshot(contacts);
    });

    // Listen for incoming calls (global handler)
    // NOTE: We only listen to 'incomingCall' here (not 'crossRoomCallOffer') because the
    // server sends BOTH events to the callee for the same call. 'incomingCall' contains
    // full call data (call_id, call_room_id) and is sufficient for mobile clients.
    // Listening to both would open two modals for the same call.
    _socketService.addListener('incomingCall', key, (
      Map<String, dynamic> data,
    ) {
      _handleIncomingCall(data);
    });

    // Listen for backend connection state changes
    _socketService.addListener('connectionChanged', key, (
      Map<String, dynamic> data,
    ) {
      final isConnected = data['connected'] as bool;
      if (mounted) {
        setState(() => _isBackendAvailable = isConnected);
      }
    });

    // Auto-reload lobby when backend reconnects
    _socketService.addListener('reconnected', key, () {
      if (mounted) {
        debugPrint('🔄 Backend reconnected - reloading lobby');
        _loadLobby();
      }
    });

    // Set initial state from current socket status
    _isBackendAvailable = _socketService.isConnected;

    // Listen for group events
    _socketService.addListener('group_created', key, (dynamic data) {
      debugPrint('🎉 Group created event received: $data');
      if (data is Map<String, dynamic>) {
        try {
          final group = Group.fromJson(data);
          if (mounted) {
            setState(() {
              _groups.insert(0, group);
            });
            _filterUsers(); // Refresh filtered lists
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('New group: ${group.name}'),
                backgroundColor: Colors.green,
              ),
            );
          }
        } catch (e) {
          debugPrint('❌ Error parsing group_created event: $e');
        }
      }
    });

    _socketService.addListener('group_updated', key, (dynamic data) {
      debugPrint('🔄 Group updated event received: $data');
      if (data is Map<String, dynamic>) {
        try {
          final updatedGroup = Group.fromJson(data);
          if (mounted) {
            setState(() {
              final index = _groups.indexWhere((g) => g.id == updatedGroup.id);
              if (index != -1) {
                _groups[index] = updatedGroup;
              }
            });
            _filterUsers(); // Refresh filtered lists
          }
        } catch (e) {
          debugPrint('❌ Error parsing group_updated event: $e');
        }
      }
    });

    _socketService.addListener('group_member_removed', key, (dynamic data) {
      debugPrint('👋 Group member removed event received: $data');
      if (data is Map<String, dynamic>) {
        final groupId = data['group_id'] as int?;
        final removedUserId = data['removed_user_id'] as int?;
        final currentUserId = StorageService.getUserId();

        if (groupId != null && removedUserId != null && mounted) {
          currentUserId.then((userId) {
            if (userId == removedUserId) {
              // Current user was removed, remove group from list
              setState(() {
                _groups.removeWhere((g) => g.id == groupId);
              });
              _filterUsers();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('You were removed from a group'),
                  backgroundColor: Colors.orange,
                ),
              );
            } else {
              // Another member was removed, reload group details
              _loadLobby(useCacheFirst: false);
            }
          });
        }
      }
    });

    // Listen for typing events from peers
    _socketService.addListener('userTyping', key, (Map<String, dynamic> data) {
      final userId = data['user_id'] as int?;
      final isTyping = data['is_typing'] as bool? ?? false;
      if (userId == null) return;
      if (!mounted) return;
      setState(() {
        if (isTyping) {
          _typingUsers[userId]?.cancel();
          _typingUsers[userId] = Timer(const Duration(seconds: 5), () {
            if (mounted) setState(() => _typingUsers.remove(userId));
          });
        } else {
          _typingUsers[userId]?.cancel();
          _typingUsers.remove(userId);
        }
      });
    });

    _socketService.addListener('typingUpdate', key, (
      Map<String, dynamic> data,
    ) {
      final userId = (data['user_id'] ?? data['sender_id']) as int?;
      if (userId == null) return;
      if (!mounted) return;
      setState(() {
        _typingUsers[userId]?.cancel();
        _typingUsers[userId] = Timer(const Duration(seconds: 5), () {
          if (mounted) setState(() => _typingUsers.remove(userId));
        });
      });
    });
  }

  /// Handle cross-room call offer from web client
  Future<void> _handleCrossRoomCallOffer(Map<String, dynamic> data) async {
    if (!mounted) return;

    // Guard against duplicate/rapid incoming call events (global flag shared with chat screen)
    if (PresenceService().isHandlingIncomingCall) {
      debugPrint(
        '⚠️ Already handling an incoming call, ignoring cross-room duplicate',
      );
      return;
    }
    PresenceService().isHandlingIncomingCall = true;

    debugPrint('📲 Cross-room call offer received in lobby: $data');

    final callerId = data['caller_id'] as int?;
    final callerUsername = data['caller_username'] as String? ?? 'Unknown';
    final callType = data['call_type'] as String? ?? 'video';
    final room = data['room'] as String?;

    if (callerId == null || room == null) {
      debugPrint('⚠️ Invalid cross-room call offer data');
      PresenceService().isHandlingIncomingCall = false;
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
      'id': DateTime.now().millisecondsSinceEpoch, // Temporary ID
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
    const crossRoomListenerKey = 'lobby_cross_room_call';
    _socketService.addListener('callEnded', crossRoomListenerKey, (
      Map<String, dynamic> endData,
    ) {
      debugPrint('📴 Call ended by remote user (lobby cross-room)');
      _socketService.stopSignalBuffering();
      callService.handleCallEnded();
    });

    _socketService.addListener('callDeclined', crossRoomListenerKey, (
      Map<String, dynamic> declineData,
    ) {
      debugPrint('❌ Call declined (lobby cross-room)');
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
                debugPrint('📞 Call declined by user');
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

          if (result is Map &&
              (result['result'] == 'accepted' ||
                  result['result'] == 'connected')) {
            final localStream = result['localStream'];
            Navigator.of(context)
                .push(
                  MaterialPageRoute(
                    fullscreenDialog: true,
                    builder: (context) => ConnectedCallScreen(
                      remoteName: callerUsername,
                      callType: callType,
                      callService: callService,
                      localStream: localStream ?? callService.localStream,
                    ),
                  ),
                )
                .then((_) {
                  _setupRealtimeListeners();
                });
          }
          PresenceService().isHandlingIncomingCall = false;
          _setupRealtimeListeners();
        });
  }

  /// Handle incoming call from another user
  Future<void> _handleIncomingCall(Map<String, dynamic> data) async {
    if (!mounted) return;

    // Guard: ignore if already in an active call (e.g. screen-share renegotiation
    // sends a new incoming_call event while ConnectedCallScreen is open)
    if (PresenceService().isCallInProgress) {
      debugPrint(
        '⚠️ Ignoring incoming_call — call already in progress (screen share or renegotiation?)',
      );
      return;
    }

    // Guard against duplicate/rapid incoming call events (global flag shared with chat screen)
    if (PresenceService().isHandlingIncomingCall) {
      debugPrint(
        '⚠️ Already handling an incoming call, ignoring duplicate event',
      );
      return;
    }
    PresenceService().isHandlingIncomingCall = true;

    debugPrint('📲 Incoming call received in lobby: $data');

    final callId = data['id'] as int?;
    final callRoomId = data['call_room_id'] as String?;
    final callType = data['call_type'] as String? ?? 'video';
    final callerData = data['caller'] as Map<String, dynamic>?;
    final callerId = callerData?['id'] as int? ?? data['caller_id'] as int?;
    final callerName =
        callerData?['full_name'] as String? ??
        callerData?['username'] as String? ??
        'Unknown';

    if (callId == null || callRoomId == null || callerId == null) {
      debugPrint('⚠️ Invalid incoming call data');
      PresenceService().isHandlingIncomingCall = false;
      return;
    }

    // START buffering WebRTC signals immediately — before the async callService.initialize().
    // Previously this was triggered by the crossRoomCallOffer socket event, but we no longer
    // listen for that in the lobby. Without buffering, any offer signal that arrives during
    // the async gap would be silently dropped (_bufferSignals=false, _onSignal=null → noop).
    _socketService.startSignalBuffering();

    // Initialize call service (fetches ICE servers) and set up the call state
    final callService = CallService();
    await callService.initialize();
    callService.handleIncomingCall(data);

    // Set up signal handler for WebRTC — buffered signals are replayed immediately
    _socketService.onSignal = (signalData) {
      debugPrint('📡 Signal received for incoming call: $signalData');
      callService.handleSignal(signalData);
    };

    // Use keyed listeners for call ended/declined handlers to avoid overwriting
    const callListenerKey = 'lobby_incoming_call';
    _socketService.addListener('callEnded', callListenerKey, (
      Map<String, dynamic> endData,
    ) {
      debugPrint('📴 Call ended by remote user (lobby)');
      callService.handleCallEnded();
    });

    _socketService.addListener('callDeclined', callListenerKey, (
      Map<String, dynamic> declineData,
    ) {
      debugPrint('❌ Call declined (lobby)');
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
                debugPrint('📞 Call declined by user');
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

          if (result is Map &&
              (result['result'] == 'accepted' ||
                  result['result'] == 'connected')) {
            // Navigate to connected call screen with the local stream from setup
            final localStream = result['localStream'];
            Navigator.of(context)
                .push(
                  MaterialPageRoute(
                    fullscreenDialog: true,
                    builder: (context) => ConnectedCallScreen(
                      remoteName: callerName,
                      callType: callType,
                      callService: callService,
                      localStream: localStream ?? callService.localStream,
                    ),
                  ),
                )
                .then((_) {
                  _setupRealtimeListeners();
                });
          }
          PresenceService().isHandlingIncomingCall = false;
          _setupRealtimeListeners();
        });
  }

  void _handleDoorbellRing(Map<String, dynamic> data) {
    // Doorbell ring sound is already played via the socket service
    // No modal needed - the notification sound is sufficient
    debugPrint('Doorbell ring received from ${data['sender_name']}');
  }

  void _handleNewMessage(Map<String, dynamic> data) {
    final senderId = data['sender_id'] as int;
    final content = data['content'] as String?;
    final createdAt = data['created_at'] as String?;

    // Update unread count and last message info for sender
    setState(() {
      final userIndex = _lobbyUsers.indexWhere((u) => u.id == senderId);
      if (userIndex != -1) {
        // Create updated user with incremented unread count and new last message
        final user = _lobbyUsers[userIndex];
        final updatedUser = LobbyUser(
          id: user.id,
          username: user.username,
          email: user.email,
          firstName: user.firstName,
          lastName: user.lastName,
          fullName: user.fullName,
          avatarUrl: user.avatarUrl,
          bio: user.bio,
          status: user.status,
          statusMessage: user.statusMessage,
          lastSeen: user.lastSeen,
          isOnline: user.isOnline,
          isAdmin: user.isAdmin,
          timezone: user.timezone,
          unreadCount: user.unreadCount + 1,
          isContact: user.isContact,
          isAdminUser: user.isAdminUser,
          // 🆕 NEW: Update last message info
          lastMessage: content ?? user.lastMessage,
          lastMessageTime: createdAt ?? user.lastMessageTime,
          lastMessageIsFromMe:
              false, // Message is from the sender, not from current user
        );

        _lobbyUsers[userIndex] = updatedUser;

        // Move to top of list (most recent message first)
        _lobbyUsers.removeAt(userIndex);
        _lobbyUsers.insert(0, updatedUser);

        // Update filtered list
        _filterUsers();
      }
    });
  }

  void _handleSentMessage(Map<String, dynamic> data) {
    final recipientId = data['recipient_id'] as int;
    final content = data['content'] as String?;
    final createdAt = data['created_at'] as String?;

    // Update last message info for recipient (showing our sent message)
    setState(() {
      final userIndex = _lobbyUsers.indexWhere((u) => u.id == recipientId);
      if (userIndex != -1) {
        // Create updated user with new last message from current user
        final user = _lobbyUsers[userIndex];
        final updatedUser = LobbyUser(
          id: user.id,
          username: user.username,
          email: user.email,
          firstName: user.firstName,
          lastName: user.lastName,
          fullName: user.fullName,
          avatarUrl: user.avatarUrl,
          bio: user.bio,
          status: user.status,
          statusMessage: user.statusMessage,
          lastSeen: user.lastSeen,
          isOnline: user.isOnline,
          isAdmin: user.isAdmin,
          timezone: user.timezone,
          unreadCount:
              0, // Reset unread count since we're in the conversation context
          isContact: user.isContact,
          isAdminUser: user.isAdminUser,
          // 🆕 NEW: Update last message info (sent by current user)
          lastMessage: content ?? user.lastMessage,
          lastMessageTime: createdAt ?? user.lastMessageTime,
          lastMessageIsFromMe: true, // Message is from current user
        );

        _lobbyUsers[userIndex] = updatedUser;

        // Move to top of list (most recent message first)
        _lobbyUsers.removeAt(userIndex);
        _lobbyUsers.insert(0, updatedUser);

        // Update filtered list
        _filterUsers();
      }
    });
  }

  void _handleFileMessage(Map<String, dynamic> data) {
    final senderId = data['sender_id'] as int;
    final fileName = data['file_name'] as String?;
    final createdAt = data['timestamp_ms'] != null
        ? DateTime.fromMillisecondsSinceEpoch(
            data['timestamp_ms'] as int,
          ).toIso8601String()
        : null;

    // Show file name as last message preview
    final filePreview = fileName != null ? "📎 $fileName" : "📎 File";

    setState(() {
      final userIndex = _lobbyUsers.indexWhere((u) => u.id == senderId);
      if (userIndex != -1) {
        final user = _lobbyUsers[userIndex];
        final updatedUser = LobbyUser(
          id: user.id,
          username: user.username,
          email: user.email,
          firstName: user.firstName,
          lastName: user.lastName,
          fullName: user.fullName,
          avatarUrl: user.avatarUrl,
          bio: user.bio,
          status: user.status,
          statusMessage: user.statusMessage,
          lastSeen: user.lastSeen,
          isOnline: user.isOnline,
          isAdmin: user.isAdmin,
          timezone: user.timezone,
          unreadCount: user.unreadCount + 1,
          isContact: user.isContact,
          isAdminUser: user.isAdminUser,
          lastMessage: filePreview,
          lastMessageTime: createdAt ?? user.lastMessageTime,
          lastMessageIsFromMe: false,
        );

        _lobbyUsers[userIndex] = updatedUser;
        _lobbyUsers.removeAt(userIndex);
        _lobbyUsers.insert(0, updatedUser);
        _filterUsers();
      }
    });
  }

  void _handleVoiceMessage(Map<String, dynamic> data) {
    final senderId = data['sender_id'] as int;
    final duration = data['duration'] as int?;
    final createdAt = data['timestamp_ms'] != null
        ? DateTime.fromMillisecondsSinceEpoch(
            data['timestamp_ms'] as int,
          ).toIso8601String()
        : null;

    // Show voice message with duration as last message preview
    final voicePreview = duration != null
        ? "🎤 Voice ${duration}s"
        : "🎤 Voice message";

    setState(() {
      final userIndex = _lobbyUsers.indexWhere((u) => u.id == senderId);
      if (userIndex != -1) {
        final user = _lobbyUsers[userIndex];
        final updatedUser = LobbyUser(
          id: user.id,
          username: user.username,
          email: user.email,
          firstName: user.firstName,
          lastName: user.lastName,
          fullName: user.fullName,
          avatarUrl: user.avatarUrl,
          bio: user.bio,
          status: user.status,
          statusMessage: user.statusMessage,
          lastSeen: user.lastSeen,
          isOnline: user.isOnline,
          isAdmin: user.isAdmin,
          timezone: user.timezone,
          unreadCount: user.unreadCount + 1,
          isContact: user.isContact,
          isAdminUser: user.isAdminUser,
          lastMessage: voicePreview,
          lastMessageTime: createdAt ?? user.lastMessageTime,
          lastMessageIsFromMe: false,
        );

        _lobbyUsers[userIndex] = updatedUser;
        _lobbyUsers.removeAt(userIndex);
        _lobbyUsers.insert(0, updatedUser);
        _filterUsers();
      }
    });
  }

  void _updateUserPresence(Map<String, dynamic> data) {
    final userId = data['user_id'] as int;
    final status = data['status'] as String;
    final isOnline = data['is_online'] as bool? ?? (status == 'online');
    final timestamp = data['timestamp'] as String?;

    setState(() {
      final userIndex = _lobbyUsers.indexWhere((u) => u.id == userId);
      if (userIndex != -1) {
        final user = _lobbyUsers[userIndex];
        final updatedUser = LobbyUser(
          id: user.id,
          username: user.username,
          email: user.email,
          firstName: user.firstName,
          lastName: user.lastName,
          fullName: user.fullName,
          avatarUrl: user.avatarUrl,
          bio: user.bio,
          status: status,
          statusMessage: user.statusMessage,
          lastSeen: timestamp ?? user.lastSeen,
          isOnline: isOnline,
          isAdmin: user.isAdmin,
          timezone: user.timezone,
          unreadCount: user.unreadCount,
          isContact: user.isContact,
          isAdminUser: user.isAdminUser,
        );

        _lobbyUsers[userIndex] = updatedUser;
        _filterUsers();
      }
    });
  }

  /// Handle presence snapshot from socket (initial state on connect)
  void _handlePresenceSnapshot(List<dynamic> contacts) {
    setState(() {
      for (final contact in contacts) {
        if (contact is Map<String, dynamic>) {
          final userId = contact['user_id'] as int?;
          final status = contact['status'] as String?;
          final timestamp = contact['timestamp'] as String?;

          if (userId != null && status != null) {
            final userIndex = _lobbyUsers.indexWhere((u) => u.id == userId);
            if (userIndex != -1) {
              final user = _lobbyUsers[userIndex];
              final isOnline = status == 'online';
              _lobbyUsers[userIndex] = LobbyUser(
                id: user.id,
                username: user.username,
                email: user.email,
                firstName: user.firstName,
                lastName: user.lastName,
                fullName: user.fullName,
                avatarUrl: user.avatarUrl,
                bio: user.bio,
                status: status,
                statusMessage: user.statusMessage,
                lastSeen: timestamp ?? user.lastSeen,
                isOnline: isOnline,
                isAdmin: user.isAdmin,
                timezone: user.timezone,
                unreadCount: user.unreadCount,
                isContact: user.isContact,
                isAdminUser: user.isAdminUser,
              );
            }
          }
        }
      }
      _filterUsers();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _lastSeenRefreshTimer?.cancel();
    // Cancel all active typing timers
    for (final timer in _typingUsers.values) {
      timer.cancel();
    }
    _typingUsers.clear();
    // Clear all lobby socket listeners to prevent memory leaks
    _socketService.removeListenersForKey('lobby');
    super.dispose();
  }

  Future<void> _loadLobby({bool useCacheFirst = true}) async {
    if (_isLoading && useCacheFirst) return;
    setState(() => _isLoading = true);
    final userId = await StorageService.getUserId();
    if (useCacheFirst && userId != null) {
      final cached = await ChatCacheService.loadLobbyUsers(userId);
      if (cached.isNotEmpty && mounted) {
        setState(() {
          _lobbyUsers = cached;
          _filteredUsers = List.from(cached);
          _isBackendAvailable = _socketService.isConnected;
        });
      }
    }
    try {
      // Load both users and groups in parallel
      final results = await Future.wait([
        LobbyService.getLobbyUsers(),
        GroupService.getGroups().catchError((e) {
          debugPrint('Groups not available yet: $e');
          return <Group>[];
        }),
      ]);

      final users = results[0] as List<LobbyUser>;
      final groups = results[1] as List<Group>;

      if (mounted) {
        setState(() {
          _lobbyUsers = users;
          _groups = groups;
          _isBackendAvailable = true;
          _isLoading = false;
          _connectivityBannerMessage = 'Server unavailable. Reconnecting...';
        });
        _filterUsers();
      }
      if (userId != null) {
        await ChatCacheService.saveLobbyUsers(userId, users);
      }
    } catch (e) {
      final friendly = _mapConnectivityError(
        e,
        offlineLabel: 'No internet connection. Showing cached contacts.',
        backendLabel:
            'Server unreachable. Showing cached contacts if available.',
      );
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isBackendAvailable = false;
          _connectivityBannerMessage = friendly;
        });
      }
      debugPrint('Error loading lobby: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendly), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _mapConnectivityError(
    Object error, {
    required String offlineLabel,
    required String backendLabel,
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
    return 'Something went wrong. Please try again in a bit.';
  }

  /// Get the effective status tier: 0=online, 1=away/lastSeen, 2=offline
  int _getStatusTier(LobbyUser user) {
    if (user.isOnline || user.status == 'online') {
      // Cross-check with last_seen to detect stale online status
      // (matches web app's grace-period logic)
      if (user.lastSeen != null) {
        try {
          final lastSeenTime = _parseUtcTimestamp(user.lastSeen!);
          final age = DateTime.now().difference(lastSeenTime);
          if (age.inMinutes > 2) {
            // Stale online status — treat as away/last seen if recent, offline otherwise
            return age.inHours < 24 ? 1 : 2;
          }
        } catch (_) {}
      }
      return 0;
    }
    if (user.status == 'away') return 1;
    // Recently seen (within 24h) counts as "last seen" tier
    if (user.lastSeen != null) {
      try {
        final lastSeenTime = _parseUtcTimestamp(user.lastSeen!);
        final age = DateTime.now().difference(lastSeenTime);
        if (age.inHours < 24) return 1;
      } catch (_) {}
    }
    return 2;
  }

  /// Parse lastMessageTime to DateTime for sorting (returns epoch 0 if null)
  DateTime _parseMessageTime(LobbyUser user) {
    if (user.lastMessageTime == null)
      return DateTime.fromMillisecondsSinceEpoch(0);
    try {
      return _parseUtcTimestamp(user.lastMessageTime!);
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  void _filterUsers() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      // Filter users
      List<LobbyUser> filtered;
      if (query.isEmpty) {
        filtered = List.from(_lobbyUsers);
      } else {
        filtered = _lobbyUsers.where((user) {
          return user.fullName.toLowerCase().contains(query) ||
              user.username.toLowerCase().contains(query);
        }).toList();
      }

      // Filter groups
      List<Group> filteredGroups;
      if (query.isEmpty) {
        filteredGroups = List.from(_groups);
      } else {
        filteredGroups = _groups.where((group) {
          return group.name.toLowerCase().contains(query) ||
              (group.description?.toLowerCase().contains(query) ?? false);
        }).toList();
      }

      switch (_sortMode) {
        case LobbySortMode.recentChats:
          // Sort by status tier first, then by most recent message within each tier
          filtered.sort((a, b) {
            final tierA = _getStatusTier(a);
            final tierB = _getStatusTier(b);
            if (tierA != tierB) return tierA.compareTo(tierB);
            // Within same tier, sort by last message time (most recent first)
            final timeA = _parseMessageTime(a);
            final timeB = _parseMessageTime(b);
            return timeB.compareTo(timeA);
          });
          // Sort groups by last message time
          filteredGroups.sort((a, b) {
            final timeA = a.lastMessage?.timestampMs ?? 0;
            final timeB = b.lastMessage?.timestampMs ?? 0;
            return timeB.compareTo(timeA);
          });
          break;
        case LobbySortMode.onlineFirst:
          // Sort purely by status tier, then alphabetically
          filtered.sort((a, b) {
            final tierA = _getStatusTier(a);
            final tierB = _getStatusTier(b);
            if (tierA != tierB) return tierA.compareTo(tierB);
            return a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());
          });
          // Sort groups alphabetically
          filteredGroups.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
          break;
        case LobbySortMode.allUsers:
          // Alphabetical only
          filtered.sort(
            (a, b) =>
                a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
          );
          filteredGroups.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
          break;
      }

      _filteredUsers = filtered;
      _filteredGroups = filteredGroups;
    });
  }

  Future<void> _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D2D),
        title: const Text('Logout', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure you want to logout?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Logout', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await AuthService.logout();
      if (mounted) {
        Navigator.pushReplacementNamed(context, SignInPage.route);
      }
    }
  }

  Color _getAvatarColor(int index) {
    return avatarColors[index % avatarColors.length];
  }

  /// Parse a timestamp string, treating it as UTC if no timezone info is present
  /// (matches the web app's parseTs() behavior)
  DateTime _parseUtcTimestamp(String timestamp) {
    final hasTimezone = RegExp(r'[zZ]|[+-]\d{2}:?\d{2}$').hasMatch(timestamp);
    final parsed = DateTime.parse(hasTimezone ? timestamp : '${timestamp}Z');
    return parsed.toLocal();
  }

  String _formatTime(String? lastSeen) {
    if (lastSeen == null) return '';
    try {
      final dateTime = _parseUtcTimestamp(lastSeen);
      final now = DateTime.now();
      final difference = now.difference(dateTime);

      if (difference.inMinutes < 1) return 'Just now';
      if (difference.inHours < 1) return '${difference.inMinutes}m ago';
      if (difference.inDays < 1) {
        final hour = dateTime.hour;
        final minute = dateTime.minute.toString().padLeft(2, '0');
        final period = hour >= 12 ? 'PM' : 'AM';
        final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
        return '$displayHour:$minute $period';
      }
      if (difference.inDays < 7) return '${difference.inDays}d ago';
      return '${dateTime.month}/${dateTime.day}';
    } catch (e) {
      return '';
    }
  }

  /// Format last seen as relative time for status display (e.g., "Last seen 5m ago")
  String _formatRelativeTime(String? lastSeen) {
    if (lastSeen == null) return 'Offline';
    try {
      final dateTime = _parseUtcTimestamp(lastSeen);
      final now = DateTime.now();
      final difference = now.difference(dateTime);

      if (difference.inMinutes < 1) return 'Last seen just now';
      if (difference.inMinutes < 60) {
        final mins = difference.inMinutes;
        return 'Last seen ${mins}m ago';
      }
      if (difference.inHours < 24) {
        final hours = difference.inHours;
        return 'Last seen ${hours}h ago';
      }
      if (difference.inDays == 1) return 'Last seen yesterday';
      if (difference.inDays < 7) return 'Last seen ${difference.inDays}d ago';
      return 'Last seen ${dateTime.month}/${dateTime.day}';
    } catch (e) {
      return 'Offline';
    }
  }

  String _sortModeLabel(LobbySortMode mode) {
    switch (mode) {
      case LobbySortMode.recentChats:
        return 'Recent Chats';
      case LobbySortMode.onlineFirst:
        return 'Online First';
      case LobbySortMode.allUsers:
        return 'A-Z';
    }
  }

  IconData _sortModeIcon(LobbySortMode mode) {
    switch (mode) {
      case LobbySortMode.recentChats:
        return Icons.access_time;
      case LobbySortMode.onlineFirst:
        return Icons.circle;
      case LobbySortMode.allUsers:
        return Icons.sort_by_alpha;
    }
  }

  void _cycleSortMode() {
    setState(() {
      switch (_sortMode) {
        case LobbySortMode.recentChats:
          _sortMode = LobbySortMode.onlineFirst;
          break;
        case LobbySortMode.onlineFirst:
          _sortMode = LobbySortMode.allUsers;
          break;
        case LobbySortMode.allUsers:
          _sortMode = LobbySortMode.recentChats;
          break;
      }
    });
    _filterUsers();
  }

  Widget _buildSectionHeader(String title, int count, Color color) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 6),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '($count)',
            style: TextStyle(color: Colors.grey[600], fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupsSectionHeader() {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 6),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFF00D9FF),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'GROUPS',
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '(${_filteredGroups.length})',
            style: TextStyle(color: Colors.grey[600], fontSize: 11),
          ),
          const Spacer(),
          // Create group button
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const CreateGroupScreen(),
                  ),
                );
                if (result == true) {
                  _loadLobby(useCacheFirst: false);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF00D9FF).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF00D9FF).withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.add, color: Color(0xFF00D9FF), size: 16),
                    const SizedBox(width: 4),
                    Text(
                      'Create',
                      style: const TextStyle(
                        color: Color(0xFF00D9FF),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShimmerTile() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF252542),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // Avatar placeholder
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.grey[800],
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 120,
                  height: 14,
                  decoration: BoxDecoration(
                    color: Colors.grey[800],
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: 80,
                  height: 10,
                  decoration: BoxDecoration(
                    color: Colors.grey[850],
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: 160,
                  height: 10,
                  decoration: BoxDecoration(
                    color: Colors.grey[850],
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingShimmer() {
    return ListView.builder(
      itemCount: 8,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemBuilder: (_, __) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Shimmer.fromColors(
            baseColor: const Color(0xFF1F1F30),
            highlightColor: const Color(0xFF2C2C45),
            child: _buildShimmerTile(),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Separate into 3 tiers
    final onlineUsers = _filteredUsers
        .where((u) => _getStatusTier(u) == 0)
        .toList();
    final lastSeenUsers = _filteredUsers
        .where((u) => _getStatusTier(u) == 1)
        .toList();
    final offlineUsers = _filteredUsers
        .where((u) => _getStatusTier(u) == 2)
        .toList();

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        elevation: 0,
        title: const Text(
          'Chats',
          style: TextStyle(
            color: Color(0xFF00D9FF),
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.check_circle_outline, color: Colors.white70),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const TaskListScreen()),
              );
            },
            tooltip: 'Tasks',
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            onPressed: () => _loadLobby(useCacheFirst: false),
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white70),
            onPressed: _handleLogout,
          ),
        ],
      ),
      body: Column(
        children: [
          // Backend connectivity banner
          if (!_isBackendAvailable)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: const Color(0xFFD32F2F),
              child: Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _connectivityBannerMessage,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _loadLobby(useCacheFirst: false),
                    child: const Text(
                      'Retry',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          // Search bar + sort button row
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Search conversations...',
                      hintStyle: TextStyle(color: Colors.grey[500]),
                      prefixIcon: Icon(Icons.search, color: Colors.grey[500]),
                      filled: true,
                      fillColor: const Color(0xFF252542),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Sort/filter button
                Material(
                  color: const Color(0xFF252542),
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: _cycleSortMode,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _sortModeIcon(_sortMode),
                            color: const Color(0xFF00D9FF),
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _sortModeLabel(_sortMode),
                            style: const TextStyle(
                              color: Color(0xFF00D9FF),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // User list
          Expanded(
            child: (_isLoading && _lobbyUsers.isEmpty && _groups.isEmpty)
                ? _buildLoadingShimmer()
                : (_filteredUsers.isEmpty && _filteredGroups.isEmpty)
                ? Center(
                    child: Text(
                      _searchController.text.isEmpty
                          ? 'No conversations yet'
                          : 'No results found',
                      style: TextStyle(color: Colors.grey[500], fontSize: 16),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: () => _loadLobby(useCacheFirst: false),
                    color: const Color(0xFF00D9FF),
                    backgroundColor: const Color(0xFF252542),
                    child: _sortMode == LobbySortMode.allUsers
                        // A-Z mode: groups first, then flat list of users
                        ? ListView(
                            children: [
                              // Groups section (always at top)
                              _buildGroupsSectionHeader(),
                              if (_filteredGroups.isNotEmpty)
                                ..._filteredGroups.map(
                                  (group) => _buildGroupTile(group),
                                ),
                              // Users
                              ..._filteredUsers.map(
                                (user) => _buildUserTile(
                                  user,
                                  isOnlineSection: _getStatusTier(user) == 0,
                                ),
                              ),
                            ],
                          )
                        // Grouped mode: groups first, then 3-tier sections
                        : ListView(
                            children: [
                              // Groups section (always at top)
                              _buildGroupsSectionHeader(),
                              if (_filteredGroups.isNotEmpty)
                                ..._filteredGroups.map(
                                  (group) => _buildGroupTile(group),
                                ),
                              // Online section
                              if (onlineUsers.isNotEmpty) ...[
                                _buildSectionHeader(
                                  'ONLINE',
                                  onlineUsers.length,
                                  const Color(0xFF00E676),
                                ),
                                ...onlineUsers.map(
                                  (user) => _buildUserTile(
                                    user,
                                    isOnlineSection: true,
                                  ),
                                ),
                              ],
                              // Last Seen section
                              if (lastSeenUsers.isNotEmpty) ...[
                                _buildSectionHeader(
                                  'LAST SEEN',
                                  lastSeenUsers.length,
                                  const Color(0xFFFFC107),
                                ),
                                ...lastSeenUsers.map(
                                  (user) => _buildUserTile(
                                    user,
                                    isOnlineSection: false,
                                  ),
                                ),
                              ],
                              // Offline section
                              if (offlineUsers.isNotEmpty) ...[
                                _buildSectionHeader(
                                  'OFFLINE',
                                  offlineUsers.length,
                                  Colors.grey,
                                ),
                                ...offlineUsers.map(
                                  (user) => _buildUserTile(
                                    user,
                                    isOnlineSection: false,
                                  ),
                                ),
                              ],
                            ],
                          ),
                  ),
          ),
          const AppVersionText(),
        ],
      ),
    );
  }

  /// Determine effective display status: online, away, or offline
  /// Matches the web app's recently-seen logic (yellow dot for offline users
  /// who were active within the last 24 hours)
  /// Also validates 'online' status against last_seen to detect stale DB entries
  String _getEffectiveStatus(LobbyUser user) {
    if (user.isOnline || user.status == 'online') {
      // Cross-check with last_seen to detect stale online status
      if (user.lastSeen != null) {
        try {
          final lastSeenTime = _parseUtcTimestamp(user.lastSeen!);
          final age = DateTime.now().difference(lastSeenTime);
          if (age.inMinutes > 2) {
            // Stale online status — show as away if recent, offline otherwise
            return age.inHours < 24 ? 'away' : 'offline';
          }
        } catch (_) {}
      }
      return 'online';
    }
    if (user.status == 'away') return 'away';
    // Check if recently seen (within 24 hours) → show as away
    if (user.lastSeen != null) {
      try {
        final lastSeenTime = _parseUtcTimestamp(user.lastSeen!);
        final age = DateTime.now().difference(lastSeenTime);
        if (age.inHours < 24) return 'away';
      } catch (_) {}
    }
    return 'offline';
  }

  /// Get status dot color: green=online, yellow=away, grey=offline
  Color _getStatusDotColor(String effectiveStatus) {
    switch (effectiveStatus) {
      case 'online':
        return const Color(0xFF00E676); // neon green
      case 'away':
        return const Color(0xFFFFC107); // yellow/amber
      default:
        return Colors.grey[600]!; // grey
    }
  }

  Widget _buildGroupTile(Group group) {
    final hasUnread = false; // TODO: Implement unread count for groups
    final lastMessageText = group.lastMessage?.content ?? 'No messages yet';
    final lastMessageTime = group.lastMessage?.formattedTime ?? '';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Stack(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: const Color(0xFF00D9FF),
            child: group.avatarUrl != null
                ? ClipOval(
                    child: Image.network(
                      group.avatarUrl!,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.group,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  )
                : const Icon(Icons.group, color: Colors.white, size: 28),
          ),
        ],
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              group.name,
              style: TextStyle(
                color: Colors.white,
                fontWeight: hasUnread ? FontWeight.bold : FontWeight.w500,
                fontSize: 16,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (lastMessageTime.isNotEmpty)
            Text(
              lastMessageTime,
              style: TextStyle(
                color: hasUnread ? const Color(0xFF00D9FF) : Colors.grey[500],
                fontSize: 12,
                fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal,
              ),
            ),
        ],
      ),
      subtitle: Row(
        children: [
          Expanded(
            child: Text(
              '${group.memberCount} members • $lastMessageText',
              style: TextStyle(
                color: hasUnread ? Colors.white70 : Colors.grey[400],
                fontSize: 14,
                fontWeight: hasUnread ? FontWeight.w500 : FontWeight.normal,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => GroupChatScreen(group: group),
          ),
        );
      },
    );
  }

  Widget _buildUserTile(LobbyUser user, {bool isOnlineSection = false}) {
    final avatarColor = _getAvatarColor(user.avatarColorIndex);
    final effectiveStatus = _getEffectiveStatus(user);

    // Format last seen date for offline users
    String _formatLastSeenDate(String? lastSeen) {
      if (lastSeen == null) return '';
      try {
        final dateTime = _parseUtcTimestamp(lastSeen);
        return 'Last seen: ${dateTime.month}/${dateTime.day}/${dateTime.year}';
      } catch (e) {
        return '';
      }
    }

    // Get last message preview
    String _getLastMessagePreview() {
      if (user.lastMessage != null && user.lastMessage!.isNotEmpty) {
        final prefix = user.lastMessageIsFromMe == true ? 'You: ' : '';
        final message = user.lastMessage!.length > 25
            ? '${user.lastMessage!.substring(0, 25)}...'
            : user.lastMessage!;
        final checkmark = user.lastMessageIsFromMe == true ? ' ✓' : '';
        return '$prefix$message$checkmark';
      }
      return 'No messages yet';
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF252542),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            // Clear unread count locally before navigating
            setState(() {
              final userIndex = _lobbyUsers.indexWhere((u) => u.id == user.id);
              if (userIndex != -1) {
                final updatedUser = LobbyUser(
                  id: user.id,
                  username: user.username,
                  email: user.email,
                  firstName: user.firstName,
                  lastName: user.lastName,
                  fullName: user.fullName,
                  avatarUrl: user.avatarUrl,
                  bio: user.bio,
                  status: user.status,
                  statusMessage: user.statusMessage,
                  lastSeen: user.lastSeen,
                  isOnline: user.isOnline,
                  isAdmin: user.isAdmin,
                  timezone: user.timezone,
                  unreadCount: 0,
                  isContact: user.isContact,
                  isAdminUser: user.isAdminUser,
                  lastMessage: user.lastMessage,
                  lastMessageTime: user.lastMessageTime,
                  lastMessageIsFromMe: user.lastMessageIsFromMe,
                );
                _lobbyUsers[userIndex] = updatedUser;
                _filterUsers();
              }
            });

            // Navigate to chat screen
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ChatScreen(otherUser: user),
              ),
            ).then((_) async {
              // Mark messages from this user as read via REST (fallback for any
              // messages the socket handler may have missed while offline)
              try {
                final token = await StorageService.getToken();
                if (token != null) {
                  // Find the most recent message ID (use a large int as sentinel)
                  await http.post(
                    Uri.parse(ApiConfig.markReadUrl),
                    headers: {
                      'Content-Type': 'application/json',
                      'Authorization': 'Bearer $token',
                    },
                    body: jsonEncode({
                      'sender_id': user.id,
                      'last_message_id':
                          2147483647, // INT_MAX — marks ALL messages
                    }),
                  );
                }
              } catch (e) {
                debugPrint('[LOBBY] mark-read REST fallback failed: $e');
              }
              // Reload lobby and restore socket listeners when returning from chat
              _loadLobby();
              _setupRealtimeListeners();
            });
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Avatar with online indicator
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: avatarColor,
                      child: user.avatarUrl != null
                          ? ClipOval(
                              child: Image.network(
                                user.avatarUrl!,
                                width: 52,
                                height: 52,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Text(
                                    user.initials,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  );
                                },
                              ),
                            )
                          : Text(
                              user.initials,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                    // Status indicator dot (green=online, yellow=away, grey=offline)
                    Positioned(
                      right: 2,
                      bottom: 2,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: _getStatusDotColor(effectiveStatus),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFF252542),
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                // User info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name
                      Text(
                        user.fullName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      // Email (admin-only view)
                      if (_isCurrentUserAdmin && user.email.isNotEmpty)
                        Text(
                          user.email,
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 11,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      const SizedBox(height: 2),
                      // Online/Away/Offline status with relative time
                      Text(
                        effectiveStatus == 'online'
                            ? 'Online'
                            : effectiveStatus == 'away'
                            ? _formatRelativeTime(user.lastSeen)
                            : _formatRelativeTime(user.lastSeen),
                        style: TextStyle(
                          color: effectiveStatus == 'online'
                              ? const Color(0xFF00E676)
                              : effectiveStatus == 'away'
                              ? const Color(0xFFFFC107)
                              : Colors.grey[500],
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      // Last message preview OR typing indicator
                      _typingUsers.containsKey(user.id)
                          ? const _TypingIndicator()
                          : Text(
                              _getLastMessagePreview(),
                              style: TextStyle(
                                color: Colors.grey[400],
                                fontSize: 12,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                    ],
                  ),
                ),
                // Time + Unread badge column (WhatsApp style)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Last message time
                    if (user.lastMessageTime != null)
                      Text(
                        _formatTime(user.lastMessageTime),
                        style: TextStyle(
                          color: user.unreadCount > 0
                              ? const Color(0xFF00D9FF)
                              : Colors.grey[500],
                          fontSize: 11,
                          fontWeight: user.unreadCount > 0
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    if (user.unreadCount > 0) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE91E63),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          user.unreadCount > 99 ? '99+' : '${user.unreadCount}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Static typing indicator label
class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'typing...',
      style: TextStyle(
        color: Color(0xFF00D9FF),
        fontSize: 12,
        fontStyle: FontStyle.italic,
      ),
    );
  }
}
