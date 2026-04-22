import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/widgets.dart' show visibleForTesting;

import 'chat_cache_service.dart';

/// Service for storing and retrieving data locally
class StorageService {
  static const String _tokenKey = 'auth_token';
  static const String _userIdKey = 'user_id';
  static const String _usernameKey = 'username';
  static const String _isAdminKey = 'is_admin';
  static const String _rememberMeKey = 'remember_me';
  static const String _rememberedUsernameKey = 'remembered_username';
  static const String _rememberedPasswordKey = 'remembered_password';
  static const String _useMilitaryTimeKey = 'use_military_time';

  static bool useMilitaryTime = false;

  static SharedPreferences? _prefs;
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// Reset cached state — for use in unit tests only.
  @visibleForTesting
  static void resetForTesting() {
    _prefs = null;
  }

  /// Warm up the SharedPreferences instance so the first write doesn't
  /// block a frame later during app usage.
  static Future<void> init() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      useMilitaryTime = _prefs!.getBool(_useMilitaryTimeKey) ?? false;
    } catch (e) {
      debugPrint('Error initializing storage: $e');
    }
  }

  static Future<SharedPreferences> _getPrefs() async {
    if (_prefs != null) {
      return _prefs!;
    }

    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;
    return prefs;
  }

  /// Save authentication token
  static Future<void> saveToken(String token) async {
    // Always write to SharedPreferences first so a secure-storage failure
    // (e.g. Android Keystore invalidation after an APK update) cannot prevent
    // the token from being persisted.
    try {
      final prefs = await _getPrefs();
      if (prefs.getString(_tokenKey) != token) {
        await prefs.setString(_tokenKey, token);
      }
    } catch (e) {
      debugPrint('Error saving token to prefs: $e');
    }
    try {
      await _secureStorage.write(key: _tokenKey, value: token);
    } catch (e) {
      debugPrint('Error saving token to secure storage: $e');
    }
  }

  /// Get authentication token
  static Future<String?> getToken() async {
    // Isolate the secure-storage read so that a keystore failure (which can
    // occur after an APK update on some Android versions) does not swallow the
    // SharedPreferences fallback and incorrectly log the user out.
    String? secureToken;
    try {
      secureToken = await _secureStorage.read(key: _tokenKey);
    } catch (e) {
      debugPrint('Secure storage read failed, falling back to SharedPreferences: $e');
    }

    if (secureToken != null && secureToken.isNotEmpty) {
      try {
        final prefs = await _getPrefs();
        // Keep SharedPreferences in sync for code paths outside StorageService.
        if (prefs.getString(_tokenKey) != secureToken) {
          await prefs.setString(_tokenKey, secureToken);
        }
      } catch (_) {}
      return secureToken;
    }

    // Fallback: read from SharedPreferences (also serves as recovery after a
    // keystore invalidation — re-migrates the token back to secure storage).
    try {
      final prefs = await _getPrefs();
      final legacyToken = prefs.getString(_tokenKey);
      if (legacyToken != null && legacyToken.isNotEmpty) {
        try {
          await _secureStorage.write(key: _tokenKey, value: legacyToken);
        } catch (e) {
          debugPrint('Could not re-write token to secure storage: $e');
        }
      }
      return legacyToken;
    } catch (e) {
      debugPrint('Error getting token from SharedPreferences: $e');
      return null;
    }
  }

  /// Save user ID
  static Future<void> saveUserId(int userId) async {
    try {
      final prefs = await _getPrefs();
      if (prefs.getInt(_userIdKey) == userId) return;
      await prefs.setInt(_userIdKey, userId);
    } catch (e) {
      debugPrint('Error saving user ID: $e');
    }
  }

  /// Get user ID
  static Future<int?> getUserId() async {
    try {
      final prefs = await _getPrefs();
      return prefs.getInt(_userIdKey);
    } catch (e) {
      debugPrint('Error getting user ID: $e');
      return null;
    }
  }

  /// Save username
  static Future<void> saveUsername(String username) async {
    try {
      final prefs = await _getPrefs();
      if (prefs.getString(_usernameKey) == username) return;
      await prefs.setString(_usernameKey, username);
    } catch (e) {
      debugPrint('Error saving username: $e');
    }
  }

  /// Get username
  static Future<String?> getUsername() async {
    try {
      final prefs = await _getPrefs();
      return prefs.getString(_usernameKey);
    } catch (e) {
      debugPrint('Error getting username: $e');
      return null;
    }
  }

  /// Save admin status
  static Future<void> saveIsAdmin(bool isAdmin) async {
    try {
      final prefs = await _getPrefs();
      if (prefs.getBool(_isAdminKey) == isAdmin) return;
      await prefs.setBool(_isAdminKey, isAdmin);
    } catch (e) {
      debugPrint('Error saving admin status: $e');
    }
  }

  /// Get admin status
  static Future<bool> getIsAdmin() async {
    try {
      final prefs = await _getPrefs();
      return prefs.getBool(_isAdminKey) ?? false;
    } catch (e) {
      debugPrint('Error getting admin status: $e');
      return false;
    }
  }

  /// Save remembered credentials for future sign-ins.
  static Future<void> saveRememberedCredentials({
    required String username,
    required String password,
  }) async {
    try {
      final prefs = await _getPrefs();
      final rememberMe = prefs.getBool(_rememberMeKey) ?? false;
      final storedUsername = prefs.getString(_rememberedUsernameKey);
      final storedPassword = await _secureStorage.read(
        key: _rememberedPasswordKey,
      );
      if (
        rememberMe &&
        storedUsername == username &&
        storedPassword == password
      ) {
        return;
      }

      await prefs.setBool(_rememberMeKey, true);
      await prefs.setString(_rememberedUsernameKey, username);
      await _secureStorage.write(key: _rememberedPasswordKey, value: password);
    } catch (e) {
      debugPrint('Error saving remembered credentials: $e');
    }
  }

  /// Save only the remembered username for legacy callers.
  static Future<void> saveRememberedUsername(String username) async {
    await saveRememberedCredentials(username: username, password: '');
  }

  /// Get remembered credentials (returns null if not set)
  static Future<RememberedCredentials?> getRememberedCredentials() async {
    try {
      final prefs = await _getPrefs();
      final rememberMe = prefs.getBool(_rememberMeKey) ?? false;
      if (!rememberMe) return null;

      final username = prefs.getString(_rememberedUsernameKey);
      final password = await _secureStorage.read(key: _rememberedPasswordKey);

      if (username == null || username.isEmpty) {
        return null;
      }

      return RememberedCredentials(
        username: username,
        password: password ?? '',
      );
    } catch (e) {
      debugPrint('Error getting remembered credentials: $e');
      return null;
    }
  }

  /// Get remembered username (returns null if not set)
  static Future<String?> getRememberedUsername() async {
    final credentials = await getRememberedCredentials();
    return credentials?.username;
  }

  /// Clear remembered credentials
  static Future<void> clearRememberedCredentials() async {
    try {
      final prefs = await _getPrefs();
      await prefs.remove(_rememberMeKey);
      await prefs.remove(_rememberedUsernameKey);
      await _secureStorage.delete(key: _rememberedPasswordKey);
    } catch (e) {
      debugPrint('Error clearing remembered credentials: $e');
    }
  }

  /// Clear all stored data (logout) — preserves remembered credentials
  static Future<void> clearAll() async {
    try {
      final prefs = await _getPrefs();
      final userId = prefs.getInt(_userIdKey);
      await _secureStorage.delete(key: _tokenKey);
      await prefs.remove(_tokenKey);
      await prefs.remove(_userIdKey);
      await prefs.remove(_usernameKey);
      await prefs.remove(_isAdminKey);
      if (userId != null) {
        await ChatCacheService.clearUserCache(userId);
      }
    } catch (e) {
      debugPrint('Error clearing storage: $e');
    }
  }

  /// Retrieve the persisted auth session in one disk read. Returns null if
  /// any of the required fields are missing.
  static Future<StoredSession?> getUserSession() async {
    try {
      final prefs = await _getPrefs();
      final token = await getToken();
      final userId = prefs.getInt(_userIdKey);

      if (token == null || token.isEmpty || userId == null) {
        return null;
      }

      return StoredSession(
        token: token,
        userId: userId,
        username: prefs.getString(_usernameKey),
        isAdmin: prefs.getBool(_isAdminKey) ?? false,
      );
    } catch (e) {
      debugPrint('Error getting user session: $e');
      return null;
    }
  }

  /// Check if user is logged in
  static Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  /// Get SharedPreferences instance for direct access
  static Future<SharedPreferences> getPreferences() async {
    return await _getPrefs();
  }

  /// Save timestamp format preference
  static Future<void> saveUseMilitaryTime(bool value) async {
    try {
      useMilitaryTime = value;
      final prefs = await _getPrefs();
      await prefs.setBool(_useMilitaryTimeKey, value);
    } catch (e) {
      debugPrint('Error saving useMilitaryTime: $e');
    }
  }
}

/// Lightweight container for the persisted auth session.
class StoredSession {
  final String token;
  final int userId;
  final String? username;
  final bool isAdmin;

  const StoredSession({
    required this.token,
    required this.userId,
    this.username,
    this.isAdmin = false,
  });
}

class RememberedCredentials {
  final String username;
  final String password;

  const RememberedCredentials({
    required this.username,
    required this.password,
  });
}
