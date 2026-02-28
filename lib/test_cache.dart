import 'package:flutter/foundation.dart';
import 'services/chat_cache_service.dart';
import 'services/storage_service.dart';
import 'models/message.dart';

/// Simple test function to verify cache is working
/// Call this from your app to test caching
Future<void> testCacheSystem() async {
  debugPrint('🧪 ========== CACHE TEST START ==========');

  // 1. Check if cache is initialized
  try {
    await ChatCacheService.init();
    debugPrint('✅ Cache initialized successfully');
  } catch (e) {
    debugPrint('❌ Cache initialization failed: $e');
    return;
  }

  // 2. Get current user ID
  final currentUserId = await StorageService.getUserId();
  debugPrint('🔍 Current user ID: $currentUserId');

  if (currentUserId == null) {
    debugPrint('❌ No user ID found - user not logged in?');
    return;
  }

  // 3. Create a test message
  final testMessage = Message(
    id: 999999,
    senderId: currentUserId,
    recipientId: 1,
    content: 'Test message for cache',
    messageType: 'text',
    timestamp: DateTime.now().toIso8601String(),
    timestampMs: DateTime.now().millisecondsSinceEpoch,
    isRead: false,
    status: 'sent',
    threadId: 'test',
    reactions: {},
    isDeleted: false,
  );

  // 4. Save test message to cache
  try {
    await ChatCacheService.saveConversationMessages(
      currentUserId,
      1, // test recipient ID
      [testMessage],
    );
    debugPrint('✅ Test message saved to cache');
  } catch (e) {
    debugPrint('❌ Failed to save test message: $e');
    return;
  }

  // 5. Load test message from cache
  try {
    final cached = await ChatCacheService.loadConversationMessages(
      currentUserId,
      1, // test recipient ID
    );
    debugPrint('✅ Loaded ${cached.length} messages from cache');

    if (cached.isNotEmpty) {
      debugPrint('✅ Cache content: ${cached.first.content}');
      debugPrint('✅ CACHE SYSTEM IS WORKING!');
    } else {
      debugPrint('❌ Cache returned empty list');
    }
  } catch (e) {
    debugPrint('❌ Failed to load from cache: $e');
    return;
  }

  debugPrint('🧪 ========== CACHE TEST END ==========');
}
