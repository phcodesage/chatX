import 'package:flutter/material.dart';
import '../models/task.dart';
import '../services/message_service.dart';
import '../services/socket_service.dart';
import 'chat_screen.dart';
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
    _socketService.clearCallbacks();
    super.dispose();
  }

  void _setupSocketListeners() {
    // Listen for task added event
    _socketService.onTaskAdded = (data) {
      _loadTasks(); // Refresh on any task change
    };

    // Listen for task completed event
    _socketService.onTaskCompleted = (data) {
      _handleTaskCompleted(data);
    };

    // Listen for task uncompleted event
    _socketService.onTaskUncompleted = (data) {
      _handleTaskUncompleted(data);
    };
  }

  void _handleTaskCompleted(Map<String, dynamic> data) {
    final messageId = data['message_id'] as int?;
    if (messageId == null) return;

    setState(() {
      final index = _chatBasedTasks.indexWhere((t) => t.id == messageId);
      if (index != -1) {
        final task = _chatBasedTasks[index];
        _chatBasedTasks[index] = Task(
          id: task.id,
          title: task.title,
          description: task.description,
          assignedToUserId: task.assignedToUserId,
          assignedToUsername: task.assignedToUsername,
          createdByUserId: task.createdByUserId,
          createdByUsername: task.createdByUsername,
          isCompleted: true,
          createdAt: task.createdAt,
          completedAt: data['completed_at'] as String? ?? DateTime.now().toIso8601String(),
        );
      }
    });
  }

  void _handleTaskUncompleted(Map<String, dynamic> data) {
    final messageId = data['message_id'] as int?;
    if (messageId == null) return;

    setState(() {
      final index = _chatBasedTasks.indexWhere((t) => t.id == messageId);
      if (index != -1) {
        final task = _chatBasedTasks[index];
        _chatBasedTasks[index] = Task(
          id: task.id,
          title: task.title,
          description: task.description,
          assignedToUserId: task.assignedToUserId,
          assignedToUsername: task.assignedToUsername,
          createdByUserId: task.createdByUserId,
          createdByUsername: task.createdByUsername,
          isCompleted: false,
          createdAt: task.createdAt,
          completedAt: null,
        );
      }
    });
  }

  Future<void> _loadTasks() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Fetch admin-created tasks from API
      final taskData = await MessageService.getAllTasks();
      final tasks = taskData.map((json) => Task.fromJson(json)).toList();

      setState(() {
        _tasks = tasks;
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

  Future<void> _toggleTaskComplete(Task task) async {
    try {
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
              completedAt: !task.isCompleted ? DateTime.now().toIso8601String() : null,
            );
          }
        });
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
            Text(
              _error!,
              style: TextStyle(color: Colors.red[300]),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadTasks,
              child: const Text('Retry'),
            ),
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

    return RefreshIndicator(
      onRefresh: _loadTasks,
      color: const Color(0xFF8B5CF6),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (pendingTasks.isNotEmpty) ...[
            _buildSectionHeader('Pending', pendingTasks.length),
            const SizedBox(height: 8),
            ...pendingTasks.map((task) => _buildTaskCard(task)),
          ],
          if (completedTasks.isNotEmpty) ...[
            const SizedBox(height: 24),
            _buildSectionHeader('Completed', completedTasks.length),
            const SizedBox(height: 8),
            ...completedTasks.map((task) => _buildTaskCard(task)),
          ],
        ],
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
            _navigateToChat(task.assignedToUserId!, task.assignedToUsername ?? 'User');
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
                      color: isCompleted ? const Color(0xFF4CAF50) : Colors.grey,
                      width: 2,
                    ),
                    color: isCompleted ? const Color(0xFF4CAF50) : Colors.transparent,
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
                        decoration: isCompleted ? TextDecoration.lineThrough : null,
                        decorationColor: Colors.grey,
                      ),
                    ),
                    if (task.description != null && task.description!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        task.description!,
                        style: TextStyle(
                          color: Colors.grey[500],
                          fontSize: 14,
                          decoration: isCompleted ? TextDecoration.lineThrough : null,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          task.formattedTime,
                          style: TextStyle(color: Colors.grey[600], fontSize: 12),
                        ),
                        if (task.createdByUsername != null) ...[
                          const SizedBox(width: 16),
                          Icon(Icons.person_outline, size: 14, color: Colors.grey[600]),
                          const SizedBox(width: 4),
                          Text(
                            task.createdByUsername!,
                            style: TextStyle(color: Colors.grey[600], fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // Delete button
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
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
          MaterialPageRoute(
            builder: (context) => ChatScreen(otherUser: user!),
          ),
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
