import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/group.dart';
import '../services/group_service.dart';
import '../services/socket_service.dart';
import '../services/storage_service.dart';
import '../widgets/reaction_picker.dart';

/// Group chat screen for messaging in a group
class GroupChatScreen extends StatefulWidget {
  final Group group;

  const GroupChatScreen({super.key, required this.group});

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final SocketService _socketService = SocketService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final FocusNode _inputFocusNode = FocusNode();

  List<GroupMessage> _messages = [];
  bool _isLoading = true;
  bool _isLoadingMessages = false;
  int? _currentUserId;

  // Scroll to bottom button state
  bool _isAtBottom = true;

  // Reply state
  GroupMessage? _replyingToMessage;

  // Reaction state
  final Map<int, Map<String, Set<String>>> _messageReactions = {};

  // Action buttons state
  bool _showActionButtons = false;

  // Emoji picker state for chat input
  bool _showEmojiPicker = false;
  int _emojiCategoryIndex = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _initialize();
  }

  Future<void> _initialize() async {
    _currentUserId = await StorageService.getUserId();
    await _loadMessages();
    _setupRealtimeListeners();
    _socketService.joinGroupChat(widget.group.id);
  }

  void _setupRealtimeListeners() {
    final key = 'group_chat_${widget.group.id}';

    // New message from another member
    _socketService.addListener('group_new_message', key, (data) {
      if (data['group_id'] == widget.group.id) {
        _handleNewMessage(data);
      }
    });

    // Message sent confirmation
    _socketService.addListener('group_message_sent', key, (data) {
      if (data['group_id'] == widget.group.id) {
        _handleMessageSent(data);
      }
    });

    // File message (also comes through group_new_message)
    _socketService.addListener('group_file_message', key, (data) {
      if (data['group_id'] == widget.group.id) {
        _handleNewMessage(data);
      }
    });

    // Message deleted
    _socketService.addListener('group_message_deleted', key, (data) {
      if (data['group_id'] == widget.group.id) {
        _handleMessageDeleted(data);
      }
    });

    // Message edited
    _socketService.addListener('group_message_edited', key, (data) {
      if (data['group_id'] == widget.group.id) {
        _handleMessageEdited(data);
      }
    });

    // Reaction updated
    _socketService.addListener('group_reaction_updated', key, (data) {
      if (data['group_id'] == widget.group.id) {
        _handleReactionUpdated(data);
      }
    });

    // Reaction cleared
    _socketService.addListener('group_reaction_cleared', key, (data) {
      if (data['group_id'] == widget.group.id) {
        _handleReactionCleared(data);
      }
    });
  }

  Future<void> _loadMessages() async {
    if (_isLoadingMessages) return;
    setState(() {
      _isLoadingMessages = true;
      _isLoading = true;
    });

    try {
      final messages = await GroupService.getMessages(
        groupId: widget.group.id,
        limit: 50,
      );

      if (mounted) {
        setState(() {
          _messages = messages.reversed.toList();
          _isLoading = false;
          _isLoadingMessages = false;
        });

        // Mark messages as viewed
        _markMessagesAsViewed();

        // Scroll to bottom
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(
              _scrollController.position.maxScrollExtent,
            );
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading group messages: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingMessages = false;
        });
      }
    }
  }

  void _handleNewMessage(Map<String, dynamic> data) {
    final message = GroupMessage.fromJson(data);

    if (mounted) {
      setState(() {
        _messages.add(message);
      });

      // Play notification sound if not from current user
      if (message.senderId != _currentUserId) {
        _playNotificationSound();
      }

      // Mark as viewed if at bottom
      if (_isAtBottom) {
        _markMessagesAsViewed();
      }

      // Scroll to bottom
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients && _isAtBottom) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  void _handleMessageSent(Map<String, dynamic> data) {
    // Message sent confirmation - update optimistic message
    final messageId = data['message_id'] as int?;
    if (messageId == null) return;

    if (mounted) {
      setState(() {
        // Find and update the message
        final index = _messages.indexWhere((m) => m.id == messageId);
        if (index != -1) {
          _messages[index] = GroupMessage.fromJson(data);
        }
      });
    }
  }

  void _handleMessageDeleted(Map<String, dynamic> data) {
    final messageId = data['message_id'] as int?;
    if (messageId == null) return;

    if (mounted) {
      setState(() {
        _messages.removeWhere((m) => m.id == messageId);
      });
    }
  }

  void _handleMessageEdited(Map<String, dynamic> data) {
    final messageId = data['message_id'] as int?;
    final newContent = data['content'] as String?;
    if (messageId == null || newContent == null) return;

    if (mounted) {
      setState(() {
        final index = _messages.indexWhere((m) => m.id == messageId);
        if (index != -1) {
          _messages[index] = GroupMessage.fromJson({
            ..._messages[index].toJson(),
            'content': newContent,
          });
        }
      });
    }
  }

  void _handleReactionUpdated(Map<String, dynamic> data) {
    final messageId = data['message_id'] as int?;
    final reactions = data['reactions'] as Map<String, dynamic>?;
    if (messageId == null || reactions == null) return;

    if (mounted) {
      setState(() {
        final index = _messages.indexWhere((m) => m.id == messageId);
        if (index != -1) {
          _messages[index] = GroupMessage.fromJson({
            ..._messages[index].toJson(),
            'reactions': reactions,
          });
        }
      });
    }
  }

  void _handleReactionCleared(Map<String, dynamic> data) {
    _handleReactionUpdated(data);
  }

  void _markMessagesAsViewed() {
    if (_messages.isEmpty || _currentUserId == null) return;

    // Get unread messages from others
    final unreadMessages = _messages
        .where((m) => m.senderId != _currentUserId)
        .map((m) => m.id)
        .toList();

    if (unreadMessages.isEmpty) return;

    // Group by sender
    final bySender = <int, List<int>>{};
    for (final msg in _messages.where((m) => m.senderId != _currentUserId)) {
      bySender.putIfAbsent(msg.senderId, () => []).add(msg.id);
    }

    // Mark as viewed for each sender
    for (final entry in bySender.entries) {
      GroupService.markMessagesViewed(
        groupId: widget.group.id,
        messageIds: entry.value,
        senderId: entry.key,
      );
    }
  }

  Future<void> _playNotificationSound() async {
    try {
      await _audioPlayer.play(AssetSource('sounds/notif-sound.wav'));
    } catch (e) {
      debugPrint('Error playing notification sound: $e');
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final isAtBottom =
        _scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 100;

    if (isAtBottom != _isAtBottom) {
      setState(() => _isAtBottom = isAtBottom);

      if (isAtBottom) {
        _markMessagesAsViewed();
      }
    }
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;

    _messageController.clear();

    try {
      final message = await GroupService.sendMessage(
        groupId: widget.group.id,
        content: content,
        replyToId: _replyingToMessage?.id,
      );

      if (mounted) {
        setState(() {
          _messages.add(message);
          _replyingToMessage = null;
        });

        // Scroll to bottom
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      }
    } catch (e) {
      debugPrint('Error sending message: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send message: $e')));
      }
    }
  }

  Future<void> _pickAndSendImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);

    if (image == null) return;

    await _uploadFile(File(image.path));
  }

  Future<void> _pickAndSendFile() async {
    final result = await FilePicker.platform.pickFiles();

    if (result == null || result.files.isEmpty) return;

    final file = File(result.files.first.path!);
    await _uploadFile(file);
  }

  Future<void> _uploadFile(File file) async {
    try {
      final message = await GroupService.uploadFile(
        groupId: widget.group.id,
        file: file,
      );

      if (mounted) {
        setState(() {
          _messages.add(message);
        });

        // Scroll to bottom
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      }
    } catch (e) {
      debugPrint('Error uploading file: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to upload file: $e')));
      }
    }
  }

  Future<void> _deleteMessage(GroupMessage message) async {
    try {
      await GroupService.deleteMessage(
        groupId: widget.group.id,
        messageId: message.id,
      );

      if (mounted) {
        setState(() {
          _messages.removeWhere((m) => m.id == message.id);
        });
      }
    } catch (e) {
      debugPrint('Error deleting message: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to delete message: $e')));
      }
    }
  }

  Future<void> _addReaction(GroupMessage message, String emoji) async {
    try {
      final reactions = await GroupService.addReaction(
        groupId: widget.group.id,
        messageId: message.id,
        emoji: emoji,
      );

      if (mounted) {
        setState(() {
          final index = _messages.indexWhere((m) => m.id == message.id);
          if (index != -1) {
            _messages[index] = GroupMessage.fromJson({
              ..._messages[index].toJson(),
              'reactions': reactions,
            });
          }
        });
      }
    } catch (e) {
      debugPrint('Error adding reaction: $e');
    }
  }

  @override
  void dispose() {
    _socketService.removeListenersForKey('group_chat_${widget.group.id}');
    _socketService.leaveGroupChat(widget.group.id);
    _messageController.dispose();
    _scrollController.dispose();
    _audioPlayer.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: _buildAppBar(),
      body: Column(
        children: [
          // Messages list
          Expanded(
            child: _isLoading
                ? _buildLoadingShimmer()
                : _messages.isEmpty
                ? const Center(
                    child: Text(
                      'No messages yet\nBe the first to send a message!',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      return _buildMessageBubble(_messages[index]);
                    },
                  ),
          ),

          // Reply preview
          if (_replyingToMessage != null) _buildReplyPreview(),

          // Input area
          _buildInputArea(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF4C1D95),
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () => Navigator.pop(context),
      ),
      title: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: const Color(0xFF00D9FF),
            child: widget.group.avatarUrl != null
                ? ClipOval(
                    child: Image.network(
                      widget.group.avatarUrl!,
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.group,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  )
                : const Icon(Icons.group, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.group.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${widget.group.memberCount} members',
                  style: TextStyle(color: Colors.grey[300], fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        // Doorbell button
        IconButton(
          icon: const Icon(Icons.notifications, color: Colors.white),
          onPressed: () async {
            try {
              await GroupService.ringDoorbell(widget.group.id);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('🔔 Doorbell sent to all members'),
                    backgroundColor: Color(0xFF4C1D95),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Failed to ring doorbell: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            }
          },
          tooltip: 'Ring Doorbell',
        ),
        // More options menu
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: Colors.white),
          color: const Color(0xFF1E1E2E),
          onSelected: (value) {
            if (value == 'members') {
              // TODO: Show members list
            } else if (value == 'settings') {
              // TODO: Show group settings
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'members',
              child: Row(
                children: [
                  Icon(Icons.people, color: Colors.white, size: 20),
                  SizedBox(width: 12),
                  Text('Members', style: TextStyle(color: Colors.white)),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'settings',
              child: Row(
                children: [
                  Icon(Icons.settings, color: Colors.white, size: 20),
                  SizedBox(width: 12),
                  Text('Group Settings', style: TextStyle(color: Colors.white)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLoadingShimmer() {
    return ListView.builder(
      itemCount: 10,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: index % 2 == 0
                ? MainAxisAlignment.start
                : MainAxisAlignment.end,
            children: [
              Container(
                width: 200,
                height: 60,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMessageBubble(GroupMessage message) {
    final isSentByMe = message.senderId == _currentUserId;
    final bool isImage =
        message.messageType == 'image' ||
        (message.fileType?.startsWith('image/') ?? false);
    final bool isVideo =
        message.messageType == 'video' ||
        (message.fileType?.startsWith('video/') ?? false);
    final bool isAudio =
        message.messageType == 'voice' ||
        message.messageType == 'audio' ||
        (message.fileType?.startsWith('audio/') ?? false);
    final bool isMedia = isImage || isVideo;

    // Check if this message has reactions to adjust bottom margin
    final hasReactions = message.reactions.isNotEmpty;

    // Build the main bubble widget
    final bubbleWidget = Container(
      margin: EdgeInsets.only(bottom: hasReactions ? 2 : 12),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.70,
      ),
      decoration: BoxDecoration(
        color: isSentByMe ? const Color(0xFF420796) : const Color(0xFF3944BC),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(isSentByMe ? 16 : 4),
          bottomRight: Radius.circular(isSentByMe ? 4 : 16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Quoted reply (if this is a reply to another message)
          if (message.replyToId != null || message.replyPreview != null)
            Opacity(
              opacity: 0.85,
              child: Container(
                margin: const EdgeInsets.only(left: 8, right: 8, top: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(38),
                  borderRadius: BorderRadius.circular(6),
                  border: const Border(
                    left: BorderSide(color: Color(0xFFB794F6), width: 3),
                  ),
                ),
                child: Builder(
                  builder: (context) {
                    // Parse reply preview
                    final preview = message.replyPreview ?? '';
                    final colonIndex = preview.indexOf(':');
                    final senderName = colonIndex > 0
                        ? preview.substring(0, colonIndex)
                        : 'Reply';
                    var contentText = colonIndex > 0
                        ? preview.substring(colonIndex + 1).trim()
                        : preview;

                    // Improve display for file messages
                    if (contentText.contains('<audio') ||
                        contentText.contains('audio/')) {
                      contentText = '🎤 Voice message';
                    } else if (contentText.contains('<img') ||
                        contentText.contains('image/')) {
                      contentText = '📷 Photo';
                    } else if (contentText.contains('<video') ||
                        contentText.contains('video/')) {
                      contentText = '🎬 Video';
                    } else if (contentText.contains('file/') ||
                        contentText.endsWith('.pdf') ||
                        contentText.endsWith('.doc')) {
                      contentText = '📎 File';
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          senderName,
                          style: TextStyle(
                            color: Colors.white.withAlpha(230),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          contentText,
                          style: TextStyle(
                            color: Colors.white.withAlpha(179),
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          // Image/Video content
          if (isMedia && message.fileUrl != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(
                  message.content.isNotEmpty &&
                          !_isOnlyFilename(message.content)
                      ? 0
                      : (isSentByMe ? 16 : 4),
                ),
                bottomRight: Radius.circular(
                  message.content.isNotEmpty &&
                          !_isOnlyFilename(message.content)
                      ? 0
                      : (isSentByMe ? 4 : 16),
                ),
              ),
              child: GestureDetector(
                onTap: () => _openMediaViewer(message),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (isImage)
                      Image.network(
                        message.fileUrl!,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Container(
                            height: 150,
                            color: Colors.grey[800],
                            child: Center(
                              child: CircularProgressIndicator(
                                value:
                                    loadingProgress.expectedTotalBytes != null
                                    ? loadingProgress.cumulativeBytesLoaded /
                                          loadingProgress.expectedTotalBytes!
                                    : null,
                                color: Colors.white,
                              ),
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            height: 100,
                            color: Colors.grey[800],
                            child: const Center(
                              child: Icon(
                                Icons.broken_image,
                                color: Colors.white54,
                                size: 40,
                              ),
                            ),
                          );
                        },
                      )
                    else if (isVideo)
                      Container(
                        height: 150,
                        color: Colors.black87,
                        child: const Center(
                          child: Icon(
                            Icons.play_circle_fill,
                            color: Colors.white,
                            size: 60,
                          ),
                        ),
                      ),
                    // Play button overlay for video
                    if (isVideo)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: const BoxDecoration(
                          color: Colors.black45,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.play_arrow,
                          color: Colors.white,
                          size: 36,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
          // Audio/Voice message content
          if (isAudio && message.fileUrl != null) ...[
            _buildAudioPlayer(message.fileUrl!),
          ],
          // Text content (if not just filename and not audio)
          if ((!isMedia && !isAudio) ||
              (message.content.isNotEmpty &&
                  !_isOnlyFilename(message.content) &&
                  !isAudio))
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                isMedia
                    ? (message.fileName ?? message.content)
                    : message.content,
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
            )
          else if (isMedia || isAudio)
            const SizedBox(height: 8),
          // Message status indicator and timestamp for sent messages
          if (isSentByMe)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Timestamp
                  Text(
                    message.formattedTime,
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                  const SizedBox(width: 4),
                  // Status indicator (simplified for groups)
                  const Icon(Icons.done_all, size: 16, color: Colors.white70),
                ],
              ),
            ),
        ],
      ),
    );

    // Wrap bubble with Column for reactions below
    return Align(
      alignment: isSentByMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isSentByMe
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Show sender name for group messages (except own messages)
          if (!isSentByMe && message.sender != null)
            Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 4),
              child: Text(
                message.sender!.fullName,
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          // The bubble
          bubbleWidget,
          // Reaction pills below bubble
          if (hasReactions)
            Padding(
              padding: EdgeInsets.only(
                left: isSentByMe ? 0 : 8,
                right: isSentByMe ? 8 : 0,
                top: 0,
                bottom: 6,
              ),
              child: Wrap(
                spacing: 4,
                children: message.reactions.entries.map((entry) {
                  final emoji = entry.key;
                  final users = entry.value as List;
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF420796),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      '$emoji ${users.length}',
                      style: const TextStyle(fontSize: 12, color: Colors.white),
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  /// Check if content is just a filename (for media messages)
  bool _isOnlyFilename(String content) {
    if (content.isEmpty) return true;
    // Check if it looks like a filename with extension
    final filenamePattern = RegExp(r'^[\w\-\.\s]+\.\w{2,5}$');
    return filenamePattern.hasMatch(content.trim());
  }

  /// Open full screen media viewer
  void _openMediaViewer(GroupMessage message) {
    if (message.fileUrl == null) return;

    final isVideo =
        message.messageType == 'video' ||
        (message.fileType?.startsWith('video/') ?? false);

    if (isVideo) {
      // For video, show a snackbar
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Video: ${message.fileName ?? "Video"}'),
          action: SnackBarAction(
            label: 'Open',
            onPressed: () {
              // Could use url_launcher to open video URL
            },
          ),
        ),
      );
    } else {
      // Show image in full screen dialog
      showDialog(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.zero,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Dark background
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(color: Colors.black87),
              ),
              // Image
              Center(
                child: InteractiveViewer(
                  child: Image.network(message.fileUrl!, fit: BoxFit.contain),
                ),
              ),
              // Close button
              Positioned(
                top: 40,
                right: 16,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 30),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  /// Build audio player widget
  Widget _buildAudioPlayer(String audioUrl) {
    return _AudioMessagePlayer(audioUrl: audioUrl);
  }

  Widget _buildReplyPreview() {
    return Container(
      padding: const EdgeInsets.all(12),
      color: const Color(0xFF1E293B),
      child: Row(
        children: [
          Container(width: 4, height: 40, color: const Color(0xFF8B5CF6)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _replyingToMessage!.sender?.firstName ?? 'Someone',
                  style: const TextStyle(
                    color: Color(0xFF8B5CF6),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _replyingToMessage!.content,
                  style: const TextStyle(color: Colors.grey, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.grey),
            onPressed: () {
              setState(() {
                _replyingToMessage = null;
              });
            },
          ),
        ],
      ),
    );
  }

  // Emoji categories with icons and data
  static const List<Map<String, dynamic>> _emojiCategories = [
    {
      'icon': '😀',
      'label': 'Smileys',
      'emojis': [
        '😀',
        '😃',
        '😄',
        '😁',
        '😆',
        '😅',
        '😂',
        '🤣',
        '🥲',
        '😊',
        '😇',
        '🙂',
        '🙃',
        '😉',
        '😌',
        '😍',
        '🥰',
        '😘',
        '😗',
        '😙',
        '😚',
        '😋',
        '😛',
        '😝',
        '😜',
        '🤪',
        '🤨',
        '🧐',
        '🤓',
        '😎',
        '🥸',
        '🤩',
        '🥳',
        '😏',
        '😒',
        '😞',
        '😔',
        '😟',
        '😕',
        '🙁',
        '😣',
        '😖',
        '😫',
        '😩',
        '🥺',
        '😢',
        '😭',
        '😤',
        '😠',
        '😡',
        '🤬',
        '🤯',
        '😳',
        '🥵',
        '🥶',
        '😱',
        '😨',
        '😰',
        '😥',
        '😓',
        '🤗',
        '🤔',
        '🫣',
        '🤭',
        '🫢',
        '🫡',
        '🤫',
        '🫠',
        '🤥',
        '😶',
        '😐',
        '😑',
        '😬',
        '🫨',
        '🙄',
        '😯',
        '😦',
        '😧',
        '😮',
        '😲',
        '🥱',
        '😴',
        '🤤',
        '😪',
        '😵',
        '😵‍💫',
        '🫥',
        '🤐',
        '🥴',
        '🤢',
        '🤮',
        '🤧',
        '😷',
        '🤒',
        '🤕',
        '🤑',
        '🤠',
        '😈',
        '👿',
        '👹',
        '👺',
        '🤡',
        '💩',
        '👻',
        '💀',
        '☠️',
        '👽',
        '👾',
        '🤖',
        '🎃',
        '😺',
        '😸',
        '😹',
        '😻',
        '😼',
        '😽',
        '🙀',
        '😿',
        '😾',
      ],
    },
    {
      'icon': '👋',
      'label': 'Gestures',
      'emojis': [
        '👋',
        '🤚',
        '🖐️',
        '✋',
        '🖖',
        '🫱',
        '🫲',
        '🫳',
        '🫴',
        '👌',
        '🤌',
        '🤏',
        '✌️',
        '🤞',
        '🫰',
        '🤟',
        '🤘',
        '🤙',
        '👈',
        '👉',
        '👆',
        '🖕',
        '👇',
        '☝️',
        '🫵',
        '👍',
        '👎',
        '✊',
        '👊',
        '🤛',
        '🤜',
        '👏',
        '🙌',
        '🫶',
        '👐',
        '🤲',
        '🤝',
        '🙏',
        '✍️',
        '💅',
        '🤳',
        '💪',
        '🦾',
        '🦿',
        '🦵',
        '🦶',
        '👂',
        '🦻',
        '👃',
        '🧠',
        '🫀',
        '🫁',
        '🦷',
        '🦴',
        '👀',
        '👁️',
        '👅',
        '👄',
        '🫦',
        '💋',
      ],
    },
    {
      'icon': '❤️',
      'label': 'Hearts',
      'emojis': [
        '❤️',
        '🧡',
        '💛',
        '💚',
        '💙',
        '💜',
        '🖤',
        '🤍',
        '🤎',
        '❤️‍🔥',
        '❤️‍🩹',
        '💔',
        '❣️',
        '💕',
        '💞',
        '💓',
        '💗',
        '💖',
        '💘',
        '💝',
        '💟',
        '♥️',
        '🩷',
        '🩵',
        '🩶',
        '💌',
        '💐',
        '🌹',
        '🥀',
        '🌺',
        '🌸',
        '🌷',
        '🌻',
        '💑',
        '👩‍❤️‍👨',
        '👨‍❤️‍👨',
        '👩‍❤️‍👩',
        '💏',
        '😍',
        '🥰',
        '😘',
        '😻',
        '💒',
        '🏩',
      ],
    },
    {
      'icon': '🐱',
      'label': 'Animals',
      'emojis': [
        '🐶',
        '🐱',
        '🐭',
        '🐹',
        '🐰',
        '🦊',
        '🐻',
        '🐼',
        '🐻‍❄️',
        '🐨',
        '🐯',
        '🦁',
        '🐮',
        '🐷',
        '🐸',
        '🐵',
        '🙈',
        '🙉',
        '🙊',
        '🐒',
        '🐔',
        '🐧',
        '🐦',
        '🐤',
        '🐣',
        '🐥',
        '🦆',
        '🦅',
        '🦉',
        '🦇',
        '🐺',
        '🐗',
        '🐴',
        '🦄',
        '🐝',
        '🪱',
        '🐛',
        '🦋',
        '🐌',
        '🐞',
        '🐜',
        '🪰',
        '🪲',
        '🪳',
        '🦟',
        '🦗',
        '🕷️',
        '🦂',
        '🐢',
        '🐍',
        '🦎',
        '🦖',
        '🦕',
        '🐙',
        '🦑',
        '🦐',
        '🦞',
        '🦀',
        '🐡',
        '🐠',
        '🐟',
        '🐬',
        '🐳',
        '🐋',
        '🦈',
        '🦭',
        '🐊',
        '🐅',
        '🐆',
        '🦓',
        '🦍',
        '🦧',
        '🐘',
        '🦛',
        '🦏',
        '🐪',
        '🐫',
        '🦒',
        '🦘',
        '🦬',
      ],
    },
    {
      'icon': '🍕',
      'label': 'Food',
      'emojis': [
        '🍏',
        '🍎',
        '🍐',
        '🍊',
        '🍋',
        '🍌',
        '🍉',
        '🍇',
        '🍓',
        '🫐',
        '🍈',
        '🍒',
        '🍑',
        '🥭',
        '🍍',
        '🥥',
        '🥝',
        '🍅',
        '🍆',
        '🥑',
        '🥦',
        '🥬',
        '🥒',
        '🌶️',
        '🫑',
        '🌽',
        '🥕',
        '🫒',
        '🧄',
        '🧅',
        '🥔',
        '🍠',
        '🥐',
        '🥯',
        '🍞',
        '🥖',
        '🥨',
        '🧀',
        '🥚',
        '🍳',
        '🧈',
        '🥞',
        '🧇',
        '🥓',
        '🥩',
        '🍗',
        '🍖',
        '🌭',
        '🍔',
        '🍟',
        '🍕',
        '🫓',
        '🥪',
        '🥙',
        '🧆',
        '🌮',
        '🌯',
        '🫔',
        '🥗',
        '🥘',
        '🫕',
        '🍝',
        '🍜',
        '🍲',
        '🍛',
        '🍣',
        '🍱',
        '🥟',
        '🦪',
        '🍤',
        '🍙',
        '🍚',
        '🍘',
        '🍥',
        '🥠',
        '🥮',
        '🍢',
        '🍡',
        '🍧',
        '🍨',
        '🍦',
        '🥧',
        '🧁',
        '🍰',
        '🎂',
        '🍮',
        '🍭',
        '🍬',
        '🍫',
        '🍩',
        '🍪',
        '🌰',
        '🥜',
        '🍯',
        '🥛',
        '🍼',
        '☕',
        '🍵',
        '🧃',
        '🥤',
        '🧋',
        '🍶',
        '🍺',
        '🍻',
        '🥂',
        '🍷',
        '🥃',
        '🍸',
        '🍹',
        '🧉',
      ],
    },
    {
      'icon': '⚽',
      'label': 'Activities',
      'emojis': [
        '⚽',
        '🏀',
        '🏈',
        '⚾',
        '🥎',
        '🎾',
        '🏐',
        '🏉',
        '🥏',
        '🎱',
        '🪀',
        '🏓',
        '🏸',
        '🏒',
        '🏑',
        '🥍',
        '🏏',
        '🪃',
        '🥅',
        '⛳',
        '🪁',
        '🏹',
        '🎣',
        '🤿',
        '🥊',
        '🥋',
        '🎽',
        '🛹',
        '🛼',
        '🛷',
        '⛸️',
        '🥌',
        '🎿',
        '⛷️',
        '🏂',
        '🪂',
        '🏋️',
        '🤼',
        '🤸',
        '🤺',
        '⛹️',
        '🤾',
        '🏌️',
        '🏇',
        '🧘',
        '🏄',
        '🏊',
        '🤽',
        '🚣',
        '🧗',
        '🚵',
        '🚴',
        '🏆',
        '🥇',
        '🥈',
        '🥉',
        '🏅',
        '🎖️',
        '🏵️',
        '🎗️',
        '🎪',
        '🤹',
        '🎭',
        '🩰',
        '🎨',
        '🎬',
        '🎤',
        '🎧',
        '🎼',
        '🎹',
        '🥁',
        '🪘',
        '🎷',
        '🎺',
        '🪗',
        '🎸',
        '🪕',
        '🎻',
        '🎲',
        '♟️',
        '🎯',
        '🎳',
        '🎮',
        '🕹️',
        '🧩',
      ],
    },
    {
      'icon': '🚗',
      'label': 'Travel',
      'emojis': [
        '🚗',
        '🚕',
        '🚙',
        '🚌',
        '🚎',
        '🏎️',
        '🚓',
        '🚑',
        '🚒',
        '🚐',
        '🛻',
        '🚚',
        '🚛',
        '🚜',
        '🏍️',
        '🛵',
        '🚲',
        '🛴',
        '🛺',
        '🚔',
        '🚍',
        '🚘',
        '🚖',
        '🛞',
        '🚡',
        '🚠',
        '🚟',
        '🚃',
        '🚋',
        '🚞',
        '🚝',
        '🚄',
        '🚅',
        '🚈',
        '🚂',
        '🚆',
        '🚇',
        '🚊',
        '🚉',
        '✈️',
        '🛫',
        '🛬',
        '🛩️',
        '💺',
        '🛰️',
        '🚀',
        '🛸',
        '🚁',
        '🛶',
        '⛵',
        '🚤',
        '🛥️',
        '🛳️',
        '⛴️',
        '🚢',
        '🗼',
        '🏰',
        '🏯',
        '🏟️',
        '🎡',
        '🎢',
        '🎠',
        '⛲',
        '⛱️',
        '🏖️',
        '🏝️',
        '🏜️',
        '🌋',
        '⛰️',
        '🏔️',
        '🗻',
        '🏕️',
        '🛖',
        '🏠',
        '🏡',
        '🏢',
        '🏬',
        '🏣',
        '🏤',
        '🏥',
      ],
    },
    {
      'icon': '💡',
      'label': 'Objects',
      'emojis': [
        '🔥',
        '💧',
        '🌟',
        '⭐',
        '✨',
        '💫',
        '🌈',
        '☀️',
        '🌤️',
        '⛅',
        '🎉',
        '🎊',
        '🎈',
        '🎁',
        '🎀',
        '🎄',
        '🪅',
        '🎆',
        '🎇',
        '🧨',
        '💡',
        '🔦',
        '🕯️',
        '🪔',
        '💎',
        '🔮',
        '🧿',
        '🪬',
        '💰',
        '💴',
        '💵',
        '💶',
        '💷',
        '🪙',
        '💳',
        '💸',
        '🧲',
        '🔧',
        '🪛',
        '🔩',
        '⚙️',
        '🧰',
        '🪜',
        '🧱',
        '🪨',
        '🪵',
        '🔗',
        '🧬',
        '🔬',
        '🔭',
        '📡',
        '💉',
        '🩸',
        '💊',
        '🩹',
        '🩼',
        '🩺',
        '🩻',
        '🚪',
        '🛗',
        '🪞',
        '🪟',
        '🛏️',
        '🛋️',
        '🪑',
        '🚽',
        '🪠',
        '🚿',
        '🛁',
        '🪤',
        '📱',
        '💻',
        '⌨️',
        '🖥️',
        '🖨️',
        '🖱️',
        '💾',
        '💿',
        '📀',
        '📷',
        '📸',
        '📹',
        '🎥',
        '📽️',
        '🎞️',
        '📞',
        '☎️',
        '📟',
        '📠',
        '📺',
        '📻',
        '🎙️',
        '🎚️',
        '🎛️',
        '🧭',
        '⏱️',
        '⏲️',
        '⏰',
        '🕰️',
        '📡',
      ],
    },
    {
      'icon': '🏁',
      'label': 'Symbols',
      'emojis': [
        '🏳️',
        '🏴',
        '🏁',
        '🚩',
        '🏳️‍🌈',
        '🏳️‍⚧️',
        '🏴‍☠️',
        '✅',
        '❌',
        '❓',
        '❗',
        '‼️',
        '⁉️',
        '💯',
        '🔴',
        '🟠',
        '🟡',
        '🟢',
        '🔵',
        '🟣',
        '⚫',
        '⚪',
        '🟤',
        '🔶',
        '🔷',
        '🔸',
        '🔹',
        '🔺',
        '🔻',
        '💠',
        '🔘',
        '🔳',
        '🔲',
        '▪️',
        '▫️',
        '◾',
        '◽',
        '◼️',
        '◻️',
        '🟥',
        '🟧',
        '🟨',
        '🟩',
        '🟦',
        '🟪',
        '⬛',
        '⬜',
        '🟫',
        '♈',
        '♉',
        '♊',
        '♋',
        '♌',
        '♍',
        '♎',
        '♏',
        '♐',
        '♑',
        '♒',
        '♓',
        '⛎',
        '🔀',
        '🔁',
        '🔂',
        '▶️',
        '⏩',
        '⏭️',
        '⏯️',
        '◀️',
        '⏪',
        '⏮️',
        '🔼',
        '⏫',
        '🔽',
        '⏬',
        '⏸️',
        '⏹️',
        '⏺️',
        '⏏️',
        '🎦',
        '♾️',
        '♻️',
        '⚜️',
        '🔱',
        '📛',
        '🔰',
        '⭕',
        '✅',
        '☑️',
        '✔️',
        '❌',
        '❎',
        '➕',
        '➖',
        '➗',
        '✖️',
        '💲',
        '💱',
        '™️',
        '©️',
        '®️',
        '〰️',
        '➰',
        '➿',
        '🔚',
        '🔙',
        '🔛',
        '🔝',
        '🔜',
        '🆕',
      ],
    },
  ];

  /// Toggle emoji picker visibility (inline below input)
  void _showEmojiPickerModal(BuildContext context) {
    if (_showEmojiPicker) {
      // Closing emoji picker → bring keyboard back
      setState(() {
        _showEmojiPicker = false;
      });
      _inputFocusNode.requestFocus();
    } else {
      // Opening emoji picker → dismiss keyboard first
      _inputFocusNode.unfocus();
      setState(() {
        _showEmojiPicker = true;
      });
    }
  }

  /// Build inline emoji picker widget with category tabs
  Widget _buildInlineEmojiPicker() {
    final category = _emojiCategories[_emojiCategoryIndex];
    final emojis = category['emojis'] as List<String>;

    return Container(
      height: 260,
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF3D3D3D),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // Category tabs
          SizedBox(
            height: 44,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              itemCount: _emojiCategories.length,
              itemBuilder: (context, index) {
                final cat = _emojiCategories[index];
                final isSelected = index == _emojiCategoryIndex;
                return GestureDetector(
                  onTap: () => setState(() => _emojiCategoryIndex = index),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF6D28D9)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        cat['icon'] as String,
                        style: const TextStyle(fontSize: 20),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          // Emoji grid
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 8,
                childAspectRatio: 1,
              ),
              itemCount: emojis.length,
              itemBuilder: (context, index) {
                return GestureDetector(
                  onTap: () {
                    // Insert emoji at cursor position
                    final text = _messageController.text;
                    final selection = _messageController.selection;
                    final cursorPos = selection.baseOffset >= 0
                        ? selection.baseOffset
                        : text.length;

                    final newText =
                        text.substring(0, cursorPos) +
                        emojis[index] +
                        text.substring(cursorPos);

                    _messageController.text = newText;
                    _messageController.selection = TextSelection.collapsed(
                      offset: cursorPos + emojis[index].length,
                    );

                    setState(
                      () {},
                    ); // Force rebuild to update button visibility
                  },
                  child: Center(
                    child: Text(
                      emojis[index],
                      style: const TextStyle(fontSize: 24),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Ring doorbell for group (notify all members)
  void _ringDoorbell() async {
    try {
      await GroupService.ringDoorbell(widget.group.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🔔 Doorbell rung for all members'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error ringing doorbell: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to ring doorbell: $e')));
      }
    }
  }

  /// Pick a file from device storage
  Future<void> _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles();
      if (result != null && result.files.single.path != null) {
        await _uploadFile(File(result.files.single.path!));
      }
    } catch (e) {
      debugPrint('Error picking file: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to pick file: $e')));
      }
    }
  }

  /// Take a photo with camera
  Future<void> _takePhoto() async {
    try {
      final picker = ImagePicker();
      final XFile? photo = await picker.pickImage(source: ImageSource.camera);
      if (photo != null) {
        await _uploadFile(File(photo.path));
      }
    } catch (e) {
      debugPrint('Error taking photo: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to take photo: $e')));
      }
    }
  }

  /// Show voice recording modal (placeholder - to be implemented)
  Future<void> _showVoiceRecordingModal() async {
    // TODO: Implement voice recording for group chat
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Voice recording coming soon for group chats'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Widget _buildInputArea() {
    final headerColor = const Color(0xFF1E293B); // Match group chat theme

    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 0,
        bottom: 4 + MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: BoxDecoration(
        color: headerColor,
        border: const Border(
          top: BorderSide(color: Color(0xFF3D3D3D), width: 1),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Reply preview (when replying to a message)
          if (_replyingToMessage != null) _buildReplyPreview(),

          // Text input field with embedded emoji button and send button
          RepaintBoundary(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Actions toggle icon (hidden when input focused or has text)
                if (!_inputFocusNode.hasFocus &&
                    _messageController.text.isEmpty)
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3D3D3D),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: IconButton(
                      onPressed: () => setState(
                        () => _showActionButtons = !_showActionButtons,
                      ),
                      icon: Icon(
                        _showActionButtons
                            ? Icons.expand_more
                            : Icons.add_circle_outline,
                        color: Colors.white70,
                        size: 18,
                      ),
                      padding: const EdgeInsets.all(6),
                      constraints: const BoxConstraints(),
                      tooltip: _showActionButtons
                          ? 'Hide Actions'
                          : 'Show Actions',
                    ),
                  ),
                // Text input field with embedded emoji button
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF4D4D4D),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        // Emoji picker button (inside input) - toggles between emoji/keyboard icon
                        IconButton(
                          onPressed: () => _showEmojiPickerModal(context),
                          icon: Icon(
                            _showEmojiPicker
                                ? Icons.keyboard_outlined
                                : Icons.sentiment_satisfied_alt_outlined,
                            color: Colors.white70,
                            size: 18,
                          ),
                          padding: const EdgeInsets.all(4),
                          constraints: const BoxConstraints(),
                          tooltip: _showEmojiPicker ? 'Keyboard' : 'Emoji',
                        ),
                        // Text input
                        Expanded(
                          child: TextField(
                            key: const ValueKey('message_input'),
                            controller: _messageController,
                            focusNode: _inputFocusNode,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Type a message...',
                              hintStyle: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 14,
                              ),
                              border: InputBorder.none,
                              filled: false,
                              contentPadding: const EdgeInsets.only(
                                left: 0,
                                right: 4,
                                top: 10,
                                bottom: 10,
                              ),
                              isDense: true,
                            ),
                            onChanged: (text) => setState(() {}),
                            minLines: 1,
                            maxLines: 5,
                            textInputAction: TextInputAction.newline,
                            keyboardType: TextInputType.multiline,
                            textCapitalization: TextCapitalization.sentences,
                            enableInteractiveSelection: true,
                            autocorrect: true,
                            enableSuggestions: true,
                            scribbleEnabled: false,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Clear (top) + Send (bottom) — always visible, vertically centred
                IntrinsicWidth(
                  child: Container(
                    margin: const EdgeInsets.only(left: 6),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Clear button (top)
                        ElevatedButton(
                          onPressed: () {
                            _messageController.clear();
                            setState(() {});
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFEF4444),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 3,
                            ),
                            minimumSize: const Size(0, 0),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text(
                            'Clear',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                        const SizedBox(height: 4),
                        // Send button (bottom)
                        ElevatedButton(
                          onPressed: _sendMessage,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6D28D9),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 3,
                            ),
                            minimumSize: const Size(0, 0),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text(
                            'Send',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Inline emoji picker (shown when active)
          if (_showEmojiPicker) _buildInlineEmojiPicker(),
          // Collapsible action buttons panel
          // Only show when emoji picker is closed AND keyboard is not visible
          if (!_showEmojiPicker &&
              MediaQuery.of(context).viewInsets.bottom == 0) ...[
            // All action buttons (shown/hidden by toggle)
            if (_showActionButtons)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    // Ring Doorbell
                    ElevatedButton(
                      onPressed: _ringDoorbell,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF8B5CF6),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      child: const Text('Ring Doorbell'),
                    ),
                    // Send File
                    ElevatedButton(
                      onPressed: _pickFile,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      child: const Text('Send File'),
                    ),
                    // Camera
                    ElevatedButton(
                      onPressed: _takePhoto,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3B82F6),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      child: const Text('Camera'),
                    ),
                    // Voice Message
                    ElevatedButton(
                      onPressed: _showVoiceRecordingModal,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEF4444),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      child: const Text('Voice Message'),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Audio Message Player Widget for playing voice messages in group chat
class _AudioMessagePlayer extends StatefulWidget {
  final String audioUrl;
  final int? fileSize;

  const _AudioMessagePlayer({required this.audioUrl, this.fileSize});

  @override
  State<_AudioMessagePlayer> createState() => _AudioMessagePlayerState();
}

class _AudioMessagePlayerState extends State<_AudioMessagePlayer> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  StreamSubscription? _durationSubscription;
  StreamSubscription? _positionSubscription;
  StreamSubscription? _completeSubscription;

  @override
  void initState() {
    super.initState();
    _setupAudioPlayer();
  }

  void _setupAudioPlayer() {
    _durationSubscription = _audioPlayer.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });

    _positionSubscription = _audioPlayer.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });

    _completeSubscription = _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _position = Duration.zero;
        });
      }
    });
  }

  @override
  void dispose() {
    _durationSubscription?.cancel();
    _positionSubscription?.cancel();
    _completeSubscription?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _togglePlayPause() async {
    try {
      if (_isPlaying) {
        await _audioPlayer.pause();
        setState(() => _isPlaying = false);
      } else {
        // Stop any current playback first
        await _audioPlayer.stop();

        // Small delay to ensure player is ready
        await Future.delayed(const Duration(milliseconds: 100));

        // Play from URL
        await _audioPlayer.play(UrlSource(widget.audioUrl));
        setState(() => _isPlaying = true);
      }
    } catch (e) {
      debugPrint('AudioPlayers Exception: $e');
      if (mounted) {
        setState(() => _isPlaying = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error playing audio: ${e.toString().split(':').last.trim()}',
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final progress = _duration.inMilliseconds > 0
        ? _position.inMilliseconds / _duration.inMilliseconds
        : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Play/Pause button
          GestureDetector(
            onTap: _togglePlayPause,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(51),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
                size: 28,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Waveform and progress
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Waveform visualization (static bars)
                Row(
                  children: List.generate(20, (index) {
                    final barHeight = [
                      8.0,
                      14.0,
                      10.0,
                      18.0,
                      12.0,
                      20.0,
                      16.0,
                      22.0,
                      14.0,
                      18.0,
                      12.0,
                      16.0,
                      20.0,
                      14.0,
                      10.0,
                      18.0,
                      12.0,
                      8.0,
                      14.0,
                      10.0,
                    ][index];
                    final isPlayed = progress > (index / 20);
                    return Container(
                      width: 3,
                      height: barHeight,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        color: isPlayed ? Colors.white : Colors.white38,
                        borderRadius: BorderRadius.circular(1.5),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 4),
                // Duration text
                Text(
                  _isPlaying || _position > Duration.zero
                      ? '${_formatDuration(_position)} / ${_formatDuration(_duration)}'
                      : _formatDuration(_duration),
                  style: TextStyle(
                    color: Colors.white.withAlpha(179),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
