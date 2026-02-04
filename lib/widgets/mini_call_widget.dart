import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/call_service.dart';

/// A floating mini call widget for ongoing calls (PiP-like)
/// Displays when user navigates away from the call screen
class MiniCallWidget extends StatefulWidget {
  final CallService callService;
  final String remoteName;
  final String callType;
  final VoidCallback? onTap;
  final VoidCallback? onEndCall;

  const MiniCallWidget({
    super.key,
    required this.callService,
    required this.remoteName,
    required this.callType,
    this.onTap,
    this.onEndCall,
  });

  @override
  State<MiniCallWidget> createState() => _MiniCallWidgetState();
}

class _MiniCallWidgetState extends State<MiniCallWidget> {
  // Position of the floating widget
  Offset _position = const Offset(20, 100);
  
  // Video renderer for remote stream
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  bool _isMuted = false;
  
  @override
  void initState() {
    super.initState();
    _initRenderer();
    
    // Listen for call state changes
    widget.callService.onCallStateChanged = (state) {
      if (state == CallState.ended || state == CallState.idle) {
        // Call ended - close the overlay
        widget.onEndCall?.call();
      }
      if (mounted) setState(() {});
    };
    
    // Listen for remote stream
    widget.callService.onRemoteStream = (stream) {
      _remoteRenderer.srcObject = stream;
      if (mounted) setState(() {});
    };
  }

  Future<void> _initRenderer() async {
    await _remoteRenderer.initialize();
    // Set initial remote stream if available
    if (widget.callService.remoteStream != null) {
      _remoteRenderer.srcObject = widget.callService.remoteStream;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _remoteRenderer.dispose();
    super.dispose();
  }

  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
      widget.callService.toggleAudio(!_isMuted);
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    const widgetWidth = 120.0;
    const widgetHeight = 180.0;

    return Positioned(
      left: _position.dx.clamp(0, screenSize.width - widgetWidth),
      top: _position.dy.clamp(0, screenSize.height - widgetHeight - 50),
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _position += details.delta;
          });
        },
        onTap: widget.onTap,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(12),
          color: Colors.transparent,
          child: Container(
            width: widgetWidth,
            height: widgetHeight,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green, width: 2),
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
              child: Stack(
                children: [
                  // Remote video or avatar
                  _buildVideoView(),
                  
                  // Remote name
                  Positioned(
                    top: 8,
                    left: 8,
                    right: 8,
                    child: Text(
                      widget.remoteName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        shadows: [Shadow(blurRadius: 4)],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  
                  // "Tap to expand" hint
                  Positioned(
                    bottom: 40,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'Tap to expand',
                          style: TextStyle(color: Colors.white, fontSize: 10),
                        ),
                      ),
                    ),
                  ),
                  
                  // Control buttons at bottom
                  Positioned(
                    bottom: 4,
                    left: 4,
                    right: 4,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        // Mute button
                        _buildMiniButton(
                          icon: _isMuted ? Icons.mic_off : Icons.mic,
                          color: _isMuted ? Colors.red : Colors.white,
                          onTap: _toggleMute,
                        ),
                        // End call button
                        _buildMiniButton(
                          icon: Icons.call_end,
                          color: Colors.red,
                          onTap: () {
                            widget.callService.endCall();
                            widget.onEndCall?.call();
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVideoView() {
    final hasRemoteStream = _remoteRenderer.srcObject != null;
    
    if (!hasRemoteStream || widget.callType == 'audio') {
      // Show avatar for audio calls or no video
      return Container(
        color: Colors.grey[900],
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: Colors.blue,
                child: Text(
                  widget.remoteName.isNotEmpty ? widget.remoteName[0].toUpperCase() : '?',
                  style: const TextStyle(fontSize: 24, color: Colors.white),
                ),
              ),
              const SizedBox(height: 8),
              if (widget.callType == 'audio')
                const Icon(Icons.phone_in_talk, color: Colors.green, size: 20),
            ],
          ),
        ),
      );
    }

    return RTCVideoView(
      _remoteRenderer,
      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
    );
  }

  Widget _buildMiniButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color, size: 18),
      ),
    );
  }
}
