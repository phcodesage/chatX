import 'package:flutter/material.dart';

/// WhatsApp/Skype-style reaction picker
/// Shows a horizontal row of quick emoji options + a "+" button to open full picker
class ReactionPicker extends StatelessWidget {
  final Function(String emoji) onReactionSelected;
  final VoidCallback onClose;
  final VoidCallback? onMorePressed;

  // Quick reaction emojis - common, well-supported emojis
  static const List<String> emojis = [
    '👍',
    '❤️',
    '😂',
    '😮',
    '😢',
    '😡',
    '🔥',
    '🎉',
  ];

  // Full emoji grid for the "+" expanded picker
  static const List<Map<String, dynamic>> emojiCategories = [
    {
      'label': 'Smileys',
      'emojis': [
        '😀', '😃', '😄', '😁', '😆', '😅', '🤣', '😂', '🙂', '😊',
        '😇', '🥰', '😍', '🤩', '😘', '😗', '😚', '😙', '🥲', '😋',
        '😛', '😜', '🤪', '😝', '🤑', '🤗', '🤭', '🤫', '🤔', '🫡',
        '🤐', '🤨', '😐', '😑', '😶', '🫥', '😏', '😒', '🙄', '😬',
        '🤥', '😌', '😔', '😪', '🤤', '😴', '😷', '🤒', '🤕', '🤢',
        '🤮', '🥵', '🥶', '🥴', '😵', '🤯', '🤠', '🥳', '🥸', '😎',
        '🤓', '🧐', '😕', '🫤', '😟', '🙁', '😮', '😯', '😲', '😳',
        '🥺', '🥹', '😦', '😧', '😨', '😰', '😥', '😢', '😭', '😱',
        '😖', '😣', '😞', '😓', '😩', '😫', '🥱', '😤', '😡', '😠',
        '🤬', '😈', '👿', '💀', '☠️', '💩', '🤡', '👹', '👺', '👻',
        '👽', '👾', '🤖', '😺', '😸', '😹', '😻', '😼', '😽', '🙀',
      ],
    },
    {
      'label': 'Gestures',
      'emojis': [
        '👍', '👎', '👊', '✊', '🤛', '🤜', '👏', '🙌', '🫶', '👐',
        '🤲', '🤝', '🙏', '✌️', '🤞', '🫰', '🤟', '🤘', '🤙', '👈',
        '👉', '👆', '🖕', '👇', '☝️', '🫵', '👋', '🤚', '🖐️', '✋',
        '🖖', '🫱', '🫲', '🫳', '🫴', '💪', '🦾', '🖖', '💅', '🤳',
      ],
    },
    {
      'label': 'Hearts',
      'emojis': [
        '❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍', '🤎', '💔',
        '❤️‍🔥', '❤️‍🩹', '❣️', '💕', '💞', '💓', '💗', '💖', '💘', '💝',
        '💟', '♥️', '💌', '💐', '🌹', '🥀', '🌺', '🌸', '🌷', '🌻',
      ],
    },
    {
      'label': 'Objects',
      'emojis': [
        '🔥', '💧', '🌟', '⭐', '✨', '💫', '🌈', '🎉', '🎊', '🎈',
        '🎁', '🎀', '🏆', '🥇', '🥈', '🥉', '💯', '💰', '💎', '🔮',
        '🎵', '🎶', '🎤', '🎸', '🎮', '🎲', '🎯', '🎳', '🎪', '🎭',
        '📱', '💻', '⌨️', '🖥️', '📷', '📸', '🔔', '🔕', '📢', '📣',
        '💡', '🔦', '🕯️', '🪔', '📖', '📚', '✏️', '🖊️', '🔑', '🗝️',
      ],
    },
    {
      'label': 'Food',
      'emojis': [
        '🍏', '🍎', '🍐', '🍊', '🍋', '🍌', '🍉', '🍇', '🍓', '🫐',
        '🍒', '🍑', '🥭', '🍍', '🥝', '🍅', '🍆', '🥑', '🌽', '🥕',
        '🍔', '🍟', '🍕', '🌭', '🥪', '🌮', '🌯', '🍣', '🍱', '🍜',
        '🍝', '🍦', '🍧', '🍨', '🎂', '🍰', '🧁', '🍩', '🍪', '🍫',
        '☕', '🍵', '🧃', '🥤', '🍺', '🍻', '🥂', '🍷', '🍸', '🍹',
      ],
    },
    {
      'label': 'Animals',
      'emojis': [
        '🐶', '🐱', '🐭', '🐹', '🐰', '🦊', '🐻', '🐼', '🐨', '🐯',
        '🦁', '🐮', '🐷', '🐸', '🐵', '🙈', '🙉', '🙊', '🐔', '🐧',
        '🐦', '🦆', '🦅', '🦉', '🐴', '🦄', '🐝', '🦋', '🐌', '🐞',
        '🐢', '🐍', '🐙', '🐬', '🐳', '🦈', '🐘', '🦒', '🦘', '🐕',
      ],
    },
  ];

