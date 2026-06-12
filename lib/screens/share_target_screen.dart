import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../models/lobby_user.dart';
import '../services/chat_cache_service.dart';
import '../services/lobby_service.dart';
import '../services/message_service.dart';
import '../services/share_intent_service.dart';
import '../services/shortcut_service.dart';
import '../services/storage_service.dart';
import 'chat_screen.dart' show ChatScreen;
import 'lobby_screen.dart';

class ShareTargetScreen extends StatefulWidget {
  final List<SharedMediaItem> sharedItems;
  final List<LobbyUser> users;
  final bool openLobbyOnExit;

  /// When set (Direct Share shortcut tapped), skip the picker and send directly
  /// to this user without any further interaction.
  final int? directShareUserId;

  const ShareTargetScreen({
    super.key,
    required this.sharedItems,
    required this.users,
    this.openLobbyOnExit = false,
    this.directShareUserId,
  });

  @override
  State<ShareTargetScreen> createState() => _ShareTargetScreenState();
}

class _ShareTargetScreenState extends State<ShareTargetScreen> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _captionController = TextEditingController();
  final Set<int> _selectedUserIds = <int>{};
  final Map<int, String> _searchKeyCache = <int, String>{};
  Timer? _searchDebounceTimer;

  late List<LobbyUser> _allUsers;
  late List<LobbyUser> _filteredUsers;
  bool _isSending = false;
  bool _isLoadingContacts = false;
  bool _hasFiredDirectSend = false; // guard: only auto-send once

  // Matches the web app (generate_avatar_url) so avatar colors line up across platforms.
  static const List<Color> _avatarColors = [
    Color(0xFF1F77B4),
    Color(0xFFFF7F0E),
    Color(0xFF2CA02C),
    Color(0xFFD62728),
    Color(0xFF9467BD),
    Color(0xFF8C564B),
    Color(0xFFE377C2),
    Color(0xFF7F7F7F),
    Color(0xFFBCBD22),
    Color(0xFF17BECF),
  ];

  @override
  void initState() {
    super.initState();
    _allUsers = _normalizeUsers(widget.users);
    _filteredUsers = List<LobbyUser>.from(_allUsers);
    _isLoadingContacts = _allUsers.isEmpty;
    _searchController.addListener(_scheduleSearch);
    _loadContacts();
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _searchController.removeListener(_scheduleSearch);
    _searchController.dispose();
    _captionController.dispose();
    super.dispose();
  }

  void _scheduleSearch() {
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(const Duration(milliseconds: 150), _applySearch);
  }

  void _applySearch() {
    final query = _searchController.text.trim().toLowerCase();

    setState(() {
      if (query.isEmpty) {
        _filteredUsers = List<LobbyUser>.from(_allUsers);
        return;
      }

      _filteredUsers = _allUsers
          .where((user) {
            final searchKey = _searchKeyCache[user.id] ?? '';
            return searchKey.contains(query);
          })
          .toList(growable: false);
    });
  }

  DateTime _parseMessageTime(String? timestamp) {
    if (timestamp == null || timestamp.isEmpty) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    try {
      return DateTime.parse(timestamp).toUtc();
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  List<LobbyUser> _normalizeUsers(List<LobbyUser> users) {
    final sortedUsers = List<LobbyUser>.from(users)
      ..sort(
        (a, b) {
          final timeCompare = _parseMessageTime(
            b.lastMessageTime,
          ).compareTo(_parseMessageTime(a.lastMessageTime));
          if (timeCompare != 0) {
            return timeCompare;
          }

          return a.fullName.toLowerCase().compareTo(
            b.fullName.toLowerCase(),
          );
        },
      );

    for (final user in sortedUsers) {
      _searchKeyCache[user.id] = '${user.fullName} ${user.username}'.toLowerCase();
    }

    return sortedUsers;
  }

  void _applyUsers(List<LobbyUser> users) {
    final normalized = _normalizeUsers(users);

    if (!mounted) {
      return;
    }

    setState(() {
      _allUsers = normalized;

      final existingIds = normalized.map((user) => user.id).toSet();
      _selectedUserIds.removeWhere((id) => !existingIds.contains(id));

      final query = _searchController.text.trim().toLowerCase();
      if (query.isEmpty) {
        _filteredUsers = List<LobbyUser>.from(normalized);
      } else {
        _filteredUsers = normalized
            .where((user) {
              return user.fullName.toLowerCase().contains(query) ||
                  user.username.toLowerCase().contains(query);
            })
            .toList(growable: false);
      }
    });

    // Direct Share: if a specific user was chosen in the share sheet,
    // pre-select them and fire send without user interaction.
    if (!_hasFiredDirectSend && widget.directShareUserId != null) {
      final target = normalized
          .cast<LobbyUser?>()
          .firstWhere((u) => u?.id == widget.directShareUserId, orElse: () => null);
      if (target != null) {
        _hasFiredDirectSend = true;
        setState(() => _selectedUserIds.add(target.id));
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _sendSharedItems();
        });
      }
    }
  }

  Future<void> _loadContacts() async {
    final currentUserId = await StorageService.getUserId();

    if (_allUsers.isEmpty && currentUserId != null) {
      final cachedUsers = await ChatCacheService.loadLobbyUsers(currentUserId);
      if (cachedUsers.isNotEmpty) {
        _applyUsers(cachedUsers);
      }
    }

    try {
      final freshUsers = await LobbyService.getLobbyUsers();
      _applyUsers(freshUsers);

      if (currentUserId != null) {
        await ChatCacheService.saveLobbyUsers(currentUserId, freshUsers);
      }
    } catch (e) {
      debugPrint('ShareTargetScreen: failed to refresh contacts: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingContacts = false);
      }
    }
  }

  Future<void> _sendSharedItems() async {
    if (_selectedUserIds.isEmpty || _isSending) {
      return;
    }

    final selectedUsers = _allUsers
        .where((user) => _selectedUserIds.contains(user.id))
        .toList(growable: false);

    if (selectedUsers.isEmpty) {
      return;
    }

    setState(() => _isSending = true);

    final caption = _captionController.text.trim();
    int sentCount = 0;
    final failedRecipients = <String>[];
    final successfulUsers = <LobbyUser>[];

    for (final user in selectedUsers) {
      try {
        for (final item in widget.sharedItems) {
          final file = File(item.path);
          if (!await file.exists()) {
            throw Exception('Shared file is no longer available');
          }

          // vCard files are sent as in-chat contact cards, not generic uploads.
          if (item.isVCard) {
            final vcardContent = await file.readAsString();
            final sent = await MessageService.sendMessage(
              recipientId: user.id,
              content: vcardContent,
              messageType: 'contact',
            );
            if (sent == null) throw Exception('Failed to send contact');
            continue;
          }

          // Text files containing URLs (from Chrome share) are sent as text messages
          if (item.mimeType == 'text/plain' || item.fileName.toLowerCase().endsWith('.txt')) {
            try {
              final textContent = await file.readAsString();
              if (textContent.isNotEmpty) {
                // Send as text message (URL will show link preview)
                final sent = await MessageService.sendMessage(
                  recipientId: user.id,
                  content: textContent,
                  messageType: 'text',
                );
                if (sent == null) throw Exception('Failed to send text');
                continue;
              }
            } catch (_) {
              // Fall through to file upload if reading fails
            }
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

        // Feed usage back to Android Sharesheet ranking so active contacts
        // are more likely to appear in the top Direct Share row.
        ShortcutService.reportShareUsed(user.id);

        sentCount++;
        successfulUsers.add(user);
      } catch (e) {
        failedRecipients.add(user.fullName);
      }
    }

    if (!mounted) {
      return;
    }

    setState(() => _isSending = false);

    if (sentCount > 0) {
      // If one chat was selected from share sheet and send succeeded,
      // open that chat room immediately.
      if (_selectedUserIds.length == 1 && successfulUsers.length == 1) {
        _openChatRoom(successfulUsers.first);
        return;
      }

      if (widget.openLobbyOnExit) {
        _goToLobby();
        return;
      }

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

  void _openChatRoom(LobbyUser user) {
    if (!mounted) {
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(otherUser: user),
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

  void _goToLobby() {
    if (!mounted) {
      return;
    }
    Navigator.pushReplacementNamed(context, LobbyScreen.route);
  }

  Widget _buildPreviewCard({
    required double previewHeight,
    required double horizontalPadding,
    required double topPadding,
    required double scale,
  }) {
    final firstItem = widget.sharedItems.first;
    final isTextFile = firstItem.mimeType == 'text/plain' ||
        firstItem.fileName.toLowerCase().endsWith('.txt');

    return Container(
      margin: EdgeInsets.fromLTRB(
        horizontalPadding,
        topPadding,
        horizontalPadding,
        8 * scale,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF252542),
        borderRadius: BorderRadius.circular(14 * scale),
        border: Border.all(
          color: const Color(0xFF00D9FF).withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(14 * scale),
            ),
            child: SizedBox(
              width: double.infinity,
              height: previewHeight,
              child: firstItem.isImage
                  ? Image.file(
                      File(firstItem.path),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return ColoredBox(
                          color: Color(0xFF1A1A2E),
                          child: Center(
                            child: Icon(
                              Icons.image_not_supported_outlined,
                              color: Colors.white54,
                              size: 44 * scale,
                            ),
                          ),
                        );
                      },
                    )
                  : isTextFile
                      ? _buildTextPreview(firstItem, scale)
                      : ColoredBox(
                          color: Color(0xFF1A1A2E),
                          child: Center(
                            child: Icon(
                              Icons.insert_drive_file_outlined,
                              color: Colors.white54,
                              size: 44 * scale,
                            ),
                          ),
                        ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              12 * scale,
              10 * scale,
              12 * scale,
              12 * scale,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.share_outlined,
                  color: Color(0xFF00D9FF),
                  size: 18 * scale,
                ),
                SizedBox(width: 8 * scale),
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

  Widget _buildTextPreview(SharedMediaItem item, double scale) {
    return FutureBuilder<String>(
      future: File(item.path).readAsString(),
      builder: (context, snapshot) {
        final text = snapshot.data ?? '';
        final isUrl = text.startsWith('http://') || text.startsWith('https://');

        return ColoredBox(
          color: const Color(0xFF1A1A2E),
          child: Padding(
            padding: EdgeInsets.all(16 * scale),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isUrl ? Icons.link : Icons.text_snippet,
                      color: const Color(0xFF00D9FF),
                      size: 20 * scale,
                    ),
                    SizedBox(width: 8 * scale),
                    Text(
                      isUrl ? 'Link' : 'Text',
                      style: TextStyle(
                        color: const Color(0xFF00D9FF),
                        fontSize: 12 * scale,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8 * scale),
                Expanded(
                  child: Text(
                    text,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 14 * scale,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildUserTile(LobbyUser user, double scale) {
    final isSelected = _selectedUserIds.contains(user.id);
    final avatarRadius = 24 * scale;
    final avatarDiameter = avatarRadius * 2;

    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: 12 * scale,
        vertical: 4 * scale,
      ),
      decoration: BoxDecoration(
        color: isSelected
            ? const Color(0xFF00D9FF).withValues(alpha: 0.18)
            : const Color(0xFF252542),
        borderRadius: BorderRadius.circular(12 * scale),
        border: Border.all(
          color: isSelected ? const Color(0xFF00D9FF) : const Color(0xFF252542),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12 * scale),
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
            padding: EdgeInsets.symmetric(
              horizontal: 12 * scale,
              vertical: 10 * scale,
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: avatarRadius,
                  backgroundColor: _avatarColorForUser(user),
                  child: user.avatarUrl != null
                      ? ClipOval(
                          child: Image.network(
                            user.avatarUrl!,
                            width: avatarDiameter,
                            height: avatarDiameter,
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
                SizedBox(width: 12 * scale),
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
                      SizedBox(height: 2 * scale),
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
    final mediaQuery = MediaQuery.of(context);
    final screenHeight = mediaQuery.size.height;
    final screenWidth = mediaQuery.size.width;
    final compactHeight = screenHeight < 760;
    final compactWidth = screenWidth < 380;
    final layoutScale = screenWidth < 360 || screenHeight < 700
        ? 0.88
        : (compactHeight || compactWidth)
        ? 0.94
        : 1.0;
    final horizontalPadding = (compactWidth ? 12.0 : 16.0) * layoutScale;
    final topPadding = (compactHeight ? 8.0 : 12.0) * layoutScale;
    final searchBottomPadding = (compactHeight ? 6.0 : 8.0) * layoutScale;
    final composerPadding = (compactHeight ? 8.0 : 12.0) * layoutScale;
    final previewHeight = (compactHeight ? 132.0 : 180.0) * layoutScale;
    final toolbarHeight = kToolbarHeight * (layoutScale < 1 ? 0.92 : 1.0);

    return PopScope(
      canPop: !widget.openLobbyOnExit,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !widget.openLobbyOnExit) {
          return;
        }
        _goToLobby();
      },
      child: MediaQuery(
        data: mediaQuery.copyWith(textScaler: TextScaler.linear(layoutScale)),
        child: Scaffold(
          backgroundColor: const Color(0xFF1A1A2E),
          appBar: AppBar(
            backgroundColor: const Color(0xFF1A1A2E),
            elevation: 0,
            toolbarHeight: toolbarHeight,
            iconTheme: IconThemeData(size: 24 * layoutScale),
            leading: widget.openLobbyOnExit
                ? IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: _goToLobby,
                  )
                : null,
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
              _buildPreviewCard(
                previewHeight: previewHeight,
                horizontalPadding: horizontalPadding,
                topPadding: topPadding,
                scale: layoutScale,
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  4 * layoutScale,
                  horizontalPadding,
                  searchBottomPadding,
                ),
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Search contacts',
                    hintStyle: TextStyle(color: Colors.grey[500]),
                    prefixIcon: Icon(
                      Icons.search,
                      color: Colors.grey[500],
                      size: 20 * layoutScale,
                    ),
                    filled: true,
                    fillColor: const Color(0xFF252542),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10 * layoutScale),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12 * layoutScale,
                      vertical: 12 * layoutScale,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _isLoadingContacts && _filteredUsers.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(strokeWidth: 2),
                            SizedBox(height: 10 * layoutScale),
                            const Text(
                              'Loading contacts...',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ],
                        ),
                      )
                    : _filteredUsers.isEmpty
                    ? Center(
                        child: Text(
                          'No contacts found',
                          style: TextStyle(color: Colors.grey[500], fontSize: 15),
                        ),
                      )
                    : ListView.builder(
                        padding: EdgeInsets.only(bottom: 4 * layoutScale),
                        itemCount: _filteredUsers.length,
                        itemBuilder: (context, index) {
                          final user = _filteredUsers[index];
                          return _buildUserTile(user, layoutScale);
                        },
                      ),
              ),
              SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding - (4 * layoutScale),
                    (compactHeight ? 6 : 8) * layoutScale,
                    horizontalPadding - (4 * layoutScale),
                    composerPadding,
                  ),
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
                              borderRadius: BorderRadius.circular(24 * layoutScale),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 16 * layoutScale,
                              vertical: 12 * layoutScale,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: 10 * layoutScale),
                      SizedBox(
                        height: 48 * layoutScale,
                        child: ElevatedButton(
                          onPressed: (_selectedUserIds.isEmpty || _isSending)
                              ? null
                              : _sendSharedItems,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00D9FF),
                            foregroundColor: const Color(0xFF10212E),
                            tapTargetSize: layoutScale < 1
                                ? MaterialTapTargetSize.shrinkWrap
                                : MaterialTapTargetSize.padded,
                            visualDensity: layoutScale < 1
                                ? const VisualDensity(horizontal: -1, vertical: -1)
                                : VisualDensity.standard,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24 * layoutScale),
                            ),
                            padding: EdgeInsets.symmetric(
                              horizontal: 18 * layoutScale,
                            ),
                          ),
                          child: _isSending
                              ? SizedBox(
                                  width: 20 * layoutScale,
                                  height: 20 * layoutScale,
                                  child: const CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
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
        ),
      ),
    );
  }
}
