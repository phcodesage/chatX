import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';
import '../models/lobby_user.dart';
import '../models/group.dart';
import '../models/message.dart';
import '../services/lobby_service.dart';
import '../services/group_service.dart';
import '../services/auth_service.dart';
import '../services/socket_service.dart';
import '../widgets/app_version_text.dart';
import '../services/call_service.dart';
import '../widgets/incoming_call_setup_modal.dart';
import 'chat_screen.dart' show ChatScreen;
import 'connected_call_screen.dart';
import 'group_chat_screen.dart';
import 'create_group_screen.dart';
import 'sign_in_page.dart';
import '../services/storage_service.dart';
import '../config/api_config.dart';
import '../services/presence_service.dart';
import '../services/chat_cache_service.dart';
import '../services/share_intent_service.dart';
import '../services/shortcut_service.dart';
import '../utils/notification_handler.dart';
import 'share_target_screen.dart';
import 'ai_chat_screen.dart';

/// Lobby/Chat list screen
class LobbyScreen extends StatefulWidget {
  static const route = '/lobby';
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

enum LobbyQuickFilter { all, online, groups, offline }

class _LobbyScreenState extends State<LobbyScreen> {
  List<LobbyUser> _lobbyUsers = [];
  List<LobbyUser> _filteredUsers = [];
  List<Group> _groups = []; // Group chats
  List<Group> _filteredGroups = []; // Filtered group chats
  bool _isLoading = false;
  bool _isCurrentUserAdmin = false;
  LobbyQuickFilter _activeFilter = LobbyQuickFilter.all;
  final TextEditingController _searchController = TextEditingController();
  final SocketService _socketService = SocketService();
  Timer? _lastSeenRefreshTimer;
  Timer? _searchDebounceTimer;
  StreamSubscription<List<SharedMediaItem>>? _shareIntentSubscription;
  StreamSubscription<int>? _shortcutLaunchSubscription;
  Future<int?> _currentUserId = StorageService.getUserId();
  bool _isSharePickerOpen = false;
  bool _hasAiSession = false;
  String? _aiLastMessageTime;
  String? _aiLastMessagePreview;
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

