import 'package:flutter/material.dart';

import '../../models/lobby_user.dart';

class ChatHeader extends StatelessWidget implements PreferredSizeWidget {
  const ChatHeader({
    super.key,
    required this.otherUser,
    required this.headerColor,
    required this.isSelfChat,
    required this.callInProgressOnOtherDevice,
    required this.partnerStatus,
    required this.partnerLastSeen,
    required this.taskCount,
    required this.excalidrawCount,
    required this.scale,
    required this.onBack,
    required this.onUserProfile,
    required this.onShowTasks,
    required this.onShowExcalidraw,
    required this.onCallAudio,
    required this.onCallVideo,
  });

  final LobbyUser otherUser;
  final Color headerColor;
  final bool isSelfChat;
  final bool callInProgressOnOtherDevice;
  final String partnerStatus;
  final String? partnerLastSeen;
  final int taskCount;
  final int excalidrawCount;
  final double scale;
  final VoidCallback onBack;
  final VoidCallback onUserProfile;
  final VoidCallback onShowTasks;
  final VoidCallback onShowExcalidraw;
  final VoidCallback onCallAudio;
  final VoidCallback onCallVideo;

  @override
  Size get preferredSize => Size.fromHeight(kToolbarHeight + 4 * scale);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: headerColor,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: onBack,
      ),
      titleSpacing: 0,
      title: GestureDetector(
        onTap: onUserProfile,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 15 * scale,
              backgroundColor: _getAvatarColor(),
              child: Text(
                otherUser.initials,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12 * scale,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            SizedBox(width: 8 * scale),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    otherUser.fullName.split(' ').first,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15 * scale,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (!isSelfChat) _buildHeaderStatusPill(scale),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (!isSelfChat && callInProgressOnOtherDevice)
          Padding(
            padding: EdgeInsets.only(right: 6 * scale),
            child: Center(
              child: Container(
                constraints: BoxConstraints(maxWidth: 180 * scale),
                padding: EdgeInsets.symmetric(
                  horizontal: 10 * scale,
                  vertical: 6 * scale,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.45),
                  ),
                ),
                child: Text(
                  'Call in progress on other device',
                  maxLines: 2,
                  softWrap: true,
                  overflow: TextOverflow.fade,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: const Color(0xFFF59E0B),
                    fontSize: 11 * scale,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          )
        else ...[
          if (!isSelfChat)
            IconButton(
              icon: Icon(Icons.videocam, color: Colors.white, size: 24 * scale),
              onPressed: onCallVideo,
              tooltip: 'Video Call',
            ),
          if (!isSelfChat)
            IconButton(
              icon: Icon(Icons.call, color: Colors.white, size: 24 * scale),
              onPressed: onCallAudio,
              tooltip: 'Audio Call',
            ),
        ],
        _buildBadgeIcon(
          context,
          icon: Icons.task_alt,
          count: taskCount,
          color: const Color(0xFFF59E0B),
          onPressed: onShowTasks,
          tooltip: 'Tasks',
          scale: scale,
        ),
        _buildBadgeIcon(
          context,
          icon: Icons.draw_outlined,
          count: excalidrawCount,
          color: const Color(0xFF7C3AED),
          onPressed: onShowExcalidraw,
          tooltip: 'Excalidraw',
          scale: scale,
        ),
      ],
    );
  }

  Widget _buildHeaderStatusPill(double scale) {
    final status = partnerStatus;
    final statusFontSize = (11.5 * scale).clamp(11.0, 13.0).toDouble();
    final label = status == 'online'
        ? 'Online'
        : partnerLastSeen != null
            ? 'Last seen: $partnerLastSeen'
            : 'Offline';

    return Padding(
      padding: EdgeInsets.only(top: 1 * scale),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.9),
          fontSize: statusFontSize,
          fontWeight: FontWeight.w500,
          height: 1.12,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildBadgeIcon(
    BuildContext context, {
    required IconData icon,
    required int count,
    required Color color,
    required VoidCallback onPressed,
    required String tooltip,
    required double scale,
  }) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: Icon(icon, color: Colors.white, size: 24 * scale),
          onPressed: onPressed,
          tooltip: tooltip,
        ),
        if (count > 0)
          Positioned(
            right: 4,
            top: 4,
            child: Container(
              padding: EdgeInsets.all(2 * scale),
              constraints: BoxConstraints(
                minWidth: 16 * scale,
                minHeight: 16 * scale,
              ),
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.black.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 9 * scale,
                  fontWeight: FontWeight.w800,
                  height: 1.0,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }

  Color _getAvatarColor() {
    return const Color(0xFF1F1F1F);
  }
}
