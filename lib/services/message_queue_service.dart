import 'package:flutter/foundation.dart';

/// Manages a queue of messages that failed to send and retries them when connection is restored.
class MessageQueueService {
  static final MessageQueueService _instance =
      MessageQueueService._internal();
  factory MessageQueueService() => _instance;
  MessageQueueService._internal();

  final List<QueuedMessage> _queue = [];
  Function(QueuedMessage)? _onRetryCallback;

  /// Register a callback to be called when a queued message should be retried
  void setRetryCallback(Function(QueuedMessage) callback) {
    _onRetryCallback = callback;
  }

  /// Add a message to the queue
  Future<void> queueMessage({
    required int recipientId,
    required String content,
    String messageType = 'text',
    int? replyToId,
    required int optimisticMessageId,
  }) async {
    final queuedMessage = QueuedMessage(
      recipientId: recipientId,
      content: content,
      messageType: messageType,
      replyToId: replyToId,
      optimisticMessageId: optimisticMessageId,
      queuedAt: DateTime.now(),
      retryCount: 0,
    );

    debugPrint('📤 Queueing message: ${queuedMessage.recipientId}');
    _queue.add(queuedMessage);
    await _persistQueue();
  }

  /// Get all queued messages
  List<QueuedMessage> getQueuedMessages() => List.from(_queue);

  /// Remove a message from the queue
  Future<void> removeFromQueue(QueuedMessage message) async {
    _queue.removeWhere((m) =>
        m.recipientId == message.recipientId &&
        m.optimisticMessageId == message.optimisticMessageId);
    await _persistQueue();
    debugPrint('✅ Removed message from queue, remaining: ${_queue.length}');
  }

  /// Retry all queued messages
  Future<void> retryAllQueued() async {
    if (_queue.isEmpty) {
      debugPrint('📤 No queued messages to retry');
      return;
    }

    debugPrint('🔄 Retrying ${_queue.length} queued messages...');
    final queue = List.from(_queue);

    for (final message in queue) {
      // Increment retry count
      message.retryCount++;
      debugPrint(
          '📤 Retrying message: ${message.recipientId} (attempt ${message.retryCount})');

      // Call the retry callback
      if (_onRetryCallback != null) {
        try {
          await _onRetryCallback!(message);
          // If successful, it will be removed from queue by the callback
        } catch (e) {
          debugPrint('❌ Retry failed for message: $e');
          // Keep it in the queue for next retry
        }
      }

      await Future.delayed(const Duration(milliseconds: 100));
    }

    await _persistQueue();
  }

  /// Clear the entire queue
  Future<void> clearQueue() async {
    _queue.clear();
    await _persistQueue();
    debugPrint('🗑️ Queue cleared');
  }

  /// Get queue size
  int getQueueSize() => _queue.length;

  /// Persist queue to local storage
  Future<void> _persistQueue() async {
    // You can implement local storage persistence here if needed
    // For now, keeping it in-memory is sufficient because messages are sent
    // as soon as connection is restored
  }
}

/// Represents a message that failed to send and is queued for retry
class QueuedMessage {
  final int recipientId;
  final String content;
  final String messageType;
  final int? replyToId;
  final int optimisticMessageId;
  final DateTime queuedAt;
  int retryCount;

  QueuedMessage({
    required this.recipientId,
    required this.content,
    required this.messageType,
    required this.replyToId,
    required this.optimisticMessageId,
    required this.queuedAt,
    required this.retryCount,
  });
}
