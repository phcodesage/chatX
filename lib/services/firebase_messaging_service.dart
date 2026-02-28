import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'fcm_service.dart';

/// Top-level function for background message handling
/// This runs in a separate isolate when app is terminated/background
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('📱 Background message received: ${message.messageId}');
  debugPrint('Data: ${message.data}');

  // Initialize local notifications for background/terminated state
  final FlutterLocalNotificationsPlugin localNotifications =
      FlutterLocalNotificationsPlugin();

  const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
    requestAlertPermission: false,
    requestBadgePermission: false,
    requestSoundPermission: false,
  );

  const InitializationSettings settings = InitializationSettings(
    android: androidSettings,
    iOS: iosSettings,
  );

  await localNotifications.initialize(settings);

  // Persist color change to SharedPreferences so ChatScreen picks it up on open
  final data = message.data;
  if (data['type'] == 'color_change') {
    try {
      final prefs = await SharedPreferences.getInstance();
      final senderId = data['sender_id']?.toString();
      final color = data['color'] as String?;
      if (senderId != null && color != null) {
        await prefs.setString('chat_color_$senderId', color);
        debugPrint(
          '🎨 Background: persisted chat color $color for user $senderId',
        );
      }
    } catch (e) {
      debugPrint('Error persisting background color change: $e');
    }
  }

  // Handle incoming call notifications specifically
  if (data['type'] == 'call') {
    debugPrint('📞 Background: Incoming call notification received');
    await _showIncomingCallNotification(localNotifications, data);
    return; // Don't show generic notification for calls
  }

  // Show the notification from data payload (data-only FCM messages)
  final String? title = data['title'];
  final String? body = data['body'];

  if (title != null && body != null) {
    String channelId = 'chat_messages';
    String channelName = 'Chat Messages';

    if (data['type'] == 'doorbell') {
      channelId = 'doorbell';
      channelName = 'Doorbell Notifications';
    } else if (data['type'] == 'call') {
      channelId = 'calls';
      channelName = 'Incoming Calls';
    }

    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          channelId,
          channelName,
          channelDescription: body,
          importance: Importance.max,
          priority: Priority.high,
          showWhen: true,
          enableVibration: true,
          playSound: true,
          icon: '@mipmap/ic_launcher',
        );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
      payload: jsonEncode(data),
    );
  }
}

/// Show incoming call notification in background/terminated state
Future<void> _showIncomingCallNotification(
  FlutterLocalNotificationsPlugin localNotifications,
  Map<String, dynamic> data,
) async {
  debugPrint('📞 Showing incoming call notification: $data');

  final senderName = data['sender_name'] as String? ?? 'Unknown';
  final callType = data['call_type'] as String? ?? 'video';

  // Create high-priority call notification
  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'incoming_calls',
    'Incoming Calls',
    channelDescription: 'Notifications for incoming calls',
    importance: Importance.max,
    priority: Priority.high,
    category: AndroidNotificationCategory.call,
    fullScreenIntent: true, // Shows as full-screen notification
    ongoing: false,
    autoCancel: true,
    showWhen: true,
    enableVibration: true,
    playSound: true,
    icon: '@mipmap/ic_launcher',
    largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
    styleInformation: BigTextStyleInformation(
      'Tap to answer the call',
      contentTitle: '📞 Incoming Call',
      summaryText: 'Tap to answer',
    ),
  );

  const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
    presentAlert: true,
    presentBadge: true,
    presentSound: true,
    categoryIdentifier: 'CALL_CATEGORY',
  );

  const NotificationDetails details = NotificationDetails(
    android: androidDetails,
    iOS: iosDetails,
  );

  // Show the call notification
  await localNotifications.show(
    999, // Use fixed ID for call notifications so they replace each other
    '📞 $senderName',
    'Incoming $callType call - Tap to answer',
    details,
    payload: jsonEncode(data),
  );

  debugPrint('📞 Call notification displayed for $senderName');
}

