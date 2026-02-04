import 'package:flutter/material.dart';
import '../services/storage_service.dart';
import '../services/socket_service.dart';
import '../services/presence_service.dart';
import '../services/fcm_service.dart';
import '../services/firebase_messaging_service.dart';
import '../utils/notification_handler.dart';
import 'sign_in_page.dart';
import 'home_page.dart';

/// Screen that checks authentication status on app start
class AuthCheckScreen extends StatefulWidget {
  const AuthCheckScreen({super.key});

  @override
  State<AuthCheckScreen> createState() => _AuthCheckScreenState();
}

class _AuthCheckScreenState extends State<AuthCheckScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    // Add a small delay for better UX
    await Future.delayed(const Duration(milliseconds: 500));

    final isLoggedIn = await StorageService.isLoggedIn();

    if (!mounted) return;

    if (isLoggedIn) {
      // User has a saved token, restore session
      final token = await StorageService.getToken();
      final userId = await StorageService.getUserId();

      if (token != null && userId != null) {
        // Re-initialize Socket.IO connection
        SocketService().initialize(token, userId);

        // Start heartbeat to maintain online status
        PresenceService().startHeartbeat();

        // Set status to online
        await PresenceService.updateStatus('online');

        // Send FCM token to backend for push notifications (on app restart)
        final fcmToken = await FirebaseMessagingService.instance.getSavedFCMToken();
        if (fcmToken != null) {
          await FCMService.updateFCMToken(fcmToken);
        }

        // Navigate to home page
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const HomePage()),
          );
          
          // Process any pending notification after navigation is complete
          Future.delayed(const Duration(milliseconds: 300), () {
            NotificationHandler.processPendingNotification();
          });
        }
      } else {
        // Token or userId is missing, go to sign in
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const SignInPage()),
          );
        }
      }
    } else {
      // No saved token, go to sign in
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const SignInPage()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF1E3A8A), // blue-900
              Color(0xFF312E81), // indigo-900
            ],
          ),
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.message_rounded,
                size: 80,
                color: Colors.white,
              ),
              SizedBox(height: 24),
              Text(
                'Flutter Messenger',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 40),
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
