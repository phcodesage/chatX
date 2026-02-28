import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/message.dart';
import '../models/group.dart';
import 'storage_service.dart';

/// Service for handling message translation
class TranslationService {
  /// Translate a message to the target language
  /// Returns the translated text or null if translation failed
  static Future<String?> translateMessage({
    required String text,
    required String targetLang,
  }) async {
    if (text.isEmpty) {
      debugPrint('Translation skipped: empty text');
      return null;
    }

    try {
      final token = await StorageService.getToken();
      if (token == null) {
        debugPrint('Translation failed: no auth token');
        return null;
      }

      final uri = Uri.parse(ApiConfig.translateMessageUrl);

      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'text': text, 'target_lang': targetLang}),
          )
          .timeout(const Duration(seconds: 15));

      debugPrint('Translation API response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final translatedText = data['translation'] as String?;
          debugPrint('Translation successful: $translatedText');
          return translatedText;
        } else {
          debugPrint('Translation failed: ${data['error']}');
        }
      } else {
        debugPrint('Translation API error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Translation error: $e');
    }

    return null;
  }

  /// Translate a message object and return a new translated message
  static Future<Message?> translateMessageObject({
    required Message message,
    required String targetLang,
  }) async {
    final translatedText = await translateMessage(
      text: message.content,
      targetLang: targetLang,
    );

    if (translatedText == null) {
      return null;
    }

    // Create a new message with translated content
    return Message(
      id: message.id,
      senderId: message.senderId,
      recipientId: message.recipientId,
      content: translatedText,
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
      fileUrl: message.fileUrl,
      fileName: message.fileName,
      fileSize: message.fileSize,
      fileType: message.fileType,
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

  /// Get the user's preferred language from storage
  static Future<String> getUserLanguage() async {
    final prefs = await StorageService.getPreferences();
    return prefs.getString('userLanguage') ?? 'en';
  }

  /// Save the user's preferred language
  static Future<void> setUserLanguage(String langCode) async {
    final prefs = await StorageService.getPreferences();
    await prefs.setString('userLanguage', langCode);
  }

  /// Translate a group message object and return a new translated group message
  static Future<GroupMessage?> translateGroupMessageObject({
    required GroupMessage message,
    required String targetLang,
  }) async {
    final translatedText = await translateMessage(
      text: message.content,
      targetLang: targetLang,
    );

    if (translatedText == null) {
      return null;
    }

    // Create a new group message with translated content
    return GroupMessage(
      id: message.id,
      messageId: message.messageId,
      groupId: message.groupId,
      senderId: message.senderId,
      sender: message.sender,
      content: translatedText,
      messageType: message.messageType,
      timestamp: message.timestamp,
      timestampMs: message.timestampMs,
      isDeleted: message.isDeleted,
      fileUrl: message.fileUrl,
      fileName: message.fileName,
      fileSize: message.fileSize,
      fileType: message.fileType,
      replyToId: message.replyToId,
      replyPreview: message.replyPreview,
      reactions: message.reactions,
    );
  }
}
