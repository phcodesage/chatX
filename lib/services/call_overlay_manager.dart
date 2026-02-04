import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'call_service.dart';
import '../widgets/mini_call_widget.dart';
import '../screens/connected_call_screen.dart';
import '../utils/notification_handler.dart';

/// Manager for the floating call overlay (PiP-like feature)
/// This is a singleton that manages showing/hiding the mini call widget
class CallOverlayManager {
  static final CallOverlayManager _instance = CallOverlayManager._internal();
  factory CallOverlayManager() => _instance;
  CallOverlayManager._internal();

  OverlayEntry? _overlayEntry;
  bool _isShowing = false;
  
  // Store call info for navigation
  CallService? _callService;
  String? _remoteName;
  String? _callType;
  MediaStream? _localStream;
  VoidCallback? _onChatPressed;
  
  // Callback to return to full call screen
  VoidCallback? onReturnToCall;
  
  bool get isShowing => _isShowing;

  /// Show the mini call overlay
  void show({
    required BuildContext context,
    required CallService callService,
    required String remoteName,
    required String callType,
    MediaStream? localStream,
    VoidCallback? onTap,
    VoidCallback? onEndCall,
    VoidCallback? onChatPressed,
  }) {
    if (_isShowing) {
      debugPrint('📱 Mini call overlay already showing');
      return;
    }

    // Store call info for later navigation
    _callService = callService;
    _remoteName = remoteName;
    _callType = callType;
    _localStream = localStream;
    _onChatPressed = onChatPressed;
    onReturnToCall = onTap;

    _overlayEntry = OverlayEntry(
      builder: (context) => MiniCallWidget(
        callService: callService,
        remoteName: remoteName,
        callType: callType,
        onTap: () {
          _returnToCallScreen();
        },
        onEndCall: () {
          hide();
          onEndCall?.call();
        },
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
    _isShowing = true;
    debugPrint('📱 Mini call overlay shown');
  }
  
  /// Return to full call screen using global navigator
  void _returnToCallScreen() {
    if (_callService == null || _remoteName == null || _callType == null) {
      debugPrint('❌ Cannot return to call screen - missing call info');
      hide();
      return;
    }
    
    final navigator = NotificationHandler.navigatorKey.currentState;
    if (navigator == null) {
      debugPrint('❌ Cannot return to call screen - no navigator');
      hide();
      return;
    }
    
    hide();
    
    navigator.push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => ConnectedCallScreen(
          remoteName: _remoteName!,
          callType: _callType!,
          callService: _callService!,
          localStream: _localStream,
          onChatPressed: _onChatPressed,
        ),
      ),
    );
  }

  /// Hide the mini call overlay
  void hide() {
    if (!_isShowing) return;

    _overlayEntry?.remove();
    _overlayEntry = null;
    _isShowing = false;
    onReturnToCall = null;
    debugPrint('📱 Mini call overlay hidden');
  }

  /// Update the overlay (e.g., when remote video changes)
  void update() {
    _overlayEntry?.markNeedsBuild();
  }
}