  bool get _showAiSuggestion => _searchController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadLobby();
    _loadAiSessionPresence();
    _loadAdminStatus();
    _searchController.addListener(_onSearchQueryChanged);
    _setupRealtimeListeners();
    _setupShareIntentListener();
    _setupShortcutLaunchListener();
    // Periodically refresh "last seen" relative labels (like the web app does)
    _lastSeenRefreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) setState(() {});
    });

    // Check for pending notification navigation after lobby is ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPendingNotification();
    });
  }

  /// Check if there's a pending notification to handle
  void _checkPendingNotification() {
    debugPrint('📱 LobbyScreen: Checking for pending notifications...');
    final pendingData = NotificationHandler.getPendingNotificationData();
    if (pendingData != null) {
      debugPrint(
        '📱 LobbyScreen: Processing pending notification: $pendingData',
      );
      // Wait a bit to ensure lobby is fully rendered
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          NotificationHandler.handleNotificationTap(
            pendingData,
            fromPending: true,
          );
        }
      });
    } else {
      debugPrint('📱 LobbyScreen: No pending notifications found');
    }
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

    // FALLBACK: Also listen for crossRoomCallOffer in case backend only sends this event
    // This handles cases where web clients call mobile and backend doesn't send 'incomingCall'
    _socketService.addListener('crossRoomCallOffer', key, (
      Map<String, dynamic> data,
    ) {
      debugPrint(
        '📲 Fallback: Received crossRoomCallOffer, converting to incomingCall format',
      );
      debugPrint('📲 Original crossRoomCallOffer data: $data');

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

      debugPrint('📲 Converted to incomingCall format: $convertedData');
      _handleIncomingCall(convertedData);
    });

    // Backend reconnected - presence snapshot will follow automatically
    // from the server, so we don't need to force a full reload here.
    // This prevents UI flickering and allows smooth presence updates.
    _socketService.addListener('reconnected', key, () {
      debugPrint('🔄 Backend reconnected - waiting for presence snapshot');
    });

    // Listen for group events
    // Group management events using standardized socket service listeners
    _socketService.addListener('groupCreated', key, (dynamic data) {
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

    _socketService.addListener('groupUpdated', key, (dynamic data) {
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

    _socketService.addListener('groupMemberAdded', key, (dynamic data) {
      debugPrint('👥 Group member added event received: $data');
      if (data is Map<String, dynamic>) {
        final groupData = data['group'] as Map<String, dynamic>?;
        final addedUserIds = List<int>.from(data['added_user_ids'] ?? []);

        if (groupData != null && mounted) {
          _currentUserId.then((userId) {
            if (userId != null && addedUserIds.contains(userId)) {
              // Current user was added to the group
              try {
                final newGroup = Group.fromJson(groupData);
                setState(() {
                  // Check if group already exists (shouldn't happen, but safety check)
                  final existingIndex = _groups.indexWhere(
                    (g) => g.id == newGroup.id,
                  );
                  if (existingIndex == -1) {
                    _groups.insert(0, newGroup);
                  } else {
                    _groups[existingIndex] = newGroup;
                  }
                });
                _filterUsers();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Added to group: ${newGroup.name}'),
                    backgroundColor: Colors.green,
                  ),
                );
              } catch (e) {
                debugPrint('❌ Error parsing group_member_added event: $e');
              }
            } else {
              // Another member was added, update existing group if we have it
              try {
                final updatedGroup = Group.fromJson(groupData);
                final index = _groups.indexWhere(
                  (g) => g.id == updatedGroup.id,
                );
                if (index != -1) {
                  setState(() {
                    _groups[index] = updatedGroup;
                  });
                  _filterUsers();
                }
              } catch (e) {
                debugPrint('❌ Error updating group after member added: $e');
              }
            }
          });
        }
      }
    });

    _socketService.addListener('groupDeleted', key, (dynamic data) {
      debugPrint('🗑️ Group deleted event received: $data');
      if (data is Map<String, dynamic>) {
        final groupId = data['group_id'] as int?;
        final groupName = data['group_name'] as String?;

        if (groupId != null && mounted) {
          setState(() {
            _groups.removeWhere((g) => g.id == groupId);
          });
          _filterUsers();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Group deleted: ${groupName ?? 'Unknown'}'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    });

    _socketService.addListener('groupMemberLeft', key, (dynamic data) {
      debugPrint('👋 Group member removed event received: $data');
      debugPrint('👋 Event data type: ${data.runtimeType}');
      if (data is Map<String, dynamic>) {
        int? groupId;
        int? removedUserId;

        // Handle different event data structures
        if (data.containsKey('group_id') && data.containsKey('user_id')) {
          // Structure: {group_id: 6, user_id: 16} - from group_member_left
          groupId = data['group_id'] as int?;
          removedUserId = data['user_id'] as int?;
          debugPrint('👋 Using group_member_left structure');
        } else if (data.containsKey('group')) {
          // Structure: {group: {...}} - from group_member_removed
          final groupData = data['group'] as Map<String, dynamic>?;
          if (groupData != null) {
            groupId = groupData['id'] as int?;
            // For group_member_removed, we need to determine which user was removed
            // by comparing the current member list with our stored list
            // For now, we'll check if current user is still in the members list
            final members = groupData['members'] as List?;
            if (members != null) {
              _currentUserId.then((userId) {
                if (userId != null) {
                  final isCurrentUserInGroup = members.any((member) {
                    final memberData = member as Map<String, dynamic>;
                    final memberUserId = memberData['user_id'] as int?;
                    return memberUserId == userId;
                  });

                  debugPrint(
                    '👋 Current user ($userId) in group: $isCurrentUserInGroup',
                  );

                  if (!isCurrentUserInGroup) {
                    // Current user was removed
                    debugPrint(
                      '👋 Current user ($userId) not found in member list, was removed from group $groupId',
                    );
                    setState(() {
                      final initialCount = _groups.length;
                      _groups.removeWhere((g) => g.id == groupId);
                      final finalCount = _groups.length;
                      debugPrint(
                        '👋 Groups count: $initialCount → $finalCount',
                      );
                    });
                    _filterUsers();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('You were removed from a group'),
                        backgroundColor: Colors.orange,
                      ),
                    );
                  } else {
                    debugPrint(
                      '👋 Current user still in group, another member was removed',
                    );
                    // Another member was removed, reload group details
                    _loadLobby(useCacheFirst: false);
                  }
                }
              });
            }
          }
          debugPrint('👋 Using group_member_removed structure');
          return; // Exit early for this structure as we handle it above
        }

        debugPrint(
          '👋 Parsed groupId: $groupId, removedUserId: $removedUserId',
        );

        if (groupId != null && removedUserId != null && mounted) {
          _currentUserId.then((userId) {
            debugPrint(
              '👋 Current userId: $userId, comparing with removedUserId: $removedUserId',
            );
            if (userId == removedUserId) {
              debugPrint(
                '👋 Current user was removed from group $groupId, removing from list',
              );
              // Current user was removed, remove group from list
              setState(() {
                final initialCount = _groups.length;
                _groups.removeWhere((g) => g.id == groupId);
                final finalCount = _groups.length;
                debugPrint('👋 Groups count: $initialCount → $finalCount');
              });
              _filterUsers();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('You were removed from a group'),
                  backgroundColor: Colors.orange,
                ),
              );
            } else {
              debugPrint('👋 Another member was removed, reloading lobby');
              // Another member was removed, reload group details
              _loadLobby(useCacheFirst: false);
            }
          });
        } else {
          debugPrint(
            '👋 Missing required data: groupId=$groupId, removedUserId=$removedUserId, mounted=$mounted',
          );
        }
      } else {
        debugPrint('👋 Event data is not a Map: $data');
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

  void _setupShareIntentListener() {
    _shareIntentSubscription?.cancel();
    _shareIntentSubscription = ShareIntentService.instance.sharedItemsStream
        .listen((_) {
          _openSharePickerIfNeeded();
        });
  }

  void _setupShortcutLaunchListener() {
    _shortcutLaunchSubscription?.cancel();
    _shortcutLaunchSubscription = ShortcutService.instance.shortcutTargetStream
        .listen((userId) {
          _openShortcutChatIfNeeded(userId);
        });
  }

  Future<void> _openShortcutChatIfNeeded(int userId) async {
    if (!mounted) return;

    LobbyUser? targetUser;
    for (final user in _lobbyUsers) {
      if (user.id == userId) {
        targetUser = user;
        break;
      }
    }

    if (targetUser == null) {
      try {
        final refreshedUsers = await LobbyService.getLobbyUsers();
        if (!mounted) return;
        setState(() {
          _lobbyUsers = _sortUsersByRecentActivity(refreshedUsers);
        });
        _filterUsers();
        for (final user in _lobbyUsers) {
          if (user.id == userId) {
            targetUser = user;
            break;
          }
        }
      } catch (e) {
        debugPrint('Failed to refresh users for shortcut launch: $e');
      }
    }

    if (!mounted || targetUser == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ChatScreen(otherUser: targetUser!)),
    );
  }

  Future<void> _openSharePickerIfNeeded() async {
    if (!mounted || _isSharePickerOpen) {
      return;
    }

    if (!ShareIntentService.instance.hasPendingItems) {
      return;
    }

    final sharedItems = await ShareIntentService.instance
        .takePendingSharedItems();
    if (!mounted || sharedItems.isEmpty) {
      return;
    }

    _isSharePickerOpen = true;
    try {
      // If the items arrived via a Direct Share shortcut tap, grab the target user id
      // so ShareTargetScreen can pre-select and auto-send without user interaction.
      final directShareUserId = sharedItems
          .map((i) => i.directShareUserId)
          .firstWhere((id) => id != null, orElse: () => null) ??
          await ShareIntentService.instance.takePendingDirectShareUserId();

      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              ShareTargetScreen(
                sharedItems: sharedItems,
                users: _lobbyUsers,
                directShareUserId: directShareUserId,
              ),
        ),
      );

      if (!mounted || result is! Map<String, dynamic>) {
        return;
      }

      final sentCount = result['sentCount'] as int? ?? 0;
      final failedCount = result['failedCount'] as int? ?? 0;

      if (sentCount > 0) {
        final message = failedCount > 0
            ? 'Sent to $sentCount chats, failed for $failedCount.'
            : 'Sent to $sentCount chats.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: failedCount > 0 ? Colors.orange : Colors.green,
          ),
        );
        _loadLobby(useCacheFirst: false);
      }
    } finally {
      _isSharePickerOpen = false;
    }
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

    // Initialize call service (fetches ICE servers)
    final callService = CallService();
    await callService.initialize();

    // CRITICAL: Set call state BEFORE setting up signal handler
    // This ensures that when buffered signals are processed, the call state is already set
    callService.handleIncomingCall(data);
    debugPrint('📲 Call state set to ringing, now setting up signal handler');

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

  int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  String? _extractEventTimestamp(Map<String, dynamic> data) {
    final createdAt = data['created_at'];
    if (createdAt is String && createdAt.trim().isNotEmpty) {
      return createdAt.trim();
    }

    final timestamp = data['timestamp'];
    if (timestamp is String && timestamp.trim().isNotEmpty) {
      return timestamp.trim();
    }

    final timestampMs = _toInt(data['timestamp_ms']);
    if (timestampMs != null && timestampMs > 0) {
      return DateTime.fromMillisecondsSinceEpoch(
        timestampMs,
        isUtc: true,
      ).toIso8601String();
    }

    final nestedMessage = data['message'];
    if (nestedMessage is Map<String, dynamic>) {
      final nestedCreatedAt = nestedMessage['created_at'];
      if (nestedCreatedAt is String && nestedCreatedAt.trim().isNotEmpty) {
        return nestedCreatedAt.trim();
      }

      final nestedTimestamp = nestedMessage['timestamp'];
      if (nestedTimestamp is String && nestedTimestamp.trim().isNotEmpty) {
        return nestedTimestamp.trim();
      }

      final nestedTimestampMs = _toInt(nestedMessage['timestamp_ms']);
      if (nestedTimestampMs != null && nestedTimestampMs > 0) {
        return DateTime.fromMillisecondsSinceEpoch(
          nestedTimestampMs,
          isUtc: true,
        ).toIso8601String();
      }
    }

    return null;
  }

  void _handleNewMessage(Map<String, dynamic> data) {
    final senderId = _toInt(data['sender_id']);
    if (senderId == null) return;
    final content = data['content'] as String?;
    final createdAt = _extractEventTimestamp(data);

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
    final senderId = _toInt(data['sender_id']);
    final currentUserId = _socketService.currentUserId;
    final recipientId =
        _toInt(data['recipient_id']) ??
        _toInt(data['receiver_id']) ??
        ((senderId != null && senderId == currentUserId)
            ? currentUserId
            : null);
    if (recipientId == null) return;
    final content = data['content'] as String?;
    final createdAt = _extractEventTimestamp(data);

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
    final senderId = _toInt(data['sender_id']);
    if (senderId == null) return;
    final fileName = data['file_name'] as String?;
    final createdAt = _extractEventTimestamp(data);

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
    final senderId = _toInt(data['sender_id']);
    if (senderId == null) return;
    final duration = data['duration'] as int?;
    final createdAt = _extractEventTimestamp(data);

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
          // ✅ IMPORTANT: Preserve message info from in-memory state
          lastMessage: user.lastMessage,
          lastMessageTime: user.lastMessageTime,
          lastMessageIsFromMe: user.lastMessageIsFromMe,
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
                // ✅ IMPORTANT: Preserve message info from in-memory state
                // This prevents messages received via socket from being wiped out
                lastMessage: user.lastMessage,
                lastMessageTime: user.lastMessageTime,
                lastMessageIsFromMe: user.lastMessageIsFromMe,
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
    _searchController.removeListener(_onSearchQueryChanged);
    _searchDebounceTimer?.cancel();
    _searchController.dispose();
    _lastSeenRefreshTimer?.cancel();
    // Cancel all active typing timers
    for (final timer in _typingUsers.values) {
      timer.cancel();
    }
    _typingUsers.clear();
    _shareIntentSubscription?.cancel();
    _shortcutLaunchSubscription?.cancel();
    // Clear all lobby socket listeners to prevent memory leaks
    _socketService.removeListenersForKey('lobby');
    super.dispose();
  }

  void _onSearchQueryChanged() {
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      _filterUsers();
    });
  }

  Future<void> _loadLobby({bool useCacheFirst = true}) async {
    if (_isLoading && useCacheFirst) return;
    setState(() => _isLoading = true);
    final userId = await StorageService.getUserId();
    if (useCacheFirst && userId != null) {
      final cached = await ChatCacheService.loadLobbyUsers(userId);
      if (cached.isNotEmpty && mounted) {
        final username = await StorageService.getUsername();
        final usersWithSelf = await _ensureSelfUserInLobby(
          users: cached,
          currentUserId: userId,
          currentUsername: username,
        );
        final sortedCachedUsers = _sortUsersByRecentActivity(usersWithSelf);
        setState(() {
          _lobbyUsers = sortedCachedUsers;
          _filteredUsers = List.from(sortedCachedUsers);
        });
        _filterUsers();
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

      final fetchedUsers = results[0] as List<LobbyUser>;
      final username = await StorageService.getUsername();
      final usersWithSelf = await _ensureSelfUserInLobby(
        users: fetchedUsers,
        currentUserId: userId,
        currentUsername: username,
      );
      final users = _sortUsersByRecentActivity(usersWithSelf);
      final groups = _sortGroupsByRecentActivity(results[1] as List<Group>);

      if (mounted) {
        setState(() {
          _lobbyUsers = users;
          _groups = groups;
          _isLoading = false;
        });
        _filterUsers();
        _openSharePickerIfNeeded();
        // Publish direct-share shortcuts so contacts appear in top row of share sheet
        ShortcutService.publishShareTargets(users);
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
        });
        _openSharePickerIfNeeded();
      }
      debugPrint('Error loading lobby: $e');
    }
  }

  Future<void> _loadAiSessionPresence() async {
    final userId = await StorageService.getUserId();
    if (userId == null) {
      if (!mounted) return;
      setState(() {
        _hasAiSession = false;
      });
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final sessionId = prefs.getInt('ai_session_id_$userId');
    final aiLastMessageTime = prefs.getString('ai_last_message_time_$userId');
    final aiLastMessagePreview = prefs.getString('ai_last_message_preview_$userId');

    if (!mounted) return;
    setState(() {
      _hasAiSession = sessionId != null;
      _aiLastMessageTime = aiLastMessageTime;
      _aiLastMessagePreview = aiLastMessagePreview;
    });
  }

  Future<List<LobbyUser>> _ensureSelfUserInLobby({
    required List<LobbyUser> users,
    required int? currentUserId,
    required String? currentUsername,
  }) async {
    if (currentUserId == null) return users;

    final exists = users.any((user) => user.id == currentUserId);
    if (exists) {
      return _hydrateSelfUserFromCache(
        users: users,
        currentUserId: currentUserId,
      );
    }

    final syntheticSelfUser = LobbyUser(
      id: currentUserId,
      username: (currentUsername?.trim().isNotEmpty ?? false)
          ? currentUsername!.trim()
          : 'you',
      email: '',
      firstName: 'You',
      lastName: '',
      fullName: 'You',
      avatarUrl: null,
      bio: null,
      status: 'online',
      statusMessage: null,
      lastSeen: null,
      isOnline: true,
      isAdmin: false,
      timezone: 'UTC',
      unreadCount: 0,
      isContact: true,
      isAdminUser: false,
      lastMessage: null,
      lastMessageTime: null,
      lastMessageIsFromMe: null,
    );

    final withSelf = List<LobbyUser>.from(users)..add(syntheticSelfUser);
    return _hydrateSelfUserFromCache(
      users: withSelf,
      currentUserId: currentUserId,
    );
  }

  Future<List<LobbyUser>> _hydrateSelfUserFromCache({
    required List<LobbyUser> users,
    required int currentUserId,
  }) async {
    final selfIndex = users.indexWhere((user) => user.id == currentUserId);
    if (selfIndex == -1) return users;

    final selfUser = users[selfIndex];
    final cachedMessages = await ChatCacheService.loadConversationMessages(
      currentUserId,
      currentUserId,
    );
    if (cachedMessages.isEmpty) return users;

    Message latestMessage = cachedMessages.first;
    for (final candidate in cachedMessages.skip(1)) {
      final candidateTime = candidate.timestampMs > 0
          ? DateTime.fromMillisecondsSinceEpoch(candidate.timestampMs)
          : _parseMessageTime(candidate.timestamp);
      final latestTime = latestMessage.timestampMs > 0
          ? DateTime.fromMillisecondsSinceEpoch(latestMessage.timestampMs)
          : _parseMessageTime(latestMessage.timestamp);
      if (candidateTime.isAfter(latestTime)) {
        latestMessage = candidate;
      }
    }

    final cachedTimestamp = latestMessage.timestamp.trim();
    final hasCurrentPreview = selfUser.lastMessage?.trim().isNotEmpty ?? false;
    final hasCurrentTime = selfUser.lastMessageTime?.trim().isNotEmpty ?? false;
    final shouldUseCachedMessage =
        !hasCurrentPreview ||
        !hasCurrentTime ||
        _parseMessageTime(cachedTimestamp).isAfter(
          _parseMessageTime(selfUser.lastMessageTime),
        );
    if (!shouldUseCachedMessage) {
      return users;
    }

    final hydratedUsers = List<LobbyUser>.from(users);
    hydratedUsers[selfIndex] = LobbyUser(
      id: selfUser.id,
      username: selfUser.username,
      email: selfUser.email,
      firstName: selfUser.firstName,
      lastName: selfUser.lastName,
      fullName: selfUser.fullName,
      avatarUrl: selfUser.avatarUrl,
      bio: selfUser.bio,
      status: selfUser.status,
      statusMessage: selfUser.statusMessage,
      lastSeen: selfUser.lastSeen,
      isOnline: selfUser.isOnline,
      isAdmin: selfUser.isAdmin,
      timezone: selfUser.timezone,
      unreadCount: 0,
      isContact: selfUser.isContact,
      isAdminUser: selfUser.isAdminUser,
      lastMessage: _previewTextForMessage(latestMessage),
      lastMessageTime: cachedTimestamp,
      lastMessageIsFromMe: true,
    );
    return hydratedUsers;
  }

  String _previewTextForMessage(Message message) {
    switch (message.messageType.toLowerCase()) {
      case 'image':
        return message.fileName?.trim().isNotEmpty == true
            ? '📷 ${message.fileName!.trim()}'
            : '📷 Photo';
      case 'video':
        return message.fileName?.trim().isNotEmpty == true
            ? '🎬 ${message.fileName!.trim()}'
            : '🎬 Video';
      case 'audio':
      case 'voice':
        return '🎤 Voice message';
      case 'file':
      case 'document':
        return message.fileName?.trim().isNotEmpty == true
            ? '📎 ${message.fileName!.trim()}'
            : '📎 File';
      default:
        final trimmedContent = message.content.trim();
        return trimmedContent.isNotEmpty ? trimmedContent : 'No messages yet';
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
    // Trust explicit online presence first to avoid false "last seen" labels.
    if (user.isOnline) {
      return 0;
    }
    if (user.status == 'online') {
      if (user.lastSeen != null) {
        try {
          final lastSeenTime = _parseUtcTimestamp(user.lastSeen!);
          final age = DateTime.now().difference(lastSeenTime);
          if (age.inMinutes <= 2) return 0;
          return age.inHours < 24 ? 1 : 2;
        } catch (_) {
          return 0;
        }
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

  DateTime _parseMessageTime(String? timestamp) {
    if (timestamp == null || timestamp.isEmpty) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
    try {
      return _parseUtcTimestamp(timestamp);
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  List<LobbyUser> _sortUsersByRecentActivity(List<LobbyUser> users) {
    final sortedUsers = List<LobbyUser>.from(users);
    sortedUsers.sort((a, b) {
      final timeCompare = _parseMessageTime(
        b.lastMessageTime,
      ).compareTo(_parseMessageTime(a.lastMessageTime));
      if (timeCompare != 0) return timeCompare;
      return a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());
    });
    return sortedUsers;
  }

  /// Builds a time-sorted list of user tiles interleaved with the AI tile,
  /// so the most recently active conversation always rises to the top.
  List<Widget> _buildSortedUserAndAiTiles(
    List<LobbyUser> users, {
    bool includeAi = false,
    bool isOnlineSection = false,
  }) {
    final entries = <({DateTime time, Widget tile})>[];

    for (final user in users) {
      entries.add((
        time: _parseMessageTime(user.lastMessageTime),
        tile: _buildUserTile(user, isOnlineSection: isOnlineSection),
      ));
    }

    if (includeAi) {
      entries.add((
        time: _parseMessageTime(_aiLastMessageTime),
        tile: _buildAiChatTile(),
      ));
    }

    entries.sort((a, b) => b.time.compareTo(a.time));
    return entries.map((e) => e.tile).toList();
  }

  List<Group> _sortGroupsByRecentActivity(List<Group> groups) {
    final sortedGroups = List<Group>.from(groups);
    sortedGroups.sort((a, b) {
      final timeCompare = (b.lastMessage?.timestampMs ?? 0).compareTo(
        a.lastMessage?.timestampMs ?? 0,
      );
      if (timeCompare != 0) return timeCompare;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return sortedGroups;
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

      filtered = _sortUsersByRecentActivity(filtered);
      filteredGroups = _sortGroupsByRecentActivity(filteredGroups);

      _filteredUsers = filtered;
      _filteredGroups = filteredGroups;
    });
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

  int _activeFilterIndex() {
    switch (_activeFilter) {
      case LobbyQuickFilter.all:
        return 0;
      case LobbyQuickFilter.online:
        return 1;
      case LobbyQuickFilter.groups:
        return 2;
      case LobbyQuickFilter.offline:
        return 3;
    }
  }

  void _setActiveFilter(int index) {
    setState(() {
      switch (index) {
        case 0:
          _activeFilter = LobbyQuickFilter.all;
          break;
        case 1:
          _activeFilter = LobbyQuickFilter.online;
          break;
        case 2:
          _activeFilter = LobbyQuickFilter.groups;
          break;
        case 3:
          _activeFilter = LobbyQuickFilter.offline;
          break;
      }
    });
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
          // Create group button (only for admin users)
          if (_isCurrentUserAdmin)
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
            )
          else
            // Show admin-only indicator for non-admin users
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.admin_panel_settings,
                    color: Colors.grey[500],
                    size: 12,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Admin only',
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
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
    // Split users into status tiers for quick filter tabs.
    final onlineUsers = _filteredUsers
        .where((u) => _getStatusTier(u) == 0)
        .toList();
    final offlineUsers = _filteredUsers
        .where((u) => _getStatusTier(u) != 0)
        .toList();

    final selectedUsers = switch (_activeFilter) {
      LobbyQuickFilter.all => _filteredUsers,
      LobbyQuickFilter.online => onlineUsers,
      LobbyQuickFilter.groups => const <LobbyUser>[],
      LobbyQuickFilter.offline => offlineUsers,
    };

    final selectedSectionTitle = switch (_activeFilter) {
      LobbyQuickFilter.all => 'CHATS',
      LobbyQuickFilter.online => 'ONLINE',
      LobbyQuickFilter.groups => 'GROUPS',
      LobbyQuickFilter.offline => 'OFFLINE',
    };

    final selectedSectionColor = switch (_activeFilter) {
      LobbyQuickFilter.all => const Color(0xFF00D9FF),
      LobbyQuickFilter.online => const Color(0xFF00E676),
      LobbyQuickFilter.groups => const Color(0xFF00D9FF),
      LobbyQuickFilter.offline => Colors.grey,
    };

    final isFilterEmpty = _activeFilter == LobbyQuickFilter.all
        ? _filteredUsers.isEmpty && _filteredGroups.isEmpty
        : _activeFilter == LobbyQuickFilter.groups
        ? _filteredGroups.isEmpty
        : selectedUsers.isEmpty;

    final query = _searchController.text.trim().toLowerCase();
    final aiMatchesQuery =
      query.isEmpty || 'ask ai ai assistant ai chat'.contains(query);
    final showAiChatTile =
      _activeFilter == LobbyQuickFilter.all && _hasAiSession && aiMatchesQuery;
    final hasVisibleResults = !isFilterEmpty || showAiChatTile;

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        elevation: 0,
        centerTitle: true,
        title: const AppVersionText(),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white70),
            color: const Color(0xFF252542),
            onSelected: (value) {
              if (value == 'logout') {
                _handleLogout();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem<String>(
                value: 'logout',
                child: Text('Logout', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search conversations or Ask AI',
                hintStyle: TextStyle(color: Colors.grey[500]),
                prefixIcon: Icon(Icons.search, color: Colors.grey[500]),
                suffixIcon: _showAiSuggestion
                    ? Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: TextButton.icon(
                          onPressed: () {
                            final query = _searchController.text.trim();
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => AiChatScreen(
                                  initialPrompt: query,
                                ),
                              ),
                            ).then((_) {
                              _loadAiSessionPresence();
                              _loadLobby(useCacheFirst: false);
                            });
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF00D9FF),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          icon: const Icon(Icons.auto_awesome, size: 16),
                          label: const Text(
                            'Ask AI',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      )
                    : null,
                suffixIconConstraints: const BoxConstraints(
                  minWidth: 0,
                  minHeight: 0,
                ),
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
          Expanded(
            child: (_isLoading && _lobbyUsers.isEmpty && _groups.isEmpty)
                ? _buildLoadingShimmer()
                : !hasVisibleResults
                ? Center(
                    child: Text(
                      _searchController.text.isEmpty
                          ? _activeFilter == LobbyQuickFilter.all
                                ? 'No chats yet'
                                : 'No ${selectedSectionTitle.toLowerCase()} yet'
                          : 'No results found',
                      style: TextStyle(color: Colors.grey[500], fontSize: 16),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: () => _loadLobby(useCacheFirst: false),
                    color: const Color(0xFF00D9FF),
                    backgroundColor: const Color(0xFF252542),
                    child: ListView(
                      children: [
                        if (_activeFilter == LobbyQuickFilter.groups)
                          _buildGroupsSectionHeader(),
                        if (_activeFilter == LobbyQuickFilter.all &&
                            _filteredGroups.isNotEmpty)
                          _buildGroupsSectionHeader(),
                        if (_activeFilter != LobbyQuickFilter.all &&
                            _activeFilter != LobbyQuickFilter.groups)
                          _buildSectionHeader(
                            selectedSectionTitle,
                            selectedUsers.length,
                            selectedSectionColor,
                          ),
                        if (_activeFilter == LobbyQuickFilter.all) ...[
                          if (_filteredGroups.isNotEmpty)
                            ..._filteredGroups.map(
                              (group) => _buildGroupTile(group),
                            ),
                          ..._buildSortedUserAndAiTiles(
                            selectedUsers,
                            includeAi: showAiChatTile,
                          ),
                        ] else if (_activeFilter == LobbyQuickFilter.groups)
                          ..._filteredGroups.map(
                            (group) => _buildGroupTile(group),
                          )
                        else
                          ..._buildSortedUserAndAiTiles(
                            selectedUsers,
                            isOnlineSection:
                                _activeFilter == LobbyQuickFilter.online,
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: const Color(0xFF1A1A2E),
        indicatorColor: const Color(0xFF252542),
        selectedIndex: _activeFilterIndex(),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: _setActiveFilter,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard, color: Color(0xFF00D9FF)),
            label: 'Chats',
          ),
          NavigationDestination(
            icon: Icon(Icons.circle_outlined),
            selectedIcon: Icon(Icons.circle, color: Color(0xFF00E676)),
            label: 'Online',
          ),
          NavigationDestination(
            icon: Icon(Icons.groups_outlined),
            selectedIcon: Icon(Icons.groups, color: Color(0xFF00D9FF)),
            label: 'Groups',
          ),
          NavigationDestination(
            icon: Icon(Icons.circle_outlined),
            selectedIcon: Icon(Icons.circle, color: Colors.grey),
            label: 'Offline',
          ),
        ],
      ),
    );
  }

  /// Determine effective display status: online, away, or offline
  /// Matches the web app's recently-seen logic (yellow dot for offline users
  /// who were active within the last 24 hours)
  /// Also validates 'online' status against last_seen to detect stale DB entries
  String _getEffectiveStatus(LobbyUser user) {
    // Trust explicit online presence first to stay consistent with in-chat header.
    if (user.isOnline) {
      return 'online';
    }
    if (user.status == 'online') {
      if (user.lastSeen != null) {
        try {
          final lastSeenTime = _parseUtcTimestamp(user.lastSeen!);
          final age = DateTime.now().difference(lastSeenTime);
          if (age.inMinutes <= 2) return 'online';
          return age.inHours < 24 ? 'away' : 'offline';
        } catch (_) {
          return 'online';
        }
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
    final lastMessageText = group.lastMessage?.content ?? 'No messages yet';
    final lastMessageTime = group.lastMessage?.formattedTime ?? '';

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
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => GroupChatScreen(group: group),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Group avatar
                CircleAvatar(
                  radius: 26,
                  backgroundColor: const Color(0xFF00D9FF),
                  child: group.avatarUrl != null
                      ? ClipOval(
                          child: Image.network(
                            group.avatarUrl!,
                            width: 52,
                            height: 52,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return const Icon(
                                Icons.group,
                                color: Colors.white,
                                size: 26,
                              );
                            },
                          ),
                        )
                      : const Icon(Icons.group, color: Colors.white, size: 26),
                ),
                const SizedBox(width: 12),
                // Group info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Group name
                      Text(
                        group.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      // Member count
                      Text(
                        '${group.memberCount} members',
                        style: TextStyle(color: Colors.grey[500], fontSize: 13),
                      ),
                      const SizedBox(height: 2),
                      // Last message preview
                      Text(
                        lastMessageText,
                        style: TextStyle(color: Colors.grey[400], fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // Time + Unread badge column
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Last message time
                    if (lastMessageTime.isNotEmpty)
                      Text(
                        lastMessageTime,
                        style: TextStyle(
                          color: Colors.grey[500],
                          fontSize: 11,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUserTile(LobbyUser user, {bool isOnlineSection = false}) {
    final avatarColor = _getAvatarColor(user.avatarColorIndex);
    final effectiveStatus = _getEffectiveStatus(user);
    final isSelfChatTile = user.id == _socketService.currentUserId;
    final displayUnreadCount = isSelfChatTile ? 0 : user.unreadCount;

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
              _loadLobby(useCacheFirst: false);
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
                          color: displayUnreadCount > 0
                              ? const Color(0xFF00D9FF)
                              : Colors.grey[500],
                          fontSize: 11,
                          fontWeight: displayUnreadCount > 0
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    if (displayUnreadCount > 0) ...[
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
                          displayUnreadCount > 99 ? '99+' : '$displayUnreadCount',
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

  Widget _buildAiChatTile() {
    final preview = _aiLastMessagePreview ?? 'Start a conversation';
    final timeLabel = _aiLastMessageTime != null
        ? _formatTime(_aiLastMessageTime!)
        : '';

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
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const AiChatScreen(),
              ),
            ).then((_) {
              _loadAiSessionPresence();
              _loadLobby(useCacheFirst: false);
            });
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Bot avatar — gradient circle with smart_toy icon
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00C9A7), Color(0xFF845EC2)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(26),
                  ),
                  child: const Icon(
                    Icons.smart_toy_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'AI Chat',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFF00E676),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        preview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.grey[400], fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      timeLabel,
                      style: TextStyle(color: Colors.grey[500], fontSize: 11),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Always on',
                      style: TextStyle(
                        color: const Color(0xFF00E676),
                        fontSize: 10,
                      ),
                    ),
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
