import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import '../services/storage_service.dart';
import '../widgets/reaction_picker.dart';
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
  final Map<int, Map<String, Set<String>>> _messageReactions =
      <int, Map<String, Set<String>>>{};
  OverlayEntry? _topActionBannerEntry;
  Timer? _topActionBannerTimer;

  bool _isLoading = true;
  bool _isSending = false;
  bool _showEmojiPicker = false;
  bool _showTimestamps = false;
  bool _autoCorrectionEnabled = true;
  bool _isAtBottom = true;
  bool _hasStreamingAssistant = false;

  int? _sessionId;
  int? _currentUserId;
  int _nextLocalMessageId = 1;

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
    _scrollController.addListener(_handleScrollPosition);
    _initialize();
  }

  @override
  void dispose() {
    _dismissTopActionBanner();
    _scrollController.removeListener(_handleScrollPosition);
    _messageController.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  void _handleScrollPosition() {
    if (!_scrollController.hasClients) return;
    const bottomThreshold = 24.0;
    final distanceFromBottom =
        _scrollController.position.maxScrollExtent - _scrollController.offset;
    final atBottom = distanceFromBottom <= bottomThreshold;
    if (_isAtBottom != atBottom && mounted) {
      setState(() {
        _isAtBottom = atBottom;
      });
    }
  }

  Future<void> _initialize() async {
    _currentUserId = await StorageService.getUserId();
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
              'id': (m['id'] ?? m['message_id'] ?? '').toString(),
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

    final userLocalId = '-${_nextLocalMessageId++}';

    setState(() {
      _isSending = true;
      _hasStreamingAssistant = false;
      _messages.add(<String, String>{
        'id': userLocalId,
        'role': 'user',
        'content': content,
        'timestamp': DateTime.now().toIso8601String(),
      });
      _messageController.clear();
    });
    _scrollToBottom();

    // Persist last AI message time + preview so lobby can sort/display correctly
    if (_currentUserId != null) {
      SharedPreferences.getInstance().then((prefs) {
        prefs.setString(
          'ai_last_message_time_$_currentUserId',
          DateTime.now().toUtc().toIso8601String(),
        );
        prefs.setString(
          'ai_last_message_preview_$_currentUserId',
          'You: $content',
        );
      });
    }

    try {
      final reply = await _sendMessageViaStream(
        token: token,
        sessionId: sessionId,
        content: content,
        userLocalId: userLocalId,
      );

      if (reply != null && reply.isNotEmpty && _currentUserId != null) {
        SharedPreferences.getInstance().then((prefs) {
          prefs.setString(
            'ai_last_message_preview_$_currentUserId',
            reply.length > 60 ? '${reply.substring(0, 60)}...' : reply,
          );
          prefs.setString(
            'ai_last_message_time_$_currentUserId',
            DateTime.now().toUtc().toIso8601String(),
          );
        });
      }
    } catch (e) {
      await _sendMessageViaLegacy(
        token: token,
        sessionId: sessionId,
        content: content,
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _isSending = false;
        _hasStreamingAssistant = false;
      });
    }
  }

  Future<String?> _sendMessageViaStream({
    required String token,
    required int sessionId,
    required String content,
    required String userLocalId,
  }) async {
    final client = http.Client();
    String? assistantLocalId;
    String assistantContent = '';

    try {
      final request = http.Request(
        'POST',
        _aiUri('/sessions/$sessionId/chat/stream'),
      );
      request.headers.addAll(<String, String>{
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
        'Authorization': 'Bearer $token',
      });
      request.body = jsonEncode(<String, dynamic>{
        'content': content,
        'model': 'llama3.2:3b',
      });

      final response = await client.send(request);
      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('HTTP ${response.statusCode}');
      }

      await for (final line in response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (!mounted) {
          break;
        }
        if (!line.startsWith('data:')) {
          continue;
        }

        final data = line.substring(5).trim();
        if (data.isEmpty || data == '[DONE]') {
          continue;
        }

        final payload = jsonDecode(data) as Map<String, dynamic>;
        final type = payload['type']?.toString();

        switch (type) {
          case 'user_message_saved':
            final userMessageId = payload['id'] as int?;
            if (userMessageId != null) {
              _replaceMessageId(userLocalId, userMessageId.toString());
            }
            break;
          case 'token':
            final tokenChunk = payload['content']?.toString() ?? '';
            if (tokenChunk.isEmpty) {
              break;
            }

            if (assistantLocalId == null) {
              assistantLocalId = '-${_nextLocalMessageId++}';
              setState(() {
                _hasStreamingAssistant = true;
                _messages.add(<String, String>{
                  'id': assistantLocalId!,
                  'role': 'assistant',
                  'content': tokenChunk,
                  'timestamp': DateTime.now().toIso8601String(),
                });
              });
              _scrollToBottom();
              assistantContent = tokenChunk;
            } else {
              assistantContent += tokenChunk;
              final idx = _messages.indexWhere(
                (message) => message['id'] == assistantLocalId,
              );
              if (idx != -1) {
                setState(() {
                  _messages[idx] = <String, String>{
                    ..._messages[idx],
                    'content': assistantContent,
                  };
                });
              }
            }
            break;
          case 'done':
            final userMessageId = payload['user_message_id'] as int?;
            final assistantMessageId = payload['assistant_message_id'] as int?;

            if (userMessageId != null) {
              _replaceMessageId(userLocalId, userMessageId.toString());
            }
            if (assistantLocalId != null && assistantMessageId != null) {
              _replaceMessageId(
                assistantLocalId!,
                assistantMessageId.toString(),
              );
            }
            break;
          case 'error':
            final err = payload['error']?.toString() ?? 'Unknown stream error';
            throw Exception(err);
          default:
            break;
        }
      }

      return assistantContent.trim().isEmpty ? null : assistantContent.trim();
    } finally {
      client.close();
    }
  }

  Future<void> _sendMessageViaLegacy({
    required String token,
    required int sessionId,
    required String content,
  }) async {
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
      if (!mounted || reply == null || reply.isEmpty) {
        return;
      }

      setState(() {
        _messages.add(<String, String>{
          'id': '-${_nextLocalMessageId++}',
          'role': 'assistant',
          'content': reply,
          'timestamp': DateTime.now().toIso8601String(),
        });
      });
      _scrollToBottom();

      if (_currentUserId != null) {
        SharedPreferences.getInstance().then((prefs) {
          prefs.setString(
            'ai_last_message_preview_$_currentUserId',
            reply.length > 60 ? '${reply.substring(0, 60)}...' : reply,
          );
          prefs.setString(
            'ai_last_message_time_$_currentUserId',
            DateTime.now().toUtc().toIso8601String(),
          );
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(<String, String>{
          'id': '-${_nextLocalMessageId++}',
          'role': 'assistant',
          'content': 'Sorry, I could not respond right now. ($e)',
          'timestamp': DateTime.now().toIso8601String(),
        });
      });
      _scrollToBottom();
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
      final response = await http
          .delete(
            _aiUri('/sessions/$sessionId/messages'),
            headers: <String, String>{
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(ApiConfig.connectionTimeout);

      if (response.statusCode == 404) {
        final newSessionId = await _createSession(token);
        final userId = await StorageService.getUserId() ?? 0;
        final prefs = await SharedPreferences.getInstance();
        if (newSessionId != null) {
          await prefs.setInt('ai_session_id_$userId', newSessionId);
        }
        if (!mounted) return;
        setState(() {
          _sessionId = newSessionId;
          _messages.clear();
        });
        _showInfo('Session expired. Started a new AI chat session.');
        return;
      }

      if (response.statusCode != 200 && response.statusCode != 204) {
        throw Exception('HTTP ${response.statusCode}');
      }

      if (!mounted) return;
      setState(() {
        _messages.clear();
      });
      _showInfo('AI chat cleared.');
    } catch (e) {
      _showError('Failed to clear AI chat: $e');
    }
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

  void _dismissTopActionBanner() {
    _topActionBannerTimer?.cancel();
    _topActionBannerTimer = null;
    _topActionBannerEntry?.remove();
    _topActionBannerEntry = null;
  }

  void _showTopActionBanner({
    required String message,
    required IconData icon,
    Color startColor = const Color(0xFF2563EB),
    Color endColor = const Color(0xFF1D4ED8),
    Duration duration = const Duration(milliseconds: 1900),
  }) {
    if (!mounted) return;

    _dismissTopActionBanner();

    final overlay = Overlay.of(context, rootOverlay: true);

    final entry = OverlayEntry(
      builder: (overlayContext) {
        final topInset = MediaQuery.of(overlayContext).padding.top;

        return Positioned(
          top: topInset + 10,
          left: 14,
          right: 14,
          child: IgnorePointer(
            child: Material(
              color: Colors.transparent,
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: 1),
                duration: const Duration(milliseconds: 230),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value,
                    child: Transform.translate(
                      offset: Offset(0, -18 * (1 - value)),
                      child: child,
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [startColor, endColor],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.25),
                      width: 0.8,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: endColor.withOpacity(0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, color: Colors.white, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          message,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(entry);
    _topActionBannerEntry = entry;
    _topActionBannerTimer = Timer(duration, _dismissTopActionBanner);
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

  void _scrollToBottomButtonTap() {
    _scrollToBottom();
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

  String _formatTimestampFull(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    try {
      final dt = DateTime.parse(raw).toLocal();
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} $h:$m';
    } catch (_) {
      return raw;
    }
  }

  int _messageId(Map<String, String> message) {
    final fromPayload = int.tryParse(message['id'] ?? '');
    if (fromPayload != null) return fromPayload;
    return (message['timestamp'] ?? message['content'] ?? '').hashCode;
  }

  String _ensureColorEmoji(String emoji) {
    const variationSelector = '\uFE0F';
    const needsSelector = <int>{
      0x2764,
      0x2602,
      0x2614,
      0x263A,
      0x2B50,
      0x2600,
      0x2601,
      0x260E,
      0x2709,
      0x270F,
      0x2744,
      0x2728,
      0x2702,
      0x26A1,
      0x2615,
    };
    if (emoji.isNotEmpty &&
        needsSelector.contains(emoji.runes.first) &&
        !emoji.contains(variationSelector)) {
      return emoji + variationSelector;
    }
    return emoji;
  }

  Widget _buildReactionPills(int messageId) {
    final reactions = _messageReactions[messageId];
    if (reactions == null || reactions.isEmpty) {
      return const SizedBox.shrink();
    }

    final currentUserStr = _currentUserId?.toString() ?? '';
    final pills = <Widget>[];

    reactions.forEach((emoji, users) {
      if (users.isEmpty) return;
      final iReacted = users.contains(currentUserStr);
      pills.add(
        Container(
          margin: const EdgeInsets.only(right: 2),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: iReacted ? const Color(0xFF3A3A5C) : const Color(0xFF2C2C2E),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: iReacted
                  ? const Color(0xFF6D28D9).withOpacity(0.5)
                  : Colors.white.withOpacity(0.15),
              width: iReacted ? 1.0 : 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_ensureColorEmoji(emoji), style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 2),
              Text(
                '${users.length}',
                style: const TextStyle(fontSize: 11, color: Colors.white70),
              ),
            ],
          ),
        ),
      );
    });

    if (pills.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 2, runSpacing: 2, children: pills);
  }

  void _toggleReaction(int messageId, String emoji) {
    final currentUserStr = _currentUserId?.toString() ?? 'me';
    setState(() {
      _messageReactions.putIfAbsent(messageId, () => <String, Set<String>>{});
      _messageReactions[messageId]!.putIfAbsent(emoji, () => <String>{});
      final users = _messageReactions[messageId]![emoji]!;

      if (users.contains(currentUserStr)) {
        users.remove(currentUserStr);
        if (users.isEmpty) {
          _messageReactions[messageId]!.remove(emoji);
        }
      } else {
        users.add(currentUserStr);
      }

      if (_messageReactions[messageId]!.isEmpty) {
        _messageReactions.remove(messageId);
      }
    });
  }

  void _showReactionPicker(BuildContext context, int messageId, Offset position) {
    ReactionPicker.show(
      context: context,
      position: position,
      onReactionSelected: (emoji) => _toggleReaction(messageId, emoji),
    );
  }

  Future<void> _showMessageContextMenu(
    Map<String, String> message,
    bool isUser,
  ) async {
    var actionInvoked = false;

    void closeWithAction(BuildContext sheetContext, VoidCallback action) {
      actionInvoked = true;
      Navigator.pop(sheetContext);
      action();
    }

    await showModalBottomSheet(
      context: context,
      requestFocus: false,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E2E),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFF7C3AED).withOpacity(0.28),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF420796).withOpacity(0.28),
                blurRadius: 24,
                spreadRadius: 0.2,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 5,
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.28),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Row(
                children: const [
                  Icon(
                    Icons.tune_rounded,
                    color: Color(0xFFB794F6),
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Message Actions',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _buildContextMenuActionTile(
                icon: Icons.copy_rounded,
                label: 'Copy',
                onTap: () {
                  closeWithAction(
                    sheetContext,
                    () => _copyMessageToClipboard(message),
                  );
                },
              ),
              if (isUser)
                _buildContextMenuActionTile(
                  icon: Icons.edit_rounded,
                  label: 'Edit',
                  onTap: () {
                    closeWithAction(
                      sheetContext,
                      () => _showEditMessageDialog(message),
                    );
                  },
                ),
              if (isUser)
                _buildContextMenuActionTile(
                  icon: Icons.delete_outline,
                  label: 'Delete',
                  iconColor: const Color(0xFFF87171),
                  textColor: const Color(0xFFFCA5A5),
                  tileColor: const Color(0xFF341E2A),
                  onTap: () {
                    closeWithAction(
                      sheetContext,
                      () => _showDeleteConfirmation(message),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );

    if (!actionInvoked && mounted) {
      FocusScope.of(context).unfocus();
    }
  }

  Widget _buildContextMenuActionTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color iconColor = Colors.white,
    Color textColor = Colors.white,
    Color tileColor = const Color(0xFF252542),
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              color: tileColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Row(
                children: [
                  Icon(icon, color: iconColor, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    label,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  int _findMessageIndex(Map<String, String> targetMessage) {
    final indexByIdentity = _messages.indexWhere(
      (message) => identical(message, targetMessage),
    );
    if (indexByIdentity != -1) {
      return indexByIdentity;
    }

    final targetId = targetMessage['id'];
    if (targetId != null && targetId.isNotEmpty) {
      final indexById = _messages.indexWhere((message) => message['id'] == targetId);
      if (indexById != -1) {
        return indexById;
      }
    }

    return -1;
  }

  int? _backendMessageId(Map<String, String> message) {
    final id = int.tryParse(message['id'] ?? '');
    if (id == null || id <= 0) {
      return null;
    }
    return id;
  }

  void _replaceMessageId(String oldId, String newId) {
    if (!mounted) return;
    final idx = _messages.indexWhere((message) => message['id'] == oldId);
    if (idx == -1) return;

    setState(() {
      _messages[idx] = <String, String>{
        ..._messages[idx],
        'id': newId,
      };
    });
  }

  void _copyMessageToClipboard(Map<String, String> message) {
    final content = (message['content'] ?? '').trim();
    if (content.isEmpty) {
      _showInfo('Nothing to copy.');
      return;
    }

    Clipboard.setData(ClipboardData(text: content));
    _showTopActionBanner(
      message: 'Copied to clipboard',
      icon: Icons.copy_rounded,
      startColor: const Color(0xFF0891B2),
      endColor: const Color(0xFF0E7490),
    );
  }

  void _showEditMessageDialog(Map<String, String> message) {
    final editController = TextEditingController(
      text: message['content'] ?? '',
    );

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text(
          'Edit Message',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: editController,
          style: const TextStyle(color: Colors.white),
          maxLines: 5,
          minLines: 1,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Edit your message...',
            hintStyle: TextStyle(color: Colors.grey[500]),
            filled: true,
            fillColor: const Color(0xFF252542),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              final newContent = editController.text.trim();
              final oldContent = (message['content'] ?? '').trim();

              Navigator.pop(dialogContext);

              if (newContent.isNotEmpty && newContent != oldContent) {
                await _editMessage(message, newContent);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF420796),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    ).then((_) {
      editController.dispose();
    });
  }

  Future<void> _editMessage(Map<String, String> message, String newContent) async {
    final index = _findMessageIndex(message);
    if (index == -1) {
      return;
    }

    final sessionId = _sessionId;
    final token = await StorageService.getToken();
    final messageId = _backendMessageId(_messages[index]);

    if (sessionId == null || token == null || token.isEmpty) {
      _showError('Session is not ready. Please try again.');
      return;
    }

    if (messageId == null) {
      _showError('Message is still syncing. Try again in a moment.');
      return;
    }

    final response = await http
        .patch(
          _aiUri('/sessions/$sessionId/messages/$messageId'),
          headers: <String, String>{
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(<String, dynamic>{'content': newContent}),
        )
        .timeout(ApiConfig.connectionTimeout);

    if (response.statusCode == 404) {
      if (!mounted) return;
      setState(() {
        _messages.removeAt(index);
      });
      _showInfo('Message no longer exists and was removed.');
      return;
    }

    if (response.statusCode == 400) {
      _showError('Message content is required.');
      return;
    }

    if (response.statusCode != 200) {
      _showError('Failed to edit message (HTTP ${response.statusCode}).');
      return;
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final updatedContent = (payload['content'] ?? newContent).toString();

    setState(() {
      _messages[index] = <String, String>{
        ..._messages[index],
        'content': updatedContent,
      };
    });

    _showTopActionBanner(
      message: 'Message edited',
      icon: Icons.edit_rounded,
      startColor: const Color(0xFF7C3AED),
      endColor: const Color(0xFF5B21B6),
    );
  }

  void _showDeleteConfirmation(Map<String, String> message) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text(
          'Delete Message',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Are you sure you want to delete this message? This action cannot be undone.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await _deleteMessage(message);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteMessage(Map<String, String> message) async {
    final index = _findMessageIndex(message);
    if (index == -1) {
      return;
    }

    final sessionId = _sessionId;
    final token = await StorageService.getToken();
    final messageId = _backendMessageId(_messages[index]);

    if (sessionId == null || token == null || token.isEmpty) {
      _showError('Session is not ready. Please try again.');
      return;
    }

    if (messageId == null) {
      _showError('Message is still syncing. Try again in a moment.');
      return;
    }

    final response = await http
        .delete(
          _aiUri('/sessions/$sessionId/messages/$messageId'),
          headers: <String, String>{
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
        )
        .timeout(ApiConfig.connectionTimeout);

    if (response.statusCode != 200 &&
        response.statusCode != 204 &&
        response.statusCode != 404) {
      _showError('Failed to delete message (HTTP ${response.statusCode}).');
      return;
    }

    setState(() {
      _messages.removeAt(index);
    });

    _showTopActionBanner(
      message: 'Message deleted',
      icon: Icons.delete_outline,
      startColor: const Color(0xFFDC2626),
      endColor: const Color(0xFF991B1B),
    );
  }

  Widget _buildMessageBubble(Map<String, String> message) {
    final isUser = message['role'] == 'user';
    final timestamp = _formatTimestamp(message['timestamp']);
    final fullTimestamp = _formatTimestampFull(message['timestamp']);
    final messageId = _messageId(message);
    final hasReactions =
        _messageReactions[messageId] != null && _messageReactions[messageId]!.isNotEmpty;

    final bubbleWidget = GestureDetector(
      onLongPress: () => _showMessageContextMenu(message, isUser),
      child: Container(
        margin: EdgeInsets.only(bottom: hasReactions ? 2 : 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.70,
        ),
        decoration: BoxDecoration(
          color: isUser ? const Color(0xFF420796) : const Color(0xFF3944BC),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                message['content'] ?? '',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  height: 1.35,
                ),
              ),
            ),
            if (isUser)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      timestamp,
                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.done_all,
                      size: 16,
                      color: Color(0xFF00BCD4),
                    ),
                  ],
                ),
              ),
            if (_showTimestamps)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Text(
                  fullTimestamp,
                  style: const TextStyle(
                    color: Color(0xFFFF69B4),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Builder(
            builder: (rowContext) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  bubbleWidget,
                  if (!isUser)
                    GestureDetector(
                      onTapDown: (details) {
                        // Use the exact tap position for stable overlay placement.
                        _showReactionPicker(
                          context,
                          messageId,
                          details.globalPosition,
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(
                          Icons.sentiment_satisfied_alt_outlined,
                          color: Colors.white.withOpacity(0.6),
                          size: 22,
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
                left: isUser ? 0 : 8,
                right: isUser ? 8 : 0,
                bottom: 6,
              ),
              child: _buildReactionPills(messageId),
            ),
        ],
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
              final textStyle = const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontFamily: 'Roboto',
                height: 1.12,
              );

              return LayoutBuilder(
                builder: (context, constraints) {
                  const iconSlotWidth = 40.0;
                  const sendButtonReserve = 88.0;
                  final estimatedTextMaxWidth = math.max(
                    120.0,
                    constraints.maxWidth - sendButtonReserve - iconSlotWidth - 28.0,
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
        title: Row(
          children: <Widget>[
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF00C9A7), Color(0xFF845EC2)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Icons.smart_toy_rounded, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('AI Chat', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                Text('Always on', style: TextStyle(fontSize: 11, color: Color(0xFF00E676))),
              ],
            ),
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
                : Stack(
                    children: [
                      ListView.builder(
                        controller: _scrollController,
                        itemCount:
                            _messages.length +
                            ((_isSending && !_hasStreamingAssistant) ? 1 : 0),
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        itemBuilder: (context, index) {
                          if (_isSending && index == _messages.length) {
                            return _buildThinkingBubble();
                          }
                          return _buildMessageBubble(_messages[index]);
                        },
                      ),
                      if (!_isAtBottom)
                        Positioned(
                          bottom: 16,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: GestureDetector(
                              onTap: _scrollToBottomButtonTap,
                              child: Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF7C3AED),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.3),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.keyboard_arrow_down,
                                  color: Colors.white,
                                  size: 28,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
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
