import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'storage_service.dart';
import 'socket_service.dart';
import 'presence_service.dart';

/// Global handler for authentication errors (401/expired token)
class AuthErrorHandler {
  static final AuthErrorHandler _instance = AuthErrorHandler._internal();
  factory AuthErrorHandler() => _instance;
  AuthErrorHandler._internal();

  /// Global navigator key - set this from main.dart
  static GlobalKey<NavigatorState>? navigatorKey;

  /// Flag to prevent multiple simultaneous logout attempts
  bool _isHandlingAuthError = false;

  /// Handle an authentication error (401/expired token)
  /// This will clear stored credentials and navigate to sign-in
  Future<void> handleAuthError({String? message}) async {
    // Prevent multiple simultaneous logout attempts
    if (_isHandlingAuthError) {
      debugPrint('🔐 Auth error already being handled, skipping...');
      return;
    }

    _isHandlingAuthError = true;
    debugPrint('🔐 Handling auth error: ${message ?? "Session expired"}');

    try {
      // Stop presence heartbeat
      PresenceService().stopHeartbeat();

      // Disconnect socket
      SocketService().disconnect();

      // Clear stored credentials
      await StorageService.clearAll();
      debugPrint('🔐 Credentials cleared');

      // Navigate to sign-in screen using post-frame callback
      // This ensures the navigation happens after the current frame
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _performNavigation(message);
      });
    } catch (e) {
      debugPrint('❌ Error handling auth error: $e');
      _isHandlingAuthError = false;
    }
  }

  void _performNavigation(String? message) {
    debugPrint('🔐 Attempting navigation to sign-in...');
    debugPrint('🔐 Navigator key exists: ${navigatorKey != null}');
    debugPrint('🔐 Navigator state exists: ${navigatorKey?.currentState != null}');
    debugPrint('🔐 Navigator context exists: ${navigatorKey?.currentContext != null}');

    if (navigatorKey?.currentState != null) {
      // Show a message to the user
      final context = navigatorKey!.currentContext;
      if (context != null) {
        try {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message ?? 'Session expired. Please sign in again.'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
        } catch (e) {
          debugPrint('⚠️ Could not show snackbar: $e');
        }
      }

      // Navigate to sign-in and clear the back stack
      try {
        navigatorKey!.currentState!.pushNamedAndRemoveUntil(
          '/sign-in',
          (route) => false,
        );
        debugPrint('✅ Navigation to sign-in successful');
      } catch (e) {
        debugPrint('❌ Navigation error: $e');
      }
    } else {
      debugPrint('⚠️ Navigator key not available for auth error redirect');
    }

    _isHandlingAuthError = false;
  }

  /// Check if a status code indicates an authentication error
  static bool isAuthError(int statusCode) {
    return statusCode == 401;
  }
}

