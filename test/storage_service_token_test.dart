// Tests that StorageService.getToken() and saveToken() remain functional
// even when FlutterSecureStorage throws (simulates Android Keystore
// invalidation that can occur after an APK update).

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_messenger/services/storage_service.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Drives the private [_secureStorage] field in [StorageService] via the
/// method channel mock provided by flutter_secure_storage's test helpers.
/// We intercept the platform channel calls instead of injecting a mock so we
/// don't need to change production code.

void _setupSecureStorageSucceeds({String? token}) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    (call) async {
      if (call.method == 'read') return token;
      if (call.method == 'write') return null;
      if (call.method == 'delete') return null;
      return null;
    },
  );
}

void _setupSecureStorageThrows() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    (call) async {
      throw PlatformException(
        code: 'KEYSTORE_INVALIDATED',
        message: 'Simulated keystore failure after APK update',
      );
    },
  );
}

void _clearSecureStorageHandler() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    null,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    // Reset SharedPreferences to a clean state before every test.
    SharedPreferences.setMockInitialValues({});
    // Reset the cached prefs instance inside StorageService so it picks up
    // the fresh mock values set above.
    StorageService.resetForTesting();
    await StorageService.init();
  });

  tearDown(() {
    _clearSecureStorageHandler();
  });

  group('StorageService.getToken()', () {
    test('returns token from secure storage when it works normally', () async {
      _setupSecureStorageSucceeds(token: 'secure-token-123');

      final token = await StorageService.getToken();

      expect(token, equals('secure-token-123'));
    });

    test(
        'falls back to SharedPreferences when secure storage throws '
        '(APK-update keystore invalidation)', () async {
      // Pre-populate SharedPreferences with a token (as would be the case for
      // an existing logged-in user) and reinit so StorageService sees it.
      SharedPreferences.setMockInitialValues({'auth_token': 'prefs-token-abc'});
      StorageService.resetForTesting();
      await StorageService.init();

      // Secure storage now throws (simulates post-update keystore failure).
      _setupSecureStorageThrows();

      final token = await StorageService.getToken();

      expect(
        token,
        equals('prefs-token-abc'),
        reason: 'User should remain logged in even if secure storage fails',
      );
    });

    test('returns null when both secure storage and SharedPreferences are empty',
        () async {
      _setupSecureStorageSucceeds(token: null);

      final token = await StorageService.getToken();

      expect(token, isNull);
    });
  });

  group('StorageService.saveToken()', () {
    test('writes to SharedPreferences even when secure storage throws', () async {
      _setupSecureStorageThrows();

      await StorageService.saveToken('new-token-xyz');

      // SharedPreferences should still contain the token.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('auth_token'), equals('new-token-xyz'));
    });

    test('writes to both storages when secure storage is healthy', () async {
      String? writtenSecureValue;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (call) async {
          if (call.method == 'write') {
            writtenSecureValue = (call.arguments as Map)['value'] as String?;
          }
          if (call.method == 'read') return null;
          return null;
        },
      );

      await StorageService.saveToken('both-token-456');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('auth_token'), equals('both-token-456'));
      expect(writtenSecureValue, equals('both-token-456'));
    });
  });

  group('isLoggedIn() after simulated APK update', () {
    test('returns true when only SharedPreferences has the token', () async {
      SharedPreferences.setMockInitialValues({'auth_token': 'alive-token'});
      StorageService.resetForTesting();
      await StorageService.init();
      _setupSecureStorageThrows();

      final loggedIn = await StorageService.isLoggedIn();

      expect(loggedIn, isTrue,
          reason: 'App update must not log the user out');
    });
  });
}
