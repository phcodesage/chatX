import 'package:flutter/material.dart';

class SwipeableMessage extends StatefulWidget {
  const SwipeableMessage({
    super.key,
    required this.isSentByMe,
    required this.onReply,
    required this.child,
  });

  final bool isSentByMe;
  final VoidCallback onReply;
  final Widget child;

  @override
  State<SwipeableMessage> createState() => _SwipeableMessageState();
}

class _SwipeableMessageState extends State<SwipeableMessage> {
  static const double _maxSlide = 70.0;
  static const double _threshold = 50.0;

  double _dragOffset = 0.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (details) {
        setState(() {
          if (widget.isSentByMe) {
            _dragOffset = (_dragOffset + details.delta.dx).clamp(
              -_maxSlide,
              0.0,
            );
          } else {
            _dragOffset = (_dragOffset + details.delta.dx).clamp(
              0.0,
              _maxSlide,
            );
          }
        });
      },
      onHorizontalDragEnd: (details) {
        if (_dragOffset.abs() > _threshold) {
          widget.onReply();
        }
        setState(() {
          _dragOffset = 0.0;
        });
      },
      child: Transform.translate(
        offset: Offset(_dragOffset, 0),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (_dragOffset.abs() > 10)
              Positioned(
                left: widget.isSentByMe ? -35 : null,
                right: widget.isSentByMe ? null : -35,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Opacity(
                    opacity: (_dragOffset.abs() / _maxSlide).clamp(0.0, 1.0),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF7C3AED).withValues(alpha: 0.9),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.reply,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ),
            widget.child,
          ],
        ),
      ),
    );
  }
}