/// Service for handling Firebase Cloud Messaging (FCM) push notifications
class FirebaseMessagingService {
  static final FirebaseMessagingService instance =
      FirebaseMessagingService._internal();
  factory FirebaseMessagingService() => instance;
  FirebaseMessagingService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  String? _fcmToken;
  String? get fcmToken => _fcmToken;

  // Track the currently active chat user ID to suppress notifications
  // Set this when entering a chat, clear when leaving
  int? activeChatUserId;

  // Callback for when notification is tapped
  Function(Map<String, dynamic>)? onNotificationTapped;

  /// Initialize Firebase Messaging and request permissions
  Future<void> initialize() async {
    try {
      // Request permission for notifications
      NotificationSettings settings = await _firebaseMessaging
          .requestPermission(
            alert: true,
            badge: true,
            sound: true,
            provisional: false,
            announcement: false,
            carPlay: false,
            criticalAlert: false,
          );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        debugPrint('✅ User granted notification permission');
      } else if (settings.authorizationStatus ==
          AuthorizationStatus.provisional) {
        debugPrint('⚠️ User granted provisional notification permission');
      } else {
        debugPrint('❌ User declined notification permission');
        return;
      }

      // Initialize local notifications for foreground display
      await _initializeLocalNotifications();

      // Get FCM token
      _fcmToken = await _firebaseMessaging.getToken();
      debugPrint('📱 FCM Token: $_fcmToken');

      // Save token locally and send to backend
      if (_fcmToken != null) {
        await _saveFCMToken(_fcmToken!);
        // Send FCM token to backend so server can send push notifications
        await _updateBackendToken(_fcmToken!);
      }

      // Listen for token refresh and update backend
      _firebaseMessaging.onTokenRefresh.listen((newToken) async {
        debugPrint('📱 FCM Token refreshed: $newToken');
        _fcmToken = newToken;
        await _saveFCMToken(newToken);
        // Also update backend with new token
        await _updateBackendToken(newToken);
      });

      // Set up background message handler
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint(
          '📨 Foreground message received: ${message.notification?.title}',
        );

        // For call notifications in foreground, trigger the call handler AND show
        // a heads-up notification so the user sees a banner even when the app is open.
        final data = message.data;
        if (data['type'] == 'call') {
          debugPrint(
            '📞 Foreground call notification - triggering call handler + showing banner',
          );
          _handleNotificationTap(data);
          // Fall through to showNotification so a banner is displayed
        }

        showNotification(message);
      });

      // Handle notification tap when app is in background
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('🔔 Notification tapped (app in background)');
        _handleNotificationTap(message.data);
      });

      // Check if app was opened from a terminated state
      RemoteMessage? initialMessage = await _firebaseMessaging
          .getInitialMessage();
      if (initialMessage != null) {
        debugPrint('🔔 App opened from terminated state via notification');
        _handleNotificationTap(initialMessage.data);
      }

      debugPrint('✅ Firebase Messaging initialized successfully');
    } catch (e) {
      debugPrint('❌ Error initializing Firebase Messaging: $e');
    }
  }

  /// Initialize local notifications plugin
  Future<void> _initializeLocalNotifications() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );

    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      settings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        debugPrint('Local notification tapped');
        if (response.payload != null) {
          _handleNotificationPayload(response.payload!);
        }
      },
    );

    // Create notification channels for Android
    const AndroidNotificationChannel messagesChannel =
        AndroidNotificationChannel(
          'chat_messages',
          'Chat Messages',
          description: 'Notifications for new chat messages',
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
        );

    const AndroidNotificationChannel doorbellChannel =
        AndroidNotificationChannel(
          'doorbell',
          'Doorbell Notifications',
          description: 'Notifications for doorbell rings',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        );

    const AndroidNotificationChannel callsChannel = AndroidNotificationChannel(
      'calls',
      'Incoming Calls',
      description: 'Notifications for incoming calls',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      showBadge: true,
    );

    const AndroidNotificationChannel
    incomingCallsChannel = AndroidNotificationChannel(
      'incoming_calls',
      'Incoming Calls (Background)',
      description:
          'High-priority notifications for incoming calls when app is in background',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      showBadge: true,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(messagesChannel);

    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(doorbellChannel);

    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(callsChannel);

    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(incomingCallsChannel);
  }

  /// Show notification using local notifications plugin
  Future<void> showNotification(RemoteMessage message) async {
    Map<String, dynamic> data = message.data;

    // Suppress notification if the user is currently viewing the chat with this sender
    final senderId = int.tryParse(data['sender_id']?.toString() ?? '');
    if (senderId != null && activeChatUserId == senderId) {
      debugPrint(
        'Suppressing notification — user is in chat with sender $senderId',
      );
      return;
    }

    // Persist color change to SharedPreferences so ChatScreen picks it up
    if (data['type'] == 'color_change') {
      try {
        final prefs = await SharedPreferences.getInstance();
        final senderIdStr = data['sender_id']?.toString();
        final color = data['color'] as String?;
        if (senderIdStr != null && color != null) {
          await prefs.setString('chat_color_$senderIdStr', color);
          debugPrint(
            'Foreground: persisted chat color $color for user $senderIdStr',
          );
        }
      } catch (e) {
        debugPrint('Error persisting foreground color change: $e');
      }
    }

    // Get title/body from data payload (data-only FCM messages)
    final String? title = data['title'];
    final String? body = data['body'];

    if (title != null && body != null) {
      // Determine notification channel based on type
      String channelId = 'chat_messages';
      String channelName = 'Chat Messages';

      if (data['type'] == 'doorbell') {
        channelId = 'doorbell';
        channelName = 'Doorbell Notifications';
      } else if (data['type'] == 'call') {
        channelId = 'calls';
        channelName = 'Incoming Calls';
      }

      final AndroidNotificationDetails
      androidDetails = AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: body,
        importance: data['type'] == 'call' ? Importance.max : Importance.high,
        priority: data['type'] == 'call' ? Priority.max : Priority.high,
        showWhen: true,
        enableVibration: true,
        playSound: true,
        icon: '@mipmap/ic_launcher',
        // For incoming calls: request full-screen intent so the notification
        // appears as a heads-up alert even when the screen is off / locked
        fullScreenIntent: data['type'] == 'call',
        ticker: data['type'] == 'call' ? 'Incoming call' : null,
      );

      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      final NotificationDetails details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _localNotifications.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title,
        body,
        details,
        payload: jsonEncode(data),
      );
    }
  }

  /// Handle notification tap
  void _handleNotificationTap(Map<String, dynamic> data) {
    debugPrint('Notification tapped with data: $data');

    // Call the callback if set
    onNotificationTapped?.call(data);
  }

  /// Handle notification payload from local notifications
  void _handleNotificationPayload(String payload) {
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      _handleNotificationTap(data);
    } catch (e) {
      debugPrint('Error parsing notification payload: $e');
    }
  }

  /// Save FCM token to local storage
  Future<void> _saveFCMToken(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('fcm_token', token);
      debugPrint('✅ FCM token saved locally');
    } catch (e) {
      debugPrint('❌ Error saving FCM token: $e');
    }
  }

  /// Update FCM token on backend (called when token refreshes)
  Future<void> _updateBackendToken(String token) async {
    try {
      await FCMService.updateFCMToken(token);
      debugPrint('✅ FCM token updated on backend after refresh');
    } catch (e) {
      debugPrint('❌ Error updating FCM token on backend: $e');
    }
  }

  /// Get saved FCM token from local storage
  Future<String?> getSavedFCMToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('fcm_token');
    } catch (e) {
      debugPrint('❌ Error getting saved FCM token: $e');
      return null;
    }
  }

  /// Clear FCM token (e.g., on logout)
  Future<void> clearFCMToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('fcm_token');
      await _firebaseMessaging.deleteToken();
      _fcmToken = null;
      debugPrint('✅ FCM token cleared');
    } catch (e) {
      debugPrint('❌ Error clearing FCM token: $e');
    }
  }
}
