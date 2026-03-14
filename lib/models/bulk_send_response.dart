class BulkSentMessage {
  final int id;
  final int senderId;
  final int recipientId;
  final String content;
  final String messageType;

  const BulkSentMessage({
    required this.id,
    required this.senderId,
    required this.recipientId,
    required this.content,
    required this.messageType,
  });

  factory BulkSentMessage.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }

    return BulkSentMessage(
      id: asInt(json['id']),
      senderId: asInt(json['sender_id']),
      recipientId: asInt(json['recipient_id']),
      content: json['content']?.toString() ?? '',
      messageType: json['message_type']?.toString() ?? 'text',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sender_id': senderId,
      'recipient_id': recipientId,
      'content': content,
      'message_type': messageType,
    };
  }
}

class BulkSendRecipientResult {
  final int recipientId;
  final bool success;
  final int? messageId;
  final String? error;

  const BulkSendRecipientResult({
    required this.recipientId,
    required this.success,
    this.messageId,
    this.error,
  });

  factory BulkSendRecipientResult.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }

    bool asBool(dynamic value) {
      if (value is bool) return value;
      if (value is num) return value != 0;
      if (value is String) {
        final normalized = value.trim().toLowerCase();
        return normalized == 'true' || normalized == '1';
      }
      return false;
    }

    return BulkSendRecipientResult(
      recipientId: asInt(json['recipient_id']),
      success: asBool(json['success']),
      messageId: json['message_id'] == null ? null : asInt(json['message_id']),
      error: json['error']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'recipient_id': recipientId,
      'success': success,
      'message_id': messageId,
      'error': error,
    };
  }
}

class BulkSendResponse {
  final String message;
  final String? bulkBatchId;
  final int requestedCount;
  final int processedCount;
  final int sentCount;
  final int failedCount;
  final List<BulkSentMessage> data;
  final List<BulkSendRecipientResult> results;

  const BulkSendResponse({
    required this.message,
    required this.bulkBatchId,
    required this.requestedCount,
    required this.processedCount,
    required this.sentCount,
    required this.failedCount,
    required this.data,
    required this.results,
  });

  bool get hasFailures => failedCount > 0;

  factory BulkSendResponse.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }

    List<BulkSentMessage> parseMessages(dynamic value) {
      if (value is! List) return const <BulkSentMessage>[];
      return value
          .whereType<Map>()
          .map(
            (item) => BulkSentMessage.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList();
    }

    List<BulkSendRecipientResult> parseResults(dynamic value) {
      if (value is! List) return const <BulkSendRecipientResult>[];
      return value
          .whereType<Map>()
          .map(
            (item) => BulkSendRecipientResult.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList();
    }

    return BulkSendResponse(
      message: json['message']?.toString() ?? 'Bulk send completed',
      bulkBatchId: json['bulk_batch_id']?.toString(),
      requestedCount: asInt(json['requested_count']),
      processedCount: asInt(json['processed_count']),
      sentCount: asInt(json['sent_count']),
      failedCount: asInt(json['failed_count']),
      data: parseMessages(json['data']),
      results: parseResults(json['results']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'message': message,
      'bulk_batch_id': bulkBatchId,
      'requested_count': requestedCount,
      'processed_count': processedCount,
      'sent_count': sentCount,
      'failed_count': failedCount,
      'data': data.map((item) => item.toJson()).toList(),
      'results': results.map((item) => item.toJson()).toList(),
    };
  }
}