  const ReactionPicker({
    Key? key,
    required this.onReactionSelected,
    required this.onClose,
    this.onMorePressed,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
          children: [
            ...emojis.map((emoji) {
              return GestureDetector(
                onTap: () {
                  onReactionSelected(emoji);
                  onClose();
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    emoji,
                    style: const TextStyle(fontSize: 22),
                  ),
                ),
              );
            }),
            // "+" button to open full emoji picker
            GestureDetector(
              onTap: () {
                onMorePressed?.call();
              },
              child: Container(
                margin: const EdgeInsets.only(left: 2),
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: const Color(0xFF4A4A4C),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.add,
                  color: Colors.white70,
                  size: 22,
                ),
              ),
            ),
          ],
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
    OverlayEntry? expandedOverlayEntry;
    bool isRemoved = false;

    void removeOverlay() {
      if (!isRemoved) {
        isRemoved = true;
        expandedOverlayEntry?.remove();
        expandedOverlayEntry = null;
        overlayEntry?.remove();
        overlayEntry = null;
      }
    }

    void showExpandedPicker() {
      // Remove the quick picker
      overlayEntry?.remove();
      overlayEntry = null;

      final screenSize = MediaQuery.of(context).size;

      expandedOverlayEntry = OverlayEntry(
        builder: (context) => Stack(
          children: [
            // Tap outside to close
            Positioned.fill(
              child: GestureDetector(
                onTap: removeOverlay,
                behavior: HitTestBehavior.translucent,
                child: Container(color: Colors.black54),
              ),
            ),
            // Expanded emoji picker centered on screen
            Center(
              child: _ExpandedReactionPicker(
                onEmojiSelected: (emoji) {
                  onReactionSelected(emoji);
                  removeOverlay();
                },
                onClose: removeOverlay,
                maxWidth: screenSize.width * 0.9,
              ),
            ),
          ],
        ),
      );

      overlay.insert(expandedOverlayEntry!);
    }

    // Calculate position to ensure picker stays on screen
    final screenSize = MediaQuery.of(context).size;
    const pickerHeight = 52.0;
    const pickerWidth = 340.0;

    double left = position.dx - (pickerWidth / 2);
    double top = position.dy - pickerHeight - 8;

    final minLeft = 8.0;
    final maxLeft = (screenSize.width - pickerWidth - 8).clamp(minLeft, screenSize.width);
    left = left.clamp(minLeft, maxLeft);

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
              child: Container(color: Colors.transparent),
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
              onMorePressed: showExpandedPicker,
            ),
          ),
        ],
      ),
    );

    overlay.insert(overlayEntry!);
  }
}

/// Expanded emoji picker with category tabs for choosing any emoji as a reaction
class _ExpandedReactionPicker extends StatefulWidget {
  final Function(String emoji) onEmojiSelected;
  final VoidCallback onClose;
  final double maxWidth;

  const _ExpandedReactionPicker({
    required this.onEmojiSelected,
    required this.onClose,
    required this.maxWidth,
  });

  @override
  State<_ExpandedReactionPicker> createState() => _ExpandedReactionPickerState();
}

class _ExpandedReactionPickerState extends State<_ExpandedReactionPicker> {
  int _selectedCategory = 0;

  @override
  Widget build(BuildContext context) {
    final categories = ReactionPicker.emojiCategories;
    final currentEmojis = categories[_selectedCategory]['emojis'] as List<String>;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: widget.maxWidth,
        height: 360,
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E2E),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  const Text(
                    'Choose a reaction',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: widget.onClose,
                    child: const Icon(Icons.close, color: Colors.white54, size: 22),
                  ),
                ],
              ),
            ),
            // Category tabs
            SizedBox(
              height: 40,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: categories.length,
                itemBuilder: (context, index) {
                  final isSelected = index == _selectedCategory;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedCategory = index),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF6D28D9) : const Color(0xFF3D3D3D),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        categories[index]['label'] as String,
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.white60,
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            // Emoji grid
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 8,
                  childAspectRatio: 1,
                ),
                itemCount: currentEmojis.length,
                itemBuilder: (context, index) {
                  return GestureDetector(
                    onTap: () => widget.onEmojiSelected(currentEmojis[index]),
                    child: Center(
                      child: Text(
                        currentEmojis[index],
                        style: const TextStyle(fontSize: 26),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
