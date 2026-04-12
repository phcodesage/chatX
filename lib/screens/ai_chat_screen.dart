import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import '../services/storage_service.dart';
import '../widgets/chat_composer_shell.dart';

class AiChatScreen extends StatefulWidget {
  final String? initialPrompt;

  const AiChatScreen({super.key, this.initialPrompt});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final List<Map<String, String>> _messages = <Map<String, String>>[];
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();

  bool _isLoading = true;
  bool _isSending = false;
  bool _showEmojiPicker = false;
  bool _showTimestamps = false;
  bool _autoCorrectionEnabled = true;

  int? _sessionId;

  static const String _showTimestampsKey = 'ai_show_timestamps';
  static const String _autoCorrectionEnabledKey = 'ai_auto_correction_enabled';

  int _emojiCategoryIndex = 0;

  static const Map<String, String> _autoCorrectionDictionary =
      <String, String>{
        'u': 'you',
        'ur': 'your',
        'pls': 'please',
        'thx': 'thanks',
        'im': "I'm",
      };

  static const List<Map<String, dynamic>> _emojiCategories = [
    {
      'icon': '😀',
      'label': 'Smileys',
      'emojis': [
        '😀', '😃', '😄', '😁', '😆', '😅', '😂', '🤣', '🥲', '😊', '😇', '🙂', '🙃', '😉', '😌', '😍', '🥰', '😘', '😗', '😙', '😚', '😋', '😛', '😝', '😜', '🤪', '🤨', '🧐', '🤓', '😎', '🥸', '🤩', '🥳', '😏', '😒', '😞', '😔', '😟', '😕', '🙁', '😣', '😖', '😫', '😩', '🥺', '😢', '😭', '😤', '😠', '😡', '🤬', '🤯', '😳', '🥵', '🥶', '😱', '😨', '😰', '😥', '😓', '🤗', '🤔', '🫣', '🤭', '🫢', '🫡', '🤫', '🫠', '🤥', '😶', '😐', '😑', '😬', '🫨', '🙄', '😯', '😦', '😧', '😮', '😲', '🥱', '😴', '🤤', '😪', '😵', '😵‍💫', '🫥', '🤐', '🥴', '🤢', '🤮', '🤧', '😷', '🤒', '🤕', '🤑', '🤠', '😈', '👿', '👹', '👺', '🤡', '💩', '👻', '💀', '☠️', '👽', '👾', '🤖', '🎃', '😺', '😸', '😹', '😻', '😼', '😽', '🙀', '😿', '😾'
      ],
    },
    {
      'icon': '👋',
      'label': 'Gestures',
      'emojis': [
        '👋', '🤚', '🖐️', '✋', '🖖', '🫱', '🫲', '🫳', '🫴', '👌', '🤌', '🤏', '✌️', '🤞', '🫰', '🤟', '🤘', '🤙', '👈', '👉', '👆', '🖕', '👇', '☝️', '🫵', '👍', '👎', '✊', '👊', '🤛', '🤜', '👏', '🙌', '🫶', '👐', '🤲', '🤝', '🙏', '✍️', '💅', '🤳', '💪', '🦾', '🦿', '🦵', '🦶', '👂', '🦻', '👃', '🧠', '🫀', '🫁', '🦷', '🦴', '👀', '👁️', '👅', '👄', '🫦', '💋'
      ],
    },
    {
      'icon': '❤️',
      'label': 'Hearts',
      'emojis': [
        '❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍', '🤎', '❤️‍🔥', '❤️‍🩹', '💔', '❣️', '💕', '💞', '💓', '💗', '💖', '💘', '💝', '💟', '♥️', '🩷', '🩵', '🩶', '💌', '💐', '🌹', '🥀', '🌺', '🌸', '🌷', '🌻', '💑', '👩‍❤️‍👨', '👨‍❤️‍👨', '👩‍❤️‍👩', '💏', '😍', '🥰', '😘', '😻', '💒', '🏩'
      ],
    },
    {
      'icon': '🐱',
      'label': 'Animals',
      'emojis': [
        '🐶', '🐱', '🐭', '🐹', '🐰', '🦊', '🐻', '🐼', '🐻‍❄️', '🐨', '🐯', '🦁', '🐮', '🐷', '🐸', '🐵', '🙈', '🙉', '🙊', '🐒', '🐔', '🐧', '🐦', '🐤', '🐣', '🐥', '🦆', '🦅', '🦉', '🦇', '🐺', '🐗', '🐴', '🦄', '🐝', '🪱', '🐛', '🦋', '🐌', '🐞', '🐜', '🪰', '🪲', '🪳', '🦟', '🦗', '🕷️', '🦂', '🐢', '🐍', '🦎', '🦖', '🦕', '🐙', '🦑', '🦐', '🦞', '🦀', '🐡', '🐠', '🐟', '🐬', '🐳', '🐋', '🦈', '🦭', '🐊', '🐅', '🐆', '🦓', '🦍', '🦧', '🐘', '🦛', '🦏', '🐪', '🐫', '🦒', '🦘', '🦬'
      ],
    },
    {
      'icon': '🍕',
      'label': 'Food',
      'emojis': [
        '🍏', '🍎', '🍐', '🍊', '🍋', '🍌', '🍉', '🍇', '🍓', '🫐', '🍈', '🍒', '🍑', '🥭', '🍍', '🥥', '🥝', '🍅', '🍆', '🥑', '🥦', '🥬', '🥒', '🌶️', '🫑', '🌽', '🥕', '🫒', '🧄', '🧅', '🥔', '🍠', '🥐', '🥯', '🍞', '🥖', '🥨', '🧀', '🥚', '🍳', '🧈', '🥞', '🧇', '🥓', '🥩', '🍗', '🍖', '🌭', '🍔', '🍟', '🍕', '🫓', '🥪', '🥙', '🧆', '🌮', '🌯', '🫔', '🥗', '🥘', '🫕', '🍝', '🍜', '🍲', '🍛', '🍣', '🍱', '🥟', '🦪', '🍤', '🍙', '🍚', '🍘', '🍥', '🥠', '🥮', '🍢', '🍡', '🍧', '🍨', '🍦', '🥧', '🧁', '🍰', '🎂', '🍮', '🍭', '🍬', '🍫', '🍩', '🍪', '🌰', '🥜', '🍯', '🥛', '🍼', '☕', '🍵', '🧃', '🥤', '🧋', '🍶', '🍺', '🍻', '🥂', '🍷', '🥃', '🍸', '🍹', '🧉'
      ],
    },
    {
      'icon': '⚽',
      'label': 'Activities',
      'emojis': [
        '⚽', '🏀', '🏈', '⚾', '🥎', '🎾', '🏐', '🏉', '🥏', '🎱', '🪀', '🏓', '🏸', '🏒', '🏑', '🥍', '🏏', '🪃', '🥅', '⛳', '🪁', '🏹', '🎣', '🤿', '🥊', '🥋', '🎽', '🛹', '🛼', '🛷', '⛸️', '🥌', '🎿', '⛷️', '🏂', '🪂', '🏋️', '🤼', '🤸', '🤺', '⛹️', '🤾', '🏌️', '🏇', '🧘', '🏄', '🏊', '🤽', '🚣', '🧗', '🚵', '🚴', '🏆', '🥇', '🥈', '🥉', '🏅', '🎖️', '🏵️', '🎗️', '🎪', '🤹', '🎭', '🩰', '🎨', '🎬', '🎤', '🎧', '🎼', '🎹', '🥁', '🪘', '🎷', '🎺', '🪗', '🎸', '🪕', '🎻', '🎲', '♟️', '🎯', '🎳', '🎮', '🕹️', '🧩'
      ],
    },
    {
      'icon': '🚗',
      'label': 'Travel',
      'emojis': [
        '🚗', '🚕', '🚙', '🚌', '🚎', '🏎️', '🚓', '🚑', '🚒', '🚐', '🛻', '🚚', '🚛', '🚜', '🏍️', '🛵', '🚲', '🛴', '🛺', '🚔', '🚍', '🚘', '🚖', '🛞', '🚡', '🚠', '🚟', '🚃', '🚋', '🚞', '🚝', '🚄', '🚅', '🚈', '🚂', '🚆', '🚇', '🚊', '🚉', '✈️', '🛫', '🛬', '🛩️', '💺', '🛰️', '🚀', '🛸', '🚁', '🛶', '⛵', '🚤', '🛥️', '🛳️', '⛴️', '🚢', '🗼', '🏰', '🏯', '🏟️', '🎡', '🎢', '🎠', '⛲', '⛱️', '🏖️', '🏝️', '🏜️', '🌋', '⛰️', '🏔️', '🗻', '🏕️', '🛖', '🏠', '🏡', '🏢', '🏬', '🏣', '🏤', '🏥'
      ],
    },
    {
      'icon': '💡',
      'label': 'Objects',
      'emojis': [
        '🔥', '💧', '🌟', '⭐', '✨', '💫', '🌈', '☀️', '🌤️', '⛅', '🎉', '🎊', '🎈', '🎁', '🎀', '🎄', '🪅', '🎆', '🎇', '🧨', '💡', '🔦', '🕯️', '🪔', '💎', '🔮', '🧿', '🪬', '💰', '💴', '💵', '💶', '💷', '🪙', '💳', '💸', '🧲', '🔧', '🪛', '🔩', '⚙️', '🧰', '🪜', '🧱', '🪨', '🪵', '🔗', '🧬', '🔬', '🔭', '📡', '💉', '🩸', '💊', '🩹', '🩼', '🩺', '🩻', '🚪', '🛗', '🪞', '🪟', '🛏️', '🛋️', '🪑', '🚽', '🪠', '🚿', '🛁', '🪤', '📱', '💻', '⌨️', '🖥️', '🖨️', '🖱️', '💾', '💿', '📀', '📷', '📸', '📹', '🎥', '📽️', '🎞️', '📞', '☎️', '📟', '📠', '📺', '📻', '🎙️', '🎚️', '🎛️', '🧭', '⏱️', '⏲️', '⏰', '🕰️', '📡'
      ],
    },
    {
      'icon': '🏁',
      'label': 'Symbols',
      'emojis': [
        '🏳️', '🏴', '🏁', '🚩', '🏳️‍🌈', '🏳️‍⚧️', '🏴‍☠️', '✅', '❌', '❓', '❗', '‼️', '⁉️', '💯', '🔴', '🟠', '🟡', '🟢', '🔵', '🟣', '⚫', '⚪', '🟤', '🔶', '🔷', '🔸', '🔹', '🔺', '🔻', '💠', '🔘', '🔳', '🔲', '▪️', '▫️', '◾', '◽', '◼️', '◻️', '🟥', '🟧', '🟨', '🟩', '🟦', '🟪', '⬛', '⬜', '🟫', '♈', '♉', '♊', '♋', '♌', '♍', '♎', '♏', '♐', '♑', '♒', '♓', '⛎', '🔀', '🔁', '🔂', '▶️', '⏩', '⏭️', '⏯️', '◀️', '⏪', '⏮️', '🔼', '⏫', '🔽', '⏬', '⏸️', '⏹️', '⏺️', '⏏️', '🎦', '♾️', '♻️', '⚜️', '🔱', '📛', '🔰', '⭕', '✅', '☑️', '✔️', '❌', '❎', '➕', '➖', '➗', '✖️', '💲', '💱', '™️', '©️', '®️', '〰️', '➰', '➿', '🔚', '🔙', '🔛', '🔝', '🔜', '🆕'
      ],
    },
  ];

