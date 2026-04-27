import 'package:flutter/material.dart';
import '../models/task.dart';
import '../services/message_service.dart';
import '../services/socket_service.dart';
import 'chat_screen.dart' show ChatScreen;
import '../models/lobby_user.dart';
import '../services/lobby_service.dart';

/// Screen to display all tasks from admin and chat-based tasks
class TaskListScreen extends StatefulWidget {
  static const route = '/tasks';

  const TaskListScreen({super.key});

  @override
  State<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends State<TaskListScreen> {
  final SocketService _socketService = SocketService();
  List<Task> _tasks = [];
  List<Task> _chatBasedTasks = []; // Tasks from chat messages
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTasks();
    _setupSocketListeners();
  }

  @override
  void dispose() {
    _socketService.removeListenersForKey('tasks');
    super.dispose();
  }

  void _setupSocketListeners() {
    const key = 'tasks';

    // Listen for task added event
    _socketService.addListener('taskAdded', key, (Map<String, dynamic> data) {
      _handleChatTaskAdded(data);
    });

    // Listen for task completed event
    _socketService.addListener('taskCompleted', key, (
      Map<String, dynamic> data,
    ) {
      _handleTaskCompleted(data);
    });

    // Listen for task uncompleted event
    _socketService.addListener('taskUncompleted', key, (
      Map<String, dynamic> data,
    ) {
      _handleTaskUncompleted(data);
    });
  }

  void _handleTaskCompleted(Map<String, dynamic> data) {
    final messageId = _extractTaskMessageId(data);
    if (messageId == null) return;

    setState(() {
      final index = _chatBasedTasks.indexWhere((t) => t.id == messageId);
      if (index != -1) {
        final task = _chatBasedTasks[index];
        _chatBasedTasks[index] = Task(
          id: task.id,
          messageId: task.messageId,
          title: task.title,
          description: task.description,
          assignedToUserId: task.assignedToUserId,
          assignedToUsername: task.assignedToUsername,
          createdByUserId: task.createdByUserId,
          createdByUsername: task.createdByUsername,
          isCompleted: true,
          createdAt: task.createdAt,
          completedAt:
              (data['task_completed_at'] as String?) ??
              (data['completed_at'] as String?) ??
              DateTime.now().toIso8601String(),
          isChatTask: true,
          isGroupTask: task.isGroupTask,
          groupId: task.groupId,
        );
      }
    });
  }

  void _handleTaskUncompleted(Map<String, dynamic> data) {
    final messageId = _extractTaskMessageId(data);
    if (messageId == null) return;

    setState(() {
      final index = _chatBasedTasks.indexWhere((t) => t.id == messageId);
      if (index != -1) {
        final task = _chatBasedTasks[index];
        _chatBasedTasks[index] = Task(
          id: task.id,
          messageId: task.messageId,
          title: task.title,
          description: task.description,
          assignedToUserId: task.assignedToUserId,
          assignedToUsername: task.assignedToUsername,
          createdByUserId: task.createdByUserId,
          createdByUsername: task.createdByUsername,
          isCompleted: false,
          createdAt: task.createdAt,
          completedAt: null,
          isChatTask: true,
          isGroupTask: task.isGroupTask,
          groupId: task.groupId,
        );
      }
    });
  }

  void _handleChatTaskAdded(Map<String, dynamic> data) {
    final messageId = _extractTaskMessageId(data);
    if (messageId == null) return;

    // Don't add a duplicate that we already loaded from the API
    if (_chatBasedTasks.any(
      (t) => t.id == messageId || t.messageId == messageId,
    )) return;

    final payload = data['message_data'] ?? data['message'];
    final Map<String, dynamic>? msg = payload is Map
        ? Map<String, dynamic>.from(payload as Map)
        : null;

    final String title = (data['title'] as String?)?.isNotEmpty == true
        ? data['title'] as String
        : (msg?['content'] as String?)?.isNotEmpty == true
            ? msg!['content'] as String
            : 'Task #$messageId';
    final createdAt =
        (data['task_created_at'] as String?) ??
        (msg?['task_created_at'] as String?) ??
        (msg?['created_at'] as String?) ??
        DateTime.now().toIso8601String();
    final createdByUserId =
        _toInt(msg?['sender_id']) ?? _toInt(data['sender_id']) ?? 0;
    final createdByUsername =
        (data['created_by_username'] as String?) ??
        (msg?['sender_username'] as String?) ??
        (data['sender_username'] as String?);
    final assignedToUserId =
        _toInt(data['assigned_to_user_id']) ??
        _toInt(msg?['recipient_id']) ??
        _toInt(data['recipient_id']);
    final assignedToUsername =
        (data['assigned_to_username'] as String?) ??
        (msg?['recipient_username'] as String?) ??
        (data['recipient_username'] as String?);
    final bool isGroupTask = data['is_group_task'] as bool? ?? false;
    final int? groupId = _toInt(data['group_id']);

    final task = Task(
      id: messageId,
      messageId: messageId,
      title: title,
      createdByUserId: createdByUserId,
      createdByUsername: createdByUsername,
      assignedToUserId: assignedToUserId,
      assignedToUsername: assignedToUsername,
      isCompleted: false,
      createdAt: createdAt,
      isChatTask: true,
      isGroupTask: isGroupTask,
      groupId: groupId,
    );

    setState(() {
      _chatBasedTasks.add(task);
    });
  }

