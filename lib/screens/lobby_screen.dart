import 'package:flutter/material.dart';
import '../models/lobby_user.dart';
import '../services/lobby_service.dart';
import '../services/auth_service.dart';
import '../services/socket_service.dart';
import '../services/call_service.dart';
import '../widgets/incoming_call_setup_modal.dart';
import 'sign_in_page.dart';
import 'chat_screen.dart';
import 'connected_call_screen.dart';

/// Lobby/Chat list screen
class LobbyScreen extends StatefulWidget {
  static const route = '/lobby';
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  List<LobbyUser> _lobbyUsers = [];
  List<LobbyUser> _filteredUsers = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  final SocketService _socketService = SocketService();

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
    _searchController.addListener(_filterUsers);
    _setupRealtimeListeners();
  }

  void _setupRealtimeListeners() {
    // Listen for doorbell rings
    _socketService.onDoorbellRing = (data) {
      _handleDoorbellRing(data);
    };

    // Listen for new messages
    _socketService.onMessageReceived = (data) {
      _handleNewMessage(data);
    };

    // Listen for presence updates
    _socketService.onPresenceUpdate = (data) {
      _updateUserPresence(data);
    };

    // Listen for incoming calls (global handler)
    _socketService.onIncomingCall = (data) {
      _handleIncomingCall(data);
    };
    
    // Listen for cross-room call offers (from web client)
    _socketService.onCrossRoomCallOffer = (data) {
      _handleCrossRoomCallOffer(data);
    };
  }
  
  /// Handle cross-room call offer from web client
  Future<void> _handleCrossRoomCallOffer(Map<String, dynamic> data) async {
    if (!mounted) return;
    
    debugPrint('📲 Cross-room call offer received in lobby: $data');
    
    final callerId = data['caller_id'] as int?;
    final callerUsername = data['caller_username'] as String? ?? 'Unknown';
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
            ),
          ),
        );
      }
    });
  }

  /// Handle incoming call from another user
  Future<void> _handleIncomingCall(Map<String, dynamic> data) async {
    if (!mounted) return;
    
    debugPrint('📲 Incoming call received in lobby: $data');
    
    final callId = data['id'] as int?;
    final callRoomId = data['call_room_id'] as String?;
    final callType = data['call_type'] as String? ?? 'video';
    final callerData = data['caller'] as Map<String, dynamic>?;
    final callerId = callerData?['id'] as int? ?? data['caller_id'] as int?;
    final callerName = callerData?['full_name'] as String? ?? 
                       callerData?['username'] as String? ?? 
                       'Unknown';
    
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
            ),
          ),
        );
      }
    });
  }

  void _handleDoorbellRing(Map<String, dynamic> data) {
    final senderId = data['sender_id'] as int;
    final senderName = data['sender_name'] as String;
    
    // Only show dialog if we're still on the lobby screen (not in a chat)
    if (!mounted) return;
    
    // Find the user in the lobby
    final user = _lobbyUsers.firstWhere(
      (u) => u.id == senderId,
      orElse: () => _lobbyUsers.first, // fallback
    );

    // Show doorbell notification only in lobby
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D2D),
        title: Row(
          children: [
            const Icon(Icons.notifications_active, color: Color(0xFFFFA726)),
            const SizedBox(width: 8),
            const Text('Doorbell Ring', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Text(
          '$senderName is calling you!',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Dismiss'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // Clear doorbell listener before navigating to chat
              _socketService.onDoorbellRing = null;
              // Navigate to chat with this user
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ChatScreen(otherUser: user),
                ),
              ).then((_) {
                // Reload lobby and restore doorbell listener
                _loadLobby();
                _setupRealtimeListeners();
              });
            },
            child: const Text('Answer'),
          ),
        ],
      ),
    );
  }

  void _handleNewMessage(Map<String, dynamic> data) {
    final senderId = data['sender_id'] as int;
    
    // Update unread count for sender
    setState(() {
      final userIndex = _lobbyUsers.indexWhere((u) => u.id == senderId);
      if (userIndex != -1) {
        // Create updated user with incremented unread count
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
        );
        
        _lobbyUsers[userIndex] = updatedUser;
        
        // Move to top of list
        _lobbyUsers.removeAt(userIndex);
        _lobbyUsers.insert(0, updatedUser);
        
        // Update filtered list
        _filterUsers();
      }
    });
  }

  void _updateUserPresence(Map<String, dynamic> data) {
    final userId = data['user_id'] as int;
    final status = data['status'] as String;
    final isOnline = data['is_online'] as bool? ?? (status == 'online');
    
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
          lastSeen: user.lastSeen,
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

  @override
  void dispose() {
    _searchController.dispose();
    // Clear socket callbacks to prevent memory leaks
    _socketService.onDoorbellRing = null;
    _socketService.onMessageReceived = null;
    _socketService.onPresenceUpdate = null;
    super.dispose();
  }

  Future<void> _loadLobby() async {
    setState(() => _isLoading = true);
    try {
      final users = await LobbyService.getLobbyUsers();
      setState(() {
        _lobbyUsers = users;
        _filteredUsers = users;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading lobby: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _filterUsers() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredUsers = _lobbyUsers;
      } else {
        _filteredUsers = _lobbyUsers.where((user) {
          return user.fullName.toLowerCase().contains(query) ||
              user.username.toLowerCase().contains(query);
        }).toList();
      }
    });
  }

  Future<void> _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D2D),
        title: const Text('Logout', style: TextStyle(color: Colors.white)),
        content: const Text('Are you sure you want to logout?', style: TextStyle(color: Colors.white70)),
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

  String _formatTime(String? lastSeen) {
    if (lastSeen == null) return '';
    try {
      final dateTime = DateTime.parse(lastSeen);
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

  @override
  Widget build(BuildContext context) {
    // Separate online and offline users
    final onlineUsers = _filteredUsers.where((u) => u.isOnline).toList();
    final offlineUsers = _filteredUsers.where((u) => !u.isOnline).toList();
    
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
            icon: const Icon(Icons.refresh, color: Colors.white70),
            onPressed: _loadLobby,
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white70),
            onPressed: _handleLogout,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
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
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ),
          // User list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF00D9FF)))
                : _filteredUsers.isEmpty
                    ? Center(
                        child: Text(
                          _searchController.text.isEmpty
                              ? 'No conversations yet'
                              : 'No results found',
                          style: TextStyle(color: Colors.grey[500], fontSize: 16),
                        ),
                      )
                    : ListView(
                        children: [
                          // Online users
                          ...onlineUsers.map((user) => _buildUserTile(user, isOnlineSection: true)),
                          // Offline section header
                          if (offlineUsers.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              child: Text(
                                'OFFLINE',
                                style: TextStyle(
                                  color: Colors.grey[500],
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ),
                            // Offline users
                            ...offlineUsers.map((user) => _buildUserTile(user, isOnlineSection: false)),
                          ],
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserTile(LobbyUser user, {bool isOnlineSection = false}) {
    final avatarColor = _getAvatarColor(user.avatarColorIndex);
    
    // Format last seen date for offline users
    String _formatLastSeenDate(String? lastSeen) {
      if (lastSeen == null) return '';
      try {
        final dateTime = DateTime.parse(lastSeen);
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
            ).then((_) {
              // Reload lobby when returning from chat to update unread counts
              _loadLobby();
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
                    // Online indicator (small green dot)
                    if (user.isOnline)
                      Positioned(
                        right: 2,
                        bottom: 2,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: const Color(0xFF4CAF50),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFF252542),
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    // Offline indicator (small grey dot)
                    if (!user.isOnline)
                      Positioned(
                        right: 2,
                        bottom: 2,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: Colors.grey[600],
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
                      const SizedBox(height: 2),
                      // Online/Offline status
                      Text(
                        user.isOnline ? 'Online' : 'Offline',
                        style: TextStyle(
                          color: user.isOnline ? const Color(0xFF4CAF50) : Colors.grey[500],
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      // Last message or last seen
                      Text(
                        user.isOnline 
                            ? _getLastMessagePreview()
                            : (user.lastMessage != null ? _getLastMessagePreview() : _formatLastSeenDate(user.lastSeen)),
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // Unread badge
                if (user.unreadCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
            ),
          ),
        ),
      ),
    );
  }
}
