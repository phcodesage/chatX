import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// Service for managing Picture-in-Picture mode on Android
/// Communicates with native Android via MethodChannel
class PipService {
  static final PipService _instance = PipService._internal();
  factory PipService() => _instance;
  PipService._internal();

  static const MethodChannel _channel = MethodChannel(
    'com.example.flutter_messenger_v2/pip',
  );

  bool _isInPipMode = false;
  bool _isPipAvailable = false;
  bool _isInCall = false;

  bool get isInPipMode => _isInPipMode;
  bool get isPipAvailable => _isPipAvailable;
  bool get isInCall => _isInCall;

  /// Initialize PiP service and check availability
  Future<void> initialize() async {
    try {
      _isPipAvailable =
          await _channel.invokeMethod<bool>('isPipAvailable') ?? false;
      debugPrint('📱 PiP available: $_isPipAvailable');

      // Listen for PiP mode changes from native side
      _channel.setMethodCallHandler(_handleMethodCall);
    } catch (e) {
      debugPrint('⚠️ PiP not supported on this device: $e');
      _isPipAvailable = false;
    }
  }

  /// Handle method calls from native Android
  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onPipModeChanged':
        _isInPipMode = call.arguments as bool? ?? false;
        debugPrint('📱 PiP mode changed: $_isInPipMode');
        onPipModeChanged?.call(_isInPipMode);
        break;
      case 'onPipAction':
        final action = call.arguments as String?;
        debugPrint('📱 PiP action received: $action');
        if (action == 'toggleMic') {
          onToggleMic?.call();
        } else if (action == 'endCall') {
          onEndCall?.call();
        }
        break;
    }
  }

  // Callback for PiP mode changes
  Function(bool isInPip)? onPipModeChanged;

  // Callbacks for PiP action buttons
  VoidCallback? onToggleMic;
  VoidCallback? onEndCall;

  /// Mark that we're in a call (enables auto-PiP on minimize)
  Future<void> setInCall(bool inCall) async {
    _isInCall = inCall;
    try {
      await _channel.invokeMethod('setInCall', {'inCall': inCall});
      debugPrint('📱 PiP setInCall: $inCall');
    } catch (e) {
      debugPrint('⚠️ Error setting in-call state: $e');
    }
  }

  /// Update the mute state on native side so PiP icon reflects current state
  Future<void> updateMuteState(bool isMuted) async {
    try {
      await _channel.invokeMethod('updateMuteState', {'isMuted': isMuted});
    } catch (e) {
      debugPrint('⚠️ Error updating mute state: $e');
    }
  }

  /// Enter PiP mode manually
  Future<bool> enterPipMode() async {
    if (!_isPipAvailable) {
      debugPrint('⚠️ PiP not available');
      return false;
    }

    try {
      final result = await _channel.invokeMethod<bool>('enterPipMode') ?? false;
      debugPrint('📱 Enter PiP result: $result');
      return result;
    } catch (e) {
      debugPrint('❌ Error entering PiP mode: $e');
      return false;
    }
  }
}
