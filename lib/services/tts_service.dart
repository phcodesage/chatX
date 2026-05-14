import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  static final TtsService _instance = TtsService._internal();
  factory TtsService() => _instance;

  final FlutterTts _flutterTts = FlutterTts();
  
  // Track which message ID is currently being read.
  // Using ValueNotifier so UI components can listen to state changes.
  final ValueNotifier<String?> readingMessageId = ValueNotifier<String?>(null);

  TtsService._internal() {
    _initTts();
  }

  Future<void> _initTts() async {
    // Configure default TTS settings if needed
    try {
      await _flutterTts.setLanguage("en-US");
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);

      _flutterTts.setStartHandler(() {
        // Handled by speak method
      });

      _flutterTts.setCompletionHandler(() {
        if (kDebugMode) {
          debugPrint('TTS Completion Handler triggered');
        }
        readingMessageId.value = null;
      });

      _flutterTts.setErrorHandler((msg) {
        if (kDebugMode) {
          debugPrint('TTS Error: $msg');
        }
        readingMessageId.value = null;
      });

      _flutterTts.setCancelHandler(() {
        if (kDebugMode) {
          debugPrint('TTS Cancelled');
        }
        readingMessageId.value = null;
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error initializing TTS: $e');
      }
    }
  }

  /// Stop current playback and read the provided text.
  /// Records the messageId as the currently reading message.
  Future<void> speak(String messageId, String text) async {
    if (text.trim().isEmpty) return;
    
    // Stop any existing speech first
    await stop();
    
    readingMessageId.value = messageId;
    try {
      final result = await _flutterTts.speak(text);
      if (result != 1) {
        // Fallback if speaking failed immediately
        readingMessageId.value = null;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('TTS Speak Error: $e');
      }
      readingMessageId.value = null;
    }
  }

  /// Stop playback
  Future<void> stop() async {
    try {
      await _flutterTts.stop();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('TTS Stop Error: $e');
      }
    } finally {
      readingMessageId.value = null;
    }
  }

  /// Clean up resources
  void dispose() {
    readingMessageId.dispose();
  }
}
