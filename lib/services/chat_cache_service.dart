import 'dart:math';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/lobby_user.dart';
import '../models/message.dart';

/// Local cache service for conversations and lobby snapshots.
class ChatCacheService {
  static const _chatBoxName = 'chat_cache';
  static const _lobbyBoxName = 'lobby_cache';
  static const _maxMessagesPerThread = 200;
  static const _maxLobbyEntries = 100;

  static bool _initialized = false;
  static late Box _chatBox;
  static late Box _lobbyBox;

  /// Initialize Hive and open cache boxes.
  static Future<void> init() async {
    if (_initialized) return;
    await Hive.initFlutter();
    _chatBox = await Hive.openBox(_chatBoxName);
    _lobbyBox = await Hive.openBox(_lobbyBoxName);
    _initialized = true;
  }

  static String _conversationKey(int currentUserId, int otherUserId) {
    final pair = <int>[currentUserId, otherUserId]..sort();
    return 'conversation_${pair[0]}_${pair[1]}';
  }

  static String _lobbyKey(int currentUserId) => 'lobby_$currentUserId';

  /// Persist the latest messages for a conversation (capped).
  static Future<void> saveConversationMessages(
    int currentUserId,
    int otherUserId,
    List<Message> messages,
  ) async {
    if (!_initialized) return;
    final capped = messages.take(_maxMessagesPerThread).toList();
    await _chatBox.put(
      _conversationKey(currentUserId, otherUserId),
      {
        'messages': capped.map((m) => m.toJson()).toList(),
        'updated_at': DateTime.now().toIso8601String(),
      },
    );
  }

  /// Retrieve cached messages for a conversation.
  static Future<List<Message>> loadConversationMessages(
    int currentUserId,
    int otherUserId,
  ) async {
    if (!_initialized) return [];
    final data = _chatBox.get(_conversationKey(currentUserId, otherUserId));
    if (data == null) return [];
    final rawList = (data['messages'] as List?) ?? const [];
    return rawList
        .map((item) => Message.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  /// Save lobby users snapshot for offline mode.
  static Future<void> saveLobbyUsers(int currentUserId, List<LobbyUser> users) async {
    if (!_initialized) return;
    final trimmed = users.take(_maxLobbyEntries).toList();
    await _lobbyBox.put(
      _lobbyKey(currentUserId),
      {
        'users': trimmed.map((u) => u.toJson()).toList(),
        'updated_at': DateTime.now().toIso8601String(),
      },
    );
  }

  /// Load cached lobby users snapshot.
  static Future<List<LobbyUser>> loadLobbyUsers(int currentUserId) async {
    if (!_initialized) return [];
    final data = _lobbyBox.get(_lobbyKey(currentUserId));
    if (data == null) return [];
    final rawList = (data['users'] as List?) ?? const [];
    return rawList
        .map((item) => LobbyUser.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  /// Optional helper to clear cache for a user (e.g., on logout).
  static Future<void> clearUserCache(int currentUserId) async {
    if (!_initialized) return;
    final keysToDelete = _chatBox.keys
        .where((key) => key is String && key.contains('conversation_'))
        .where((key) => (key as String).contains('_$currentUserId') || (key as String).contains('${currentUserId}_'))
        .toList();
    await _chatBox.deleteAll(keysToDelete);
    await _lobbyBox.delete(_lobbyKey(currentUserId));
  }

  /// Utility to trim caches if boxes grow beyond limits.
  static Future<void> pruneCaches() async {
    if (!_initialized) return;
    if (_chatBox.length > 200) {
      final keys = _chatBox.keys.toList()..sort((a, b) => a.toString().compareTo(b.toString()));
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
