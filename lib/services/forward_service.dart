import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/message.dart';
import 'storage_service.dart';

/// Result of a forward operation.
class ForwardResult {
  final Map<int, bool> results;

  const ForwardResult({required this.results});

  factory ForwardResult.empty() => const ForwardResult(results: {});

  int get successCount => results.values.where((v) => v).length;
  int get failureCount => results.values.where((v) => !v).length;
  bool get allSucceeded => results.isNotEmpty && results.values.every((v) => v);
  bool get allFailed => results.isNotEmpty && results.values.every((v) => !v);
}

/// Service for forwarding messages to other DM contacts.
class ForwardService {
  /// Forward a message to one or more DM recipients.
  static Future<ForwardResult> forwardToUsers({
    required Message message,
    required List<int> recipientIds,
  }) async {
    if (recipientIds.isEmpty) return ForwardResult.empty();

    try {
      final token = await StorageService.getToken();
      if (token == null) {
        return ForwardResult(
          results: {for (final id in recipientIds) id: false},
        );
      }

      final payload = _buildPayload(message);

      if (recipientIds.length == 1) {
        final response = await http
            .post(
              Uri.parse(ApiConfig.sendMessageUrl),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
              },
              body: jsonEncode({
                'recipient_id': recipientIds.first,
                ...payload,
              }),
            )
            .timeout(const Duration(seconds: 10));

        final success =
            response.statusCode == 200 || response.statusCode == 201;
        return ForwardResult(results: {recipientIds.first: success});
      } else {
        final response = await http
            .post(
              Uri.parse(ApiConfig.sendManyMessagesUrl),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
              },
              body: jsonEncode({
                'recipient_ids': recipientIds,
                ...payload,
              }),
            )
            .timeout(const Duration(seconds: 15));

        if (response.statusCode == 200 || response.statusCode == 201) {
          return ForwardResult(
            results: {for (final id in recipientIds) id: true},
          );
        }
        return ForwardResult(
          results: {for (final id in recipientIds) id: false},
        );
      }
    } catch (e) {
      debugPrint('Forward to users error: $e');
      return ForwardResult(
        results: {for (final id in recipientIds) id: false},
      );
    }
  }

  /// Build the request payload for forwarding.
  /// For text messages: sends content + message_type.
  /// For media/file messages: also includes file_url, file_name, file_size, file_type
  /// so the backend creates a proper file message without re-upload.
  static Map<String, dynamic> _buildPayload(Message message) {
    final isMedia = message.messageType != 'text' &&
        message.messageType != 'system' &&
        message.fileUrl != null;

    if (isMedia) {
      return {
        'content': message.fileName ?? message.content,
        'message_type': message.messageType,
        'file_url': message.fileUrl,
        if (message.fileName != null) 'file_name': message.fileName,
        if (message.fileSize != null) 'file_size': message.fileSize,
        if (message.fileType != null) 'file_type': message.fileType,
      };
    }

    return {
      'content': message.content,
      'message_type': 'text',
    };
  }
}
