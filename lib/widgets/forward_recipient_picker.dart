import 'package:flutter/material.dart';

import '../models/lobby_user.dart';
import '../services/lobby_service.dart';

/// Bottom sheet picker for selecting DM contacts to forward a message to.
class ForwardRecipientPicker extends StatefulWidget {
  final int currentUserId;
  final void Function(List<int> selectedUserIds) onConfirm;

  const ForwardRecipientPicker({
    super.key,
    required this.currentUserId,
    required this.onConfirm,
  });

  /// Shows the picker as a modal bottom sheet and returns selected user IDs.
  static Future<void> show(
    BuildContext context, {
    required int currentUserId,
    required void Function(List<int> selectedUserIds) onConfirm,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ForwardRecipientPicker(
        currentUserId: currentUserId,
        onConfirm: onConfirm,
      ),
    );
  }

  @override
  State<ForwardRecipientPicker> createState() => _ForwardRecipientPickerState();
}

class _ForwardRecipientPickerState extends State<ForwardRecipientPicker> {
  final Set<int> _selectedIds = {};
  String _searchQuery = '';
  List<LobbyUser>? _users;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    try {
      final users = await LobbyService.getLobbyUsers();
      if (mounted) {
        setState(() {
          _users = users
              .where((u) => u.id != widget.currentUserId)
              .toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load contacts';
          _isLoading = false;
        });
      }
    }
  }

  List<LobbyUser> get _filteredUsers {
    if (_users == null) return [];
    if (_searchQuery.isEmpty) return _users!;
    final q = _searchQuery.toLowerCase();
    return _users!
        .where((u) =>
            u.fullName.toLowerCase().contains(q) ||
            u.username.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Color(0xFF1a1a2e),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                const Text(
                  'Forward to...',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (_selectedIds.isNotEmpty)
                  Text(
                    '${_selectedIds.length} selected',
                    style: const TextStyle(
                      color: Color(0xFFa78bfa),
                      fontSize: 13,
                    ),
                  ),
              ],
            ),
          ),
          // Search bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              onChanged: (v) => setState(() => _searchQuery = v),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search contacts...',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.search, color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF16213e),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          // Contact list
          Expanded(
            child: _buildContent(),
          ),
          // Confirm button
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _selectedIds.isEmpty
                      ? null
                      : () {
                          Navigator.pop(context);
                          widget.onConfirm(_selectedIds.toList());
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7c3aed),
                    disabledBackgroundColor:
                        const Color(0xFF7c3aed).withValues(alpha: 0.3),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    _selectedIds.isEmpty
                        ? 'Select recipients'
                        : 'Forward to ${_selectedIds.length} recipient${_selectedIds.length > 1 ? "s" : ""}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF7c3aed)),
      );
    }

    if (_error != null) {
      return Center(
        child: Text(
          _error!,
          style: const TextStyle(color: Colors.white54),
        ),
      );
    }

    final users = _filteredUsers;
    if (users.isEmpty) {
      return const Center(
        child: Text(
          'No contacts found',
          style: TextStyle(color: Colors.white54),
        ),
      );
    }

    return ListView.builder(
      itemCount: users.length,
      itemBuilder: (context, index) {
        final user = users[index];
        final isSelected = _selectedIds.contains(user.id);

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: const Color(0xFF7c3aed),
            backgroundImage: user.avatarUrl != null
                ? NetworkImage(user.avatarUrl!)
                : null,
            child: user.avatarUrl == null
                ? Text(
                    user.initials,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                : null,
          ),
          title: Text(
            user.fullName,
            style: const TextStyle(color: Colors.white, fontSize: 15),
          ),
          subtitle: Text(
            '@${user.username}',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          trailing: Checkbox(
            value: isSelected,
            onChanged: (_) => _toggleUser(user.id),
            activeColor: const Color(0xFF7c3aed),
            checkColor: Colors.white,
          ),
          onTap: () => _toggleUser(user.id),
        );
      },
    );
  }

  void _toggleUser(int userId) {
    setState(() {
      if (_selectedIds.contains(userId)) {
        _selectedIds.remove(userId);
      } else {
        _selectedIds.add(userId);
      }
    });
  }
}
