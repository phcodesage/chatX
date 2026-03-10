import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'dart:async';
import '../services/call_service.dart';

/// Incoming call modal that shows when receiving a call
/// Displays caller info and accept/decline buttons
class IncomingCallModal extends StatefulWidget {
  final String callerName;
  final int callerId;
  final String callType; // 'video' or 'audio'
  final CallService callService;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;

  const IncomingCallModal({
    super.key,
    required this.callerName,
    required this.callerId,
    required this.callType,
    required this.callService,
    this.onAccept,
    this.onDecline,
  });

  @override
  State<IncomingCallModal> createState() => _IncomingCallModalState();
}

class _IncomingCallModalState extends State<IncomingCallModal>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  Timer? _autoDeclineTimer;
  MediaStream? _localStream;
  bool _isAccepting = false;

  static const Duration autoDeclineTimeout = Duration(seconds: 45);

  @override
  void initState() {
    super.initState();

    // Set up pulse animation
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    // Auto-decline after timeout
    _autoDeclineTimer = Timer(autoDeclineTimeout, () {
      if (mounted) {
        _handleDecline();
      }
    });

    // Listen for call state changes
    widget.callService.onCallStateChanged = _handleCallStateChanged;
  }

  @override
  void dispose() {
    _autoDeclineTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _handleCallStateChanged(CallState state) {
    if (!mounted) return;

    if (state == CallState.ended || state == CallState.failed) {
      // Call was ended/cancelled by caller
      Navigator.of(context).pop('ended');
    } else if (state == CallState.connected) {
      // Call connected - navigate to connected screen
      // Add small delay to ensure UI is ready in release builds
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          Navigator.of(context).pop('connected');
        }
      });
    }
  }

  Future<void> _handleAccept() async {
    if (_isAccepting) return;

    setState(() {
      _isAccepting = true;
    });

    _autoDeclineTimer?.cancel();

    try {
      // Get local media stream
      final mediaConstraints = {
        'audio': true,
        'video': widget.callType == 'video'
            ? {
                'facingMode': 'user',
                'width': {'ideal': 1280},
                'height': {'ideal': 720},
              }
            : false,
      };

      _localStream = await navigator.mediaDevices.getUserMedia(
        mediaConstraints,
      );

      // Answer the call
      await widget.callService.answerCall(localStream: _localStream!);

      widget.onAccept?.call();

      // Pop with 'accepted' result - parent will show connected call screen
      if (mounted) {
        Navigator.of(context).pop('accepted');
      }
    } catch (e) {
      debugPrint('❌ Error accepting call: $e');
      setState(() {
        _isAccepting = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to accept call: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _handleDecline() {
    _autoDeclineTimer?.cancel();
    widget.callService.declineCall();
    widget.onDecline?.call();

    if (mounted) {
      Navigator.of(context).pop('declined');
    }
  }

  Widget _buildControlButton({
    required String label,
    required VoidCallback onPressed,
    required Color backgroundColor,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _handleDecline();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF1A1A2E),
        body: SafeArea(
          child: Column(
            children: [
              // Top bar with call type
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      widget.callType == 'video' ? Icons.videocam : Icons.phone,
                      color: Colors.white70,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Incoming ${widget.callType == 'video' ? 'Video' : 'Audio'} Call',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              // Main content
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Pulsing avatar
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        // Pulse animation
                        AnimatedBuilder(
                          animation: _pulseController,
                          builder: (context, child) {
                            return Container(
                              width: 140 + (_pulseController.value * 20),
                              height: 140 + (_pulseController.value * 20),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color.fromRGBO(
                                  76,
                                  175,
                                  80,
                                  0.3 - (_pulseController.value * 0.2),
                                ),
                              ),
                            );
                          },
                        ),

                        // Avatar circle
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                const Color(0xFF4CAF50),
                                const Color(0xFF388E3C),
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color.fromRGBO(76, 175, 80, 0.4),
                                blurRadius: 20,
                                spreadRadius: 5,
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              widget.callerName.isNotEmpty
                                  ? widget.callerName[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 48,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 32),

                    // Caller name
                    Text(
                      widget.callerName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Status text
                    Text(
                      _isAccepting ? 'Connecting...' : 'Incoming call...',
                      style: const TextStyle(
                        color: Color(0xFF4CAF50),
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              // Accept/Decline buttons with grid layout
              if (!_isAccepting)
                Container(
                  padding: const EdgeInsets.only(top: 8, left: 10, right: 10, bottom: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B1530),
                    border: Border(
                      top: BorderSide(
                        color: const Color(0xFF2D3748),
                        width: 1,
                      ),
                    ),
                  ),
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: 2,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 2.6,
                    ),
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        // Decline button
                        return _buildControlButton(
                          label: 'Decline',
                          onPressed: _handleDecline,
                          backgroundColor: const Color(0xFFEF4444),
                        );
                      } else {
                        // Accept button
                        return _buildControlButton(
                          label: widget.callType == 'video' ? 'Answer Video' : 'Answer Call',
                          onPressed: _handleAccept,
                          backgroundColor: const Color(0xFF22C55E),
                        );
                      }
                    },
                  ),
                ),

              // Loading indicator when accepting
              if (_isAccepting)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(color: Color(0xFF4CAF50)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
