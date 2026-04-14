/// Task model for admin-created and chat-based tasks
class Task {
  final int id;
  /// For chat tasks this is the underlying message id (may differ from id).
  final int? messageId;
  final String title;
  final String? description;
  final int? assignedToUserId;
  final String? assignedToUsername;
  final int createdByUserId;
  final String? createdByUsername;
  final bool isCompleted;
  final String createdAt;
  final String? completedAt;
  final bool isChatTask;
  final bool isGroupTask;
  final int? groupId;

  Task({
    required this.id,
    this.messageId,
    required this.title,
    this.description,
    this.assignedToUserId,
    this.assignedToUsername,
    required this.createdByUserId,
    this.createdByUsername,
    required this.isCompleted,
    required this.createdAt,
    this.completedAt,
    this.isChatTask = false,
    this.isGroupTask = false,
    this.groupId,
  });

  factory Task.fromJson(Map<String, dynamic> json, {bool isChatTask = false}) {
    final bool isChatFlag =
        isChatTask || (json['is_chat_task'] as bool? ?? false);
    final bool isGroupFlag = json['is_group_task'] as bool? ?? false;

    // For chat tasks the backend returns `message_id` as the canonical
    // message reference and `id` as the row id (they may be the same).
    final int rowId = _parseInt(json['id']) ?? 0;
    final int? msgId = _parseInt(json['message_id']);

    // Prefer task_created_at / task_completed_at if present (chat tasks),
    // fall back to created_at / completed_at (admin tasks).
    final String createdAt =
        (json['task_created_at'] as String?)?.isNotEmpty == true
            ? json['task_created_at'] as String
            : (json['created_at'] as String? ?? DateTime.now().toIso8601String());

    final String? completedAt =
        (json['task_completed_at'] as String?)?.isNotEmpty == true
            ? json['task_completed_at'] as String
            : json['completed_at'] as String?;

    // is_completed can come from the bool field or be inferred from completedAt.
    final bool isCompleted =
        json['is_completed'] as bool? ?? completedAt != null;

    return Task(
      id: rowId,
      messageId: msgId,
      title: json['title'] as String? ?? 'Untitled Task',
      description: json['description'] as String? ?? json['content'] as String?,
      assignedToUserId: _parseInt(json['assigned_to_user_id']),
      assignedToUsername: json['assigned_to_username'] as String?,
      createdByUserId: _parseInt(json['created_by_user_id']) ?? 0,
      createdByUsername: json['created_by_username'] as String?,
      isCompleted: isCompleted,
      createdAt: createdAt,
      completedAt: completedAt,
      isChatTask: isChatFlag,
      isGroupTask: isGroupFlag,
      groupId: isGroupFlag ? _parseInt(json['group_id']) : null,
    );
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      if (messageId != null) 'message_id': messageId,
      'title': title,
      'description': description,
      'assigned_to_user_id': assignedToUserId,
      'assigned_to_username': assignedToUsername,
      'created_by_user_id': createdByUserId,
      'created_by_username': createdByUsername,
      'is_completed': isCompleted,
      'created_at': createdAt,
      'completed_at': completedAt,
      'is_chat_task': isChatTask,
      'is_group_task': isGroupTask,
      if (groupId != null) 'group_id': groupId,
    };
  }

  String get formattedTime {
    try {
      final dateTime = DateTime.parse(createdAt);
      final now = DateTime.now();
      final difference = now.difference(dateTime);

      if (difference.inDays > 0) {
        return '${difference.inDays}d ago';
      } else if (difference.inHours > 0) {
        return '${difference.inHours}h ago';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes}m ago';
      } else {
        return 'Just now';
      }
    } catch (e) {
      return '';
    }
  }
}
