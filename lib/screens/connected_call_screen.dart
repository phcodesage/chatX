import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'dart:async';
import '../services/call_service.dart';
import '../services/call_overlay_manager.dart';
import '../services/socket_service.dart';
import '../services/call_notification_service.dart';
import '../services/pip_service.dart';
import '../services/presence_service.dart';

/// Connected call screen that shows during an active call
/// Displays: Remote video (fullscreen), Local video (PiP), Controls bar
class ConnectedCallScreen extends StatefulWidget {
  final String remoteName;
  final String callType; // 'video' or 'audio'
  final CallService callService;
  final MediaStream? localStream;
  final VoidCallback? onChatPressed;

  const ConnectedCallScreen({
    super.key,
    required this.remoteName,
    required this.callType,
    required this.callService,
    this.localStream,
    this.onChatPressed,
  });

  @override
  State<ConnectedCallScreen> createState() => _ConnectedCallScreenState();
}

class _ConnectedCallScreenState extends State<ConnectedCallScreen> with WidgetsBindingObserver {
  // Video renderers
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  
  // Local video position for draggable PiP
  Offset _localVideoPosition = const Offset(16, 100);
  
  // Control states
  bool _isMicMuted = false;
  bool _isVideoHidden = false;
  bool _showControls = true;
  bool _isSpeakerOn = true;
  bool _isScreenSharing = false;
  bool _remoteIsScreenSharing = false;
  
  // Call duration
  Timer? _durationTimer;
  int _callDuration = 0;
  
  // Prevent multiple pops
  bool _isEnding = false;
  
  // Device lists
  List<MediaDeviceInfo> _microphones = [];
  List<MediaDeviceInfo> _cameras = [];
  List<MediaDeviceInfo> _speakers = [];
  
  // Selected devices
  String? _selectedMicId;
  String? _selectedCameraId;
  String? _selectedSpeakerId;

