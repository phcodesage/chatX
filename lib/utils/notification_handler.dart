import 'package:flutter/material.dart';
import '../screens/chat_screen.dart';
import '../models/lobby_user.dart';

/// Helper class to handle notification taps and navigate to appropriate screens
class NotificationHandler {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  
  // Store pending navigation data for when app opens from terminated state
  static Map<String, dynamic>? _pendingNotificationData;

  /// Handle notification tap and navigate to the appropriate screen
  static void handleNotificationTap(Map<String, dynamic> data) {
    debugPrint('🔔 NotificationHandler.handleNotificationTap called with: $data');
    
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
        _navigateToChat(senderId, senderName ?? 'User');
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
  
  /// Check and process any pending notification navigation
  /// Call this after the app is fully initialized
  static void processPendingNotification() {
    if (_pendingNotificationData != null) {
      debugPrint('🔔 Processing pending notification: $_pendingNotificationData');
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

    // Navigate to chat screen, pushing on top of current stack
    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (context) => ChatScreen(otherUser: user),
      ),
    );
  }
}
