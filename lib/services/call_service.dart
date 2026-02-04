import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'socket_service.dart';
import '../config/api_config.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

/// Call state enum
enum CallState {
  idle,
  initiating,
  ringing,
  connecting,
  connected,
  ended,
  failed,
}

/// Call direction
enum CallDirection { outgoing, incoming }

/// Service for managing WebRTC calls
class CallService {
  static final CallService _instance = CallService._internal();
  factory CallService() => _instance;
  CallService._internal();

  final SocketService _socketService = SocketService();
  
  // WebRTC components
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  
  // Call state
  CallState _callState = CallState.idle;
  CallDirection? _callDirection;
  int? _callId;
  int? _remoteUserId;
  String? _callRoomId;
  String? _callType; // 'video' or 'audio'
  
  // Callbacks
  Function(CallState state)? onCallStateChanged;
  Function(MediaStream stream)? onLocalStream;
  Function(MediaStream stream)? onRemoteStream;
  Function(Map<String, dynamic> data)? onIncomingCall;
  Function(String error)? onCallError;
  
  // ICE servers
  List<Map<String, dynamic>> _iceServers = [];
  
  // ICE candidate queuing (for candidates that arrive before PC or remote description is set)
  final List<RTCIceCandidate> _earlyIceCandidates = [];  // Before PC exists
  final List<RTCIceCandidate> _candidateQueue = [];      // Before remote description is set
  bool _remoteDescriptionSet = false;
  
  // Getters
  CallState get callState => _callState;
  int? get callId => _callId;
  int? get remoteUserId => _remoteUserId;
  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;

  /// Initialize the call service and set up socket listeners
  Future<void> initialize() async {
    _setupSocketListeners();
    await _fetchIceServers();
  }

  /// Reset call state (for cleaning up stale state)
  void reset() {
    debugPrint('🔄 Resetting CallService state');
    _cleanup();
  }

  /// Fetch ICE servers from backend
  Future<void> _fetchIceServers() async {
    try {
      // Get auth token from storage
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      
      final headers = <String, String>{
        'Content-Type': 'application/json',
      };
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }
      
      debugPrint('📡 Fetching ICE servers from ${ApiConfig.baseUrl}/get-ice-servers');
      
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/get-ice-servers'),
        headers: headers,
      );
      