  // Services for ongoing call notification and PiP
  final CallNotificationService _callNotificationService = CallNotificationService();
  final PipService _pipService = PipService();
  bool _isInPipMode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Mark call in progress so PresenceService keeps status 'online' when backgrounded
    PresenceService().isCallInProgress = true;
    _initializeRenderers();
    _startCallDurationTimer();
    _loadDevices();
    _setupCallListeners();
    _initCallServices();
  }

  /// Initialize ongoing call notification and PiP
  Future<void> _initCallServices() async {
    // Show ongoing call notification in status bar
    await _callNotificationService.initialize();
    await _callNotificationService.show(
      remoteName: widget.remoteName,
      callType: widget.callType,
    );
    _callNotificationService.onEndCallFromNotification = () {
      _endCall();
    };

    // Initialize PiP and mark as in-call (await so native flag is set)
    await _pipService.initialize();
    await _pipService.setInCall(true);
    _pipService.onPipModeChanged = (isInPip) {
      if (mounted) {
        setState(() {
          _isInPipMode = isInPip;
        });
      }
    };
    // Handle PiP action buttons (mute/end call from PiP overlay)
    _pipService.onToggleMic = () {
      _toggleMic();
      _pipService.updateMuteState(_isMicMuted);
    };
    _pipService.onEndCall = () {
      _endCall();
    };
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    debugPrint('📱 App lifecycle state: $state (isEnding: $_isEnding)');
    // PiP is handled natively via onUserLeaveHint in MainActivity
    // We just track the mode change here via the callback
  }

  Future<void> _initializeRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    
    // Set local stream
    if (widget.localStream != null) {
      _localRenderer.srcObject = widget.localStream;
    } else if (widget.callService.localStream != null) {
      _localRenderer.srcObject = widget.callService.localStream;
    }
    
    // Set remote stream if already available
    if (widget.callService.remoteStream != null) {
      _remoteRenderer.srcObject = widget.callService.remoteStream;
    }
    
    setState(() {});
  }

  void _setupCallListeners() {
    final socketService = SocketService();
    
    // Listen for remote stream
    widget.callService.onRemoteStream = (stream) {
      debugPrint('🎥 Connected call screen received remote stream');
      _remoteRenderer.srcObject = stream;
      setState(() {});
    };
    
    // Listen for call state changes
    widget.callService.onCallStateChanged = (state) {
      debugPrint('📞 Call state changed to: $state');
      if (state == CallState.ended || state == CallState.failed) {
        _endCall();
      }
    };
    
    // Listen for screen share changes (local or remote)
    widget.callService.onScreenShareChanged = (isSharing) {
      debugPrint('🖥️ Screen share changed: $isSharing');
      if (mounted) {
        setState(() {
          // If we're not sharing, it means remote started/stopped
          if (!_isScreenSharing) {
            _remoteIsScreenSharing = isSharing;
          }
        });
      }
    };
    
    // Listen for call ended from socket (remote user ended call)
    socketService.onCallEnded = (data) {
      debugPrint('📴 Call ended event received from socket');
      widget.callService.handleCallEnded();
    };
    
    // Listen for signals during the call
    socketService.onSignal = (data) {
      widget.callService.handleSignal(data);
    };
  }

  Future<void> _loadDevices() async {
    try {
      final devices = await navigator.mediaDevices.enumerateDevices();
      setState(() {
        _microphones = devices.where((d) => d.kind == 'audioinput').toList();
        _cameras = devices.where((d) => d.kind == 'videoinput').toList();
        _speakers = devices.where((d) => d.kind == 'audiooutput').toList();
        
        if (_microphones.isNotEmpty) {
          _selectedMicId = _microphones.first.deviceId;
        }
        if (_cameras.isNotEmpty) {
          _selectedCameraId = _cameras.first.deviceId;
        }
        if (_speakers.isNotEmpty) {
          _selectedSpeakerId = _speakers.first.deviceId;
        }
      });
    } catch (e) {
      debugPrint('Error loading devices: $e');
    }
  }

  void _startCallDurationTimer() {
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _callDuration++;
        });
      }
    });
  }

  String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  void _toggleMic() {
    final stream = widget.localStream ?? widget.callService.localStream;
    if (stream != null) {
      for (var track in stream.getAudioTracks()) {
        track.enabled = _isMicMuted;
      }
    }
    setState(() {
      _isMicMuted = !_isMicMuted;
    });
  }

  void _toggleVideo() {
    final stream = widget.localStream ?? widget.callService.localStream;
    if (stream != null) {
      for (var track in stream.getVideoTracks()) {
        track.enabled = _isVideoHidden;
      }
    }
    setState(() {
      _isVideoHidden = !_isVideoHidden;
    });
  }

  Future<void> _switchCamera() async {
    final stream = widget.localStream ?? widget.callService.localStream;
    if (stream != null && _cameras.length > 1) {
      final currentIndex = _cameras.indexWhere((c) => c.deviceId == _selectedCameraId);
      final nextIndex = (currentIndex + 1) % _cameras.length;
      _selectedCameraId = _cameras[nextIndex].deviceId;
      
      // Switch camera using Helper
      await Helper.switchCamera(stream.getVideoTracks().first);
      setState(() {});
    }
  }

  void _toggleSpeaker() {
    setState(() {
      _isSpeakerOn = !_isSpeakerOn;
    });
    // On mobile, toggle between earpiece and speaker
    Helper.setSpeakerphoneOn(_isSpeakerOn);
  }

  Future<void> _toggleScreenShare() async {
    final result = await widget.callService.toggleScreenShare();
    setState(() {
      _isScreenSharing = result;
    });
  }

  void _endCall() {
    if (_isEnding) return; // Prevent multiple calls
    _isEnding = true;
    debugPrint('📞 Ending call from connected screen');
    
    // Clear call-in-progress flag so presence resumes normal behavior
    PresenceService().isCallInProgress = false;
    
    // Show "Call Ended" notification and disable PiP
    _callNotificationService.showCallEnded();
    _pipService.setInCall(false); // fire-and-forget is fine on cleanup
    
    widget.callService.endCall();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
  }

  void _minimizeToOverlay() {
    // Show the floating mini call widget with all call info
    CallOverlayManager().show(
      context: context,
      callService: widget.callService,
      remoteName: widget.remoteName,
      callType: widget.callType,
      localStream: widget.localStream,
      onChatPressed: widget.onChatPressed,
      onEndCall: () {
        widget.callService.endCall();
      },
    );
    
    // Only pop the call screen - the overlay manager handles navigation back
    Navigator.of(context).pop();
  }

  void _showDeviceSelector(String type) {
    List<MediaDeviceInfo> devices;
    String? selectedId;
    String title;
    
    switch (type) {
      case 'mic':
        devices = _microphones;
        selectedId = _selectedMicId;
        title = 'Select Microphone';
        break;
      case 'camera':
        devices = _cameras;
        selectedId = _selectedCameraId;
        title = 'Select Camera';
        break;
      case 'speaker':
        devices = _speakers;
        selectedId = _selectedSpeakerId;
        title = 'Select Speaker';
        break;
      default:
        return;
    }
    
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => _buildDeviceSelector(title, devices, selectedId, type),
    );
  }

  Widget _buildDeviceSelector(String title, List<MediaDeviceInfo> devices, String? selectedId, String type) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[600],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          ...devices.map((device) => ListTile(
            leading: Icon(
              type == 'mic' ? Icons.mic : 
              type == 'camera' ? Icons.videocam : Icons.speaker,
              color: device.deviceId == selectedId 
                  ? const Color(0xFF8B5CF6) 
                  : Colors.grey,
            ),
            title: Text(
              device.label.isNotEmpty ? device.label : 'Device ${device.deviceId.substring(0, 8)}',
              style: TextStyle(
                color: device.deviceId == selectedId ? const Color(0xFF8B5CF6) : Colors.white,
              ),
            ),
            trailing: device.deviceId == selectedId
                ? const Icon(Icons.check, color: Color(0xFF8B5CF6))
                : null,
            onTap: () {
              setState(() {
                switch (type) {
                  case 'mic':
                    _selectedMicId = device.deviceId;
                    break;
                  case 'camera':
                    _selectedCameraId = device.deviceId;
                    break;
                  case 'speaker':
                    _selectedSpeakerId = device.deviceId;
                    break;
                }
              });
              Navigator.pop(context);
            },
          )),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _durationTimer?.cancel();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    
    // Clean up notification and PiP if not already ended
    if (!_isEnding) {
      _callNotificationService.showCallEnded();
    }
    _pipService.setInCall(false);
    
    // Ensure call flag is cleared even if _endCall wasn't called
    PresenceService().isCallInProgress = false;
    
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _showEndCallConfirmation();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onTap: _toggleControls,
          child: Stack(
            children: [
              // Remote video (fullscreen background)
              _buildRemoteVideo(),
              
              // Local video (PiP, draggable) - hide in PiP mode
              if (!_isInPipMode) _buildLocalVideoPiP(),
              
              // Top bar with call info - hide in PiP mode
              if (_showControls && !_isInPipMode) _buildTopBar(),
              
              // Bottom controls - hide in PiP mode
              if (_showControls && !_isInPipMode) _buildBottomControls(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRemoteVideo() {
    final hasRemoteStream = _remoteRenderer.srcObject != null;
    
    if (!hasRemoteStream || widget.callType == 'audio') {
      // Audio call or no remote stream - show avatar
      return Container(
        color: const Color(0xFF1A1A2E),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Avatar
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF8B5CF6),
                      const Color(0xFF6D28D9),
                    ],
                  ),
                ),
                child: Center(
                  child: Text(
                    widget.remoteName.isNotEmpty
                        ? widget.remoteName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                widget.remoteName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _formatDuration(_callDuration),
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      );
    }
    
    // Use RTCVideoViewObjectFitContain to show full width video without cropping
    return Stack(
      children: [
        Container(
          color: Colors.black,
          width: double.infinity,
          height: double.infinity,
          child: RTCVideoView(
            _remoteRenderer,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
          ),
        ),
        // Screen share indicator
        if (_remoteIsScreenSharing)
          Positioned(
            top: MediaQuery.of(context).padding.top + 60,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.screen_share, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Screen is being shared',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildLocalVideoPiP() {
    final hasLocalStream = _localRenderer.srcObject != null && !_isVideoHidden;
    
    if (!hasLocalStream || widget.callType == 'audio') {
      return const SizedBox.shrink();
    }
    
    return Positioned(
      left: _localVideoPosition.dx,
      top: _localVideoPosition.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _localVideoPosition += details.delta;
            // Keep within screen bounds
            final size = MediaQuery.of(context).size;
            _localVideoPosition = Offset(
              _localVideoPosition.dx.clamp(0, size.width - 120),
              _localVideoPosition.dy.clamp(0, size.height - 180),
            );
          });
        },
        onDoubleTap: _switchCamera,
        child: Container(
          width: 120,
          height: 160,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white30, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: RTCVideoView(
              _localRenderer,
              mirror: true,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 8,
          left: 16,
          right: 16,
          bottom: 16,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.7),
              Colors.transparent,
            ],
          ),
        ),
        child: Row(
          children: [
            // Call type icon
            Icon(
              widget.callType == 'video' ? Icons.videocam : Icons.phone,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 8),
            // Name
            Expanded(
              child: Text(
                widget.remoteName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Duration
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color.fromRGBO(0, 0, 0, 0.4),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                _formatDuration(_callDuration),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          top: 24,
          left: 16,
          right: 16,
          bottom: MediaQuery.of(context).padding.bottom + 24,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withValues(alpha: 0.8),
              Colors.transparent,
            ],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Main control row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Mute mic
                _buildControlButton(
                  icon: _isMicMuted ? Icons.mic_off : Icons.mic,
                  label: _isMicMuted ? 'Unmute' : 'Mute',
                  isActive: !_isMicMuted,
                  onTap: _toggleMic,
                  onLongPress: () => _showDeviceSelector('mic'),
                ),
                
                // Video toggle
                if (widget.callType == 'video')
                  _buildControlButton(
                    icon: _isVideoHidden ? Icons.videocam_off : Icons.videocam,
                    label: _isVideoHidden ? 'Show' : 'Hide',
                    isActive: !_isVideoHidden,
                    onTap: _toggleVideo,
                    onLongPress: () => _showDeviceSelector('camera'),
                  ),
                
                // Switch camera
                if (widget.callType == 'video' && _cameras.length > 1)
                  _buildControlButton(
                    icon: Icons.flip_camera_ios,
                    label: 'Flip',
                    isActive: true,
                    onTap: _switchCamera,
                  ),
                
                // Speaker
                _buildControlButton(
                  icon: _isSpeakerOn ? Icons.volume_up : Icons.hearing,
                  label: _isSpeakerOn ? 'Speaker' : 'Earpiece',
                  isActive: _isSpeakerOn,
                  onTap: _toggleSpeaker,
                  onLongPress: () => _showDeviceSelector('speaker'),
                ),
                
                // Screen share
                _buildControlButton(
                  icon: _isScreenSharing ? Icons.stop_screen_share : Icons.screen_share,
                  label: _isScreenSharing ? 'Stop Share' : 'Share',
                  isActive: _isScreenSharing,
                  onTap: _toggleScreenShare,
                ),
                
                // Chat (minimizes to overlay)
                if (widget.onChatPressed != null)
                  _buildControlButton(
                    icon: Icons.chat_bubble_outline,
                    label: 'Chat',
                    isActive: true,
                    onTap: _minimizeToOverlay,
                  ),
              ],
            ),
            
            const SizedBox(height: 24),
            
            // End call button
            GestureDetector(
              onTap: _endCall,
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.red,
                  boxShadow: [
                    BoxShadow(
                      color: const Color.fromRGBO(244, 67, 54, 0.4),
                      blurRadius: 15,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.call_end,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
  }) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive 
                  ? const Color.fromRGBO(255, 255, 255, 0.2)
                  : const Color.fromRGBO(255, 82, 82, 0.7),
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: Colors.grey[300],
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  void _showEndCallConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D2D),
        title: const Text('End Call?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure you want to end this call?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _endCall();
            },
            child: const Text('End Call', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
