import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'socket_service.dart';

/// A fire-and-forget socket event that was emitted while the socket was
/// disconnected and is persisted for replay once connectivity returns.
class _QueuedSocketEvent {
  /// The socket.io event name (e.g. `ring_doorbell`, `change_color`).
  final String event;

  /// The JSON-serializable payload.
  final Map<String, dynamic> payload;

  _QueuedSocketEvent({required this.event, required this.payload});

  Map<String, dynamic> toJson() => {'event': event, 'payload': payload};

  factory _QueuedSocketEvent.fromJson(Map<String, dynamic> json) =>
      _QueuedSocketEvent(
        event: json['event'] as String,
        payload: Map<String, dynamic>.from(json['payload'] as Map),
      );
}

/// Persists "fire-and-forget" socket events (doorbell rings, background-color
/// changes, …) that were triggered while offline, and replays them when the
/// device/socket comes back online.
///
/// [SocketService.emit] silently drops events when the socket is disconnected,
/// so without this queue an offline doorbell or color change is lost forever.
/// This mirrors [TextMessageRetryService] / [MediaUploadRetryService].
class SocketEventQueueService {
  static final SocketEventQueueService _instance =
      SocketEventQueueService._internal();
  factory SocketEventQueueService() => _instance;
  SocketEventQueueService._internal();

  final List<_QueuedSocketEvent> _queue = [];
  static late Box _box;
  bool _flushing = false;

  /// Whether there are events waiting to be replayed.
  bool get hasPending => _queue.isNotEmpty;

  /// Loads any persisted events and wires up automatic replay triggers.
  Future<void> initialize() async {
    _box = await Hive.openBox('socket_event_queue_cache');
    final data = _box.get('queue') as List?;
    if (data != null) {
      _queue.clear();
      for (final item in data) {
        if (item is Map) {
          _queue.add(
            _QueuedSocketEvent.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
      debugPrint('🔔 Loaded ${_queue.length} pending socket events from cache');
    }

    Connectivity().onConnectivityChanged.listen((results) {
      if (results.isNotEmpty && results.first != ConnectivityResult.none) {
        if (_queue.isNotEmpty) {
          debugPrint('📡 Connectivity restored, flushing socket events...');
          flush();
        }
      }
    });

    SocketService().addListener('reconnected', 'SocketEventQueueService', () {
      if (_queue.isNotEmpty) {
        debugPrint('🔌 Socket reconnected, flushing socket events...');
        flush();
      }
    });

    if (_queue.isNotEmpty) flush();
  }

  Future<void> _persist() async {
    await _box.put('queue', _queue.map((e) => e.toJson()).toList());
  }

  /// Queues [event]/[payload] for replay when the socket reconnects.
  Future<void> queueEvent(String event, Map<String, dynamic> payload) async {
    _queue.add(_QueuedSocketEvent(event: event, payload: payload));
    await _persist();
    debugPrint(
      '🔔 Queued offline socket event "$event" (size: ${_queue.length})',
    );
  }

  /// Replays all queued events in order if the socket is connected.
  Future<void> flush() async {
    if (_queue.isEmpty || _flushing) return;

    final socket = SocketService();
    // Give a freshly-restored connection a moment to finish its handshake.
    if (!socket.isConnected) {
      for (int i = 0; i < 10 && !socket.isConnected; i++) {
        await Future.delayed(const Duration(milliseconds: 200));
      }
    }
    if (!socket.isConnected) {
      debugPrint('🔔 Socket still disconnected, keeping events queued');
      return;
    }

    _flushing = true;
    try {
      // Remove-before-send: emit is fire-and-forget, so draining the queue as we
      // go avoids re-sending the same event on the next trigger.
      while (_queue.isNotEmpty && socket.isConnected) {
        final item = _queue.removeAt(0);
        await _persist();
        socket.emit(item.event, item.payload);
        debugPrint('🔔 Replayed offline socket event "${item.event}"');
        await Future.delayed(const Duration(milliseconds: 60));
      }
    } finally {
      _flushing = false;
    }
  }
}