      debugPrint('📡 ICE servers response status: ${response.statusCode}');
      debugPrint('📡 ICE servers response body: ${response.body}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        // Backend may return 'iceServers' (camelCase) or 'ice_servers' (snake_case)
        final servers = data['iceServers'] ?? data['ice_servers'];
        debugPrint('📡 Raw iceServers value: $servers');
        debugPrint('📡 iceServers type: ${servers.runtimeType}');
        
        if (servers != null && servers is List) {
          _iceServers = List<Map<String, dynamic>>.from(servers);
          debugPrint('📡 ICE servers parsed: ${_iceServers.length} servers');
          
          for (var i = 0; i < _iceServers.length; i++) {
            final server = _iceServers[i];
            debugPrint('📡 Server $i:');
            debugPrint('   urls: ${server['urls']}');
            debugPrint('   username: ${server['username'] != null ? '(set)' : '(not set)'}');
            debugPrint('   credential: ${server['credential'] != null ? '(set)' : '(not set)'}');
          }
        } else {
          debugPrint('⚠️ iceServers is null or not a list');
          _iceServers = [];
        }
        
        // If we got 0 servers, fall back to default
        if (_iceServers.isEmpty) {
          debugPrint('⚠️ Backend returned empty ICE servers, using defaults');
          _iceServers = [
            {'urls': 'stun:stun.l.google.com:19302'},
            {'urls': 'stun:stun1.l.google.com:19302'},
          ];
        }
      } else {
        debugPrint('⚠️ ICE servers API returned ${response.statusCode}');
        // Use default STUN servers
        _iceServers = [
          {'urls': 'stun:stun.l.google.com:19302'},
          {'urls': 'stun:stun1.l.google.com:19302'},
        ];
        debugPrint('⚠️ Using default STUN servers');
      }
    } catch (e, stack) {
      debugPrint('❌ Error fetching ICE servers: $e');
      debugPrint('❌ Stack trace: $stack');
      _iceServers = [
        {'urls': 'stun:stun.l.google.com:19302'},
      ];
    }
  }

  /// Set up socket event listeners for call signaling
  void _setupSocketListeners() {
    final socket = _socketService;
    
    // Listen for incoming call
    socket.emit('subscribe_calls', {});
    
    // We need to add listeners to the socket directly
    // These will be added via the socket_service callbacks
  }

  /// Initiate a call to another user
  Future<void> initiateCall({
    required int calleeId,
    required String callType,
    required MediaStream localStream,
  }) async {
    // Reset if in a stale state (not actively connected)
    if (_callState != CallState.idle && _callState != CallState.connected) {
      debugPrint('⚠️ Resetting stale call state: $_callState');
      _cleanup();
    }
    
    if (_callState != CallState.idle) {
      debugPrint('⚠️ Cannot initiate call - already in a call');
      return;
    }

    try {
      _callState = CallState.initiating;
      _callDirection = CallDirection.outgoing;
      _remoteUserId = calleeId;
      _callType = callType;
      _localStream = localStream;
      onCallStateChanged?.call(_callState);

      debugPrint('📞 Initiating $callType call to user $calleeId');

      // Emit initiate_call event
      _socketService.emit('initiate_call', {
        'callee_id': calleeId,
        'call_type': callType,
      });

      // Set up peer connection
      await _createPeerConnection();

      // Add local stream tracks to peer connection
      for (var track in _localStream!.getTracks()) {
        await _peerConnection!.addTrack(track, _localStream!);
      }

      // Create and send offer
      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);

      debugPrint('📤 Sending WebRTC offer');
      _socketService.emit('signal', {
        'signal': {
          'type': 'offer',
          'sdp': offer.sdp,
        },
      });

      _callState = CallState.ringing;
      onCallStateChanged?.call(_callState);

    } catch (e) {
      debugPrint('❌ Error initiating call: $e');
      _callState = CallState.failed;
      onCallStateChanged?.call(_callState);
      onCallError?.call('Failed to initiate call: $e');
    }
  }

  /// Create WebRTC peer connection
  Future<void> _createPeerConnection() async {
    final config = {
      'iceServers': _iceServers.isNotEmpty ? _iceServers : [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
      'sdpSemantics': 'unified-plan',
    };

    debugPrint('🔧 Creating RTCPeerConnection with config:');
    debugPrint('🔧 iceServers count: ${(config['iceServers'] as List).length}');
    debugPrint('🔧 Full config: $config');

    _peerConnection = await createPeerConnection(config);

    // Handle ICE candidates
    _peerConnection!.onIceCandidate = (candidate) {
      if (candidate.candidate != null) {
        debugPrint('🧊 Sending ICE candidate');
        _socketService.emit('signal', {
          'signal': {
            'type': 'ice-candidate',
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          },
        });
      }
    };

    // Handle ICE connection state
    _peerConnection!.onIceConnectionState = (state) {
      debugPrint('🧊 ICE connection state: $state');
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected) {
        _callState = CallState.connected;
        onCallStateChanged?.call(_callState);
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed ||
                 state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        debugPrint('⚠️ ICE connection failed or disconnected');
      }
    };

    // Handle remote tracks
    _peerConnection!.onTrack = (event) {
      debugPrint('🎥 Received remote track: ${event.track.kind}');
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        onRemoteStream?.call(_remoteStream!);
      }
    };

    // Handle connection state
    _peerConnection!.onConnectionState = (state) {
      debugPrint('🔗 Connection state: $state');
    };
  }

  /// Handle incoming signal (offer/answer/ICE candidate)
  Future<void> handleSignal(Map<String, dynamic> signalData) async {
    final signal = signalData['signal'] as Map<String, dynamic>?;
    if (signal == null) return;

    final type = signal['type'] as String?;
    
    // Web client may send ICE candidates without 'type' field
    // Detect by presence of 'candidate' key
    if (type == null && signal.containsKey('candidate')) {
      debugPrint('🧊 ICE candidate signal detected (no type field)');
      await _handleIceCandidate(signal);
      return;
    }

    switch (type) {
      case 'offer':
        await _handleOffer(signal);
        break;
      case 'answer':
        await _handleAnswer(signal);
        break;
      case 'ice-candidate':
        await _handleIceCandidate(signal);
        break;
      default:
        debugPrint('⚠️ Unknown signal type: $type');
    }
  }

  /// Handle incoming offer
  Future<void> _handleOffer(Map<String, dynamic> signal) async {
    debugPrint('📥 Received WebRTC offer');
    
    if (_peerConnection == null) {
      await _createPeerConnection();
    }

    final sdp = signal['sdp'] as String;
    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(sdp, 'offer'),
    );
    
    _remoteDescriptionSet = true;
    debugPrint('📥 Remote description set (offer)');
    
    // Process any queued ICE candidates
    await _processQueuedCandidates();

    // Add local stream if we have one
    if (_localStream != null) {
      for (var track in _localStream!.getTracks()) {
        await _peerConnection!.addTrack(track, _localStream!);
      }
    }

    // Create and send answer
    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);

    debugPrint('📤 Sending WebRTC answer');
    _socketService.emit('signal', {
      'signal': {
        'type': 'answer',
        'sdp': answer.sdp,
      },
    });

    _callState = CallState.connecting;
    onCallStateChanged?.call(_callState);
  }

  /// Handle incoming answer
  Future<void> _handleAnswer(Map<String, dynamic> signal) async {
    debugPrint('📥 Received WebRTC answer');
    
    if (_peerConnection == null) return;

    final sdp = signal['sdp'] as String;
    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(sdp, 'answer'),
    );
    
    _remoteDescriptionSet = true;
    debugPrint('📥 Remote description set (answer)');
    
    // Process any queued ICE candidates
    await _processQueuedCandidates();

    _callState = CallState.connecting;
    onCallStateChanged?.call(_callState);
  }

  /// Handle ICE candidate with queuing support
  Future<void> _handleIceCandidate(Map<String, dynamic> signal) async {
    final candidate = RTCIceCandidate(
      signal['candidate'] as String?,
      signal['sdpMid'] as String?,
      signal['sdpMLineIndex'] as int?,
    );
    
    // Queue if no peer connection yet
    if (_peerConnection == null) {
      _earlyIceCandidates.add(candidate);
      debugPrint('🧊 Queued early ICE candidate (no PC). Queue size: ${_earlyIceCandidates.length}');
      return;
    }
    
    // Queue if remote description not set
    if (!_remoteDescriptionSet) {
      _candidateQueue.add(candidate);
      debugPrint('🧊 Queued ICE candidate (no remote desc). Queue size: ${_candidateQueue.length}');
      return;
    }
    
    // Add immediately if ready
    try {
      debugPrint('🧊 Adding ICE candidate immediately');
      await _peerConnection!.addCandidate(candidate);
    } catch (e) {
      debugPrint('⚠️ Error adding ICE candidate: $e - will queue for retry');
      _candidateQueue.add(candidate);
    }
  }
  
  /// Process all queued ICE candidates
  Future<void> _processQueuedCandidates() async {
    if (_peerConnection == null || !_remoteDescriptionSet) {
      debugPrint('⚠️ Cannot process queued candidates - PC or remote desc not ready');
      return;
    }
    
    // First, move early candidates to main queue
    if (_earlyIceCandidates.isNotEmpty) {
      debugPrint('🧊 Flushing ${_earlyIceCandidates.length} early ICE candidates');
      _candidateQueue.addAll(_earlyIceCandidates);
      _earlyIceCandidates.clear();
    }
    
    final totalCandidates = _candidateQueue.length;
    debugPrint('🧊 Processing $totalCandidates queued ICE candidates');
    
    int processed = 0;
    int failed = 0;
    
    while (_candidateQueue.isNotEmpty) {
      final candidate = _candidateQueue.removeAt(0);
      try {
        await _peerConnection!.addCandidate(candidate);
        processed++;
        debugPrint('🧊 Added queued ICE candidate ($processed/$totalCandidates)');
      } catch (e) {
        failed++;
        debugPrint('❌ Error adding queued ICE candidate: $e');
      }
    }
    
    debugPrint('🧊 Queue processing complete: $processed added, $failed failed');
  }

  /// Answer an incoming call
  Future<void> answerCall({required MediaStream localStream}) async {
    if (_callState != CallState.ringing) {
      debugPrint('⚠️ Cannot answer - not ringing');
      return;
    }

    _localStream = localStream;
    onLocalStream?.call(_localStream!);

    _socketService.emit('answer_call', {
      'call_id': _callId,
    });

    _callState = CallState.connecting;
    onCallStateChanged?.call(_callState);
  }

  /// Decline an incoming call
  void declineCall() {
    if (_callId == null) return;

    _socketService.emit('decline_call', {
      'call_id': _callId,
    });

    _cleanup();
  }

  /// End the current call
  void endCall() {
    if (_callId != null) {
      _socketService.emit('end_call', {
        'call_id': _callId,
      });
    }

    _cleanup();
  }

  /// Handle call ended event
  void handleCallEnded() {
    debugPrint('📴 Call ended');
    _cleanup();
  }

  /// Handle incoming call event
  void handleIncomingCall(Map<String, dynamic> data) {
    debugPrint('📲 Incoming call: $data');
    
    _callId = data['id'] as int?;
    _callRoomId = data['call_room_id'] as String?;
    _callType = data['call_type'] as String?;
    _remoteUserId = data['caller']?['id'] as int?;
    _callDirection = CallDirection.incoming;
    _callState = CallState.ringing;
    
    onCallStateChanged?.call(_callState);
    onIncomingCall?.call(data);
  }

  /// Handle call initiated confirmation
  void handleCallInitiated(Map<String, dynamic> data) {
    debugPrint('✅ Call initiated: $data');
    _callId = data['id'] as int?;
    _callRoomId = data['call_room_id'] as String?;
  }

  /// Clean up resources
  void _cleanup() {
    _peerConnection?.close();
    _peerConnection = null;
    
    // Don't dispose local stream - let the caller manage it
    _localStream = null;
    _remoteStream = null;
    
    _callState = CallState.idle;
    _callDirection = null;
    _callId = null;
    _remoteUserId = null;
    _callRoomId = null;
    _callType = null;
    
    // Reset ICE candidate queuing state
    _remoteDescriptionSet = false;
    _earlyIceCandidates.clear();
    _candidateQueue.clear();
    
    onCallStateChanged?.call(_callState);
  }

  /// Toggle local video
  void toggleVideo(bool enabled) {
    if (_localStream != null) {
      for (var track in _localStream!.getVideoTracks()) {
        track.enabled = enabled;
      }
    }
  }

  /// Toggle local audio (mute/unmute)
  void toggleAudio(bool enabled) {
    if (_localStream != null) {
      for (var track in _localStream!.getAudioTracks()) {
        track.enabled = enabled;
      }
    }
  }

  /// Switch camera (front/back)
  Future<void> switchCamera() async {
    if (_localStream != null) {
      final videoTrack = _localStream!.getVideoTracks().firstOrNull;
      if (videoTrack != null) {
        await Helper.switchCamera(videoTrack);
      }
    }
  }
}
