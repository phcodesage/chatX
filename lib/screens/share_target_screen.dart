import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../models/lobby_user.dart';
import '../services/message_service.dart';
import '../services/share_intent_service.dart';

class ShareTargetScreen extends StatefulWidget {
  final List<SharedMediaItem> sharedItems;
  final List<LobbyUser> users;

  const ShareTargetScreen({
    super.key,
    required this.sharedItems,
    required this.users,
  });

  @override
  State<ShareTargetScreen> createState() => _ShareTargetScreenState();
}

class _ShareTargetScreenState extends State<ShareTargetScreen> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _captionController = TextEditingController();
  final Set<int> _selectedUserIds = <int>{};

  late List<LobbyUser> _filteredUsers;
  bool _isSending = false;

  static const List<Color> _avatarColors = [
    Color(0xFFE91E63),
    Color(0xFF9C27B0),
    Color(0xFF673AB7),
    Color(0xFF3F51B5),
    Color(0xFF2196F3),
    Color(0xFF00BCD4),
    Color(0xFF009688),
    Color(0xFF4CAF50),
    Color(0xFFFF9800),
    Color(0xFFFF5722),
  ];

  @override
  void initState() {
    super.initState();
    _filteredUsers = List<LobbyUser>.from(widget.users)
      ..sort(
        (a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
      );
    _searchController.addListener(_applySearch);
  }

  @override
  void dispose() {
    _searchController.removeListener(_applySearch);
    _searchController.dispose();
    _captionController.dispose();
    super.dispose();
  }

  void _applySearch() {
    final query = _searchController.text.trim().toLowerCase();

    setState(() {
      if (query.isEmpty) {
        _filteredUsers = List<LobbyUser>.from(widget.users)
          ..sort(
            (a, b) =>
                a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
          );
        return;
      }

      _filteredUsers =
          widget.users
              .where((user) {
                return user.fullName.toLowerCase().contains(query) ||
                    user.username.toLowerCase().contains(query);
              })
              .toList(growable: false)
            ..sort(
              (a, b) =>
                  a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
            );
    });
  }

  Future<void> _sendSharedItems() async {
    if (_selectedUserIds.isEmpty || _isSending) {
      return;
    }

    final selectedUsers = widget.users
        .where((user) => _selectedUserIds.contains(user.id))
        .toList(growable: false);

    if (selectedUsers.isEmpty) {
      return;
    }

    setState(() => _isSending = true);

    final caption = _captionController.text.trim();
    int sentCount = 0;
    final failedRecipients = <String>[];

    for (final user in selectedUsers) {
      try {
        for (final item in widget.sharedItems) {
          final file = File(item.path);
          if (!await file.exists()) {
            throw Exception('Shared file is no longer available');
          }

          final multipartFile = await http.MultipartFile.fromPath(
            'file',
            file.path,
            filename: item.fileName,
            contentType: _parseMediaType(item.mimeType),
          );

          final uploadResult = await MessageService.uploadFile(
            file: multipartFile,
            recipientId: user.id,
          );

          if (uploadResult == null || uploadResult['success'] != true) {
            final error = uploadResult?['error']?.toString() ?? 'Upload failed';
            throw Exception(error);
          }
        }

        if (caption.isNotEmpty) {
          await MessageService.sendMessage(
            recipientId: user.id,
            content: caption,
          );
        }

        sentCount++;
      } catch (e) {
        failedRecipients.add(user.fullName);
      }
    }

    if (!mounted) {
      return;
    }

    setState(() => _isSending = false);

    if (sentCount > 0) {
      Navigator.pop(context, {
        'sentCount': sentCount,
        'failedCount': failedRecipients.length,
      });
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Could not send. Please try again.'),
        backgroundColor: Colors.red,
      ),
    );
  }

  MediaType _parseMediaType(String rawMimeType) {
    try {
      return MediaType.parse(rawMimeType);
    } catch (_) {
      return MediaType('application', 'octet-stream');
    }
  }

  Color _avatarColorForUser(LobbyUser user) {
    return _avatarColors[user.avatarColorIndex % _avatarColors.length];
  }

  Widget _buildPreviewCard() {
    final firstItem = widget.sharedItems.first;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF252542),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF00D9FF).withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            child: SizedBox(
              width: double.infinity,
              height: 180,
              child: firstItem.isImage
                  ? Image.file(
                      File(firstItem.path),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return const ColoredBox(
                          color: Color(0xFF1A1A2E),
                          child: Center(
                            child: Icon(
                              Icons.image_not_supported_outlined,
                              color: Colors.white54,
                              size: 44,
                            ),
                          ),
                        );
                      },
                    )
                  : const ColoredBox(
                      color: Color(0xFF1A1A2E),
                      child: Center(
                        child: Icon(
                          Icons.insert_drive_file_outlined,
                          color: Colors.white54,
                          size: 44,
                        ),
                      ),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Row(
              children: [
                const Icon(
                  Icons.share_outlined,
                  color: Color(0xFF00D9FF),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.sharedItems.length == 1
                        ? '1 item ready to send'
                        : '${widget.sharedItems.length} items ready to send',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserTile(LobbyUser user) {
    final isSelected = _selectedUserIds.contains(user.id);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: isSelected
            ? const Color(0xFF00D9FF).withValues(alpha: 0.18)
            : const Color(0xFF252542),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? const Color(0xFF00D9FF) : const Color(0xFF252542),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            setState(() {
              if (isSelected) {
                _selectedUserIds.remove(user.id);
              } else {
                _selectedUserIds.add(user.id);
              }
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: _avatarColorForUser(user),
                  child: user.avatarUrl != null
                      ? ClipOval(
                          child: Image.network(
                            user.avatarUrl!,
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Text(
                                user.initials,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              );
                            },
                          ),
                        )
                      : Text(
                          user.initials,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.fullName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '@${user.username}',
                        style: TextStyle(color: Colors.grey[400], fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(
                  isSelected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked,
                  color: isSelected
                      ? const Color(0xFF00D9FF)
                      : Colors.grey[500],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        elevation: 0,
        title: const Text(
          'Send to',
          style: TextStyle(
            color: Color(0xFF00D9FF),
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Column(
        children: [
          _buildPreviewCard(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search contacts',
                hintStyle: TextStyle(color: Colors.grey[500]),
                prefixIcon: Icon(Icons.search, color: Colors.grey[500]),
                filled: true,
                fillColor: const Color(0xFF252542),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
            ),
          ),
          Expanded(
            child: _filteredUsers.isEmpty
                ? Center(
                    child: Text(
                      'No contacts found',
                      style: TextStyle(color: Colors.grey[500], fontSize: 15),
                    ),
                  )
                : ListView.builder(
                    itemCount: _filteredUsers.length,
                    itemBuilder: (context, index) {
                      final user = _filteredUsers[index];
                      return _buildUserTile(user);
                    },
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _captionController,
                      enabled: !_isSending,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Add a caption (optional)',
                        hintStyle: TextStyle(color: Colors.grey[500]),
                        filled: true,
                        fillColor: const Color(0xFF252542),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: (_selectedUserIds.isEmpty || _isSending)
                          ? null
                          : _sendSharedItems,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00D9FF),
                        foregroundColor: const Color(0xFF10212E),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                      ),
                      child: _isSending
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              _selectedUserIds.isEmpty
                                  ? 'Send'
                                  : 'Send (${_selectedUserIds.length})',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
