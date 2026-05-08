import 'package:flutter/material.dart';

import '../../models/message.dart';
import 'audio_message_player.dart';
import 'contact_card_widget.dart';

class ChatMessageBubble extends StatelessWidget {
  const ChatMessageBubble({
    super.key,
    required this.message,
    required this.isSentByMe,
    required this.scale,
    required this.showTimestamps,
    required this.isSelected,
    required this.messageReactions,
    required this.messageTranslations,
    required this.onTapUp,
    required this.onLongPress,
    required this.onShowReactionPicker,
    required this.onOpenMediaViewer,
    required this.onDownloadIncomingFile,
    required this.onOpenMessageUrl,
    required this.statusForUi,
    required this.isOnlyFilename,
    required this.canQuickToggleExcalidrawPin,
    required this.formatFileSize,
    required this.buildReactionPills,
    required this.buildLinkifiedMessageText,
    required this.buildStatusIndicator,
  });

  final Message message;
  final bool isSentByMe;
  final double scale;
  final bool showTimestamps;
  final bool isSelected;
  final Map<int, Map<String, Set<String>>> messageReactions;
  final Map<int, String> messageTranslations;
  final void Function(TapUpDetails details) onTapUp;
  final VoidCallback onLongPress;
  final void Function(BuildContext context, int messageId, Offset position)
      onShowReactionPicker;
  final void Function(Message message) onOpenMediaViewer;
  final void Function(Message message) onDownloadIncomingFile;
  final void Function(String url) onOpenMessageUrl;
  final String Function(Message message) statusForUi;
  final bool Function(String content) isOnlyFilename;
  final bool Function(Message message) canQuickToggleExcalidrawPin;
  final String Function(int fileSize) formatFileSize;
  final Widget Function(int messageId) buildReactionPills;
  final Widget Function({
    required String text,
    required bool isTaskMessage,
    required Color taskAccentColor,
  }) buildLinkifiedMessageText;
  final Widget Function(String status, double scale) buildStatusIndicator;

