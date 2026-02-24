import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service for storing and retrieving data locally
class StorageService {
  static const String _tokenKey = 'auth_token';
  static const String _userIdKey = 'user_id';
  static const String _usernameKey = 'username';
  static const String _isAdminKey = 'is_admin';
  static const String _rememberMeKey = 'remember_me';
  static const String _rememberedUsernameKey = 'remembered_username';

  /// Save authentication token
  static Future<void> saveToken(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, token);
    } catch (e) {
      debugPrint('Error saving token: $e');
    }
  }

  /// Get authentication token
  static Future<String?> getToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_tokenKey);
    } catch (e) {
      debugPrint('Error getting token: $e');
      return null;
    }
  }

  /// Save user ID
  static Future<void> saveUserId(int userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_userIdKey, userId);
    } catch (e) {
      debugPrint('Error saving user ID: $e');
    }
  }

  /// Get user ID
  static Future<int?> getUserId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_userIdKey);
    } catch (e) {
      debugPrint('Error getting user ID: $e');
      return null;
    }
  }

  /// Save username
  static Future<void> saveUsername(String username) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_usernameKey, username);
    } catch (e) {
      debugPrint('Error saving username: $e');
    }
  }

  /// Get username
  static Future<String?> getUsername() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_usernameKey);
    } catch (e) {
      debugPrint('Error getting username: $e');
      return null;
    }
  }

  /// Save admin status
  static Future<void> saveIsAdmin(bool isAdmin) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_isAdminKey, isAdmin);
    } catch (e) {
      debugPrint('Error saving admin status: $e');
    }
  }

  /// Get admin status
  static Future<bool> getIsAdmin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_isAdminKey) ?? false;
    } catch (e) {
      debugPrint('Error getting admin status: $e');
      return false;
    }
  }

  /// Save remembered username (no password is ever persisted)
  static Future<void> saveRememberedUsername(String username) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_rememberMeKey, true);
      await prefs.setString(_rememberedUsernameKey, username);
    } catch (e) {
      debugPrint('Error saving remembered username: $e');
    }
  }

  /// Get remembered username (returns null if not set)
  static Future<String?> getRememberedUsername() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rememberMe = prefs.getBool(_rememberMeKey) ?? false;
      if (!rememberMe) return null;
      return prefs.getString(_rememberedUsernameKey);
    } catch (e) {
      debugPrint('Error getting remembered username: $e');
      return null;
    }
  }

  /// Clear remembered credentials
  static Future<void> clearRememberedCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_rememberMeKey);
      await prefs.remove(_rememberedUsernameKey);
    } catch (e) {
      debugPrint('Error clearing remembered credentials: $e');
    }
  }

  /// Clear all stored data (logout) — preserves remembered credentials
  static Future<void> clearAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_tokenKey);
      await prefs.remove(_userIdKey);
      await prefs.remove(_usernameKey);
      await prefs.remove(_isAdminKey);
    } catch (e) {
      debugPrint('Error clearing storage: $e');
    }
  }

  /// Check if user is logged in
  static Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }
}
