import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/message.dart';
import 'storage_service.dart';
import 'auth_error_handler.dart';
import 'chat_cache_service.dart';

/// Service for handling message API calls
/// Enhanced with offline-first capabilities
class MessageService {
  /// Get conversation messages with offline-first approach
  /// Returns cached messages immediately, then syncs with server
  static Future<List<Message>> getConversationMessages({
    required int userId,
    int limit = 50,
    int? beforeId,
    bool offlineFirst = true,
  }) async {
    debugPrint(
      '🔍 getConversationMessages called for userId: $userId, offlineFirst: $offlineFirst',
    );

    // Get current user ID for cache
    final currentUserId = await StorageService.getUserId();
    debugPrint('🔍 Current user ID: $currentUserId');

    // Load from cache first for instant display
    if (offlineFirst && currentUserId != null) {
      debugPrint('🔍 Attempting to load from cache...');
      final cachedMessages = await ChatCacheService.loadConversationMessages(
        currentUserId,
        userId,
      );
      debugPrint('🔍 Cache returned ${cachedMessages.length} messages');

      // Return cached messages immediately if available
      if (cachedMessages.isNotEmpty) {
        debugPrint('📦 Loaded ${cachedMessages.length} messages from cache');

        // Fetch fresh data in background (don't await)
        _syncMessagesInBackground(userId, currentUserId, limit, beforeId);

        return cachedMessages;
      } else {
        debugPrint('📦 Cache is empty, will try server');
      }
    } else {
      debugPrint(
        '🔍 Skipping cache: offlineFirst=$offlineFirst, currentUserId=$currentUserId',
      );
    }

    // No cache or offline mode disabled - fetch from server
    debugPrint('🔍 Fetching from server...');
    return await _fetchMessagesFromServer(
      userId: userId,
      currentUserId: currentUserId,
      limit: limit,
      beforeId: beforeId,
    );
  }

