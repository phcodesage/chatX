/// Task model for admin-created tasks
class Task {
  final int id;
  final String title;
  final String? description;
  final int? assignedToUserId;
  final String? assignedToUsername;
  final int createdByUserId;
  final String? createdByUsername;
  final bool isCompleted;
  final String createdAt;
  final String? completedAt;

  Task({
    required this.id,
    required this.title,
    this.description,
    this.assignedToUserId,
    this.assignedToUsername,
    required this.createdByUserId,
    this.createdByUsername,
    required this.isCompleted,
    required this.createdAt,
    this.completedAt,
  });

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: json['id'] as int,
      title: json['title'] as String? ?? 'Untitled Task',
      description: json['description'] as String?,
      assignedToUserId: json['assigned_to_user_id'] as int?,
      assignedToUsername: json['assigned_to_username'] as String?,
      createdByUserId: json['created_by_user_id'] as int? ?? 0,
      createdByUsername: json['created_by_username'] as String?,
      isCompleted: json['is_completed'] as bool? ?? false,
      createdAt: json['created_at'] as String? ?? DateTime.now().toIso8601String(),
      completedAt: json['completed_at'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'assigned_to_user_id': assignedToUserId,
      'assigned_to_username': assignedToUsername,
      'created_by_user_id': createdByUserId,
      'created_by_username': createdByUsername,
      'is_completed': isCompleted,
      'created_at': createdAt,
      'completed_at': completedAt,
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
