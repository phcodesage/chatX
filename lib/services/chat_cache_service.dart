import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/lobby_user.dart';
import '../models/message.dart';
import '../models/group.dart';

/// Local cache service for conversations and lobby snapshots.
/// Enhanced for offline-first messaging like WhatsApp.
class ChatCacheService {
  static const _chatBoxName = 'chat_cache';
  static const _lobbyBoxName = 'lobby_cache';
  static const _groupChatBoxName = 'group_chat_cache';
  static const _maxMessagesPerThread = 1000; // Increased from 200
  static const _maxLobbyEntries = 100;

  static bool _initialized = false;
  static late Box _chatBox;
  static late Box _lobbyBox;
  static late Box _groupChatBox;

  /// Initialize Hive and open cache boxes.
  static Future<void> init() async {
    if (_initialized) return;
    await Hive.initFlutter();
    _chatBox = await Hive.openBox(_chatBoxName);
    _lobbyBox = await Hive.openBox(_lobbyBoxName);
    _groupChatBox = await Hive.openBox(_groupChatBoxName);
    _initialized = true;
  }

  static String _conversationKey(int currentUserId, int otherUserId) {
    final pair = <int>[currentUserId, otherUserId]..sort();
    return 'conversation_${pair[0]}_${pair[1]}';
  }

  static String _groupConversationKey(int groupId) => 'group_$groupId';

  static String _lobbyKey(int currentUserId) => 'lobby_$currentUserId';

  /// Persist the latest messages for a conversation (capped).
  /// Enhanced to store more messages for offline access.
  /// Only caches text content - strips file URLs to save storage space.
  static Future<void> saveConversationMessages(
    int currentUserId,
    int otherUserId,
    List<Message> messages,
  ) async {
    if (!_initialized) {
      debugPrint('⚠️ ChatCacheService not initialized, cannot save!');
      return;
    }

    final key = _conversationKey(currentUserId, otherUserId);
    final capped = messages.take(_maxMessagesPerThread).toList();

    debugPrint('💾 Saving ${capped.length} messages to cache with key: $key');

    // Strip file URLs to save storage - only keep text content
    final cachedMessages = capped.map((m) => _stripFileData(m)).toList();

    await _chatBox.put(key, {
      'messages': cachedMessages.map((m) => m.toJson()).toList(),
      'updated_at': DateTime.now().toIso8601String(),
      'message_count': cachedMessages.length,
    });

    debugPrint(
      '✅ Successfully saved ${cachedMessages.length} messages to cache',
    );
  }

  /// Strip file URLs from message to save storage space
  /// Only keeps text content for offline reading
  static Message _stripFileData(Message message) {
    // If it's a text message, return as-is
    if (message.messageType == 'text' &&
        !message.isTask &&
        !message.isExcalidrawLink) {
      return message;
    }

    // For file messages, strip the file URL but keep the message structure
    // The content field already contains a preview like "📷 Photo" or "🎬 Video"
    return Message(
      id: message.id,
      senderId: message.senderId,
      recipientId: message.recipientId,
      content: message.content, // This already has the preview text
      messageType: message.messageType,
      timestamp: message.timestamp,
      timestampMs: message.timestampMs,
      isRead: message.isRead,
      readAt: message.readAt,
      readAtMs: message.readAtMs,
      deliveredAt: message.deliveredAt,
      deliveredAtMs: message.deliveredAtMs,
      status: message.status,
      threadId: message.threadId,
      replyToId: message.replyToId,
      replyPreview: message.replyPreview,
      reactions: message.reactions,
      fileUrl: null, // Strip file URL to save space
      fileName: null,
      fileSize: null,
      fileType: null,
      isDeleted: message.isDeleted,
      isTask: message.isTask,
      taskCreatedAt: message.taskCreatedAt,
      taskCompletedAt: message.taskCompletedAt,
      isExcalidrawLink: message.isExcalidrawLink,
      excalidrawPinnedAt: message.excalidrawPinnedAt,
      isPinned: message.isPinned,
      pinnedAt: message.pinnedAt,
      pinnedByUserId: message.pinnedByUserId,
    );
  }

  /// Add a single message to the cache (for real-time updates).
  static Future<void> addMessageToCache(
    int currentUserId,
    int otherUserId,
    Message message,
  ) async {
    if (!_initialized) return;
    final existing = await loadConversationMessages(currentUserId, otherUserId);

    // Check if message already exists (by ID)
    final messageExists = existing.any((m) => m.id == message.id);
    if (messageExists) {
      // Update existing message
      final updated = existing
          .map((m) => m.id == message.id ? message : m)
          .toList();
      await saveConversationMessages(currentUserId, otherUserId, updated);
    } else {
      // Add new message
      final updated = [message, ...existing];
      await saveConversationMessages(currentUserId, otherUserId, updated);
    }
  }