  /// Fetch messages from server and update cache
  static Future<List<Message>> _fetchMessagesFromServer({
    required int userId,
    required int? currentUserId,
    int limit = 50,
    int? beforeId,
  }) async {
    try {
      final token = await StorageService.getToken();

      if (token == null) {
        throw Exception('No authentication token found');
      }

      final queryParams = {
        'limit': limit.toString(),
        if (beforeId != null) 'before_id': beforeId.toString(),
      };

      final uri = Uri.parse(
        '${ApiConfig.baseUrl}${ApiConfig.mobilePrefix}/messages/conversation/$userId',
      ).replace(queryParameters: queryParams);

      final response = await http
          .get(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(ApiConfig.connectionTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final messages = (data['messages'] as List)
            .map((json) => Message.fromJson(json))
            .toList();

        // Sync cache with server response
        if (currentUserId != null) {
          if (messages.isNotEmpty) {
            await ChatCacheService.saveConversationMessages(
              currentUserId,
              userId,
              messages,
            );
            debugPrint('💾 Cached ${messages.length} messages');
          } else {
            // Server returned 0 messages — clear stale cache
            await ChatCacheService.clearConversationCache(
              currentUserId,
              userId,
            );
            debugPrint('🗑️ Server returned 0 messages — cache cleared');
          }
        }

        return messages;
      } else if (response.statusCode == 401) {
        debugPrint('🔐 Token expired - redirecting to sign in');
        await AuthErrorHandler().handleAuthError(
          message: 'Your session has expired. Please sign in again.',
        );
        throw Exception('Session expired');
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to load messages');
      }
    } catch (e) {
      debugPrint('Get conversation messages error: $e');

      // If network error and we have currentUserId, try returning cached data
      if (currentUserId != null) {
        final cachedMessages = await ChatCacheService.loadConversationMessages(
          currentUserId,
          userId,
        );
        if (cachedMessages.isNotEmpty) {
          debugPrint(
            '📦 Network error - returning ${cachedMessages.length} cached messages',
          );
          return cachedMessages;
        }
      }

      rethrow;
    }
  }

  /// Background sync without blocking UI
  static Future<void> _syncMessagesInBackground(
    int userId,
    int currentUserId,
    int limit,
    int? beforeId,
  ) async {
    try {
      await _fetchMessagesFromServer(
        userId: userId,
        currentUserId: currentUserId,
        limit: limit,
        beforeId: beforeId,
      );
    } catch (e) {
      debugPrint('Background sync failed: $e');
      // Silently fail - user already has cached data
    }
  }

  /// Send a message via REST API (alternative to Socket.IO)
  static Future<Message?> sendMessage({
    required int recipientId,
    required String content,
    String messageType = 'text',
    int? replyToId,
  }) async {
    try {
      final token = await StorageService.getToken();

      if (token == null) {
        throw Exception('No authentication token found');
      }

      final response = await http
          .post(
            Uri.parse(ApiConfig.sendMessageUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'recipient_id': recipientId,
              'content': content,
              'message_type': messageType,
              if (replyToId != null) 'reply_to_id': replyToId,
            }),
          )
          .timeout(ApiConfig.connectionTimeout);

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return Message.fromJson(data['data']);
      } else if (response.statusCode == 401) {
        // Token expired - trigger auth error handler
        debugPrint('🔐 Token expired - redirecting to sign in');
        await AuthErrorHandler().handleAuthError(
          message: 'Your session has expired. Please sign in again.',
        );
        throw Exception('Session expired');
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to send message');
      }
    } catch (e) {
      debugPrint('Send message error: $e');
      rethrow;
    }
  }

  /// Mark messages as read
  static Future<void> markAsRead({
    required int senderId,
    required int lastMessageId,
  }) async {
    try {
      final token = await StorageService.getToken();

      if (token == null) return;

      await http
          .post(
            Uri.parse(
              '${ApiConfig.baseUrl}${ApiConfig.mobilePrefix}/messages/mark-read',
            ),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'sender_id': senderId,
              'last_message_id': lastMessageId,
            }),
          )
          .timeout(ApiConfig.connectionTimeout);
    } catch (e) {
      debugPrint('Mark as read error: $e');
    }
  }

  /// Upload a file to the server
  static Future<Map<String, dynamic>?> uploadFile({
    required dynamic file,
    required int recipientId,
  }) async {
    try {
      final token = await StorageService.getToken();

      if (token == null) {
        throw Exception('No authentication token found');
      }

      final uri = Uri.parse(
        '${ApiConfig.baseUrl}${ApiConfig.mobilePrefix}/messages/upload',
      );

      final request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = 'Bearer $token';
      request.fields['recipient_id'] = recipientId.toString();

      // Add file to request
      if (file is http.MultipartFile) {
        request.files.add(file);
      } else {
        // Assume it's a dart:io File
        request.files.add(await http.MultipartFile.fromPath('file', file.path));
      }

      final streamedResponse = await request.send().timeout(
        const Duration(minutes: 2),
      );
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return {
          'success': true,
          'file_url': data['file_url'] ?? data['url'],
          'file_id': data['file_id'] ?? data['id'],
          ...data,
        };
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Upload failed');
      }
    } catch (e) {
      debugPrint('Upload file error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Get all tasks for the current user
  static Future<List<Map<String, dynamic>>> getAllTasks() async {
    try {
      final token = await StorageService.getToken();

      if (token == null) {
        throw Exception('No authentication token found');
      }

      final response = await http
          .get(
            Uri.parse(ApiConfig.tasksUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(ApiConfig.connectionTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final tasks = data['tasks'] as List?;
        return tasks?.cast<Map<String, dynamic>>() ?? [];
      } else if (response.statusCode == 401) {
        debugPrint('🔐 Token expired - redirecting to sign in');
        await AuthErrorHandler().handleAuthError(
          message: 'Your session has expired. Please sign in again.',
        );
        throw Exception('Session expired');
      } else {
        debugPrint('Get tasks error - Status: ${response.statusCode}');
        return []; // Return empty list if endpoint doesn't exist yet
      }
    } catch (e) {
      debugPrint('Get all tasks error: $e');
      return []; // Return empty list on error
    }
  }

  /// Create a new task
  static Future<Map<String, dynamic>?> createTask({
    required String title,
    String? description,
    int? assignedToUserId,
  }) async {
    try {
      final token = await StorageService.getToken();

      if (token == null) {
        throw Exception('No authentication token found');
      }

      final response = await http
          .post(
            Uri.parse(ApiConfig.tasksUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'title': title,
              if (description != null) 'description': description,
              if (assignedToUserId != null)
                'assigned_to_user_id': assignedToUserId,
            }),
          )
          .timeout(ApiConfig.connectionTimeout);

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return data['task'] as Map<String, dynamic>?;
      } else if (response.statusCode == 401) {
        await AuthErrorHandler().handleAuthError(
          message: 'Your session has expired. Please sign in again.',
        );
        throw Exception('Session expired');
      } else {
        debugPrint('Create task error - Status: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('Create task error: $e');
      return null;
    }
  }

  /// Complete a task
  static Future<bool> completeTask(int taskId) async {
    try {
      final token = await StorageService.getToken();

      if (token == null) {
        throw Exception('No authentication token found');
      }

      final response = await http
          .post(
            Uri.parse(ApiConfig.getTaskCompleteUrl(taskId)),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(ApiConfig.connectionTimeout);

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Complete task error: $e');
      return false;
    }
  }

  /// Delete a task
  static Future<bool> deleteTask(int taskId) async {
    try {
      final token = await StorageService.getToken();

      if (token == null) {
        throw Exception('No authentication token found');
      }

      final response = await http
          .delete(
            Uri.parse(ApiConfig.getTaskUrl(taskId)),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(ApiConfig.connectionTimeout);

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Delete task error: $e');
      return false;
    }
  }

  /// Get all excalidraw boards
  static Future<List<Map<String, dynamic>>> getAllExcalidrawBoards() async {
    try {
      final token = await StorageService.getToken();

      if (token == null) {
        throw Exception('No authentication token found');
      }

      final response = await http
          .get(
            Uri.parse(ApiConfig.excalidrawBoardsUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(ApiConfig.connectionTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final boards = data['boards'] as List?;
        return boards?.cast<Map<String, dynamic>>() ?? [];
      } else if (response.statusCode == 401) {
        await AuthErrorHandler().handleAuthError(
          message: 'Your session has expired. Please sign in again.',
        );
        throw Exception('Session expired');
      } else {
        debugPrint(
          'Get excalidraw boards error - Status: ${response.statusCode}',
        );
        return [];
      }
    } catch (e) {
      debugPrint('Get all excalidraw boards error: $e');
      return [];
    }
  }
}
