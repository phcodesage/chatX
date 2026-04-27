import 'package:flutter/material.dart';

class ChatMessageItem extends StatelessWidget {
  const ChatMessageItem({
    super.key,
    required this.content,
    required this.messageKey,
    this.dateSeparator,
  });

  final Widget content;
  final Key messageKey;
  final Widget? dateSeparator;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        dateSeparator ?? const SizedBox.shrink(),
        SizedBox(
          key: messageKey,
          child: content,
        ),
      ],
    );
  }
}