  static const Map<String, String> _emojiCompatibilityFallbacks = {
    '🩷': '💗',
    '🩵': '💙',
    '🩶': '🤍',
    '🫶': '🤝',
    '🫵': '👉',
    '🫱': '👈',
    '🫲': '👉',
    '🫳': '👇',
    '🫴': '🖐️',
    '🫰': '👌',
    '🫠': '🙂',
    '🫡': '👍',
    '🫣': '🙈',
    '🫢': '🤐',
    '🫥': '😶',
    '🫨': '😲',
    '🫦': '💋',
    '🫀': '❤️',
    '🫁': '💨',
    '🩻': '🦴',
    '🩼': '🦯',
  };

  bool _isPotentiallyUnsupportedEmoji(String emoji) {
    for (final rune in emoji.runes) {
      if (rune >= 0x1FA70 && rune <= 0x1FAFF) {
        return true;
      }
    }
    return false;
  }

  String _normalizeEmojiForCompatibility(String emoji) {
    final mapped = _emojiCompatibilityFallbacks[emoji];
    if (mapped != null) {
      return mapped;
    }

    if (_isPotentiallyUnsupportedEmoji(emoji)) {
      return '';
    }

    return emoji;
  }

  List<String> _normalizedEmojiList(List<String> emojis) {
    final normalized = <String>[];
    final seen = <String>{};

    for (final emoji in emojis) {
      final safeEmoji = _normalizeEmojiForCompatibility(emoji);
      if (safeEmoji.isEmpty) {
        continue;
      }

      if (seen.add(safeEmoji)) {
        normalized.add(safeEmoji);
      }
    }

    return normalized;
  }

