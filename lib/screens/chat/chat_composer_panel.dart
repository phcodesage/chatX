import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../widgets/chat_composer_shell.dart';

class ChatComposerPanel extends StatelessWidget {
  const ChatComposerPanel({
    super.key,
    required this.scale,
    required this.backgroundColor,
    required this.composerInset,
    required this.showEmojiPicker,
    required this.stablePanelHeight,
    required this.onShowEmojiPickerModal,
    required this.onTextChanged,
    required this.onSend,
    required this.messageController,
    required this.inputFocusNode,
    required this.inputScrollController,
    required this.compactSelectionControls,
    required this.buildDoorbellComposerButton,
    required this.isComposerMultiline,
    required this.replyPreview,
    required this.sendToManyQuickAction,
    required this.unifiedActionsBar,
    required this.inlineEmojiPickerBuilder,
  });

  final double scale;
  final Color backgroundColor;
  final double composerInset;
  final bool showEmojiPicker;
  final double stablePanelHeight;
  final VoidCallback onShowEmojiPickerModal;
  final void Function(String) onTextChanged;
  final VoidCallback onSend;
  final TextEditingController messageController;
  final FocusNode inputFocusNode;
  final ScrollController inputScrollController;
  final TextSelectionControls compactSelectionControls;
  final Widget Function({required bool showLabel, required double iconSize, required EdgeInsets padding}) buildDoorbellComposerButton;
  final bool Function(String, TextStyle, double) isComposerMultiline;
  final Widget replyPreview;
  final Widget sendToManyQuickAction;
  final Widget unifiedActionsBar;
  final Widget Function(double) inlineEmojiPickerBuilder;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ChatComposerShell(
        composerInset: composerInset,
        backgroundColor: backgroundColor,
        padding: EdgeInsets.only(
          left: 8 * scale,
          right: 12 * scale,
          top: 6,
          bottom: 8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            replyPreview,
            sendToManyQuickAction,
            if (!showEmojiPicker) unifiedActionsBar,
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: messageController,
              builder: (context, value, _) {
                const sendButtonColor = Color(0xFF6D28D9);
                final messageTextStyle = TextStyle(
                  color: Colors.white,
                  fontSize: 18 * scale,
                  fontFamily: 'Roboto',
                  height: 1.12,
                );
                final hasDraftText =
                    value.text.trim().isNotEmpty &&
                    !_isStampOnlyDraft(value.text);

                return RepaintBoundary(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final iconSlotWidth = 40.0 * scale;
                      final sendButtonReserve = 88.0 * scale;
                      final doorbellReserve = hasDraftText
                          ? (38.0 * scale)
                          : (100.0 * scale);
                      final estimatedTextMaxWidth = math.max(
                        120.0,
                        constraints.maxWidth -
                            sendButtonReserve -
                            iconSlotWidth -
                            doorbellReserve -
                            (28.0 * scale),
                      );

                      final isComposerExpanded = isComposerMultiline(
                        value.text,
                        messageTextStyle,
                        estimatedTextMaxWidth,
                      );

                      return Row(
                        crossAxisAlignment: isComposerExpanded
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Container(
                              constraints: BoxConstraints(
                                minHeight: 44 * scale,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E2430),
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: Row(
                                crossAxisAlignment: isComposerExpanded
                                    ? CrossAxisAlignment.end
                                    : CrossAxisAlignment.center,
                                children: [
                                  Padding(
                                    padding: EdgeInsets.only(
                                      bottom: isComposerExpanded ? 10 : 0,
                                    ),
                                    child: _buildComposerIconButton(
                                      onPressed: onShowEmojiPickerModal,
                                      icon: showEmojiPicker
                                          ? Icons.keyboard_outlined
                                          : Icons.sentiment_satisfied_alt_outlined,
                                      iconSize: 24 * scale,
                                      padding: EdgeInsets.all(6 * scale),
                                      tooltip:
                                          showEmojiPicker ? 'Keyboard' : 'Emoji',
                                    ),
                                  ),
                                  Expanded(
                                    child: Theme(
                                      data: Theme.of(context).copyWith(
                                        textSelectionTheme:
                                            const TextSelectionThemeData(
                                          cursorColor: Color(0xFF25D366),
                                          selectionHandleColor:
                                              Color(0xFF25D366),
                                          selectionColor: Color(0x6637D67A),
                                        ),
                                      ),
                                      child: Scrollbar(
                                        controller: inputScrollController,
                                        thumbVisibility: false,
                                        thickness: 3,
                                        radius: const Radius.circular(2),
                                        child: TextField(
                                          key: const ValueKey('message_input'),
                                          controller: messageController,
                                          focusNode: inputFocusNode,
                                          scrollController: inputScrollController,
                                          onTapOutside: (_) {},
                                          selectionControls:
                                              compactSelectionControls,
                                          cursorColor: const Color(0xFF25D366),
                                          cursorHeight: 26 * scale,
                                          cursorWidth: 2.6,
                                          scrollPadding: EdgeInsets.only(
                                            bottom: 220 * scale,
                                          ),
                                          style: messageTextStyle,
                                          decoration: InputDecoration(
                                            hintText: 'Type a message...',
                                            hintStyle: TextStyle(
                                              color: Colors.grey[600],
                                              fontSize: 17 * scale,
                                              fontFamily: 'Roboto',
                                              height: 1.12,
                                            ),
                                            border: InputBorder.none,
                                            filled: false,
                                            contentPadding:
                                                const EdgeInsets.only(
                                              left: 0,
                                              right: 4,
                                              top: 10,
                                              bottom: 10,
                                            ),
                                            isDense: true,
                                          ),
                                          onChanged: onTextChanged,
                                          textAlign: TextAlign.start,
                                          minLines: 1,
                                          maxLines: 6,
                                          textInputAction: TextInputAction.newline,
                                          keyboardType:
                                              TextInputType.multiline,
                                          textCapitalization:
                                              TextCapitalization.sentences,
                                          enableInteractiveSelection: true,
                                          autocorrect: true,
                                          enableSuggestions: true,
                                          stylusHandwritingEnabled: false,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: EdgeInsets.only(
                                      right: 6 * scale,
                                      bottom: isComposerExpanded ? 10 : 0,
                                    ),
                                    child: buildDoorbellComposerButton(
                                      showLabel: !hasDraftText,
                                      iconSize: 24 * scale,
                                      padding: EdgeInsets.all(6 * scale),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Container(
                            margin: EdgeInsets.only(
                              left: 6,
                              bottom: isComposerExpanded ? 10 : 0,
                            ),
                            child: ElevatedButton(
                              onPressed: onSend,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: sendButtonColor,
                                foregroundColor: Colors.white,
                                overlayColor: Colors.white
                                    .withValues(alpha: 0.22),
                                padding: EdgeInsets.symmetric(
                                  horizontal: 14 * scale,
                                  vertical: 10 * scale,
                                ),
                                minimumSize: const Size(0, 0),
                                tapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              ),
                              child: Text(
                                'Send',
                                style: TextStyle(
                                  fontSize: 13.5 * scale,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                );
              },
            ),
            if (showEmojiPicker) inlineEmojiPickerBuilder(stablePanelHeight),
          ],
        ),
      ),
    );
  }

  bool _isStampOnlyDraft(String text) {
    return text.trim().isEmpty;
  }

  Widget _buildComposerIconButton({
    required VoidCallback onPressed,
    required IconData icon,
    required double iconSize,
    required EdgeInsets padding,
    required String tooltip,
  }) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: iconSize, color: Colors.white),
      padding: padding,
      tooltip: tooltip,
    );
  }
}