  @override
  Widget build(BuildContext context) {
    final maxBubbleWidth = MediaQuery.of(context).size.width *
      (scale < 0.9 ? 0.82 : 0.70);
    final int imageCacheWidth = ((maxBubbleWidth *
          MediaQuery.of(context).devicePixelRatio)
        .round()
        .clamp(320, 2048))
      as int;
    final bool isImage = message.messageType == 'image' ||
        (message.fileType?.startsWith('image/') ?? false);
    final bool isVideo = message.messageType == 'video' ||
        (message.fileType?.startsWith('video/') ?? false);
    final bool isAudio = message.messageType == 'voice' ||
        message.messageType == 'audio' ||
        (message.fileType?.startsWith('audio/') ?? false);
    final bool isMedia = isImage || isVideo;
    final bool isContact = message.messageType == 'contact';
    final bool isGenericFile =
        (!isMedia && !isAudio && !isContact) &&
            ((message.messageType == 'file' ||
                    message.messageType == 'document') ||
                (message.fileUrl != null && message.fileUrl!.isNotEmpty));
    final bool canSaveAttachment =
      message.fileUrl != null &&
      message.fileUrl!.isNotEmpty &&
      (isMedia || isAudio || isGenericFile);

    final hasReactions =
        messageReactions[message.id] != null &&
            messageReactions[message.id]!.isNotEmpty;
    final isTaskMessage = message.isTask;
    final bool isTaskCompleted = message.taskCompletedAt != null;
    final bool isPinnedExcalidraw =
        canQuickToggleExcalidrawPin(message) &&
            message.excalidrawPinnedAt != null;
    const excalidrawAccentColor = Color(0xFFB794F6);
    final taskAccentColor = isTaskCompleted
        ? const Color(0xFF22C55E)
        : const Color(0xFFF59E0B);
    final bubbleAccentColor = isTaskMessage
        ? taskAccentColor
        : (isPinnedExcalidraw ? excalidrawAccentColor : null);

    final bubbleWidget = GestureDetector(
      onTapUp: (details) {
        onTapUp(details);
      },
      onLongPress: onLongPress,
      child: Container(
        margin: EdgeInsets.only(bottom: hasReactions ? 2 : 12),
        constraints: BoxConstraints(
          maxWidth: maxBubbleWidth,
        ),
        decoration: BoxDecoration(
          color: isSentByMe ? const Color(0xFF420796) : const Color(0xFF3944BC),
          border: bubbleAccentColor != null
              ? Border.all(
                  color: bubbleAccentColor.withValues(alpha:  0.85),
                  width: 1.4,
                )
              : null,
          boxShadow: bubbleAccentColor != null
              ? [
                  BoxShadow(
                    color: bubbleAccentColor.withValues(alpha:  0.45),
                    blurRadius: 14,
                    spreadRadius: 0.2,
                  ),
                ]
              : null,
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
            if (isPinnedExcalidraw)
              _buildPinnedExcalidrawLabel(scale, excalidrawAccentColor),
            if (message.replyToId != null || message.replyPreview != null)
              _buildReplyPreview(message, scale),
            if (isMedia && message.fileUrl != null)
              _buildMediaContent(isImage, isVideo, message, imageCacheWidth),
            if (isAudio && message.fileUrl != null)
              AudioMessagePlayer(
                audioUrl: message.fileUrl!,
                fileSize: message.fileSize,
              ),
            if (isContact)
              ContactCardWidget(
                vcard: message.content,
                isSentByMe: isSentByMe,
              ),
            if (isGenericFile)
              _buildGenericFileContent(message, taskAccentColor, scale),
            if (!isContact &&
                ((!isMedia && !isAudio && !isGenericFile) ||
                    (message.content.isNotEmpty &&
                        !isOnlyFilename(message.content) &&
                        !isAudio &&
                        !isGenericFile)))
              _buildTextContent(
                message,
                isTaskMessage,
                taskAccentColor,
                scale,
              )
            else if (isMedia || isAudio)
              const SizedBox(height: 8),
            if (isSentByMe)
              _buildSentStatusRow(
                message,
                scale,
                canSaveAttachment: canSaveAttachment,
              )
            else
              _buildIncomingTimeRow(
                message,
                scale,
                canSaveAttachment: canSaveAttachment,
              ),
            if (showTimestamps)
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 16 * scale,
                  vertical: 6 * scale,
                ),
                child: Text(
                  message.formattedTimestampFull,
                  style: TextStyle(
                    color: const Color(0xFFFF69B4),
                    fontSize: 12 * scale,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      color: isSelected
          ? Colors.white.withValues(alpha:  0.07)
          : Colors.transparent,
      child: Align(
        alignment: isSentByMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Column(
          crossAxisAlignment:
              isSentByMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Builder(
              builder: (rowContext) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    bubbleWidget,
                    if (!isSentByMe)
                      GestureDetector(
                        onTap: () {
                          final renderBox = rowContext.findRenderObject() as RenderBox?;
                          if (renderBox != null) {
                            final position = renderBox.localToGlobal(Offset.zero);
                            onShowReactionPicker(context, message.id, position);
                          }
                        },
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4 * scale),
                          child: Icon(
                            Icons.sentiment_satisfied_alt_outlined,
                            color: Colors.white.withValues(alpha:  0.6),
                            size: 22 * scale,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            if (hasReactions)
              Padding(
                padding: EdgeInsets.only(
                  left: isSentByMe ? 0 : 8,
                  right: isSentByMe ? 8 : 0,
                  top: 0,
                  bottom: 6,
                ),
                child: buildReactionPills(message.id),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPinnedExcalidrawLabel(double scale, Color excalidrawAccentColor) {
    return Padding(
      padding: EdgeInsets.fromLTRB(12 * scale, 8 * scale, 12 * scale, 2),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: 9 * scale,
          vertical: 3 * scale,
        ),
        decoration: BoxDecoration(
          color: excalidrawAccentColor.withValues(alpha:  0.18),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: excalidrawAccentColor.withValues(alpha:  0.55),
          ),
        ),
        child: Text(
          'Pinned Excalidraw',
          style: TextStyle(
            color: Colors.white,
            fontSize: 11 * scale,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildReplyPreview(Message message, double scale) {
    final preview = message.replyPreview ?? '';
    final colonIndex = preview.indexOf(':');
    final senderName = colonIndex > 0 ? preview.substring(0, colonIndex) : 'Reply';
    var contentText = colonIndex > 0 ? preview.substring(colonIndex + 1).trim() : preview;

    if (contentText.contains('<audio') || contentText.contains('audio/')) {
      contentText = '🎤 Voice message';
    } else if (contentText.contains('<img') || contentText.contains('image/')) {
      contentText = '🖼️ Photo';
    } else if (contentText.contains('<video') || contentText.contains('video/')) {
      contentText = '🎥 Video';
    } else if (contentText.contains('file/') || contentText.endsWith('.pdf') ||
        contentText.endsWith('.doc')) {
      contentText = '📄 File';
    }

    return Opacity(
      opacity: 0.85,
      child: Container(
        margin: EdgeInsets.only(
          left: 8 * scale,
          right: 8 * scale,
          top: 8 * scale,
        ),
        padding: EdgeInsets.symmetric(
          horizontal: 10 * scale,
          vertical: 6 * scale,
        ),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha:  0.15),
          borderRadius: BorderRadius.circular(6),
          border: const Border(
            left: BorderSide(color: Color(0xFFB794F6), width: 3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              senderName,
              style: TextStyle(
                color: Colors.white.withValues(alpha:  0.9),
                fontSize: 11 * scale,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 2 * scale),
            Text(
              contentText,
              style: TextStyle(
                color: Colors.white.withValues(alpha:  0.7),
                fontSize: 12 * scale,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaContent(bool isImage, bool isVideo, Message message, int imageCacheWidth) {
    // Fixed aspect ratio prevents layout shifts when the image loads,
    // which is the primary cause of scroll momentum being broken.
    const double mediaAspectRatio = 4 / 3;

    final borderRadius = BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: Radius.circular(
        message.content.isNotEmpty && !isOnlyFilename(message.content)
            ? 0
            : (isSentByMe ? 16 : 4),
      ),
      bottomRight: Radius.circular(
        message.content.isNotEmpty && !isOnlyFilename(message.content)
            ? 0
            : (isSentByMe ? 4 : 16),
      ),
    );

    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: borderRadius,
        child: GestureDetector(
          onTap: () => onOpenMediaViewer(message),
          child: AspectRatio(
            aspectRatio: mediaAspectRatio,
            child: Stack(
              fit: StackFit.expand,
              alignment: Alignment.center,
              children: [
                // Placeholder shown while image loads — same size as the
                // final image so layout never shifts.
                Container(color: Colors.grey[850]),

                if (isImage)
                  Image.network(
                    message.fileUrl!,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    cacheWidth: imageCacheWidth,
                    filterQuality: FilterQuality.low,
                    // frameBuilder gives a smooth fade-in without blocking
                    // the scroll thread the way loadingBuilder can.
                    frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                      if (wasSynchronouslyLoaded || frame != null) {
                        return child;
                      }
                      return AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: frame == null
                            ? Container(
                                key: const ValueKey('placeholder'),
                                color: Colors.grey[850],
                              )
                            : child,
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
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
                    color: Colors.black87,
                    child: const Center(
                      child: Icon(
                        Icons.play_circle_fill,
                        color: Colors.white,
                        size: 60,
                      ),
                    ),
                  ),

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
      ),
    );
  }

  Widget _buildGenericFileContent(
    Message message,
    Color taskAccentColor,
    double scale,
  ) {
    return Container(
      padding: EdgeInsets.all(16 * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.attach_file,
                color: Colors.white70,
                size: 24,
              ),
              SizedBox(width: 12 * scale),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (message.fileName?.isNotEmpty ?? false)
                          ? message.fileName!
                          : (message.fileUrl != null
                              ? Uri.tryParse(message.fileUrl!)
                                      ?.pathSegments
                                      .last
                                      .replaceAll('%20', ' ') ??
                                  'File'
                              : 'File'),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12 * scale,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 4 * scale),
                    Text(
                      message.fileUrl != null
                          ? ((message.fileSize != null && message.fileSize! > 0)
                              ? formatFileSize(message.fileSize!)
                              : 'Unknown size')
                          : 'File not available',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 12 * scale,
                      ),
                    ),
                  ],
                ),
              ),
              if (message.fileUrl != null && isSentByMe)
                IconButton(
                  onPressed: () => onOpenMessageUrl(message.fileUrl!),
                  icon: const Icon(
                    Icons.open_in_new,
                    color: Colors.white70,
                    size: 20,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTextContent(
    Message message,
    bool isTaskMessage,
    Color taskAccentColor,
    double scale,
  ) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 16 * scale,
        vertical: 10 * scale,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          buildLinkifiedMessageText(
            text: isMediaDescription(message, isMedia: false),
            isTaskMessage: isTaskMessage,
            taskAccentColor: taskAccentColor,
          ),
          if (messageTranslations.containsKey(message.id)) ...[
            const SizedBox(height: 8),
            Container(
              height: 1,
              color: Colors.white.withValues(alpha:  0.3),
              margin: const EdgeInsets.symmetric(vertical: 4),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.language,
                  size: 14,
                  color: Colors.white.withValues(alpha:  0.7),
                ),
                const SizedBox(width: 4),
                Text(
                  'auto → en',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha:  0.7),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              messageTranslations[message.id]!,
              style: TextStyle(
                color: Colors.white.withValues(alpha:  0.9),
                fontSize: 14,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String isMediaDescription(Message message, {required bool isMedia}) {
    return message.content;
  }

  Widget _buildSentStatusRow(
    Message message,
    double scale, {
    required bool canSaveAttachment,
  }) {
    if (!canSaveAttachment) {
      return Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 16 * scale,
          vertical: 6 * scale,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              message.formattedTime,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 11 * scale,
              ),
            ),
            SizedBox(width: 4 * scale),
            buildStatusIndicator(statusForUi(message), scale),
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 16 * scale,
        vertical: 6 * scale,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          Text(
            message.formattedTime,
            style: TextStyle(
              color: Colors.white70,
              fontSize: 11 * scale,
            ),
          ),
          SizedBox(width: 4 * scale),
          buildStatusIndicator(statusForUi(message), scale),
          const Spacer(),
          _buildFooterSaveAction(message, scale),
        ],
      ),
    );
  }

  Widget _buildIncomingTimeRow(
    Message message,
    double scale, {
    required bool canSaveAttachment,
  }) {
    if (!canSaveAttachment) {
      return Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 16 * scale,
          vertical: 6 * scale,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message.formattedTime,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 11 * scale,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 16 * scale,
        vertical: 6 * scale,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          Text(
            message.formattedTime,
            style: TextStyle(
              color: Colors.white70,
              fontSize: 11 * scale,
            ),
          ),
          const Spacer(),
          _buildFooterSaveAction(message, scale),
        ],
      ),
    );
  }

  Widget _buildFooterSaveAction(Message message, double scale) {
    return TextButton(
      onPressed: () => onDownloadIncomingFile(message),
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 0),
        visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
      ),
      child: Text(
        'Save',
        style: TextStyle(
          fontSize: 11 * scale,
          fontWeight: FontWeight.w600,
          height: 1,
        ),
      ),
    );
  }
}
