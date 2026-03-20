import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_fonts/google_fonts.dart';
import 'firebase_options.dart';
import 'screens/auth_check_screen.dart';
import 'screens/sign_in_page.dart';
import 'screens/register_page.dart';
import 'screens/forgot_password_page.dart';
import 'screens/reset_password_page.dart';
import 'screens/home_page.dart';
import 'screens/lobby_screen.dart';
import 'services/firebase_messaging_service.dart';
import 'services/auth_error_handler.dart';
import 'services/chat_cache_service.dart';
import 'services/storage_service.dart';
import 'services/share_intent_service.dart';
import 'utils/notification_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await ChatCacheService.init();
  await StorageService.init();
  await ShareIntentService.instance.initialize();

  // Initialize Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Register FCM background message handler
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // Initialize Firebase Cloud Messaging
  await FirebaseMessagingService.instance.initialize();

  // Set up notification tap handler
  FirebaseMessagingService.instance.onNotificationTapped = (data) {
    NotificationHandler.handleNotificationTap(data);
  };

  // Set up auth error handler with navigator key
  AuthErrorHandler.navigatorKey = NotificationHandler.navigatorKey;

  // Note: FCM token will be sent to backend after successful login

  runApp(const MessengerApp());
}

class MessengerApp extends StatelessWidget {
  const MessengerApp({super.key});

  static const Color blue900 = Color(0xFF1E3A8A); // rgb(30,58,138)
  static const Color card = Color(0xFF344256); // slate-ish dark card
  static const Color primaryBtn = Color(0xFF2E2A8B); // deep indigo button

  @override
  Widget build(BuildContext context) {
    final baseTheme = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: blue900,
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
      scaffoldBackgroundColor: Colors.transparent,
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: Color(0xFFEFF6FF),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
          borderSide: BorderSide.none,
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      textTheme: GoogleFonts.interTextTheme(
        const TextTheme(
          bodyLarge: TextStyle(color: Colors.black),
          bodyMedium: TextStyle(color: Colors.black),
        ),
      ),
    );

    return MaterialApp(
      title: 'Flutter Messenger',
      debugShowCheckedModeBanner: false,
      navigatorKey: NotificationHandler.navigatorKey,
      theme: baseTheme.copyWith(
        // Kill all page-route transitions globally
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: _NoTransitionBuilder(),
            TargetPlatform.iOS: _NoTransitionBuilder(),
            TargetPlatform.windows: _NoTransitionBuilder(),
            TargetPlatform.linux: _NoTransitionBuilder(),
            TargetPlatform.macOS: _NoTransitionBuilder(),
          },
        ),
        // Remove ink splash / ripple animations
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
      ),
      home: const AuthCheckScreen(),
      routes: {
        SignInPage.route: (_) => const SignInPage(),
        RegisterPage.route: (_) => const RegisterPage(),
        ForgotPasswordPage.route: (_) => const ForgotPasswordPage(),
        ResetPasswordPage.route: (_) => const ResetPasswordPage(),
        HomePage.route: (_) => const HomePage(),
        LobbyScreen.route: (_) => const LobbyScreen(),
      },
    );
  }
}

/// Zero-duration page transition — replaces slides/fades with instant swap.
class _NoTransitionBuilder extends PageTransitionsBuilder {
  const _NoTransitionBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return child;
  }
}
