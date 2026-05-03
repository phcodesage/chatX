import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_fonts/google_fonts.dart';
import 'firebase_options.dart';
import 'models/lobby_user.dart';
import 'screens/sign_in_page.dart';
import 'screens/register_page.dart';
import 'screens/forgot_password_page.dart';
import 'screens/reset_password_page.dart';
import 'screens/home_page.dart';
import 'screens/lobby_screen.dart';
import 'screens/share_target_screen.dart';
import 'screens/chat_screen.dart';
import 'services/firebase_messaging_service.dart';
import 'services/fcm_service.dart';
import 'services/auth_error_handler.dart';
import 'services/chat_cache_service.dart';
import 'services/lobby_service.dart';
import 'services/storage_service.dart';
import 'services/share_intent_service.dart';
import 'services/shortcut_service.dart';
import 'services/socket_service.dart';
import 'services/presence_service.dart';
import 'services/version_service.dart';
import 'utils/notification_handler.dart';

final Completer<void> _bootstrapReadyCompleter = Completer<void>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (kDebugMode) {
    debugPrint('🚀 Performance debug logging enabled');
    debugPrintRebuildDirtyWidgets = true;
    debugProfileBuildsEnabled = true;
    WidgetsBinding.instance.addTimingsCallback((timings) {
      for (final timing in timings) {
        final totalMs = timing.totalSpan.inMilliseconds;
        if (totalMs > 16) {
          debugPrint(
            '🐢 Slow frame #${timing.frameNumber}: total=${totalMs}ms, '
            'build=${timing.buildDuration.inMilliseconds}ms, '
            'raster=${timing.rasterDuration.inMilliseconds}ms, '
            'route=${PerformanceRouteObserver.currentRoute}',
          );
        }
      }
    });
  }

  // Set auth error navigation immediately; this does not require async setup.
  AuthErrorHandler.navigatorKey = NotificationHandler.navigatorKey;

  // Keep Android OS launch window visible until we know the first real screen.
  await StorageService.init();
  await ChatCacheService.init();
  await ShareIntentService.instance.initialize();
  await ShortcutService.instance.initialize();

  final initialHome = await _resolveInitialHome();

  runApp(MessengerApp(initialHome: initialHome));

  // Warm up non-critical services in background so startup stays snappy.
  unawaited(_bootstrapAppServices());
}

Future<Widget> _resolveInitialHome() async {
  final token = await StorageService.getToken();
  final userId = await StorageService.getUserId();

  if (token == null || token.isEmpty || userId == null) {
    return const SignInPage();
  }

  // Restore realtime services for authenticated sessions.
  SocketService().initialize(token, userId);
  PresenceService().startHeartbeat();
  unawaited(PresenceService.updateStatus('online'));

  // Prime Android Direct Share shortcuts from local cache so top-row
  // conversation targets are available even before lobby fully loads.
  final cachedUsers = await ChatCacheService.loadLobbyUsers(userId);
  if (cachedUsers.isNotEmpty) {
    unawaited(ShortcutService.publishShareTargets(cachedUsers));
  }

  final sharedItems = await ShareIntentService.instance
      .takePendingSharedItems();
  if (sharedItems.isNotEmpty) {
    final directShareUserId = sharedItems
        .map((item) => item.directShareUserId)
      .firstWhere((id) => id != null, orElse: () => null) ??
      await ShareIntentService.instance.takePendingDirectShareUserId();

    return ShareTargetScreen(
      sharedItems: sharedItems,
      users: cachedUsers,
      openLobbyOnExit: true,
      directShareUserId: directShareUserId,
    );
  }

  final shortcutUserId = await ShortcutService.instance
      .takePendingShortcutUserId();
  if (shortcutUserId != null) {
    final shortcutUser = await _resolveLobbyUser(shortcutUserId, userId);
    if (shortcutUser != null) {
      return ChatScreen(otherUser: shortcutUser);
    }
  }

  return const LobbyScreen();
}

Future<LobbyUser?> _resolveLobbyUser(int targetUserId, int currentUserId) async {
  final cachedUsers = await ChatCacheService.loadLobbyUsers(currentUserId);
  for (final user in cachedUsers) {
    if (user.id == targetUserId) {
      return user;
    }
  }

  try {
    final freshUsers = await LobbyService.getLobbyUsers();
    await ChatCacheService.saveLobbyUsers(currentUserId, freshUsers);
    for (final user in freshUsers) {
      if (user.id == targetUserId) {
        return user;
      }
    }
  } catch (e) {
    debugPrint('Failed to resolve launcher shortcut user: $e');
  }

  return null;
}

Future<void> _bootstrapAppServices() async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Register FCM background message handler
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Initialize Firebase Cloud Messaging
    await FirebaseMessagingService.instance.initialize();

    // Set up notification tap handler
    FirebaseMessagingService.instance.onNotificationTapped = (data) {
      NotificationHandler.handleNotificationTap(data);
    };

    final isLoggedIn = await StorageService.isLoggedIn();
    if (isLoggedIn) {
      final fcmToken = await FirebaseMessagingService.instance
          .getSavedFCMToken();
      if (fcmToken != null) {
        await FCMService.updateFCMToken(fcmToken);
      }
    }

    unawaited(FirebaseMessagingService.instance.checkInitialMessage());
  } catch (e) {
    debugPrint('Firebase bootstrap failed: $e');
  } finally {
    if (!_bootstrapReadyCompleter.isCompleted) {
      _bootstrapReadyCompleter.complete();
    }
  }
}

