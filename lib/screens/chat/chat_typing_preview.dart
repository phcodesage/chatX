import 'package:flutter/material.dart';

class ChatTypingPreviewBubble extends StatelessWidget {
  const ChatTypingPreviewBubble({
    super.key,
    required this.scale,
    required this.otherUserName,
    required this.typingPreview,
  });

  final double scale;
  final String otherUserName;
  final String typingPreview;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: 16 * scale,
          vertical: 10 * scale,
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFFA32CC4),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          '$otherUserName: $typingPreview',
          style: TextStyle(color: Colors.white, fontSize: 15 * scale),
        ),
      ),
    );
  }
}
