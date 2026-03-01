import 'package:flutter/foundation.dart';
import 'socket_service.dart';

/// Service to track which chat/group the user is currently viewing
/// This helps prevent FCM notifications for messages the user can already see
class ActiveChatService {
  static final ActiveChatService _instance = ActiveChatService._internal();
  factory ActiveChatService() => _instance;
  ActiveChatService._internal();

  final SocketService _socketService = SocketService();

  // Current active chat state
  int? _activeGroupId;
  int? _activeUserId; // For 1-on-1 chats
  bool _isAppInForeground = true;

  // Getters
  int? get activeGroupId => _activeGroupId;
  int? get activeUserId => _activeUserId;
  bool get isAppInForeground => _isAppInForeground;

  /// Set the currently active group chat
  void setActiveGroup(int groupId) {
    if (_activeGroupId == groupId) return; // No change

    debugPrint('📱 [ACTIVE CHAT] Setting active group: $groupId');

    // Clear previous active chat
    _clearActiveChat();

    // Set new active group
    _activeGroupId = groupId;
    _activeUserId = null;

    // Notify backend about active group (prevents FCM for this group)
    _notifyBackendActiveChat();
  }

  /// Set the currently active 1-on-1 chat
  void setActiveUser(int userId) {
    if (_activeUserId == userId) return; // No change

    debugPrint('📱 [ACTIVE CHAT] Setting active user chat: $userId');

    // Clear previous active chat
    _clearActiveChat();

    // Set new active user
    _activeUserId = userId;
    _activeGroupId = null;

    // Notify backend about active chat (prevents FCM for this user)
    _notifyBackendActiveChat();
  }

  /// Clear active chat (user left chat screen)
  void clearActiveChat() {
    debugPrint('📱 [ACTIVE CHAT] Clearing active chat');
    _clearActiveChat();
    _notifyBackendActiveChat();
  }

  /// Set app foreground/background state
  void setAppForegroundState(bool isInForeground) {
    if (_isAppInForeground == isInForeground) return; // No change

    debugPrint('📱 [ACTIVE CHAT] App foreground state: $isInForeground');
    _isAppInForeground = isInForeground;

    // Notify backend about app state change
    _notifyBackendActiveChat();
  }

  /// Check if a group message should trigger FCM notification
  bool shouldShowGroupNotification(int groupId) {
    // Show notification if:
    // 1. App is in background, OR
    // 2. User is not currently viewing this group
    final shouldShow = !_isAppInForeground || _activeGroupId != groupId;

    debugPrint(
      '📱 [ACTIVE CHAT] Should show notification for group $groupId: $shouldShow',
    );
    debugPrint(
      '📱 [ACTIVE CHAT] App in foreground: $_isAppInForeground, Active group: $_activeGroupId',
    );

    return shouldShow;
  }

  /// Check if a user message should trigger FCM notification
  bool shouldShowUserNotification(int userId) {
    // Show notification if:
    // 1. App is in background, OR
    // 2. User is not currently viewing this user's chat
    final shouldShow = !_isAppInForeground || _activeUserId != userId;

    debugPrint(
      '📱 [ACTIVE CHAT] Should show notification for user $userId: $shouldShow',
    );
    debugPrint(
      '📱 [ACTIVE CHAT] App in foreground: $_isAppInForeground, Active user: $_activeUserId',
    );

    return shouldShow;
  }

  /// Internal method to clear active chat state
  void _clearActiveChat() {
    _activeGroupId = null;
    _activeUserId = null;
  }

  /// Notify backend about current active chat to prevent unnecessary FCM notifications
  void _notifyBackendActiveChat() {
    if (!_socketService.isConnected) {
      debugPrint(
        '📱 [ACTIVE CHAT] Socket not connected, skipping backend notification',
      );
      return;
    }

    final data = <String, dynamic>{'app_in_foreground': _isAppInForeground};

    if (_activeGroupId != null) {
      data['active_group_id'] = _activeGroupId;
    }

    if (_activeUserId != null) {
      data['active_user_id'] = _activeUserId;
    }

    debugPrint('📱 [ACTIVE CHAT] Notifying backend: $data');
    _socketService.emit('set_active_chat', data);
  }
}
