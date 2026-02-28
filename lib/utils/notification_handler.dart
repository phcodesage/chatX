import 'package:flutter/material.dart';
import '../screens/chat_screen.dart';
import '../screens/connected_call_screen.dart';
import '../screens/lobby_screen.dart';
import '../widgets/incoming_call_setup_modal.dart';
import '../models/lobby_user.dart';
import '../services/call_service.dart';
import '../services/socket_service.dart';
import '../services/presence_service.dart';

/// Helper class to handle notification taps and navigate to appropriate screens
class NotificationHandler {
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  // Store pending navigation data for when app opens from terminated state
  static Map<String, dynamic>? _pendingNotificationData;

  // Callback for incoming call from FCM (set by lobby/chat screens)
  static Function(Map<String, dynamic>)? onIncomingCallFromFCM;

  /// Handle notification tap and navigate to the appropriate screen
  static void handleNotificationTap(Map<String, dynamic> data) {
    debugPrint(
      '🔔 NotificationHandler.handleNotificationTap called with: $data',
    );

    final type = data['type'] as String?;
    final senderId = int.tryParse(data['sender_id']?.toString() ?? '');
    final senderName = data['sender_name'] as String?;

    if (senderId == null) {
      debugPrint('❌ Invalid sender_id in notification data');
      return;
    }

    // Check if navigator is ready
    if (navigatorKey.currentState == null) {
      debugPrint('⏳ Navigator not ready, storing pending notification');
      _pendingNotificationData = data;
      return;
    }

    switch (type) {
      case 'message':
        _navigateToChat(senderId, senderName ?? 'User');
        break;
      case 'doorbell':
        _navigateToChat(senderId, senderName ?? 'User');
        break;
      case 'call':
        debugPrint('📞 FCM notification tapped - handling incoming call');
        _handleIncomingCallNotification(data);
        break;
      case 'color_change':
        _navigateToChat(senderId, senderName ?? 'User');
        break;
      default:
        debugPrint('⚠️ Unknown notification type: $type');
        // Still navigate to chat for unknown types if we have sender info
        _navigateToChat(senderId, senderName ?? 'User');
    }
  }

