import 'package:flutter/material.dart';

/// WhatsApp/Skype-style reaction picker
/// Shows a horizontal row of emoji options above or below the message
class ReactionPicker extends StatelessWidget {
  final Function(String emoji) onReactionSelected;
  final VoidCallback onClose;

  // Common reaction emojis (matching web app)
  static const List<String> emojis = [
    '👍',
    '❤️',
    '🤣',
    '😨',
    '🥺',
    '🙏',
    '😊',
    '🔥',
    '🎉',
    '👏',
  ];

  const ReactionPicker({
    Key? key,
    required this.onReactionSelected,
    required this.onClose,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF2C2C2E),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: emojis.map((emoji) {
            return GestureDetector(
              onTap: () {
                onReactionSelected(emoji);
                onClose();
              },
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  emoji,
                  style: const TextStyle(fontSize: 28),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  /// Show the reaction picker as an overlay
  static void show({
    required BuildContext context,
    required Offset position,
    required Function(String emoji) onReactionSelected,
  }) {
    final overlay = Overlay.of(context);
    OverlayEntry? overlayEntry;
    bool isRemoved = false;

    void removeOverlay() {
      if (!isRemoved && overlayEntry != null) {
        isRemoved = true;
        overlayEntry!.remove();
        overlayEntry = null;
      }
    }

    // Calculate position to ensure picker stays on screen
    final screenSize = MediaQuery.of(context).size;
    const pickerHeight = 60.0;
    const pickerWidth = 360.0; // Reduced to fit better on mobile

    double left = position.dx - (pickerWidth / 2);
    double top = position.dy - pickerHeight - 8; // Position above by default

    // Clamp horizontal position (ensure min <= max)
    final minLeft = 8.0;
    final maxLeft = (screenSize.width - pickerWidth - 8).clamp(minLeft, screenSize.width);
    left = left.clamp(minLeft, maxLeft);

    // If not enough space above, show below
    if (top < 8) {
      top = position.dy + 8;
    }

    overlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          // Tap outside to close
          Positioned.fill(
            child: GestureDetector(
              onTap: removeOverlay,
              behavior: HitTestBehavior.translucent,
              child: Container(
                color: Colors.transparent,
              ),
            ),
          ),
          // The picker itself
          Positioned(
            left: left,
            top: top,
            child: ReactionPicker(
              onReactionSelected: (emoji) {
                onReactionSelected(emoji);
                removeOverlay();
              },
              onClose: removeOverlay,
            ),
          ),
        ],
      ),
    );

    overlay.insert(overlayEntry!);
  }
}
