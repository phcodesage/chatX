import 'package:flutter/material.dart';

/// WhatsApp/Skype-style reaction picker
/// Shows a horizontal row of quick emoji options + a "+" button to open full picker
class ReactionPicker extends StatefulWidget {
  final Function(String emoji) onReactionSelected;
  final VoidCallback onClose;
  final VoidCallback? onMorePressed;

  // Default quick reaction emojis (10 total, scrollable)
  static const List<String> _defaultEmojis = [
    '👍',
    '💗',
    '😂',
    '😢',
    '🔥',
    '🎉',
    '😍',
    '😮',
    '😡',
    '🙏',
  ];
  
  // Custom emoji picked from expanded picker (replaces first position)
  static String? _customFirstEmoji;
  
  // Get the current emojis list with custom emoji at first position if set
  static List<String> get emojis {
    if (_customFirstEmoji != null && !_defaultEmojis.contains(_customFirstEmoji)) {
      return [_customFirstEmoji!, ..._defaultEmojis.take(9)];
    }
    return _defaultEmojis;
  }
  
  // Set custom emoji at first position
  static void setCustomFirstEmoji(String emoji) {
    _customFirstEmoji = emoji;
  }

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
  State<ReactionPicker> createState() => _ReactionPickerState();

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
        builder: (context) => Material(
          type: MaterialType.transparency,
          child: Stack(
            fit: StackFit.expand,
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
                    // Add the picked emoji to quick reactions (first position)
                    ReactionPicker.setCustomFirstEmoji(emoji);
                    onReactionSelected(emoji);
                    removeOverlay();
                  },
                  onClose: removeOverlay,
                  maxWidth: screenSize.width * 0.9,
                ),
              ),
            ],
          ),
        ),
      );

      overlay.insert(expandedOverlayEntry!);
    }

    // Calculate position to ensure picker stays on screen (full width)
    const pickerHeight = 52.0;
    const spacing = 12.0; // Space between picker and message
    
    // Position above the message bubble
    double left = 0; // Full width
    double top = position.dy - pickerHeight - spacing;
    
    // Ensure it stays on screen (with safe area consideration)
    if (top < MediaQuery.of(context).padding.top + 8) {
      // Not enough space above, position below instead
      top = position.dy + spacing;
    }
    
    overlayEntry = OverlayEntry(
      builder: (context) => Material(
        type: MaterialType.transparency,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Tap outside to close
            Positioned.fill(
              child: GestureDetector(
                onTap: removeOverlay,
                behavior: HitTestBehavior.translucent,
                child: Container(color: Colors.transparent),
              ),
            ),
            // The picker itself (full width)
            Positioned(
              left: left,
              top: top,
              right: 0,
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
      ),
    );

    overlay.insert(overlayEntry!);
  }
}

class _ReactionPickerState extends State<ReactionPicker> {
  final Map<int, double> _emojiTapScales = {};

  void _onEmojiTapDown(int index) {
    setState(() => _emojiTapScales[index] = 1.4);
  }

  void _onEmojiTapUp(int index) {
    setState(() => _emojiTapScales[index] = 1.0);
  }

  void _onEmojiTapCancel(int index) {
    setState(() => _emojiTapScales[index] = 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final emojis = ReactionPicker.emojis;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: screenWidth,
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
          children: [
            // Scrollable emoji list (takes remaining space)
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ...emojis.asMap().entries.map((entry) {
                      final index = entry.key;
                      final emoji = entry.value;
                      final tapScale = _emojiTapScales[index] ?? 1.0;

                      return Transform.scale(
                        scale: tapScale,
                        child: GestureDetector(
                          onTapDown: (_) => _onEmojiTapDown(index),
                          onTapUp: (_) => _onEmojiTapUp(index),
                          onTapCancel: () => _onEmojiTapCancel(index),
                          onTap: () {
                            widget.onReactionSelected(emoji);
                            widget.onClose();
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
                              style: const TextStyle(fontSize: 24),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
            // Fixed "+" button on the right
            GestureDetector(
              onTap: () {
                widget.onMorePressed?.call();
              },
              child: Container(
                margin: const EdgeInsets.only(left: 8),
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

  void _selectCategory(int index) {
    if (index == _selectedCategory) return;
    setState(() {
      _selectedCategory = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final categories = ReactionPicker.emojiCategories;
    final currentEmojis =
        categories[_selectedCategory]['emojis'] as List<String>;

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
              height: 34,
              child: ShaderMask(
                shaderCallback: (Rect bounds) {
                  return const LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [Colors.white, Colors.white, Colors.white, Colors.transparent],
                    stops: [0.0, 0.85, 0.92, 1.0],
                  ).createShader(bounds);
                },
                blendMode: BlendMode.dstIn,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: categories.length,
                  itemBuilder: (context, index) {
                    final isSelected = index == _selectedCategory;
                    return GestureDetector(
                      onTap: () => _selectCategory(index),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFF6D28D9) : const Color(0xFF3D3D3D),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Center(
                          child: Text(
                            categories[index]['label'] as String,
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.white60,
                              fontSize: 12,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Emoji grid (no animation)
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