class MessengerApp extends StatefulWidget {
  final Widget initialHome;

  const MessengerApp({super.key, required this.initialHome});

  static const Color blue900 = Color(0xFF1E3A8A); // rgb(30,58,138)
  static const Color card = Color(0xFF344256); // slate-ish dark card
  static const Color primaryBtn = Color(0xFF2E2A8B); // deep indigo button

  @override
  State<MessengerApp> createState() => _MessengerAppState();
}

class _MessengerAppState extends State<MessengerApp>
    with WidgetsBindingObserver {
  DateTime? _lastResumeUpdateCheck;
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _hasInternetConnection = true;
  bool _showBackOnlineBanner = false;
  bool _didReceiveConnectivityUpdate = false;
  Timer? _backOnlineBannerTimer;

  Future<void> _initializeConnectivityMonitoring() async {
    final currentResults = await _connectivity.checkConnectivity();
    _updateConnectivity(currentResults);

    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      _updateConnectivity,
    );
  }

  void _updateConnectivity(List<ConnectivityResult> results) {
    final hasConnection =
        results.isNotEmpty && !results.contains(ConnectivityResult.none);
    if (!mounted) return;

    if (!_didReceiveConnectivityUpdate) {
      _didReceiveConnectivityUpdate = true;
      setState(() {
        _hasInternetConnection = hasConnection;
      });
      return;
    }

    if (_hasInternetConnection == hasConnection) return;

    setState(() {
      _hasInternetConnection = hasConnection;
      if (!hasConnection) {
        _showBackOnlineBanner = false;
      } else {
        _showBackOnlineBanner = true;
      }
    });

    _backOnlineBannerTimer?.cancel();
    if (hasConnection) {
      _backOnlineBannerTimer = Timer(const Duration(seconds: 2), () {
        if (!mounted) return;
        setState(() {
          _showBackOnlineBanner = false;
        });
      });
    }
  }

  void _scheduleUpdateCheck({int retryCount = 0}) {
    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_bootstrapReadyCompleter.isCompleted) {
        debugPrint(
          '[VersionService] Waiting for Firebase bootstrap before first version check.',
        );
        _bootstrapReadyCompleter.future.then((_) {
          if (!mounted) return;
          _scheduleUpdateCheck(retryCount: retryCount);
        });
        return;
      }

      final checkContext = NotificationHandler.navigatorKey.currentContext;
      if (checkContext == null) {
        if (retryCount < 3) {
          Future<void>.delayed(const Duration(milliseconds: 450), () {
            _scheduleUpdateCheck(retryCount: retryCount + 1);
          });
        }
        return;
      }

      VersionService().checkAndPromptUpdate(checkContext);

      if (retryCount < 3) {
        Future<void>.delayed(const Duration(milliseconds: 450), () {
          _scheduleUpdateCheck(retryCount: retryCount + 1);
        });
      }
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _scheduleUpdateCheck();
    unawaited(_initializeConnectivityMonitoring());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;

    final now = DateTime.now();
    if (_lastResumeUpdateCheck != null &&
        now.difference(_lastResumeUpdateCheck!) <
            const Duration(seconds: 5)) {
      return;
    }

    _lastResumeUpdateCheck = now;
    _scheduleUpdateCheck();
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _backOnlineBannerTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseTheme = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: MessengerApp.blue900,
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
      scaffoldBackgroundColor: Colors.transparent,
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: Color(0xFFCB6CFF),
        selectionColor: Color(0x668B5CF6),
        selectionHandleColor: Color(0xFFCB6CFF),
      ),
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
      navigatorObservers: [PerformanceRouteObserver()],
      builder: (context, child) {
        final appContent = child ?? const SizedBox.shrink();
        final showStatusBanner = !_hasInternetConnection || _showBackOnlineBanner;
        return Stack(
          children: [
            appContent,
            if (showStatusBanner)
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, animation) {
                  final offsetAnimation = Tween<Offset>(
                    begin: const Offset(0, -0.25),
                    end: Offset.zero,
                  ).animate(animation);
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: offsetAnimation,
                      child: child,
                    ),
                  );
                },
                child: _ConnectionStatusBanner(
                  key: ValueKey<String>(
                    _hasInternetConnection ? 'online' : 'offline',
                  ),
                  isOnline: _hasInternetConnection,
                ),
              ),
          ],
        );
      },
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
      home: widget.initialHome,
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
class PerformanceRouteObserver extends NavigatorObserver {
  static String currentRoute = 'unknown';

  void _logRoute(String action, Route<dynamic>? route) {
    if (route == null) return;
    currentRoute = route.settings.name ?? route.runtimeType.toString();
    debugPrint('🧭 Route $action: $currentRoute');
  }

  @override
  void didPush(Route route, Route? previousRoute) {
    _logRoute('pushed', route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _logRoute('replaced', newRoute);
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    _logRoute('popped', route);
    if (previousRoute != null) {
      _logRoute('restored', previousRoute);
    }
  }
}

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

class _ConnectionStatusBanner extends StatelessWidget {
  const _ConnectionStatusBanner({super.key, required this.isOnline});

  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = isOnline
        ? const Color(0xFF2E7D32)
        : const Color(0xFFC62828);
    final icon = isOnline ? Icons.wifi_rounded : Icons.wifi_off_rounded;
    final text = isOnline ? 'Back online' : 'No internet connection';

    return SafeArea(
      bottom: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 26),
            ],
          ),
        ),
      ),
    );
  }
}
