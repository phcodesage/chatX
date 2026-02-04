import 'package:flutter/material.dart';
import 'dart:async';
import '../services/call_service.dart';

/// Outgoing call modal that shows call status when initiating a call
/// Displays: Calling → Ringing → Connected / Declined / No Answer / Cancelled / Failed
class OutgoingCallModal extends StatefulWidget {
  final String recipientName;
  final String callType; // 'video' or 'audio'
  final CallService callService;
  final VoidCallback? onCancel;
  final VoidCallback? onConnected;

  const OutgoingCallModal({
    super.key,
    required this.recipientName,
    required this.callType,
    required this.callService,
    this.onCancel,
    this.onConnected,
  });

  @override
  State<OutgoingCallModal> createState() => _OutgoingCallModalState();
}

class _OutgoingCallModalState extends State<OutgoingCallModal>
    with SingleTickerProviderStateMixin {
  CallState _currentState = CallState.initiating;
  Timer? _noAnswerTimer;
  Timer? _dotsTimer;
  int _dotsCount = 0;
  late AnimationController _pulseController;
  
  static const Duration noAnswerTimeout = Duration(seconds: 45);

  @override
  void initState() {
    super.initState();
    
    // Set up pulse animation
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    
    // Set up dots animation
    _dotsTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (mounted) {
        setState(() {
          _dotsCount = (_dotsCount + 1) % 4;
        });
      }
    });
    
    // Listen to call state changes
    widget.callService.onCallStateChanged = _handleCallStateChanged;
    
    // Start no-answer timer
    _startNoAnswerTimer();
  }

  @override
  void dispose() {
    _noAnswerTimer?.cancel();
    _dotsTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _startNoAnswerTimer() {
    _noAnswerTimer?.cancel();
    _noAnswerTimer = Timer(noAnswerTimeout, () {
      if (_currentState == CallState.initiating || 
          _currentState == CallState.ringing) {
        debugPrint('📞 No answer timeout');
        _handleNoAnswer();
      }
    });
  }

  void _handleCallStateChanged(CallState state) {
    if (!mounted) return;
    
    setState(() {
      _currentState = state;
    });
    
    if (state == CallState.connected) {
      _noAnswerTimer?.cancel();
      widget.onConnected?.call();
      // Navigate to connected call screen (handled by parent)
      // Pop this modal so the parent can show the connected call screen
      if (mounted) {
        Navigator.of(context).pop('connected');
      }
    } else if (state == CallState.failed || state == CallState.ended) {
      _noAnswerTimer?.cancel();
      // Auto-close after showing status
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          Navigator.of(context).pop();
        }
      });
    }
  }

  void _handleNoAnswer() {
    if (!mounted) return;
    
    // Cancel the call
    widget.callService.endCall();
    
    setState(() {
      _currentState = CallState.ended;
    });
    
    // Show "No Answer" then close
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  void _handleCancel() {
    debugPrint('📞 User cancelled outgoing call');
    _noAnswerTimer?.cancel();
    
    // Cancel the call via service
    widget.callService.endCall();
    
    widget.onCancel?.call();
    Navigator.of(context).pop();
  }

  String _getStatusText() {
    final dots = '.' * _dotsCount;
    final padding = ' ' * (3 - _dotsCount);
    
    switch (_currentState) {
      case CallState.initiating:
        return 'Calling$dots$padding';
      case CallState.ringing:
        return 'Ringing$dots$padding';
      case CallState.connecting:
        return 'Connecting$dots$padding';
      case CallState.connected:
        return 'Connected!';
      case CallState.failed:
        return 'Call Failed';
      case CallState.ended:
        return 'No Answer';
      case CallState.idle:
        return 'Cancelled';
    }
  }

  Color _getStatusColor() {
    switch (_currentState) {
      case CallState.initiating:
      case CallState.ringing:
      case CallState.connecting:
        return const Color(0xFF8B5CF6); // Purple
      case CallState.connected:
        return Colors.green;
      case CallState.failed:
      case CallState.ended:
        return Colors.red;
      case CallState.idle:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon() {
    switch (_currentState) {
      case CallState.initiating:
        return Icons.phone;
      case CallState.ringing:
        return Icons.notifications_active;
      case CallState.connecting:
        return Icons.sync;
      case CallState.connected:
        return Icons.check_circle;
      case CallState.failed:
      case CallState.ended:
        return Icons.phone_disabled;
      case CallState.idle:
        return Icons.cancel;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isActive = _currentState == CallState.initiating ||
        _currentState == CallState.ringing ||
        _currentState == CallState.connecting;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _handleCancel();
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
                      widget.callType == 'video' ? 'Video Call' : 'Audio Call',
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
                        if (isActive)
                          AnimatedBuilder(
                            animation: _pulseController,
                            builder: (context, child) {
                              return Container(
                                width: 140 + (_pulseController.value * 20),
                                height: 140 + (_pulseController.value * 20),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Color.fromRGBO(
                                    139, 
                                    92, 
                                    246, 
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
                                const Color(0xFF8B5CF6),
                                const Color(0xFF6D28D9),
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Color.fromRGBO(139, 92, 246, 0.4),
                                blurRadius: 20,
                                spreadRadius: 5,
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              widget.recipientName.isNotEmpty
                                  ? widget.recipientName[0].toUpperCase()
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
                    
                    // Recipient name
                    Text(
                      widget.recipientName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Status indicator
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _getStatusIcon(),
                          color: _getStatusColor(),
                          size: 24,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _getStatusText(),
                          style: TextStyle(
                            color: _getStatusColor(),
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              // Cancel button
              if (isActive)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: GestureDetector(
                    onTap: _handleCancel,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.red,
                        boxShadow: [
                          BoxShadow(
                            color: Color.fromRGBO(244, 67, 54, 0.4),
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
                ),
            ],
          ),
        ),
      ),
    );
  }
}