  /// Retrieve cached messages for a conversation.
  /// Returns messages immediately for offline access.
  static Future<List<Message>> loadConversationMessages(
    int currentUserId,
    int otherUserId,
  ) async {
    if (!_initialized) {
      debugPrint('⚠️ ChatCacheService not initialized!');
      return [];
    }

    final key = _conversationKey(currentUserId, otherUserId);
    debugPrint('🔍 Loading cache for key: $key');

    final data = _chatBox.get(key);
    if (data == null) {
      debugPrint('📦 No cache found for key: $key');
      return [];
    }

    debugPrint('📦 Cache data found: ${data.keys}');
    final rawList = (data['messages'] as List?) ?? const [];
    debugPrint('📦 Cache has ${rawList.length} messages');

    return rawList
        .map((item) => Message.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  /// Save group messages to cache.
  /// Preserves all message data including file URLs for proper display.
  static Future<void> saveGroupMessages(
    int groupId,
    List<GroupMessage> messages,
  ) async {
    if (!_initialized) return;
    final capped = messages.take(_maxMessagesPerThread).toList();

    // Don't strip file URLs anymore - preserve all data for proper display
    final cachedMessages = capped.map((m) => _stripGroupFileData(m)).toList();

    await _groupChatBox.put(_groupConversationKey(groupId), {
      'messages': cachedMessages.map((m) => m.toJson()).toList(),
      'updated_at': DateTime.now().toIso8601String(),
      'message_count': cachedMessages.length,
    });
  }

  /// Strip file URLs from group message to save storage space
  static GroupMessage _stripGroupFileData(GroupMessage message) {
    // Don't strip file data anymore - we need it for proper display
    // The storage savings aren't worth the broken file message display
    return message;
  }

  /// Load cached group messages.
  static Future<List<GroupMessage>> loadGroupMessages(int groupId) async {
    if (!_initialized) return [];
    final data = _groupChatBox.get(_groupConversationKey(groupId));
    if (data == null) return [];
    final rawList = (data['messages'] as List?) ?? const [];
    return rawList
        .map(
          (item) =>
              GroupMessage.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

  /// Add a single group message to the cache.
  static Future<void> addGroupMessageToCache(
    int groupId,
    GroupMessage message,
  ) async {
    if (!_initialized) return;
    final existing = await loadGroupMessages(groupId);

    // Check if message already exists
    final messageExists = existing.any((m) => m.id == message.id);
    if (messageExists) {
      // Update existing message
      final updated = existing
          .map((m) => m.id == message.id ? message : m)
          .toList();
      await saveGroupMessages(groupId, updated);
    } else {
      // Add new message
      final updated = [message, ...existing];
      await saveGroupMessages(groupId, updated);
    }
  }

  /// Save lobby users snapshot for offline mode.
  static Future<void> saveLobbyUsers(
    int currentUserId,
    List<LobbyUser> users,
  ) async {
    if (!_initialized) return;
    final trimmed = users.take(_maxLobbyEntries).toList();
    await _lobbyBox.put(_lobbyKey(currentUserId), {
      'users': trimmed.map((u) => u.toJson()).toList(),
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  /// Load cached lobby users snapshot.
  static Future<List<LobbyUser>> loadLobbyUsers(int currentUserId) async {
    if (!_initialized) return [];
    final data = _lobbyBox.get(_lobbyKey(currentUserId));
    if (data == null) return [];
    final rawList = (data['users'] as List?) ?? const [];
    return rawList
        .map(
          (item) => LobbyUser.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

  /// Optional helper to clear cache for a user (e.g., on logout).
  static Future<void> clearUserCache(int currentUserId) async {
    if (!_initialized) return;
    final keysToDelete = _chatBox.keys
        .where((key) => key is String && key.contains('conversation_'))
        .where(
          (key) =>
              key.toString().contains('_$currentUserId') ||
              key.toString().contains('${currentUserId}_'),
        )
        .toList();
    await _chatBox.deleteAll(keysToDelete);
    await _lobbyBox.delete(_lobbyKey(currentUserId));
  }

  /// Clear all group message caches.
  static Future<void> clearAllGroupCaches() async {
    if (!_initialized) return;
    await _groupChatBox.clear();
  }

  /// Clear cache for a specific group.
  static Future<void> clearGroupCache(int groupId) async {
    if (!_initialized) return;
    await _groupChatBox.delete(_groupConversationKey(groupId));
  }

  /// Utility to trim caches if boxes grow beyond limits.
  static Future<void> pruneCaches() async {
    if (!_initialized) return;
    if (_chatBox.length > 200) {
      final keys = _chatBox.keys.toList()
        ..sort((a, b) => a.toString().compareTo(b.toString()));
      final excess = max(0, keys.length - 200);
      if (excess > 0) {
        await _chatBox.deleteAll(keys.sublist(0, excess));
      }
    }
    if (_lobbyBox.length > 50) {
      final keys = _lobbyBox.keys.toList();
      final excess = max(0, keys.length - 50);
      if (excess > 0) {
        await _lobbyBox.deleteAll(keys.sublist(0, excess));
      }
    }
  }
}