  Future<void> _loadTasks() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Fetch admin-created tasks and chat-based tasks in parallel
      final results = await Future.wait([
        MessageService.getAllTasks(),
        MessageService.getChatTasks(),
      ]);

      final tasks = results[0].map((json) => Task.fromJson(json)).toList();
      final chatTasks = results[1]
          .map((json) => Task.fromJson(json, isChatTask: true))
          .toList();

      setState(() {
        _tasks = tasks;
        _chatBasedTasks = chatTasks;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Failed to load tasks';
      });
      debugPrint('Error loading tasks: $e');
    }
  }

  int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  int? _extractTaskMessageId(Map<String, dynamic> data) {
    final directId =
        _toInt(data['message_id']) ??
        _toInt(data['messageId']) ??
        _toInt(data['id']);
    if (directId != null) {
      return directId;
    }

    final nestedMessage = data['message_data'] ?? data['message'];
    if (nestedMessage is Map<String, dynamic>) {
      return _toInt(nestedMessage['message_id']) ??
          _toInt(nestedMessage['messageId']) ??
          _toInt(nestedMessage['id']);
    }

    if (nestedMessage is Map) {
      final casted = Map<String, dynamic>.from(nestedMessage);
      return _toInt(casted['message_id']) ??
          _toInt(casted['messageId']) ??
          _toInt(casted['id']);
    }

    return null;
  }

  Future<void> _toggleTaskComplete(Task task) async {
    try {
      if (task.isChatTask) {
        // Chat-based tasks are toggled via socket.
        // Use the underlying message id (messageId) when available.
        final socketId = task.messageId ?? task.id;
        if (task.isCompleted) {
          _socketService.uncompleteTask(socketId);
        } else {
          _socketService.completeTask(socketId);
        }
        // Optimistically update local state; socket will confirm via event.
        setState(() {
          final index = _chatBasedTasks.indexWhere((t) => t.id == task.id);
          if (index != -1) {
            _chatBasedTasks[index] = Task(
              id: task.id,
              messageId: task.messageId,
              title: task.title,
              description: task.description,
              assignedToUserId: task.assignedToUserId,
              assignedToUsername: task.assignedToUsername,
              createdByUserId: task.createdByUserId,
              createdByUsername: task.createdByUsername,
              isCompleted: !task.isCompleted,
              createdAt: task.createdAt,
              completedAt: !task.isCompleted
                  ? DateTime.now().toIso8601String()
                  : null,
              isChatTask: true,
              isGroupTask: task.isGroupTask,
              groupId: task.groupId,
            );
          }
        });
      } else {
        final success = await MessageService.completeTask(task.id);
        if (success) {
          setState(() {
            final index = _tasks.indexWhere((t) => t.id == task.id);
            if (index != -1) {
              _tasks[index] = Task(
                id: task.id,
                title: task.title,
                description: task.description,
                assignedToUserId: task.assignedToUserId,
                assignedToUsername: task.assignedToUsername,
                createdByUserId: task.createdByUserId,
                createdByUsername: task.createdByUsername,
                isCompleted: !task.isCompleted,
                createdAt: task.createdAt,
                completedAt: !task.isCompleted
                    ? DateTime.now().toIso8601String()
                    : null,
              );
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Error toggling task: $e');
    }
  }

  Future<void> _deleteTask(Task task) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('Delete Task', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to delete "${task.title}"?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final success = await MessageService.deleteTask(task.id);
        if (success) {
          setState(() {
            _tasks.removeWhere((t) => t.id == task.id);
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Task deleted'),
                backgroundColor: Color(0xFF4CAF50),
              ),
            );
          }
        }
      } catch (e) {
        debugPrint('Error deleting task: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121218),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text(
          'Tasks',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadTasks,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF8B5CF6)),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: Colors.red[300], size: 48),
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: Colors.red[300])),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loadTasks, child: const Text('Retry')),
          ],
        ),
      );
    }

    final allTasks = [..._tasks, ..._chatBasedTasks];

    if (allTasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.task_alt, color: Colors.grey[600], size: 64),
            const SizedBox(height: 16),
            Text(
              'No tasks yet',
              style: TextStyle(color: Colors.grey[500], fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              'Tasks created by admins will appear here',
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
          ],
        ),
      );
    }

    // Separate completed and pending tasks
    final pendingTasks = allTasks.where((t) => !t.isCompleted).toList();
    final completedTasks = allTasks.where((t) => t.isCompleted).toList();

    final taskBuilders = <Widget Function()>[];
    if (pendingTasks.isNotEmpty) {
      taskBuilders.add(() => _buildSectionHeader('Pending', pendingTasks.length));
      taskBuilders.add(() => const SizedBox(height: 8));
      taskBuilders.addAll(pendingTasks.map((task) => () => _buildTaskCard(task)));
    }
    if (completedTasks.isNotEmpty) {
      taskBuilders.add(() => const SizedBox(height: 24));
      taskBuilders.add(() => _buildSectionHeader('Completed', completedTasks.length));
      taskBuilders.add(() => const SizedBox(height: 8));
      taskBuilders.addAll(completedTasks.map((task) => () => _buildTaskCard(task)));
    }

    return RefreshIndicator(
      onRefresh: _loadTasks,
      color: const Color(0xFF8B5CF6),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: taskBuilders.length,
        itemBuilder: (context, index) => taskBuilders[index](),
      ),
    );
  }

  Widget _buildSectionHeader(String title, int count) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFF8B5CF6),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            count.toString(),
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildTaskCard(Task task) {
    final isCompleted = task.isCompleted;

    return Card(
      color: const Color(0xFF1E1E2E),
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () {
          // If task has an associated conversation, navigate to chat
          if (task.assignedToUserId != null) {
            _navigateToChat(
              task.assignedToUserId!,
              task.assignedToUsername ?? 'User',
            );
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Checkbox
              InkWell(
                onTap: () => _toggleTaskComplete(task),
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isCompleted
                          ? const Color(0xFF4CAF50)
                          : Colors.grey,
                      width: 2,
                    ),
                    color: isCompleted
                        ? const Color(0xFF4CAF50)
                        : Colors.transparent,
                  ),
                  child: isCompleted
                      ? const Icon(Icons.check, size: 16, color: Colors.white)
                      : null,
                ),
              ),
              const SizedBox(width: 16),
              // Task content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        decoration: isCompleted
                            ? TextDecoration.lineThrough
                            : null,
                        decorationColor: Colors.grey,
                      ),
                    ),
                    if (task.description != null &&
                        task.description!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        task.description!,
                        style: TextStyle(
                          color: Colors.grey[500],
                          fontSize: 14,
                          decoration: isCompleted
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 14,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          task.formattedTime,
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                        if (task.createdByUsername != null) ...[
                          const SizedBox(width: 16),
                          Icon(
                            Icons.person_outline,
                            size: 14,
                            color: Colors.grey[600],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            task.createdByUsername!,
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // Delete button
              IconButton(
                icon: const Icon(
                  Icons.delete_outline,
                  color: Colors.red,
                  size: 20,
                ),
                onPressed: () => _deleteTask(task),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _navigateToChat(int userId, String username) async {
    try {
      // Get user details first
      final users = await LobbyService.getLobbyUsers();
      LobbyUser? user;

      try {
        user = users.firstWhere((u) => u.id == userId);
      } catch (e) {
        // User not found in lobby, create a minimal user object
        user = null;
      }

      if (mounted && user != null) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => ChatScreen(otherUser: user!)),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('User not found: $username'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error navigating to chat: $e');
    }
  }
}
