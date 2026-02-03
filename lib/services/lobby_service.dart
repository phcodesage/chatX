import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/lobby_user.dart';
import 'storage_service.dart';
import 'auth_error_handler.dart';

/// Service for handling lobby/contact list API calls
class LobbyService {
  /// Get lobby users (contacts + admins for new users)
  static Future<List<LobbyUser>> getLobbyUsers() async {
    try {
      final token = await StorageService.getToken();
      
      if (token == null) {
        throw Exception('No authentication token found');
      }

      final response = await http.get(
        Uri.parse(ApiConfig.lobbyUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(ApiConfig.connectionTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final lobbyUsers = data['lobby_users'] as List;
        return lobbyUsers.map((json) => LobbyUser.fromJson(json)).toList();
      } else if (response.statusCode == 401) {
        // Token expired or invalid - trigger auth error handler
        debugPrint('🔐 Token expired - redirecting to sign in');
        await AuthErrorHandler().handleAuthError(
          message: 'Your session has expired. Please sign in again.',
        );
        throw Exception('Session expired');
      } else {
        debugPrint('❌ Lobby API Error - Status: ${response.statusCode}');
        debugPrint('❌ Response body: ${response.body}');
        try {
          final error = jsonDecode(response.body);
          throw Exception(error['error'] ?? 'Failed to load lobby users');
        } catch (e) {
          throw Exception('Failed to load lobby users - Status: ${response.statusCode}');
        }
      }
    } catch (e) {
      debugPrint('Get lobby users error: $e');
      rethrow;
    }
  }
}