  /// Handle incoming call notification tap - show incoming call modal
  static Future<void> _handleIncomingCallNotification(
    Map<String, dynamic> data,
  ) async {
    debugPrint('📞 Handling incoming call notification: $data');

    // Guard against duplicate call setups (same as lobby/chat screens)
    // This prevents conflicts when both socket events and FCM notifications arrive
    if (PresenceService().isHandlingIncomingCall) {
      debugPrint(
        '⚠️ Already handling an incoming call, ignoring FCM duplicate',
      );
      return;
    }
    PresenceService().isHandlingIncomingCall = true;

    final senderId = int.tryParse(data['sender_id']?.toString() ?? '');
    final senderName = data['sender_name'] as String? ?? 'Unknown';
    final callType = data['call_type'] as String? ?? 'video';
    final callId = int.tryParse(data['call_id']?.toString() ?? '');
    final callRoomId = data['call_room_id'] as String?;

    if (senderId == null) {
      debugPrint('❌ Invalid sender_id for call notification');
      PresenceService().isHandlingIncomingCall = false;
      return;
    }

    final context = navigatorKey.currentContext;
    if (context == null) {
      debugPrint('❌ No context available for showing call modal');
      PresenceService().isHandlingIncomingCall = false;
      return;
    }

    debugPrint('✅ Context available, proceeding with call setup');
    debugPrint(
      '📞 Call details: senderId=$senderId, senderName=$senderName, callType=$callType, callId=$callId, callRoomId=$callRoomId',
    );

    // Initialize call service
    final callService = CallService();
    await callService.initialize();
    debugPrint('✅ Call service initialized');

    // Set up socket service and start signal buffering BEFORE handling incoming call
    final socketService = SocketService();
    socketService.startSignalBuffering();
    debugPrint('📡 Started signal buffering for FCM call');

    // Set up socket signal handler
    socketService.onSignal = (signalData) {
      debugPrint('📡 Signal received for FCM call: $signalData');
      callService.handleSignal(signalData);
    };

    // For FCM notifications, request pending offer since the original offer
    // may have been sent while the app was in background
    if (callRoomId != null) {
      debugPrint('📞 Requesting pending offer for FCM call: $callRoomId');
      // Add a small delay to ensure socket connection is stable
      Future.delayed(const Duration(milliseconds: 500), () {
        socketService.emit('request_pending_offer', {'room': callRoomId});
        debugPrint('📞 Pending offer request sent for room: $callRoomId');
      });

      // Also request a fresh offer as backup
      Future.delayed(const Duration(milliseconds: 800), () {
        debugPrint('📡 Requesting fresh WebRTC offer for FCM call (backup)');
        socketService.emit('request_call_offer', {
          'call_room_id': callRoomId,
          'caller_id': senderId,
        });
      });
    }

    // Create call data for the call service
    final callData = {
      'id': callId ?? DateTime.now().millisecondsSinceEpoch,
      'call_room_id':
          callRoomId ??
          '${senderId}_call_${DateTime.now().millisecondsSinceEpoch}',
      'call_type': callType,
      'caller_id': senderId,
      'caller': {
        'id': senderId,
        'username': senderName,
        'full_name': senderName,
      },
    };
    debugPrint('📞 Created call data: $callData');
    callService.handleIncomingCall(callData);

    // Use addListener with unique key for proper event handling
    const listenerKey = 'fcm_call_handler';
    socketService.addListener('callEnded', listenerKey, (
      Map<String, dynamic> endData,
    ) {
      debugPrint('📴 Call ended by remote user (FCM handler)');
      callService.handleCallEnded();
    });

    socketService.addListener('callDeclined', listenerKey, (
      Map<String, dynamic> declineData,
    ) {
      debugPrint('❌ Call declined (FCM handler)');
      callService.handleCallDeclined();
    });

    // Show incoming call setup modal
    debugPrint('📞 Attempting to show IncomingCallSetupModal');
    navigatorKey.currentState
        ?.push(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (context) => IncomingCallSetupModal(
              callerName: senderName,
              callerId: senderId,
              callType: callType,
              callService: callService,
              onDecline: () {
                debugPrint('📞 Call declined by user from FCM notification');
                // Clean up listeners
                socketService.removeListener('callEnded', listenerKey);
                socketService.removeListener('callDeclined', listenerKey);
                // Reset the handling flag
                PresenceService().isHandlingIncomingCall = false;

                // Navigate to chat with the caller when call is declined
                // This provides better UX - user can see the chat context
                debugPrint('📱 Navigating to chat with caller after decline');
                _navigateToChat(senderId, senderName);
              },
            ),
          ),
        )
        .then((result) {
          debugPrint('📞 IncomingCallSetupModal closed with result: $result');
          // Clean up listeners when modal closes
          socketService.removeListener('callEnded', listenerKey);
          socketService.removeListener('callDeclined', listenerKey);
          // Reset the handling flag
          PresenceService().isHandlingIncomingCall = false;

          if (result is Map &&
              (result['result'] == 'accepted' ||
                  result['result'] == 'connected')) {
            final localStream = result['localStream'];
            debugPrint('📞 Call accepted, showing ConnectedCallScreen');
            navigatorKey.currentState?.push(
              MaterialPageRoute(
                fullscreenDialog: true,
                builder: (context) => ConnectedCallScreen(
                  remoteName: senderName,
                  callType: callType,
                  callService: callService,
                  localStream: localStream ?? callService.localStream,
                ),
              ),
            );
          } else {
            // Call was declined or modal closed without accepting
            // Navigate to chat with the caller for better UX
            debugPrint(
              '📱 Call declined/dismissed, navigating to chat with caller',
            );
            _navigateToChat(senderId, senderName);
          }
        });
  }

  /// Check and process any pending notification navigation
  /// Call this after the app is fully initialized
  static void processPendingNotification() {
    if (_pendingNotificationData != null) {
      debugPrint(
        '🔔 Processing pending notification: $_pendingNotificationData',
      );
      final data = _pendingNotificationData!;
      _pendingNotificationData = null;

      // Delay slightly to ensure navigation stack is ready
      Future.delayed(const Duration(milliseconds: 500), () {
        handleNotificationTap(data);
      });
    }
  }

  /// Navigate to chat screen with the specified user
  static void _navigateToChat(int userId, String userName) {
    debugPrint('🚀 Navigating to chat with user: $userId ($userName)');

    // Create a LobbyUser object with minimal information
    final user = LobbyUser(
      id: userId,
      username: userName,
      email: '',
      firstName: userName.split(' ').first,
      lastName: userName.split(' ').length > 1 ? userName.split(' ').last : '',
      fullName: userName,
      avatarUrl: null,
      bio: null,
      status: 'online',
      statusMessage: null,
      lastSeen: DateTime.now().toIso8601String(),
      isOnline: true,
      isAdmin: false,
      timezone: 'UTC',
      unreadCount: 0,
      isContact: false,
      isAdminUser: false,
    );

    // Ensure proper navigation stack by going to lobby first, then chat
    // This prevents black screen issues when app is opened from terminated state
    navigatorKey.currentState?.pushNamedAndRemoveUntil(
      LobbyScreen.route,
      (route) => false, // Clear all previous routes
    );

    // Small delay to ensure lobby screen is loaded, then navigate to chat
    Future.delayed(const Duration(milliseconds: 300), () {
      navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (context) => ChatScreen(otherUser: user)),
      );
    });
  }
}
