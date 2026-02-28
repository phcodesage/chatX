# Auto-Translate Implementation for Flutter Mobile App

## Overview
This document provides instructions for implementing auto-translate functionality in the Flutter mobile app.

## Backend Setup (Already Complete)

### 1. Translate API Endpoint
The backend has been updated with a new `/api/translate_message` endpoint in `app/routes/mobile_api.py`.

**Endpoint:** `POST /api/translate_message`

**Request:**
```json
{
  "text": "Hello world",
  "target_lang": "en"
}
```

**Response:**
```json
{
  "success": true,
  "translation": "Hello world",
  "detected_language": "es",
  "target_language": "en"
}
```

**Error Response:**
```json
{
  "success": false,
  "error": "No text provided"
}
```

## Flutter Implementation

### Step 1: Store Auth Token in WebView localStorage

When the user logs in or the app starts, store the auth token in the WebView's localStorage. This allows the web content to detect it's running in the mobile app.

```dart
import 'package:webview_flutter/webview_flutter.dart';

class ChatWebView {
  late WebViewWidget _webView;
  
  void _onWebViewCreated(WebViewController controller) async {
    // Store auth token in localStorage
    final String authToken = await _getAuthToken(); // Your method to get token
    
    if (authToken.isNotEmpty) {
      await controller.runJavaScript(
        "localStorage.setItem('auth_token', '$authToken');"
      );
    }
    
    // Set flag to use mobile API
    await controller.runJavaScript(
      "window.useMobileApi = true;"
    );
  }
}
```

### Step 2: Auto-Translate Toggle

Add a toggle button in your Flutter chat UI to enable/disable auto-translate:

```dart
class TranslateToggle extends StatefulWidget {
  @override
  _TranslateToggleState createState() => _TranslateToggleState();
}

class _TranslateToggleState extends State<TranslateToggle> {
  bool _autoTranslateEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _autoTranslateEnabled = prefs.getBool('autoTranslate') ?? false;
    });
  }

  Future<void> _toggleTranslate(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('autoTranslate', value);
    
    setState(() {
      _autoTranslateEnabled = value;
    });
    
    // Notify web view to translate existing messages
    if (value) {
      await _webViewController?.runJavaScript(
        "if (window.TranslateManager && typeof window.TranslateManager.toggle === 'function') { window.TranslateManager.toggle(); }"
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: Text('Auto-Translate'),
      subtitle: Text(_autoTranslateEnabled ? 'Enabled' : 'Disabled'),
      value: _autoTranslateEnabled,
      onChanged: _toggleTranslate,
      activeColor: Colors.purple,
    );
  }
}
```

### Step 3: Translate Existing Messages

When auto-translate is enabled, translate existing messages in the chat:

```dart
Future<void> translateExistingMessages(WebViewController controller) async {
  await controller.runJavaScript("""
    if (window.TranslateManager && typeof window.TranslateManager.translateExistingMessages === 'function') {
      window.TranslateManager.translateExistingMessages();
    }
  """);
}
```

### Step 4: Handle Translation API Call

The web content will automatically use `/api/translate_message` when `window.useMobileApi = true`.

## Testing

### Test the Translate API

```bash
curl -X POST http://localhost:5000/api/translate_message \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d '{"text": "Hola mundo", "target_lang": "en"}'
```

### Test in Flutter WebView

1. Open the chat screen
2. Enable auto-translate toggle
3. Send/receive a Japanese message
4. The message should be automatically translated to English

## Troubleshooting

### Issue: Translation not working
- Check if `window.useMobileApi = true` is set in WebView
- Check if auth token is stored in localStorage
- Verify the `/api/translate_message` endpoint is accessible
- Check browser console for errors

### Issue: Translation API returns error
- Verify the auth token is valid
- Check if the text parameter is not empty
- Verify network connectivity

### Issue: Messages not translating
- Check if auto-translate is enabled
- Verify the message is not a file/image (only text messages are translated)
- Check if the message is older than 15 minutes (old messages are skipped)

## Files Modified

1. `app/routes/mobile_api.py` - Added `/api/translate_message` endpoint
2. `app/static/js/translate-manager.js` - Updated to support mobile API
3. `app/templates/base.html` - Added mobile app detection

## Related Documentation

- [API Documentation](../guides/FLUTTER_API_GUIDE.md)
- [Auto-Translate Feature](../guides/AUTO_TRANSLATE_FEATURE.md)
