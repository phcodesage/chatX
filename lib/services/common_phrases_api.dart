import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/common_phrase.dart';
import 'storage_service.dart';

/// Service for managing common phrases API calls
class CommonPhrasesApi {
  static void _trace(String message) {
    if (kDebugMode) {
      debugPrint(message);
    }
  }

  CommonPhrasesApi({
    required this.baseUrl,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  Future<Map<String, String>> _headers() async {
    final token = await StorageService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  /// Fetch common phrases from server
  /// Default limit is 8, but user can override
  Future<List<CommonPhrase>> fetch({int limit = 8}) async {
    try {
      _trace('🔍 Fetching common phrases with limit: $limit');
      final uri = Uri.parse(
        '$baseUrl${ApiConfig.mobilePrefix}/messages/common-phrases?limit=$limit',
      );
      final res = await _client.get(uri, headers: await _headers());

      if (res.statusCode < 200 || res.statusCode >= 300) {
        _trace(
          '❌ Failed to fetch common phrases (${res.statusCode}): ${res.body}',
        );
        throw Exception(
          'Failed to fetch common phrases (${res.statusCode})',
        );
      }

      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      final list = (decoded['phrases'] as List<dynamic>? ?? <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(CommonPhrase.fromJson)
          .toList();

      _trace('📦 Fetched ${list.length} common phrases');
      return list;
    } catch (e) {
      _trace('❌ Error fetching common phrases: $e');
      rethrow;
    }
  }

  /// Track usage of a phrase
  Future<void> trackUse(String phrase) async {
    try {
      _trace('📝 Tracking phrase usage: $phrase');
      final uri = Uri.parse(
        '$baseUrl${ApiConfig.mobilePrefix}/messages/common-phrases/use',
      );
      final res = await _client.post(
        uri,
        headers: await _headers(),
        body: jsonEncode({'phrase': phrase}),
      );

      if (res.statusCode < 200 || res.statusCode >= 300) {
        _trace(
          '❌ Failed to track phrase usage (${res.statusCode}): ${res.body}',
        );
        throw Exception(
          'Failed to track phrase usage (${res.statusCode})',
        );
      }

      _trace('✅ Phrase usage tracked');
    } catch (e) {
      _trace('❌ Error tracking phrase usage: $e');
      // Don't rethrow - this is a background operation
    }
  }

  /// Save a custom phrase
  Future<void> savePhrase(String phrase) async {
    try {
      _trace('📝 Saving custom phrase: $phrase');
      final uri = Uri.parse(
        '$baseUrl${ApiConfig.mobilePrefix}/messages/common-phrases',
      );
      final res = await _client.post(
        uri,
        headers: await _headers(),
        body: jsonEncode({'phrase': phrase}),
      );

      if (res.statusCode < 200 || res.statusCode >= 300) {
        _trace(
          '❌ Failed to save phrase (${res.statusCode}): ${res.body}',
        );
        throw Exception('Failed to save phrase (${res.statusCode})');
      }

      _trace('✅ Phrase saved');
    } catch (e) {
      _trace('❌ Error saving phrase: $e');
      rethrow;
    }
  }

  /// Delete a custom phrase by ID
  Future<void> deletePhrase(int phraseId) async {
    try {
      _trace('🗑️ Deleting phrase with ID: $phraseId');
      final uri = Uri.parse(
        '$baseUrl${ApiConfig.mobilePrefix}/messages/common-phrases/$phraseId',
      );
      final res = await _client.delete(uri, headers: await _headers());

      if (res.statusCode < 200 || res.statusCode >= 300) {
        _trace(
          '❌ Failed to delete phrase (${res.statusCode}): ${res.body}',
        );
        throw Exception('Failed to delete phrase (${res.statusCode})');
      }

      _trace('✅ Phrase deleted');
    } catch (e) {
      _trace('❌ Error deleting phrase: $e');
      rethrow;
    }
  }
}
