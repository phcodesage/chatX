import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/lobby_user.dart';

/// Publishes Android Sharing Shortcuts so the app's contacts appear in the
/// "Direct Share" top row of the Android share sheet (API 25+).
///
/// Call [publishShareTargets] whenever the contact list changes.
class ShortcutService {
  ShortcutService._();

  static const _channel = MethodChannel(
    'com.example.flutter_messenger_v2/shortcuts',
  );

  static Future<void> publishShareTargets(List<LobbyUser> users) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>(
        'pushShareTargets',
        users
            .take(4)
            .map(
              (u) => <String, Object>{
                'id': u.id,
                'name': u.fullName,
                'avatarColorIndex': u.avatarColorIndex,
              },
            )
            .toList(),
      );
    } catch (e) {
      debugPrint('ShortcutService.publishShareTargets: $e');
    }
  }
}