  String get _baseUrl {
    final raw = ApiConfig.baseUrl.trim();
    if (raw.endsWith('/')) {
      return raw.substring(0, raw.length - 1);
    }
    return raw;
  }

  Uri _aiUri(String path) => Uri.parse('$_baseUrl/api/ai$path');

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    await _loadUiPreferences();
    await _initializeAiSession();
  }

  Future<void> _loadUiPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _showTimestamps = prefs.getBool(_showTimestampsKey) ?? false;
      _autoCorrectionEnabled = prefs.getBool(_autoCorrectionEnabledKey) ?? true;
    });
  }

  Future<void> _initializeAiSession() async {
    try {
      final token = await StorageService.getToken();
      if (token == null || token.isEmpty) {
        throw Exception('No auth token found');
      }

      final userId = await StorageService.getUserId() ?? 0;
      final prefs = await SharedPreferences.getInstance();
      final sessionKey = 'ai_session_id_$userId';
      final savedSessionId = prefs.getInt(sessionKey);

      if (savedSessionId != null) {
        final loaded = await _loadMessages(token, savedSessionId);
        if (loaded) {
          _sessionId = savedSessionId;
        }
      }

      if (_sessionId == null) {
        _sessionId = await _createSession(token);
        if (_sessionId != null) {
          await prefs.setInt(sessionKey, _sessionId!);
        }
      }

      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });

      final initialPrompt = widget.initialPrompt?.trim();
      if (initialPrompt != null && initialPrompt.isNotEmpty) {
        _messageController.text = initialPrompt;
        await _sendMessage();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      _showError('Failed to initialize AI chat: $e');
    }
  }

  Future<bool> _loadMessages(String token, int sessionId) async {
    try {
      final response = await http
          .get(
            _aiUri('/sessions/$sessionId/messages'),
            headers: <String, String>{
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(ApiConfig.connectionTimeout);

      if (response.statusCode != 200) {
        return false;
      }

      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final rawMessages = (payload['messages'] as List<dynamic>? ?? <dynamic>[]);

      final parsed = rawMessages
          .map((m) => m as Map<String, dynamic>)
          .where(
            (m) =>
                (m['role'] == 'user' || m['role'] == 'assistant') &&
                (m['content']?.toString().trim().isNotEmpty ?? false),
          )
          .map(
            (m) => <String, String>{
              'role': m['role'].toString(),
              'content': m['content'].toString(),
              'timestamp': (m['created_at'] ?? m['timestamp'] ?? '')
                  .toString(),
            },
          )
          .toList();

      if (!mounted) return true;
      setState(() {
        _messages
          ..clear()
          ..addAll(parsed);
      });
      _scrollToBottom();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<int?> _createSession(String token) async {
    try {
      final response = await http
          .post(
            _aiUri('/sessions'),
            headers: <String, String>{
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode(<String, dynamic>{'title': 'AI Chat'}),
          )
          .timeout(ApiConfig.connectionTimeout);

      if (response.statusCode != 200 && response.statusCode != 201) {
        return null;
      }

      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final session = payload['session'] as Map<String, dynamic>?;
      final id = session?['id'] ?? payload['id'];
      return id is int ? id : int.tryParse(id?.toString() ?? '');
    } catch (_) {
      return null;
    }
  }

  String _applyAutoCorrection(String input) {
    if (!_autoCorrectionEnabled) {
      return input;
    }

    final words = input.split(RegExp(r'\s+'));
    return words.map((word) {
      final lowered = word.toLowerCase();
      final corrected = _autoCorrectionDictionary[lowered];
      return corrected ?? word;
    }).join(' ');
  }

  Future<void> _sendMessage() async {
    final rawContent = _messageController.text.trim();
    await _sendRawMessage(rawContent);
  }

  Future<void> _sendRawMessage(String rawContent) async {
    if (_isSending) return;

    if (rawContent.isEmpty) return;
    final content = _applyAutoCorrection(rawContent);

    final token = await StorageService.getToken();
    if (token == null || token.isEmpty) {
      _showError('You are not authenticated. Please sign in again.');
      return;
    }

    final sessionId = _sessionId;
    if (sessionId == null) {
      _showError('AI session not ready yet. Please try again.');
      return;
    }

    if (_showEmojiPicker) {
      setState(() {
        _showEmojiPicker = false;
      });
    }

    setState(() {
      _isSending = true;
      _messages.add(<String, String>{
        'role': 'user',
        'content': content,
        'timestamp': DateTime.now().toIso8601String(),
      });
      _messageController.clear();
    });
    _scrollToBottom();

    try {
      final response = await http
          .post(
            _aiUri('/sessions/$sessionId/chat'),
            headers: <String, String>{
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode(<String, dynamic>{'content': content}),
          )
          .timeout(ApiConfig.connectionTimeout);

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final reply = payload['response']?.toString().trim();
      if (reply != null && reply.isNotEmpty) {
        if (!mounted) return;
        setState(() {
          _messages.add(<String, String>{
            'role': 'assistant',
            'content': reply,
            'timestamp': DateTime.now().toIso8601String(),
          });
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(<String, String>{
          'role': 'assistant',
          'content': 'Sorry, I could not respond right now. ($e)',
          'timestamp': DateTime.now().toIso8601String(),
        });
      });
      _scrollToBottom();
    } finally {
      if (!mounted) return;
      setState(() {
        _isSending = false;
      });
    }
  }

  Future<void> _toggleTimestamps() async {
    final next = !_showTimestamps;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showTimestampsKey, next);
    if (!mounted) return;
    setState(() {
      _showTimestamps = next;
    });
  }

  Future<void> _toggleAutoCorrection() async {
    final next = !_autoCorrectionEnabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoCorrectionEnabledKey, next);
    if (!mounted) return;
    setState(() {
      _autoCorrectionEnabled = next;
    });
    _showInfo(
      next
          ? 'Auto-correction enabled for AI input'
          : 'Auto-correction disabled for AI input',
    );
  }

  Future<void> _exportChat() async {
    if (_messages.isEmpty) {
      _showInfo('No AI messages to export yet.');
      return;
    }

    final transcript = _messages.map((m) {
      final role = m['role'] == 'user' ? 'You' : 'AI';
      final ts = _formatTimestamp(m['timestamp']);
      return '[$ts] $role: ${m['content'] ?? ''}';
    }).join('\n\n');

    await Clipboard.setData(ClipboardData(text: transcript));
    _showInfo('AI chat copied to clipboard.');
  }

  Future<void> _deleteMessages() async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete AI chat messages?'),
          content: const Text(
            'This will clear your AI conversation history for this session.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true) return;

    final token = await StorageService.getToken();
    final sessionId = _sessionId;
    if (token == null || token.isEmpty || sessionId == null) {
      setState(() {
        _messages.clear();
      });
      return;
    }

    try {
      await http
          .delete(
            _aiUri('/sessions/$sessionId'),
            headers: <String, String>{
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(ApiConfig.connectionTimeout);

      final newSessionId = await _createSession(token);
      final userId = await StorageService.getUserId() ?? 0;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('ai_session_id_$userId', newSessionId ?? sessionId);

      if (!mounted) return;
      setState(() {
        _sessionId = newSessionId;
        _messages.clear();
      });
      _showInfo('AI chat cleared.');
    } catch (e) {
      _showError('Failed to clear AI chat: $e');
    }
  }

  void _onRingDoorbell() {
    _showInfo('Ring doorbell UI is shown in AI chat, action is disabled.');
  }

  void _insertEmoji(String emoji) {
    final current = _messageController.text;
    final selection = _messageController.selection;
    final start = selection.start < 0 ? current.length : selection.start;
    final end = selection.end < 0 ? current.length : selection.end;
    final updated = current.replaceRange(start, end, emoji);

    _messageController.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
      ),
    );
  }

  void _showInfo(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF252542),
      ),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  String _formatTimestamp(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    try {
      final dt = DateTime.parse(raw).toLocal();
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m';
    } catch (_) {
      return '';
    }
  }

  Widget _buildMessageBubble(Map<String, String> message) {
    final isUser = message['role'] == 'user';
    final timestamp = _formatTimestamp(message['timestamp']);

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        constraints: const BoxConstraints(maxWidth: 340),
        child: Column(
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isUser ? const Color(0xFF00D9FF) : const Color(0xFF252542),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                message['content'] ?? '',
                style: TextStyle(
                  color: isUser ? Colors.black87 : Colors.white,
                  height: 1.35,
                ),
              ),
            ),
            if (_showTimestamps && timestamp.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
                child: Text(
                  timestamp,
                  style: TextStyle(color: Colors.grey[500], fontSize: 11),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildThinkingBubble() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF252542),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _ThinkingDots(),
            SizedBox(width: 8),
            Text(
              'AI is thinking...',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComposerIconButton({
    required VoidCallback onPressed,
    required IconData icon,
    required double iconSize,
    required EdgeInsetsGeometry padding,
    required String tooltip,
    Color color = Colors.white70,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkResponse(
          onTap: onPressed,
          containedInkWell: true,
          highlightShape: BoxShape.circle,
          radius: iconSize * 0.9,
          splashColor: Colors.white.withOpacity(0.22),
          highlightColor: Colors.white.withOpacity(0.14),
          child: Padding(
            padding: padding,
            child: Icon(icon, color: color, size: iconSize),
          ),
        ),
      ),
    );
  }

  Widget _buildDoorbellComposerButton({required bool showLabel}) {
    const doorbellColor = Colors.white;

    if (!showLabel) {
      return Tooltip(
        message: 'Ring Doorbell',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _onRingDoorbell,
            borderRadius: BorderRadius.circular(999),
            splashColor: Colors.white.withOpacity(0.20),
            highlightColor: Colors.white.withOpacity(0.10),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                color: doorbellColor,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.notifications_active_outlined,
                color: Colors.black,
                size: 22,
              ),
            ),
          ),
        ),
      );
    }

    return Tooltip(
      message: 'Ring Doorbell',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _onRingDoorbell,
          borderRadius: BorderRadius.circular(999),
          splashColor: Colors.white.withOpacity(0.20),
          highlightColor: Colors.white.withOpacity(0.10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: doorbellColor,
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Text(
              'Ring Doorbell',
              style: TextStyle(
                color: Colors.black,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompressedActionChip({
    required String label,
    required Color backgroundColor,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          alignment: Alignment.center,
          constraints: const BoxConstraints(minHeight: 34),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              height: 1.05,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTwoRowActions(List<Widget> allButtons) {
    final splitIndex = (allButtons.length / 2).ceil();
    final topRow = allButtons.take(splitIndex).toList();
    final bottomRow = allButtons.skip(splitIndex).toList();

    Widget buildFittedRow(List<Widget> rowButtons) {
      if (rowButtons.isEmpty) return const SizedBox.shrink();

      return LayoutBuilder(
        builder: (context, constraints) {
          const gap = 4.0;
          final totalGap = gap * (rowButtons.length - 1);
          final itemWidth = math.max(
            58.0,
            (constraints.maxWidth - totalGap) / rowButtons.length,
          );

          return Wrap(
            spacing: gap,
            runSpacing: 0,
            children: rowButtons
                .map((button) => SizedBox(width: itemWidth, child: button))
                .toList(),
          );
        },
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildFittedRow(topRow),
        if (bottomRow.isNotEmpty) const SizedBox(height: 4),
        if (bottomRow.isNotEmpty) buildFittedRow(bottomRow),
      ],
    );
  }

  Widget _buildUnifiedActionsBar() {
    final allButtons = <Widget>[
      _buildCompressedActionChip(
        label: 'Auto Correction',
        backgroundColor: const Color(0xFFF59E0B),
        onPressed: _toggleAutoCorrection,
      ),
      _buildCompressedActionChip(
        label: 'Export Chat',
        backgroundColor: const Color(0xFF475569),
        onPressed: _exportChat,
      ),
      _buildCompressedActionChip(
        label: _showTimestamps ? 'Hide\nTimestamps' : 'Show\nTimestamps',
        backgroundColor: _showTimestamps
            ? const Color(0xFF4338CA)
            : const Color(0xFF6366F1),
        onPressed: _toggleTimestamps,
      ),
      _buildCompressedActionChip(
        label: 'Delete Messages',
        backgroundColor: const Color(0xFFDC2626),
        onPressed: _deleteMessages,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Transform.translate(
        offset: const Offset(-2, 0),
        child: Align(
          alignment: Alignment.centerLeft,
          child: _buildTwoRowActions(allButtons),
        ),
      ),
    );
  }

  Widget _buildEmojiPanel() {
    final category = _emojiCategories[_emojiCategoryIndex];
    final emojis = _normalizedEmojiList(category['emojis'] as List<String>);

    return Container(
      height: 230,
      decoration: BoxDecoration(
        color: const Color(0xFF3D3D3D),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 44,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              itemCount: _emojiCategories.length,
              itemBuilder: (context, index) {
                final cat = _emojiCategories[index];
                final icon = _normalizeEmojiForCompatibility(
                  cat['icon'] as String,
                );
                final isSelected = index == _emojiCategoryIndex;

                return GestureDetector(
                  onTap: () => setState(() => _emojiCategoryIndex = index),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF6D28D9)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        icon.isEmpty ? '🙂' : icon,
                        style: const TextStyle(fontSize: 20),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 8,
                childAspectRatio: 1,
              ),
              itemCount: emojis.length,
              itemBuilder: (context, index) {
                return GestureDetector(
                  onTap: () => _insertEmoji(emojis[index]),
                  child: Center(
                    child: Text(
                      emojis[index],
                      style: const TextStyle(fontSize: 24),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComposer() {
    const sendButtonColor = Color(0xFF6D28D9);

    return ChatComposerShell(
      composerInset: 0,
      backgroundColor: const Color(0xFF1A1A2E),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (!_showEmojiPicker) _buildUnifiedActionsBar(),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _messageController,
            builder: (context, value, _) {
              final hasDraftText = value.text.trim().isNotEmpty;
              final textStyle = const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontFamily: 'Roboto',
                height: 1.12,
              );

              return LayoutBuilder(
                builder: (context, constraints) {
                  final estimatedTextMaxWidth = math.max(
                    120.0,
                    constraints.maxWidth - 88.0 - 40.0 - 100.0 - 28.0,
                  );

                  final isComposerExpanded = _isComposerMultiline(
                    value.text,
                    textStyle,
                    estimatedTextMaxWidth,
                  );

                  return Row(
                    crossAxisAlignment: isComposerExpanded
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.center,
                    children: <Widget>[
                      Expanded(
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 44),
                          decoration: BoxDecoration(
                            color: const Color(0xFF4D4D4D),
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
                                  onPressed: () {
                                    setState(() {
                                      _showEmojiPicker = !_showEmojiPicker;
                                    });
                                    if (_showEmojiPicker) {
                                      _inputFocusNode.unfocus();
                                    } else {
                                      _inputFocusNode.requestFocus();
                                    }
                                  },
                                  icon: _showEmojiPicker
                                      ? Icons.keyboard_outlined
                                      : Icons.sentiment_satisfied_alt_outlined,
                                  iconSize: 24,
                                  padding: const EdgeInsets.all(6),
                                  tooltip: _showEmojiPicker
                                      ? 'Keyboard'
                                      : 'Emoji',
                                ),
                              ),
                              Expanded(
                                child: TextField(
                                  controller: _messageController,
                                  focusNode: _inputFocusNode,
                                  enabled: !_isLoading && !_isSending,
                                  style: textStyle,
                                  minLines: 1,
                                  maxLines: 6,
                                  textInputAction: TextInputAction.newline,
                                  keyboardType: TextInputType.multiline,
                                  textCapitalization:
                                      TextCapitalization.sentences,
                                  autocorrect: true,
                                  enableSuggestions: true,
                                  decoration: InputDecoration(
                                    hintText: 'Type a message...',
                                    hintStyle: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 17,
                                      fontFamily: 'Roboto',
                                      height: 1.12,
                                    ),
                                    border: InputBorder.none,
                                    filled: false,
                                    contentPadding: const EdgeInsets.only(
                                      left: 0,
                                      right: 4,
                                      top: 10,
                                      bottom: 10,
                                    ),
                                    isDense: true,
                                  ),
                                ),
                              ),
                              Padding(
                                padding: EdgeInsets.only(
                                  right: 6,
                                  bottom: isComposerExpanded ? 10 : 0,
                                ),
                                child: _buildDoorbellComposerButton(
                                  showLabel: !hasDraftText,
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
                          onPressed: (_isLoading || _isSending)
                              ? null
                              : _sendMessage,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: sendButtonColor,
                            foregroundColor: Colors.white,
                            overlayColor: Colors.white.withOpacity(0.22),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            minimumSize: const Size(0, 0),
                            tapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                          child: _isSending
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Send',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
          if (_showEmojiPicker) _buildEmojiPanel(),
        ],
      ),
    );
  }

  bool _isComposerMultiline(
    String text,
    TextStyle style,
    double maxWidth,
  ) {
    if (text.isEmpty) return false;

    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 6,
    )..layout(maxWidth: maxWidth);

    return painter.computeLineMetrics().length > 1;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        elevation: 0,
        title: const Row(
          children: <Widget>[
            Icon(Icons.auto_awesome, color: Color(0xFF00D9FF)),
            SizedBox(width: 8),
            Text('Ask AI'),
          ],
        ),
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF00D9FF)),
                  )
                : _messages.isEmpty
                ? Center(
                    child: Text(
                      'Start a conversation with AI',
                      style: TextStyle(color: Colors.grey[400]),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    itemCount: _messages.length + (_isSending ? 1 : 0),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemBuilder: (context, index) {
                      if (_isSending && index == _messages.length) {
                        return _buildThinkingBubble();
                      }
                      return _buildMessageBubble(_messages[index]);
                    },
                  ),
          ),
          _buildComposer(),
        ],
      ),
    );
  }
}

class _ThinkingDots extends StatefulWidget {
  const _ThinkingDots();

  @override
  State<_ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<_ThinkingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;

        double opacityFor(int index) {
          final shifted = (t - (index * 0.18)) % 1.0;
          final pulse = 1.0 - ((shifted - 0.5).abs() * 2);
          return 0.25 + (pulse.clamp(0.0, 1.0) * 0.75);
        }

        Widget dot(int index) {
          return Opacity(
            opacity: opacityFor(index),
            child: Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: Color(0xFF00D9FF),
                shape: BoxShape.circle,
              ),
            ),
          );
        }

        return Row(
          children: <Widget>[
            dot(0),
            const SizedBox(width: 4),
            dot(1),
            const SizedBox(width: 4),
            dot(2),
          ],
        );
      },
    );
  }
}
